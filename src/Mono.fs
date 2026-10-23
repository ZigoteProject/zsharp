/// Monomorphization: copies each generic function once per concrete instantiation reachable
/// from main. The output has no type variables.
module Mono

open System.Collections.Generic
open Core

type MFun =
    { name: string
      pars: (string * Ty) list
      ret: Ty
      /// What the body performs (the row of the last parameter's arrow); empty after Evidence.
      row: Ty
      body: CExpr
      file: string
      line: int }

/// Units of measure are erased, so measure arguments don't distinguish instances, and an empty
/// row (a function's effects: none) isn't shown, so a pure instance has the name it always had.
let mangle (name: string) (inst: Ty list) =
    let shown =
        inst
        |> List.filter (fun t ->
            match prune t with
            | TMeas _ -> false
            | t -> not (isRowEmpty t))

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
    | TCon("span", a) -> TCon(windowType, List.map (concrete inst) a) // a window: Core's windowType
    | TCon("Buffer", a) -> TCon("ref", [ TCon(bufferType, List.map (concrete inst) a) ]) // a window that grows
    | TCon("share", [ f ]) -> concrete inst f // a function that may cross threads is a function
    | TCon(("$ext" | "$total"), _) as r -> concreteRow inst r
    | TCon(n, []) when n.StartsWith "$sk" -> tUnit // an operation's own type in its clause: no value has it
    | TCon(n, a) -> TCon(n, List.map (concrete inst) a)
    | TFun(a, b, r) -> TFun(concrete inst a, concrete inst b, concreteRow inst r)
    | TTuple ts -> TTuple(List.map (concrete inst) ts)
    | TVar _ as t -> resolve t

/// A concrete row: closed, its labels in canonical order (as resolveRow).
and private concreteRow (inst: Ty list) (r: Ty) =
    let ls, tail = rowParts r

    let more =
        match prune tail with
        | TGen i -> fst (rowParts (List.item i inst))
        | _ -> []

    mkRow (List.map (concrete inst) ls @ more |> List.sortBy labelName) rowEmpty

/// Binds TGen variables of a generic type so that it equals a concrete one.
let rec private matchTy (binds: Ty option[]) (pattern: Ty) (concrete: Ty) =
    match prune pattern, prune concrete with
    | TGen i, c -> binds[i] <- Some c
    | TCon(_, ps), TCon(_, cs)
    | TTuple ps, TTuple cs when ps.Length = cs.Length -> List.iter2 (matchTy binds) ps cs
    | TFun(a, b, r), TFun(c, d, s) ->
        matchTy binds a c
        matchTy binds b d
        matchTy binds r s
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

/// A float, or a vector of floats: what [<FastMath>]'s fast operators are for.
let private isFloaty (t: Ty) =
    match prune t with
    | TCon(n, []) -> floats.Contains n || (isVectorName n && floats.Contains(fst vectorInfo[n]))
    | _ -> false

let private isPrim (t: Ty) =
    match prune t with
    | TCon(n, []) -> prims.Contains n
    | _ -> false

/// Copies of each function reached from roots, at each instantiation reached: a generic
/// function once per type arguments, the others once. def: a function's checked definition;
/// external: a non-generic function another module has the code of, which isn't copied.
/// The program with its types' fields as monomorphization gives every other type: units of
/// measure erased, a Buffer as its cell, a span as its window. The passes after it read a
/// field's type from the table. A copy: the checker's table stays as the checker made it.
let lowered (prog: Program) : Program =
    let rec lower (t: Ty) =
        match prune t with
        | TCon(n, _) when nums.Contains n -> TCon(n, [])
        | TMeas _ -> measOne
        | TCon("Buffer", a) -> TCon("ref", [ TCon(bufferType, List.map lower a) ])
        | TCon("span", a) -> TCon(windowType, List.map lower a)
        | TCon(n, a) -> TCon(n, List.map lower a)
        | TFun(a, b, r) -> TFun(lower a, lower b, r)
        | TTuple ts -> TTuple(List.map lower ts)
        | t -> t

    let types = Dictionary<string, TypeInfo>()

    for KeyValue(n, info) in prog.types do
        types[n] <-
            { info with
                def =
                    match info.def with
                    | RecordDef fs -> RecordDef(fs |> List.map (fun (f, t) -> f, lower t))
                    | UnionDef cs -> UnionDef(cs |> List.map (fun (c, ts) -> c, List.map lower ts)) }

    { prog with types = types }

