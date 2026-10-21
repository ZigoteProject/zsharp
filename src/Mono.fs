/// Monomorphization: copies each generic function once per concrete instantiation reachable
/// from main. The output has no type variables.
module Mono

open System.Collections.Generic
open Core

type MFun =
    { name: string
      pars: (string * Ty) list
      ret: Ty
      body: CExpr
      file: string
      line: int }

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
        name + "<" + (shown |> List.map showFull |> String.concat ",") + ">"

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
            | t -> showFull t

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

        if not (isPrim t || isTuple) || prog.impls.ContainsKey((tm.owner, showFull t)) then
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
                        // wrapping: a hash may overflow on purpose
                        mk (CPrim("wrap+", [ mk (CPrim("wrap*", [ acc; mk (CInt 31L) tInt ])) tInt; h ])) tInt)
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

    for _, init in prog.values do
        request init [] |> ignore

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
                    | CLetRec(fs, rest) -> CLetRec(fs |> List.map (fun (n, ps, b) -> n, ps |> List.map (fun (x, t) -> x, ct t), ex b), ex rest)
                    | CMatch(s, cases) -> CMatch(ex s, cases |> List.map (fun (p, g, b) -> mapPatTypes ct p, Option.map ex g, ex b))
                    | k -> mapChildren ex k

                { k = k; ty = ct e.ty }

        out.Add
            { name = mangle name inst
              pars = f.pars |> List.map (fun (x, t) -> x, ct t)
              ret = ct f.ret
              body = ex f.body
              file = f.file
              line = f.line }

    List.ofSeq out

// ---- list fusion: List.init n g |> List.map f |> List.filter p |> List.sum (or sumBy, fold,
// length) becomes one loop with an accumulator, building no lists. Only when every function in
// the chain is a lambda that is pure (arithmetic, comparisons, local bindings, conditionals):
// then running the stages per element instead of per list can't change what the program does.

type private Stage =
    | MapS of CExpr
    | FilterS of CExpr

let fuse (funs: MFun list) : MFun list =
    let count = ref 0

    let fresh (p: string) =
        count.Value <- count.Value + 1
        sprintf "$fuse%d.%s" count.Value p

    let mk k ty = { k = k; ty = ty }

    let baseName (g: string) =
        match g.IndexOf '<' with
        | -1 -> g
        | i -> g.Substring(0, i)

    let call (e: CExpr) =
        match e.k with
        | CApp({ k = CGlobal(g, _) }, args) -> Some(baseName g, args)
        | _ -> None

    let rec pure (e: CExpr) =
        match e.k with
        | CInt _
        | CFloat _
        | CBool _
        | CUnit
        | CLocal _ -> true
        | CBin(_, a, b) -> pure a && pure b
        | CNeg a
        | CNot a
        | CLine(_, a) -> pure a
        | CIf(c, t, f) -> pure c && pure t && pure f
        | CLet(_, v, b) -> pure v && pure b
        | CPrim(("conv" | "wrap+" | "wrap-" | "wrap*"), args) -> List.forall pure args
        | _ -> false

    let pureLambda (e: CExpr) arity =
        match e.k with
        | CLam(ps, body) -> ps.Length = arity && pure body
        | _ -> false

    /// (lambda applied to args) as lets of its parameters around its body
    let beta (lam: CExpr) (args: CExpr list) =
        match lam.k with
        | CLam(ps, body) -> List.foldBack2 (fun (p, _) a acc -> mk (CLet(p, a, acc)) acc.ty) ps args body
        | _ -> failwith "beta"

    let numeric (t: Ty) =
        match prune t with
        | TCon(n, []) -> nums.Contains n
        | _ -> false

    let zeroOf (t: Ty) =
        match prune t with
        | TCon(n, []) when floats.Contains n -> mk (CFloat 0.0) t
        | _ -> mk (CInt 0L) t

    /// The producer chain under a consumer: stages (outermost last) down to List.init n g.
    let rec chain (xs: CExpr) (stages: Stage list) =
        match call xs with
        | Some("Collections.List.map", [ f; ys ]) when pureLambda f 1 -> chain ys (MapS f :: stages)
        | Some("Collections.List.filter", [ p; ys ]) when pureLambda p 1 -> chain ys (FilterS p :: stages)
        | Some("Collections.List.init", [ n; g ]) when pureLambda g 1 -> Some(n, g, stages)
        | _ -> None

    /// The fused loop: acc starts at `start`; for each element x surviving the stages, acc <- step acc x.
    let loop (n: CExpr) (g: CExpr) (stages: Stage list) (start: CExpr) (step: CExpr -> CExpr -> CExpr) =
        let acc, nv, i = fresh "acc", fresh "n", fresh "i"
        let accTy = start.ty
        let accRef = mk (CLocal acc) accTy

        let rec through (x: CExpr) (stages: Stage list) : CExpr =
            match stages with
            | [] -> mk (CAssign(acc, step accRef x)) tUnit
            | MapS f :: rest ->
                let y = fresh "x"
                let fx = beta f [ x ]
                mk (CLet(y, fx, through (mk (CLocal y) fx.ty) rest)) tUnit
            | FilterS p :: rest -> mk (CIf(beta p [ x ], through x rest, mk CUnit tUnit)) tUnit

        let x0 = fresh "x"
        let gi = beta g [ mk (CLocal i) tInt ]
        let body = mk (CLet(x0, gi, through (mk (CLocal x0) gi.ty) stages)) tUnit
        let last = mk (CBin("-", mk (CLocal nv) tInt, mk (CInt 1L) tInt)) tInt
        let forLoop = mk (CFor(i, mk (CInt 0L) tInt, mk (CInt 1L) tInt, last, body)) tUnit
        mk (CLet(nv, n, mk (CLetMut(acc, start, mk (CSeq(forLoop, accRef)) accTy)) accTy)) accTy

    let rec ex (e: CExpr) : CExpr =
        let fused =
            match call e with
            | Some("Collections.List.sum", [ xs ]) when numeric e.ty ->
                chain xs [] |> Option.map (fun (n, g, st) -> loop n g st (zeroOf e.ty) (fun a x -> mk (CBin("+", a, x)) e.ty))
            | Some("Collections.List.sumBy", [ f; xs ]) when numeric e.ty && pureLambda f 1 ->
                chain xs [] |> Option.map (fun (n, g, st) -> loop n g st (zeroOf e.ty) (fun a x -> mk (CBin("+", a, beta f [ x ])) e.ty))
            | Some("Collections.List.length", [ xs ]) ->
                chain xs [] |> Option.map (fun (n, g, st) -> loop n g st (mk (CInt 0L) tInt) (fun a _ -> mk (CBin("+", a, mk (CInt 1L) tInt)) tInt))
            | Some("Collections.List.fold", [ f; s; xs ]) when pureLambda f 2 && pure s -> // s is now evaluated after n
                chain xs [] |> Option.map (fun (n, g, st) -> loop n g st s (fun a x -> beta f [ a; x ]))
            | _ -> None

        match fused with
        | Some f -> { f with k = mapChildren ex f.k }
        | None -> { e with k = mapChildren ex e.k }

    // ponytail: only chains from List.init; a source list or array could be fused the same way
    // (a loop over it), and List.map into another list consumer (fusing into one map) too
    funs |> List.map (fun f -> { f with body = ex f.body })
