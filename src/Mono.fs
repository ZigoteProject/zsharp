/// Monomorphization: copies each generic function once per concrete instantiation reachable
/// from main. The output has no type variables.
module Mono

open System.Collections.Generic
open Core

type MFun =
    { name: string
      pars: (string * Ty) list
      ret: Ty
      body: CExpr }

let mangle (name: string) (inst: Ty list) =
    if inst.IsEmpty then
        name
    else
        name + "<" + (inst |> List.map show |> String.concat ",") + ">"

/// Concrete type: quantified variables replaced, everything else resolved (defaulted).
let rec private concrete (inst: Ty list) t =
    match prune t with
    | TGen i -> List.item i inst
    | TCon(n, a) -> TCon(n, List.map (concrete inst) a)
    | TFun(a, b) -> TFun(concrete inst a, concrete inst b)
    | TTuple ts -> TTuple(List.map (concrete inst) ts)
    | TVar _ as t -> resolve t

/// Binds TGen variables of a generic type so that it equals a concrete one.
let rec private matchTy (binds: Ty option[]) (pattern: Ty) (concrete: Ty) =
    match prune pattern, prune concrete with
    | TGen i, c -> binds[i] <- Some c
    | TCon(_, ps), TCon(_, cs)
    | TTuple ps, TTuple cs when ps.Length = cs.Length -> List.iter2 (matchTy binds) ps cs
    | TFun(a, b), TFun(c, d) ->
        matchTy binds a c
        matchTy binds b d
    | _ -> ()

let private opTrait =
    dict
        [ "+", ("Add", "add")
          "-", ("Num", "sub")
          "*", ("Num", "mul")
          "/", ("Num", "div")
          "%", ("Num", "rem")
          "=", ("Eq", "equal")
          "<>", ("Eq", "equal")
          "<", ("Ord", "compare")
          ">", ("Ord", "compare")
          "<=", ("Ord", "compare")
          ">=", ("Ord", "compare") ]

let private isPrim (t: Ty) =
    match prune t with
    | TCon(n, []) -> prims.Contains n
    | _ -> false