let runFrom (prog: Program) (def: string -> FunDef) (roots: string list) (external: string -> bool) : MFun list =
    let seen = HashSet<string>()
    let queue = Queue<string * Ty list>()
    let out = ResizeArray<MFun>()

    let request name inst =
        let m = mangle name inst

        // an instance another module has the code of: a non-generic function's, or the pure
        // instance (its rows empty) of one generic only in its effects
        let own = inst |> List.forall (fun t -> isRowEmpty t || (match prune t with TMeas _ -> true | _ -> false))

        if seen.Add m && not (own && external name) then
            queue.Enqueue(name, inst)

        m

    let mk k ty = { k = k; ty = ty }
    let count = ref 0

    /// The impl function (instantiated) for trait method `trait.m` at concrete type t.
    // the name an impl is kept under for a type, lowered already (concrete) or not: a span is a
    // window, a Buffer a cell over one
    let implHead (t: Ty) =
        match prune t with
        | TCon(n, _) when n = windowType -> "span"
        | TCon("ref", [ TCon(n, _) ]) when n = bufferType -> "Buffer"
        | TCon(n, _) -> n
        | TTuple ts -> tupleHead ts.Length
        | t -> showFull t

    let implFn (tr: string) (m: string) (t: Ty) (methodTy: Ty) : CExpr =
        let tn = implHead t

        match prog.impls.TryGetValue((tr, tn)) with
        | true, table ->
            let fname = table[m]
            let fd = def fname
            let binds = Array.create fd.ngen None
            matchTy binds (List.foldBack (fun (_, p) acc -> tfun p acc) fd.pars fd.ret) methodTy
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
            // a number, a string, a char or a bool differs as a whole: the prelude's diffShown
            | "Diff.diff", _ -> CApp(mk (CGlobal(request "diffShown" [ t ], Some [])) (tfun t (tfun t resTy)), args)
            | "Format.format", _ -> CPrim("format", args)
            | "Hash.hash", _ -> CPrim("hash", args)
            | _ -> Syntax.fail 0 (sprintf "%s has no built-in %s" (show t) q)

        mk k resTy

    /// A trait's methods, in the order of a dyn Trait's vtable (by name).
    let methodLists = Dictionary<string, string list>()

    let methodsOf (tr: string) =
        match methodLists.TryGetValue tr with
        | true, ms -> ms
        | _ ->
            let ms = prog.traitMethods.Values |> Seq.filter (fun m -> m.owner = tr) |> Seq.map (fun m -> m.name) |> Seq.sort |> List.ofSeq
            methodLists[tr] <- ms
            ms

    let isDyn (t: Ty) =
        match prune t with
        | TCon(n, []) -> isDynName n
        | _ -> false

    /// Trait method `q` at its instantiation, applied to args (possibly none).
    let rec dispatch (q: string) (inst: Ty list) (headTy: Ty) (args: CExpr list) (resTy: Ty) : CExpr =
        let tm = prog.traitMethods[q]
        let t = List.head inst

        let arity =
            let rec go t =
                match prune t with
                | TFun(_, r, _) -> 1 + go r
                | _ -> 0

            go headTy

        let inline' (args: CExpr list) res =
            match prune t with
            | TTuple ts -> tupleMethod q ts args res
            // a dyn value: the method its vtable has, given the value and the other arguments
            | _ when isDyn t -> mk (CPrim(sprintf "dyn.call:%d" (List.findIndex ((=) tm.name) (methodsOf tm.owner)), args)) res
            | _ -> builtinMethod q t args res

        let isTuple =
            match prune t with
            | TTuple _ -> true
            | _ -> false

        if not (isPrim t || isTuple || isDyn t) || prog.impls.ContainsKey((tm.owner, showFull t)) || prog.impls.ContainsKey((tm.owner, implHead t)) then
            let f = implFn tm.owner tm.name t headTy
            if args.IsEmpty then f else mk (CApp(f, args)) resTy
        elif args.Length = arity then
            inline' args resTy
        else
            // a built-in method used as a value: wrap it in a lambda
            let rec peel n t =
                match n, prune t with
                | 0, r -> [], r
                | n, TFun(p, r, _) ->
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

    /// The functions in the vtable of a dyn Trait over type t, one per method: each takes the dyn
    /// value and the method's other arguments, and applies t's impl to the value it holds. They
    /// are ordinary functions, so the passes after this one see them (and call the impl with as
    /// many arguments as it takes).
    let entries = HashSet<string>()

    let entryFor (tr: string) (m: string) (t: Ty) : string =
        let name = sprintf "dyn:%s#%s" (mangle tr [ t ]) m

        if entries.Add name then
            let tm = prog.traitMethods[tr + "." + m]
            let methodTy = substGen [ t; rowEmpty ] tm.ty // through dyn, the ambient row is empty (0025)

            let rec split ty =
                match prune ty with
                | TFun(a, r, _) ->
                    let ps, res = split r
                    a :: ps, res
                | r -> [], r

            let ps, res = split methodTy
            let dynTy = TCon("dyn:" + tr, [])
            let others = ps.Tail |> List.mapi (fun i p -> sprintf "$a%d" i, p)
            let value = mk (CPrim("dyn.unbox", [ mk (CLocal "$self") dynTy ])) t
            let body = dispatch (tr + "." + m) [ t ] methodTy (value :: (others |> List.map (fun (x, p) -> mk (CLocal x) p))) res

            // where it is from, for debug info: the impl's file
            let file =
                match prog.impls.TryGetValue((tr, (match prune t with TCon(n, _) -> n | t -> showFull t))) with
                | true, table -> (def table[m]).file
                | _ -> ""

            out.Add
                { name = name
                  pars = ("$self", dynTy) :: others
                  ret = res
                  row = rowEmpty
                  body = body
                  file = file
                  line = 1 }

        name

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

    // a root generic only in its effects is its pure instance
    for r in roots do
        request r (List.replicate (def r).ngen rowEmpty) |> ignore

    while queue.Count > 0 do
        let name, inst = queue.Dequeue()
        let f = def name
        let ct = concrete inst
        count.Value <- 0 // names numbered per instance: its code doesn't depend on others'

        let rec ex (e: CExpr) : CExpr =
            match e.k with
            | CPrim(op, [ v ]) when op.StartsWith "dyn.box:" ->
                // a value made a dyn Trait: its vtable's functions at the value's type
                let tr = op.Substring 8
                let t = ct v.ty
                let refs = methodsOf tr |> List.map (fun m -> mk (CPrim("fn:" + entryFor tr m t, [])) tUnit)
                mk (CPrim(op, ex v :: refs)) (ct e.ty)
            | CApp({ k = CGlobal(q, Some gi) } as h, args) when prog.traitMethods.ContainsKey q ->
                dispatch q (List.map ct gi) (ct h.ty) (List.map ex args) (ct e.ty)
            | CGlobal(q, Some gi) when prog.traitMethods.ContainsKey q -> dispatch q (List.map ct gi) (ct e.ty) [] (ct e.ty)
            // a global function opened to a row (Typer.opened) that came out its own: as it is
            | CPrim("eff.open", [ g ]) when ct g.ty = ct e.ty -> ex g
            | CBin(op, a, b) when not (isPrim (ct a.ty)) -> operator (op.Replace("wrap", "").Replace("fast", "")) (ex a) (ex b) (ct e.ty)
            | CBin(op, a, b) when op.StartsWith "fast" && not (isFloaty (ct a.ty)) ->
                ex { e with k = CBin(op.Substring 4, a, b) } // [<FastMath>]'s mark is for floats
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
                    | CPerform(l, op, args) -> CPerform(ct l, op, List.map ex args)
                    | CHandle(l, b, cls, (r, rt), rb) ->
                        let cls' = cls |> List.map (fun (op, ps, (k, kt), c) -> op, ps |> List.map (fun (x, t) -> x, ct t), (k, ct kt), ex c)
                        CHandle(ct l, ex b, cls', (r, ct rt), ex rb)
                    | k -> mapChildren ex k

                { k = k; ty = ct e.ty }

        out.Add
            { name = mangle name inst
              pars = f.pars |> List.map (fun (x, t) -> x, ct t)
              ret = ct f.ret
              row = ct f.row
              body = ex f.body
              file = f.file
              line = f.line }

    List.ofSeq out

/// The whole program from its entry points: main, the exported functions, the tests and the
/// values' initializers.
let run (prog: Program) : MFun list =
    let defs = prog.funs |> List.map (fun f -> f.name, f) |> dict

    let roots =
        (if defs.ContainsKey "main" then [ "main" ] else [])
        @ (prog.exports |> List.map (fun e -> e.fname))
        @ prog.tests
        @ (prog.values |> List.map snd)

    runFrom prog (fun n -> defs[n]) roots (fun _ -> false)

// ---- fusion: a pipeline of maps and filters over a list or an array, ending in a consumer
// (sum, sumBy, length, fold, iter), becomes one loop that builds no intermediate list or array:
//   List.init n g, a list, Array.init n g or an array
//   |> map f |> filter p … (List's or Array's)
//   |> sum / sumBy f / length / fold f s / iter f
// A pipeline of several maps and filters that builds a list (or of maps building an array) is
// one pass building that list or array.
// The stages run per element instead of per list, so their functions must be pure lambdas
// (arithmetic, comparisons, local bindings, conditionals): running them in another order can't
// change what the program does. A consumer's function that does something else (iter's,
// usually) still sees the elements in order; the stages must then be unable to panic, so no
// effect of the consumer happens that a panic in a stage would have prevented.

/// What a function reaches that threads can't share: the first top-level value of a type that
/// isn't Share it uses, following its calls (and the local functions it calls), with the
/// functions on the way there, its own first. external: what another module's code says of its
/// functions (Driver's ABI); unknown functions reach nothing.
let reaching (prog: Program) (funs: MFun list) (external: string -> (string * string list * Ty) option) =
    let byName = funs |> List.map (fun f -> f.name, f) |> dict
    // the values of let-bound locals and local functions, by unique name, per function: one
    // that calls a function it captured runs that one's code
    let locals = Dictionary<string, Dictionary<string, CExpr>>()

    let localsOf (f: MFun) =
        match locals.TryGetValue f.name with
        | true, d -> d
        | _ ->
            let d = Dictionary<string, CExpr>()

            let rec collect (e: CExpr) =
                match e.k with
                | CLetFun(n, _, ps, b, _) -> d[n] <- { k = CLam(ps, b); ty = e.ty }
                | CLetRec(fs, _) ->
                    for n, ps, b in fs do
                        d[n] <- { k = CLam(ps, b); ty = e.ty }
                | CLet(x, v, _) -> d[x] <- v
                | _ -> ()

                children e.k |> List.iter collect

            collect f.body
            locals[f.name] <- d
            d

    let memo = Dictionary<string, (string * string list * Ty) option>()
    let visiting = HashSet<string>()
    // the functions the outermost walk has gone through and found nothing in: a walk that meets
    // one again doesn't walk it again (so a walk is linear, whatever cycles it meets), and when
    // the outermost walk ends with nothing, each of them reaches nothing. A walk meeting a
    // function it's inside of takes nothing from it: what that one reaches, that walk finds.
    let nothingYet = HashSet<string>()

    /// What an expression of function f reaches (f's locals, for the local functions it calls).
    let rec inExpr (mine: Dictionary<string, CExpr>) (seen: HashSet<string>) (e: CExpr) : (string * string list * Ty) option =
        let here =
            match e.k with
            | CGlobalVal x ->
                match shareBlocker ignore prog.types Set.empty e.ty with
                | Some _ -> Some(x, [], e.ty)
                | None -> None
            | CGlobal(g, _) -> through g
            | CPrim(p, _) when p.StartsWith "fn:" -> through (p.Substring 3)
            | CLocal x ->
                match prune e.ty, mine.TryGetValue x with
                | TFun _, (true, v) when seen.Add x -> inExpr mine seen v
                | _ -> None
            | _ -> None

        match here with
        | Some r -> Some r
        | None -> children e.k |> List.tryPick (inExpr mine seen)

    /// What calling g reaches, g on the way.
    and through (g: string) =
        reach g |> Option.map (fun (x, path, t) -> x, (g.Split('<')[0]) :: path, t)

    and reach (g: string) =
        match memo.TryGetValue g with
        | true, r -> r
        | _ when nothingYet.Contains g -> None
        | _ ->
            match byName.TryGetValue g with
            | true, f when visiting.Add g ->
                let r = inExpr (localsOf f) (HashSet()) f.body
                visiting.Remove g |> ignore

                match r with
                | Some _ -> memo[g] <- r
                | None -> nothingYet.Add g |> ignore

                if visiting.Count = 0 then
                    // the outermost walk: with nothing found, nothing was there to find
                    if r.IsNone then
                        for h in nothingYet do
                            memo[h] <- None

                    nothingYet.Clear()

                r
            | true, _ -> None
            | _ -> external g

    reach, (fun (f: MFun) (e: CExpr) -> inExpr (localsOf f) (HashSet()) e)

/// A function given to another thread (share.fn, from the type checker) mustn't reach a
/// top-level value threads can't share, such as a `ref`: each thread would change it at once.
/// Checked through what the function calls, after monomorphization so that every trait method
/// call has its impl (and other modules' functions by what their code says, external); then
/// the marks go.
let checkSharedWith (prog: Program) (external: string -> (string * string list * Ty) option) (funs: MFun list) : MFun list =
    let _, inExpr = reaching prog funs external

    let check (f: MFun) (line: int) (start: CExpr) =
        match inExpr f start with
        | Some(x, path, t) ->
            let through = if path.IsEmpty then "" else sprintf " (through %s)" (path |> List.map (sprintf "'%s'") |> String.concat ", ")
            let part = shareBlocker ignore prog.types Set.empty t |> Option.defaultValue t
            let holds = if part = t then "" else sprintf ", which holds %s" (show part)

            raise (Syntax.CompileErrorAt(f.file, line, 0, sprintf "this function crosses threads, but it uses the top-level value '%s'%s : %s%s, which threads can't share; pass it what it needs instead" x through (show t) holds))
        | None -> ()

    let rec strip (f: MFun) (line: int) (e: CExpr) : CExpr =
        match e.k with
        | CLine(l, _) -> { e with k = mapChildren (strip f l) e.k }
        | CPrim("share.fn", [ g ]) ->
            check f line g
            strip f line g
        | CPrim("share.as", [ g ]) -> strip f line g
        | k -> { e with k = mapChildren (strip f line) k }

    funs |> List.map (fun f -> { f with body = strip f f.line f.body })

let checkShared (prog: Program) (funs: MFun list) : MFun list = checkSharedWith prog (fun _ -> None) funs

type private Stage =
    | MapS of CExpr
    | FilterS of CExpr

type private Source =
    | Init of n: CExpr * g: CExpr // List.init n g / Array.init n g
    | OfList of CExpr
    | OfArray of CExpr

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

    // a function with effects is called as it is: its stages would run inside a loop with none
    let rec pureFor n (t: Ty) =
        n = 0
        || (match prune t with
            | TFun(_, r, row) -> isRowEmpty row && pureFor (n - 1) r
            | _ -> false)

    let call (e: CExpr) =
        match e.k with
        | CApp({ k = CGlobal(g, _) } as h, args) when pureFor args.Length h.ty -> Some(baseName g, args)
        | _ -> None

    let isInt (t: Ty) =
        match prune t with
        | TCon(n, []) -> ints.Contains n
        | _ -> false

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

    /// Pure, and can't panic: no checked integer arithmetic (it traps on overflow), no division
    /// that could be by zero.
    let rec total (e: CExpr) =
        pure e
        && (match e.k with
            | CBin(("+" | "-" | "*"), a, _) when isInt a.ty -> false
            | CBin(("/" | "%"), a, b) when isInt a.ty ->
                match b.k with
                | CInt d -> d <> 0L && d <> -1L
                | _ -> false
            | CNeg a when isInt a.ty -> false
            | k -> children k |> List.forall total)

    let lambda (e: CExpr) arity =
        match e.k with
        | CLam(ps, body) when ps.Length = arity -> Some body
        | _ -> None

    let pureLambda (e: CExpr) arity = lambda e arity |> Option.exists pure

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

    let elemOf (t: Ty) =
        match prune t with
        | TCon(("list" | "array"), [ el ]) -> el
        | TCon(n, [ el ]) when n = windowType -> el // a span: read as an array is
        | TCon("ref", [ TCon(n, [ el ]) ]) when n = bufferType -> el // a Buffer
        | t -> failwithf "fusion: %s has no elements" (show t)

    /// The pipeline under a consumer of a list (or an array): its stages, in order, and its source.
    let rec chain (isArray: bool) (xs: CExpr) (stages: Stage list) : Source * Stage list =
        let m = if isArray then "Collections.Array." else "Collections.List."

        match call xs with
        | _ when isArray && (match xs.k with
                             | CPrim(("span.ofArray" | "span.ofBuffer"), _) -> true
                             | _ -> false) ->
            // an array as a span: its elements are the span's
            match xs.k with
            | CPrim(_, [ a ]) -> chain isArray a stages
            | _ -> failwith "unreachable"
        | Some(f, [ g; ys ]) when f = m + "map" && pureLambda g 1 -> chain isArray ys (MapS g :: stages)
        | Some(f, [ p; ys ]) when f = m + "filter" && pureLambda p 1 -> chain isArray ys (FilterS p :: stages)
        | Some(f, [ n; g ]) when f = m + "init" && pureLambda g 1 -> Init(n, g), stages
        | Some("Collections.Array.toList", [ a ]) when not isArray -> OfArray a, stages
        | _ -> (if isArray then OfArray xs else OfList xs), stages

    /// Worth a loop of its own: a source that builds a list or array, or a stage to run.
    let fusible (src: Source) (stages: Stage list) =
        match src with
        | Init _ -> true
        | OfArray _ -> not stages.IsEmpty
        | OfList _ -> not stages.IsEmpty

    let stagesTotal (stages: Stage list) =
        stages
        |> List.forall (fun s ->
            match s with
            | MapS f
            | FilterS f -> (lambda f 1).Value |> total)

    /// The stages applied to element x: `keep y` for an element that survives them, `skip ()`
    /// for one a filter drops.
    let rec through (x: CExpr) (stages: Stage list) (keep: CExpr -> CExpr) (skip: unit -> CExpr) : CExpr =
        match stages with
        | [] -> keep x
        | MapS f :: rest ->
            let y = fresh "x"
            let fx = beta f [ x ]
            let inner = through (mk (CLocal y) fx.ty) rest keep skip
            mk (CLet(y, fx, inner)) inner.ty
        | FilterS p :: rest ->
            let inner = through x rest keep skip
            mk (CIf(beta p [ x ], inner, skip ())) inner.ty

    /// The surviving elements folded: acc starts as `start`, then acc <- step acc y for each.
    let foldOver (src: Source) (stages: Stage list) (start: CExpr) (step: CExpr -> CExpr -> CExpr) : CExpr =
        let accTy = start.ty

        match src with
        | OfList xs ->
            // a local function over the list's cells, as the library's own folds (a loop after
            // compilation): acc is a parameter, since a local function can't share a mutable
            let go, acc, cur, rest = fresh "go", fresh "acc", fresh "xs", fresh "rest"
            let accRef = mk (CLocal acc) accTy
            let x = fresh "x"
            let el = elemOf xs.ty
            let again (a: CExpr) = mk (CApp(mk (CLocal go) (tfun accTy (tfun xs.ty accTy)), [ a; mk (CLocal rest) xs.ty ])) accTy

            let body =
                mk
                    (CMatch(
                        mk (CLocal cur) xs.ty,
                        [ CPCtor("list", 0, []), None, accRef
                          CPCtor("list", 1, [ CPVar(x, el); CPVar(rest, xs.ty) ]),
                          None,
                          through (mk (CLocal x) el) stages (fun y -> again (step accRef y)) (fun () -> again accRef) ]
                    ))
                    accTy

            mk (CLetRec([ go, [ acc, accTy; cur, xs.ty ], body ], mk (CApp(mk (CLocal go) (tfun accTy (tfun xs.ty accTy)), [ start; xs ])) accTy)) accTy
        | Init _
        | OfArray _ ->
            let acc, nv, i = fresh "acc", fresh "n", fresh "i"
            let accRef = mk (CLocal acc) accTy

            // the count, then (for an array) the array itself, in the order the program has them
            let count, element, bind =
                match src with
                | Init(n, g) -> n, (fun (iv: CExpr) -> beta g [ iv ]), id
                | OfArray a ->
                    let av = fresh "a"
                    let aRef = mk (CLocal av) a.ty
                    mk (CPrim("Array.length", [ aRef ])) tInt, (fun iv -> mk (CPrim("array.get", [ aRef; iv ])) (elemOf a.ty)), (fun (e: CExpr) -> mk (CLet(av, a, e)) e.ty)
                | OfList _ -> failwith "unreachable"

            let x0 = fresh "x"
            let gi = element (mk (CLocal i) tInt)
            let body = mk (CLet(x0, gi, through (mk (CLocal x0) gi.ty) stages (fun y -> mk (CAssign(acc, step accRef y)) tUnit) (fun () -> mk CUnit tUnit))) tUnit
            let last = mk (CBin("-", mk (CLocal nv) tInt, mk (CInt 1L) tInt)) tInt
            let forLoop = mk (CFor(i, mk (CInt 0L) tInt, mk (CInt 1L) tInt, last, body)) tUnit
            bind (mk (CLet(nv, count, mk (CLetMut(acc, start, mk (CSeq(forLoop, accRef)) accTy)) accTy)) accTy)

    /// The surviving elements as a list, built in one pass.
    let listOf (src: Source) (stages: Stage list) (resTy: Ty) : CExpr =
        let el = elemOf resTy
        let nil = mk (CCtor("list", 0, [])) resTy
        let cons (y: CExpr) (tl: CExpr) = mk (CCtor("list", 1, [ y; tl ])) resTy

        match src with
        | Init(n, g) ->
            // from the last element down, so no reversing (the stages are pure)
            let acc, nv, i, x0 = fresh "acc", fresh "n", fresh "i", fresh "x"
            let accRef = mk (CLocal acc) resTy
            let gi = beta g [ mk (CLocal i) tInt ]
            let body = mk (CLet(x0, gi, through (mk (CLocal x0) gi.ty) stages (fun y -> mk (CAssign(acc, cons y accRef)) tUnit) (fun () -> mk CUnit tUnit))) tUnit
            let last = mk (CBin("-", mk (CLocal nv) tInt, mk (CInt 1L) tInt)) tInt
            let forLoop = mk (CFor(i, last, mk (CInt -1L) tInt, mk (CInt 0L) tInt, body)) tUnit
            mk (CLet(nv, n, mk (CLetMut(acc, nil, mk (CSeq(forLoop, accRef)) resTy)) resTy)) resTy
        | _ ->
            // reversed as it's built, then reversed again: both in place when the cells are unique
            let reversed = foldOver src stages nil (fun acc y -> cons y acc)
            let rv, out, cur, y, rest = fresh "rev", fresh "out", fresh "ys", fresh "y", fresh "rest"
            let rvTy = tfun resTy (tfun resTy resTy)
            let again = mk (CApp(mk (CLocal rv) rvTy, [ cons (mk (CLocal y) el) (mk (CLocal out) resTy); mk (CLocal rest) resTy ])) resTy

            let body =
                mk
                    (CMatch(
                        mk (CLocal cur) resTy,
                        [ CPCtor("list", 0, []), None, mk (CLocal out) resTy
                          CPCtor("list", 1, [ CPVar(y, el); CPVar(rest, resTy) ]), None, again ]
                    ))
                    resTy

            mk (CLetRec([ rv, [ out, resTy; cur, resTy ], body ], mk (CApp(mk (CLocal rv) rvTy, [ nil; reversed ])) resTy)) resTy

    /// Maps over an array (or Array.init) as one array: Array.init's loop with the maps inside.
    let arrayOf (src: Source) (stages: Stage list) (resTy: Ty) : CExpr =
        let el = elemOf resTy
        let nv, r, i = fresh "n", fresh "r", fresh "i"

        let count, element, bind =
            match src with
            | Init(n, g) -> n, (fun (iv: CExpr) -> beta g [ iv ]), id
            | OfArray a ->
                let av = fresh "a"
                let aRef = mk (CLocal av) a.ty
                mk (CPrim("Array.length", [ aRef ])) tInt, (fun iv -> mk (CPrim("array.get", [ aRef; iv ])) (elemOf a.ty)), (fun (e: CExpr) -> mk (CLet(av, a, e)) e.ty)
            | OfList _ -> failwith "unreachable"

        let mapped (iv: CExpr) = through (element iv) stages id (fun () -> failwith "a filter building an array")
        let n = mk (CLocal nv) tInt
        let first = mk (CPrim("Array.create", [ n; mapped (mk (CInt 0L) tInt) ])) resTy
        let set = mk (CArraySet(r, mk (CLocal i) tInt, mapped (mk (CLocal i) tInt))) tUnit
        let last = mk (CBin("-", n, mk (CInt 1L) tInt)) tInt
        let fill = mk (CFor(i, mk (CInt 1L) tInt, mk (CInt 1L) tInt, last, set)) tUnit
        let filled = mk (CLetMut(r, first, mk (CSeq(fill, mk (CLocal r) resTy)) resTy)) resTy
        let empty = mk (CPrim("array.lit", [])) resTy
        let isEmpty = mk (CBin("<=", n, mk (CInt 0L) tInt)) tBool
        bind (mk (CLet(nv, count, mk (CIf(isEmpty, empty, filled)) resTy)) resTy)

    let rec ex (e: CExpr) : CExpr =
        let consume (isArray: bool) (xs: CExpr) (pureStep: bool) (k: Source -> Stage list -> CExpr) =
            let src, stages = chain isArray xs []
            // a consumer whose function may do anything needs stages that can't panic
            if fusible src stages && (pureStep || stagesTotal stages) then Some(k src stages) else None

        let fused =
            match call e with
            | Some(("Collections.List.sum" | "Collections.Array.sum") as f, [ xs ]) when numeric e.ty ->
                consume (f.Contains "Array") xs true (fun src st -> foldOver src st (zeroOf e.ty) (fun a x -> mk (CBin("+", a, x)) e.ty))
            | Some("Collections.List.sumBy", [ f; xs ]) when numeric e.ty && pureLambda f 1 ->
                consume false xs true (fun src st -> foldOver src st (zeroOf e.ty) (fun a x -> mk (CBin("+", a, beta f [ x ])) e.ty))
            | Some("Collections.List.length", [ xs ]) ->
                consume false xs true (fun src st -> foldOver src st (mk (CInt 0L) tInt) (fun a _ -> mk (CBin("+", a, mk (CInt 1L) tInt)) tInt))
            | Some(("Collections.List.fold" | "Collections.Array.fold") as fn, [ f; s; xs ]) when pureLambda f 2 && pure s -> // s is now evaluated after n
                consume (fn.Contains "Array") xs true (fun src st -> foldOver src st s (fun a x -> beta f [ a; x ]))
            | Some(("Collections.List.iter" | "Collections.Array.iter") as fn, [ f; xs ]) ->
                // the function is evaluated first, as the call would; a lambda is applied in place
                let isArray = fn.Contains "Array"
                let pureF = pureLambda f 1

                consume isArray xs pureF (fun src st ->
                    match lambda f 1 with
                    | Some _ -> foldOver src st (mk CUnit tUnit) (fun _ x -> beta f [ x ])
                    | None ->
                        let fv = fresh "f"
                        let apply x = mk (CApp(mk (CLocal fv) f.ty, [ x ])) tUnit
                        mk (CLet(fv, f, foldOver src st (mk CUnit tUnit) (fun _ x -> apply x))) tUnit)
            | Some(("Collections.List.map" | "Collections.List.filter"), [ g; _ ]) when pureLambda g 1 ->
                // a pipeline of several stages building a list
                let src, stages = chain false e []

                let worth =
                    match src with
                    | Init _ -> true
                    | _ -> stages.Length >= 2

                if worth then Some(listOf src stages e.ty) else None
            | Some("Collections.Array.map", [ g; _ ]) when pureLambda g 1 ->
                // maps building an array
                let src, stages = chain true e []

                let maps =
                    stages
                    |> List.forall (fun s ->
                        match s with
                        | MapS _ -> true
                        | FilterS _ -> false)

                let worth =
                    match src with
                    | Init _ -> true
                    | _ -> stages.Length >= 2

                if maps && worth then Some(arrayOf src stages e.ty) else None
            | _ -> None

        match fused with
        | Some f -> { f with k = mapChildren ex f.k }
        | None -> { e with k = mapChildren ex e.k }

    funs
    |> List.map (fun f ->
        count.Value <- 0 // per function, as Mono's names
        { f with body = ex f.body })
