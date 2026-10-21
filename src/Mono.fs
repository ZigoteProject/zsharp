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

/// Units of measure are erased, so measure arguments don't distinguish instances.
let mangle (name: string) (inst: Ty list) =
    let shown =
        inst
        |> List.filter (fun t ->
            match prune t with
            | TMeas _ -> false
            | _ -> true)

    if shown.IsEmpty then
        name
    else
        name + "<" + (shown |> List.map show |> String.concat ",") + ">"

/// Concrete type: quantified variables replaced, everything else resolved (defaulted).
let rec private concrete (inst: Ty list) t =
    match prune t with
    | TGen i -> List.item i inst
    | TCon(n, _) when nums.Contains n -> TCon(n, []) // units of measure are erased
    | TMeas _ -> measOne
    | TCon("Buffer", a) -> TCon("array", List.map (concrete inst) a) // same storage, shared instead of copied
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
    let rec dispatch (q: string) (inst: Ty list) (headTy: Ty) (args: CExpr list) (resTy: Ty) : CExpr =
        let tm = prog.traitMethods[q]
        let t = List.head inst

        let arity =
            let rec go t =
                match prune t with
                | TFun(_, r) -> 1 + go r
                | _ -> 0

            go headTy

        let inline' (args: CExpr list) res =
            match prune t with
            | TTuple ts -> tupleMethod q ts args res
            | _ -> builtinMethod q t args res

        let isTuple =
            match prune t with
            | TTuple _ -> true
            | _ -> false

        if not (isPrim t || isTuple) || prog.impls.ContainsKey((tm.owner, show t)) then
            let f = implFn tm.owner tm.name t headTy
            if args.IsEmpty then f else mk (CApp(f, args)) resTy
        elif args.Length = arity then
            inline' args resTy
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

            let lam = mk (CLam(ps, inline' (ps |> List.map (fun (x, p) -> mk (CLocal x) p)) res)) headTy
            if args.IsEmpty then lam else mk (CApp(lam, args)) resTy

    /// Structural Eq/Ord/Show/Hash for tuples, component by component.
    and tupleMethod (q: string) (ts: Ty list) (args: CExpr list) (resTy: Ty) : CExpr =
        let temp (e: CExpr) =
            count.Value <- count.Value + 1
            sprintf "$tt%d" count.Value, e

        let bound = args |> List.map temp
        let comp (x, a: CExpr) i t = mk (CField(mk (CLocal x) a.ty, i)) t
        let call m (t: Ty) cargs res = dispatch m [ t ] (substGen [ t ] prog.traitMethods[m].ty) cargs res
        let ts' = List.indexed ts

        let body =
            match q, bound with
            | "Show.show", [ a ] ->
                let parts = ts' |> List.map (fun (i, t) -> call "Show.show" t [ comp a i t ] tStr)
                let sep (x: CExpr) (y: CExpr) = mk (CBin("+", mk (CBin("+", x, mk (CStr ", ") tStr)) tStr, y)) tStr
                let inner = List.reduce sep parts
                mk (CBin("+", mk (CBin("+", mk (CStr "(") tStr, inner)) tStr, mk (CStr ")") tStr)) tStr
            | "Eq.equal", [ a; b ] ->
                List.foldBack
                    (fun (i, t) acc ->
                        mk (CIf(call "Eq.equal" t [ comp a i t; comp b i t ] tBool, acc, mk (CBool false) tBool)) tBool)
                    ts'
                    (mk (CBool true) tBool)
            | "Ord.compare", [ a; b ] ->
                // lexicographic: the first component that differs decides
                List.foldBack
                    (fun (i, t) acc ->
                        count.Value <- count.Value + 1
                        let c = sprintf "$tc%d" count.Value
                        let cv = mk (CLocal c) tInt
                        let differs = mk (CBin("<>", cv, mk (CInt 0L) tInt)) tBool
                        mk (CLet(c, call "Ord.compare" t [ comp a i t; comp b i t ] tInt, mk (CIf(differs, cv, acc)) tInt)) tInt)
                    ts'
                    (mk (CInt 0L) tInt)
            | "Hash.hash", [ a ] ->
                ts'
                |> List.fold
                    (fun acc (i, t) ->
                        let h = call "Hash.hash" t [ comp a i t ] tInt
                        mk (CBin("+", mk (CBin("*", acc, mk (CInt 31L) tInt)) tInt, h)) tInt)
                    (mk (CInt 17L) tInt)
            | _ -> Syntax.fail 0 (sprintf "tuples have no %s" q)

        List.foldBack (fun (x, e: CExpr) acc -> mk (CLet(x, e, acc)) acc.ty) bound body

    /// An operator on a non-primitive type calls the type's trait impl.
    let operator (op: string) (a: CExpr) (b: CExpr) (resTy: Ty) : CExpr =
        let tr, m = opTrait[op]
        let methodTy = substGen [ a.ty ] prog.traitMethods[tr + "." + m].ty
        let call = dispatch (tr + "." + m) [ a.ty ] methodTy [ a; b ] (if tr = "Ord" then tInt else resTy)

        match op with
        | "<>" -> mk (CNot call) tBool
        | "<"
        | ">"
        | "<="
        | ">=" -> mk (CBin(op, call, mk (CInt 0L) tInt)) tBool
        | _ -> call

    // roots: main (if any) and every exported function
    if defs.ContainsKey "main" then
        request "main" [] |> ignore

    for e in prog.exports do
        request e.fname [] |> ignore

    for t in prog.tests do
        request t [] |> ignore

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