let run (prog: Program) : MFun list =
    let defs = prog.funs |> List.map (fun f -> f.name, f) |> dict
    let seen = HashSet<string>()
    let queue = Queue<string * Ty list>()
    let out = ResizeArray<MFun>()

    let request name inst =
        let m = mangle name inst

        if seen.Add m then
            queue.Enqueue(name, inst)

        m

    let mk k ty = { k = k; ty = ty }
    let count = ref 0

    /// The impl function (instantiated) for trait method `trait.m` at concrete type t.
    let implFn (tr: string) (m: string) (t: Ty) (methodTy: Ty) : CExpr =
        let tn =
            match prune t with
            | TCon(n, _) -> n
            | t -> show t

        match prog.impls.TryGetValue((tr, tn)) with
        | true, table ->
            let fname = table[m]
            let fd = defs[fname]
            let binds = Array.create fd.ngen None
            matchTy binds (List.foldBack (fun (_, p) acc -> TFun(p, acc)) fd.pars fd.ret) methodTy
            let inst = binds |> Array.map (Option.defaultValue tInt) |> List.ofArray
            mk (CGlobal(request fname inst, Some [])) methodTy
        | _ -> Syntax.fail 0 (sprintf "%s does not implement %s" (show t) tr)

    /// A trait method applied to (exactly its arity of) arguments, for a primitive type.
    let builtinMethod (q: string) (t: Ty) (args: CExpr list) (resTy: Ty) : CExpr =
        let a i = List.item i args

        let k =
            match q, args with
            | "Add.add", _ -> CBin("+", a 0, a 1)
            | "Add.zero", _ ->
                match prune t with
                | TCon(("f64" | "f32"), []) -> CFloat 0.0
                | TCon("string", []) -> CStr ""
                | _ -> CInt 0L
            | "Num.sub", _ -> CBin("-", a 0, a 1)
            | "Num.mul", _ -> CBin("*", a 0, a 1)
            | "Num.div", _ -> CBin("/", a 0, a 1)
            | "Num.rem", _ -> CBin("%", a 0, a 1)
            | "Num.neg", _ -> CNeg(a 0)
            | "Eq.equal", _ -> CBin("=", a 0, a 1)
            | "Ord.compare", _ -> CPrim("compare", args)
            | "Show.show", _ -> CPrim("string", args)
            | "Hash.hash", _ -> CPrim("hash", args)
            | _ -> Syntax.fail 0 (sprintf "%s has no built-in %s" (show t) q)

        mk k resTy

    /// Trait method `q` at its instantiation, applied to args (possibly none).
    let dispatch (q: string) (inst: Ty list) (headTy: Ty) (args: CExpr list) (resTy: Ty) : CExpr =
        let tm = prog.traitMethods[q]
        let t = List.head inst

        let arity =
            let rec go t =
                match prune t with
                | TFun(_, r) -> 1 + go r
                | _ -> 0

            go headTy

        if not (isPrim t) || prog.impls.ContainsKey((tm.owner, show t)) then
            let f = implFn tm.owner tm.name t headTy
            if args.IsEmpty then f else mk (CApp(f, args)) resTy
        elif args.Length = arity then
            builtinMethod q t args resTy
        else
            // a built-in method used as a value: wrap it in a lambda
            let rec peel n t =
                match n, prune t with
                | 0, r -> [], r
                | n, TFun(p, r) ->
                    let ps, res = peel (n - 1) r
                    p :: ps, res
                | _ -> failwith "dispatch: not a function"

            let ptys, res = peel arity headTy

            let ps =
                ptys
                |> List.map (fun p ->
                    count.Value <- count.Value + 1
                    sprintf "$tm%d" count.Value, p)

            let lam = mk (CLam(ps, builtinMethod q t (ps |> List.map (fun (x, p) -> mk (CLocal x) p)) res)) headTy
            if args.IsEmpty then lam else mk (CApp(lam, args)) resTy

    /// An operator on a non-primitive type calls the type's trait impl.
    let operator (op: string) (a: CExpr) (b: CExpr) (resTy: Ty) : CExpr =
        let tr, m = opTrait[op]
        let methodTy = substGen [ a.ty ] prog.traitMethods[tr + "." + m].ty
        let call = mk (CApp(implFn tr m a.ty methodTy, [ a; b ])) (if tr = "Ord" then tInt else resTy)

        match op with
        | "<>" -> mk (CNot call) tBool
        | "<"
        | ">"
        | "<="
        | ">=" -> mk (CBin(op, call, mk (CInt 0L) tInt)) tBool
        | _ -> call

    request "main" [] |> ignore

    while queue.Count > 0 do
        let name, inst = queue.Dequeue()
        let f = defs[name]
        let ct = concrete inst

        let rec ex (e: CExpr) : CExpr =
            match e.k with
            | CApp({ k = CGlobal(q, Some gi) } as h, args) when prog.traitMethods.ContainsKey q ->
                dispatch q (List.map ct gi) (ct h.ty) (List.map ex args) (ct e.ty)
            | CGlobal(q, Some gi) when prog.traitMethods.ContainsKey q -> dispatch q (List.map ct gi) (ct e.ty) [] (ct e.ty)
            | CBin(op, a, b) when not (isPrim (ct a.ty)) -> operator op (ex a) (ex b) (ct e.ty)
            | CNeg a when not (isPrim (ct a.ty)) ->
                let methodTy = substGen [ ct a.ty ] prog.traitMethods["Num.neg"].ty
                mk (CApp(implFn "Num" "neg" (ct a.ty) methodTy, [ ex a ])) (ct e.ty)
            | _ ->
                let k =
                    match e.k with
                    | CGlobal(g, Some gi) -> CGlobal(request g (List.map ct gi), Some [])
                    | CGlobal(g, None) -> CGlobal(request g inst, Some []) // self-recursion
                    | CLam(ps, b) -> CLam(ps |> List.map (fun (x, t) -> x, ct t), ex b)
                    | CLetFun(n, r, ps, b, rest) -> CLetFun(n, r, ps |> List.map (fun (x, t) -> x, ct t), ex b, ex rest)
                    | CMatch(s, cases) -> CMatch(ex s, cases |> List.map (fun (p, g, b) -> mapPatTypes ct p, Option.map ex g, ex b))
                    | k -> mapChildren ex k

                { k = k; ty = ct e.ty }

        out.Add
            { name = mangle name inst
              pars = f.pars |> List.map (fun (x, t) -> x, ct t)
              ret = ct f.ret
              body = ex f.body }

    List.ofSeq out
