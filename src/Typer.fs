/// Type inference: Hindley-Milner with kinded variables (int literals, numeric operators),
/// let-polymorphism for top-level functions, and lowering to Core IR.
module Typer

open System.Collections.Generic
open Syntax
open Core

exception private Mismatch
exception private NoImpl of string * Ty // trait, type

let private kindOf (r: TV ref) =
    match r.Value with
    | Unbound(_, k) -> k
    | Link _ -> kAny

/// Checks whether a type implements a trait through a user impl (set by `check`), pushing the
/// impl's own requirements onto the type's arguments.
let mutable private userImpl: string -> Ty -> bool = fun _ _ -> false

/// Both constraints at once. Literal kinds keep only the types that also have the traits.
let private meet (a: Kind) (b: Kind) : Kind =
    let traits = Set.union a.traits b.traits

    let allowed =
        match a.allowed, b.allowed with
        | None, k
        | k, None -> k
        | Some x, Some y -> Some(Set.intersect x y)

    let has tr n =
        hasBuiltinImpl tr n || userImpl tr (tcon n)

    match allowed with
    | Some s ->
        let ok = s |> Set.filter (fun n -> traits |> Set.forall (fun tr -> has tr n))

        if s.IsEmpty then
            raise Mismatch
        elif ok.IsEmpty then
            let tr = traits |> Seq.find (fun tr -> s |> Set.forall (fun n -> not (has tr n)))
            raise (NoImpl(tr, tcon (if s.Contains "int" then "int" elif s.Contains "f64" then "f64" else Seq.head s)))
        else
            { allowed = Some ok; traits = traits }
    | None -> { allowed = None; traits = traits }

let rec private occurs r t =
    match prune t with
    | TVar r2 -> obj.ReferenceEquals(r, r2)
    | TCon(_, ts)
    | TTuple ts -> List.exists (occurs r) ts
    | TFun(a, b) -> occurs r a || occurs r b
    | TMeas(_, vs) -> vs |> List.exists (fst >> occurs r)
    | TGen _ -> false

/// Unifies two units of measure (Kennedy): solve a/b = 1 for the variable with the smallest
/// exponent, when every other exponent is divisible by it.
let private unifyMeas (a: Ty) (b: Ty) =
    match normMeas (measDiv a b) with
    | [], [] -> ()
    | _, [] -> raise Mismatch
    | us, vs ->
        let v, e = vs |> List.minBy (snd >> abs)
        let others = vs |> List.filter (fun (w, _) -> not (obj.ReferenceEquals(w, v)))
        let divisible = (us |> List.forall (fun (_, k) -> k % e = 0)) && (others |> List.forall (fun (_, k) -> k % e = 0))

        match prune v with
        | TVar r when divisible ->
            // v^e * rest = 1  =>  v = rest^(-1/e)
            r.Value <- Link(TMeas(us |> List.map (fun (u, k) -> u, -k / e), others |> List.map (fun (w, k) -> w, -k / e)))
        | _ -> raise Mismatch // ponytail: Kennedy's general case (a fresh variable) hasn't been needed yet

let private satisfies (k: Kind) t =
    let allowedOk =
        match k.allowed, t with
        | None, _ -> true
        | Some s, TCon(n, []) -> s.Contains n
        | _ -> false

    allowedOk
    && k.traits
       |> Set.forall (fun tr ->
           let ok =
               match t with
               | TCon(n, []) when hasBuiltinImpl tr n -> true
               | TCon(n, [ TMeas _ ]) when hasBuiltinImpl tr n -> true
               | _ -> userImpl tr t

           if not ok then
               raise (NoImpl(tr, t))

           true)

let rec private unify a b =
    match prune a, prune b with
    | TVar r1, TVar r2 when obj.ReferenceEquals(r1, r2) -> ()
    | TVar r1, TVar r2 ->
        let k = meet (kindOf r1) (kindOf r2)

        match r2.Value with
        | Unbound(id, _) -> r2.Value <- Unbound(id, k)
        | Link _ -> ()

        r1.Value <- Link(TVar r2)
    | TVar r, t
    | t, TVar r ->
        if occurs r t || not (satisfies (kindOf r) t) then
            raise Mismatch

        r.Value <- Link t
    | TCon(a, xs), TCon(b, ys) when a = b && nums.Contains a -> unifyMeas (measOf xs) (measOf ys)
    | TMeas _, _
    | _, TMeas _ -> unifyMeas a b
    | TCon(a, xs), TCon(b, ys) when a = b && xs.Length = ys.Length -> List.iter2 unify xs ys
    | TFun(a1, b1), TFun(a2, b2) ->
        unify a1 a2
        unify b1 b2
    | TTuple xs, TTuple ys when xs.Length = ys.Length -> List.iter2 unify xs ys
    | TGen i, TGen j when i = j -> ()
    | _ -> raise Mismatch

let private expect what expected actual =
    try
        unify expected actual
    with
    | Mismatch -> fail 0 (sprintf "%s: expected %s, got %s" what (show expected) (show actual))
    | NoImpl(tr, t) -> fail 0 (sprintf "%s: %s does not implement %s" what (show t) tr)

/// Quantifies the unbound variables of a top-level function's type (linking them to TGen).
let private generalize (t: Ty) : Kind list =
    let found = ResizeArray<TV ref * Kind>()

    let rec go t =
        match prune t with
        | TVar r ->
            match r.Value with
            | Unbound(_, k) when not (found.Exists(fun (r2, _) -> obj.ReferenceEquals(r, r2))) -> found.Add(r, k)
            | _ -> ()
        | TCon(_, ts)
        | TTuple ts -> List.iter go ts
        | TFun(a, b) ->
            go a
            go b
        | TMeas(_, vs) -> vs |> List.iter (fst >> go)
        | TGen _ -> ()

    go t
    found |> Seq.iteri (fun i (r, _) -> r.Value <- Link(TGen i))
    found |> Seq.map snd |> List.ofSeq

let private funTy (ps: Ty list) (ret: Ty) = List.foldBack (fun p acc -> TFun(p, acc)) ps ret

/// Splits a function type into its first n parameter types and the rest.
let rec private peel n t =
    match n, prune t with
    | 0, t -> [], t
    | n, TFun(a, b) ->
        let ps, r = peel (n - 1) b
        a :: ps, r
    | _ -> failwith "peel: not a function type"

type private Builtin =
    { prim: string
      kinds: Kind list
      ty: Ty
      arity: int }

let private builtins =
    let a = TGen 0
    let f x y = TFun(x, y)

    let b name prim kinds ty arity =
        name,
        { prim = prim
          kinds = kinds
          ty = ty
          arity = arity }

    dict (
        [ b "ignore" "ignore" [ kAny ] (f a tUnit) 1
          b "panic" "panic" [ kAny ] (f tStr a) 1
          b "failwith" "panic" [ kAny ] (f tStr a) 1
          b "assert" "assert" [] (f tBool tUnit) 1
          b "print" "print" [] (f tStr tUnit) 1
          b "println" "println" [] (f tStr tUnit) 1
          b "String.length" "String.length" [] (f tStr tInt) 1
          b "String.ofCStr" "String.ofCStr" [] (f tCStr tStr) 1
          b "String.sub" "String.sub" [] (f tStr (f tInt (f tInt tStr))) 3
          b "String.byte" "String.byte" [] (f tStr (f tInt (tcon "u8"))) 2
          b "String.ofByte" "String.ofByte" [] (f (tcon "u8") tStr) 1
          b "String.indexOfFrom" "String.indexOfFrom" [] (f tStr (f tStr (f tInt tInt))) 3
          b "String.trim" "String.trim" [] (f tStr tStr) 1
          b "String.toUpper" "String.toUpper" [] (f tStr tStr) 1
          b "String.toLower" "String.toLower" [] (f tStr tStr) 1
          b "String.replace" "String.replace" [] (f tStr (f tStr (f tStr tStr))) 3
          b "String.isFloat" "String.isFloat" [] (f tStr tBool) 1
          b "String.toFloat" "String.toFloat" [] (f tStr (tcon "f64")) 1
          b "Console.readLineRaw" "Console.readLineRaw" [] (f tUnit tStr) 1
          b "Console.eof" "Console.eof" [] (f tUnit tBool) 1
          b "eprintln" "eprintln" [] (f tStr tUnit) 1
          b "ref" "ref" [ kAny ] (f a (TCon("ref", [ a ]))) 1
          b "Array.create" "Array.create" [ kAny ] (f tInt (f a (TCon("array", [ a ])))) 2
          b "Array.set" "array.update" [ kAny ] (f (TCon("array", [ a ])) (f tInt (f a (TCon("array", [ a ]))))) 3
          b "Buffer.create" "Array.create" [ kAny ] (f tInt (f a (TCon("Buffer", [ a ])))) 2
          b "Buffer.length" "Array.length" [ kAny ] (f (TCon("Buffer", [ a ])) tInt) 1
          b "Buffer.ofArray" "array.copy" [ kAny ] (f (TCon("array", [ a ])) (TCon("Buffer", [ a ]))) 1
          b "Buffer.toArray" "array.copy" [ kAny ] (f (TCon("Buffer", [ a ])) (TCon("array", [ a ]))) 1
          b "Int.wrappingAdd" "wrap+" [ kInt ] (f a (f a a)) 2
          b "Int.wrappingSub" "wrap-" [ kInt ] (f a (f a a)) 2
          b "Int.wrappingMul" "wrap*" [ kInt ] (f a (f a a)) 2
          b "Runtime.allocations" "Runtime.allocations" [] (f tUnit tInt) 1
          b "Process.exit" "Process.exit" [ kAny ] (f tInt a) 1
          b "Env.argc" "Env.argc" [] (f tUnit tInt) 1
          b "Env.arg" "Env.arg" [] (f tInt tStr) 1
          b "Env.has" "Env.has" [] (f tStr tBool) 1
          b "Env.get" "Env.get" [] (f tStr tStr) 1
          b "Io.ok" "Io.ok" [] (f tUnit tBool) 1
          b "Io.error" "Io.error" [] (f tUnit tStr) 1
          b "File.readRaw" "File.readRaw" [] (f tStr tStr) 1
          b "File.writeRaw" "File.writeRaw" [] (f tStr (f tStr tUnit)) 2
          b "File.appendRaw" "File.appendRaw" [] (f tStr (f tStr tUnit)) 2
          b "File.exists" "File.exists" [] (f tStr tBool) 1
          b "File.deleteRaw" "File.deleteRaw" [] (f tStr tUnit) 1
          b "Dir.exists" "Dir.exists" [] (f tStr tBool) 1
          b "Dir.createRaw" "Dir.createRaw" [] (f tStr tUnit) 1
          b "Dir.listRaw" "Dir.listRaw" [] (f tStr tStr) 1
          b "Process.runRaw" "Process.runRaw" [] (f tStr (f tStr tStr)) 2
          b "Process.code" "Process.code" [] (f tUnit tInt) 1
          b "Array.length" "Array.length" [ kAny ] (f (TCon("array", [ a ])) tInt) 1 ]
        @ [ for t in Seq.append nums [ "i64"; "float"; "c_int" ] ->
                let target =
                    match typeAliases.TryGetValue t with
                    | true, c -> c
                    | _ -> t

                b t "conv" [ kNumeric ] (f a (tcon target)) 1 ]
    )

type private Local =
    { u: string // unique name in Core
      ty: Ty
      mut: bool
      depth: int } // closure nesting depth where it is bound

type private MemberInfo =
    { gname: string // the function implementing it
      isStatic: bool
      isProperty: bool
      mpars: MemberParam list }

type private Global =
    { mutable ty: Ty
      mutable kinds: Kind list
      arity: int
      mutable defining: bool }

/// modules: (file, module name, declarations) in dependency order; the prelude and the main
/// file have no module name (their declarations are global).
/// collect: report every declaration's error (editors) instead of stopping at the first.
let check (requireMain: bool) (collect: bool) (modules: (string * string option * (int * Decl) list) list) : Program =
    let decls = modules |> List.collect (fun (_, _, ds) -> ds)
    let types = Dictionary<string, TypeInfo>()
    let ctors = Dictionary<string, string * int>() // constructor -> union, tag
    let fieldOwner = Dictionary<string, string>() // field -> last record declaring it
    let records = ResizeArray<string>() // record types in declaration order
    let recordDefaults = Dictionary<string, Expr option list>() // record -> default per field
    let ctorFieldNames = Dictionary<string, string option list>() // constructor -> field names
    let members = Dictionary<string, Dictionary<string, MemberInfo>>() // type -> member name -> info
    let traitMethods = Dictionary<string, TraitMethod>() // "Show.show" -> method
    let traitAliases = Dictionary<string, string>() // "show" -> "Show.show"
    let impls = Dictionary<string * string, Dictionary<string, string>>() // (trait, type) -> method -> function
    let implRequires = Dictionary<string * string, Set<string> list>() // traits each type argument needs
    let derives = Dictionary<string, (int * string * Param list * SType option * Expr) list>()
    // active pattern case -> (function, total?, number of parameters before the value)
    let activePatterns = Dictionary<string, string * bool * int>()
    let apCtors = HashSet<string>() // cases of total active patterns: payload optional
    let manualImpls = HashSet<string * string>()
    let optOut = HashSet<string * string>() // [<NoEquality>] / [<NoComparison>]
    let mutable autoDerive: string -> string -> bool = fun _ _ -> false // set once derives can run

    userImpl <-
        fun tr t ->
            match prune t with
            | TCon(n, args) ->
                if not (implRequires.ContainsKey((tr, n))) then
                    autoDerive tr n |> ignore

                match implRequires.TryGetValue((tr, n)) with
                | true, reqs ->
                    for a, trs in List.zip args reqs do
                        for tr2 in trs do
                            unify (fresh (kTrait tr2)) a

                    true
                | _ -> false
            | TTuple ts when List.contains tr [ "Eq"; "Ord"; "Show"; "Hash" ] ->
                // tuples have structural Eq/Ord/Show/Hash when their components do
                for a in ts do
                    unify (fresh (kTrait tr)) a

                true
            | _ -> false
    let globals = Dictionary<string, Global>()
    let externs = Dictionary<string, ExternSig>()
    let funs = ResizeArray<FunDef>()
    let tyvars = Dictionary<string, Ty>() // 'a in the current function's annotations
    let counter = ref 0
    let measures = HashSet<string>() // [<Measure>] types
    let diagnostics = ResizeArray<Diagnostic>()
    let hovers = ResizeArray<Hover>()
    let currentFile = ref ""
    let currentLine = ref 0 // of the expression being inferred (assert messages)

    /// Remembers the type at a node's source position, and what the name refers to.
    let recordKey (node: obj) (name: string) (t: Ty) (inlay: bool) (key: string) (isDef: bool) =
        match positions.TryGetValue node with
        | true, (l, c, len) ->
            hovers.Add
                { hfile = currentFile.Value
                  hline = l
                  hcol = c
                  hlen = max len name.Length
                  name = name
                  hty = t
                  constraints = ""
                  decl = false
                  key = key
                  isDef = isDef
                  inlay = inlay }
        | _ -> ()

    let record (node: obj) (name: string) (t: Ty) (inlay: bool) = recordKey node name t inlay "" false

    /// Errors raised while checking a positioned node (a name, call or field) point at it.
    let at (node: obj) (f: unit -> 'r) : 'r =
        try
            f ()
        with CompileError(0, msg) when positions.ContainsKey node ->
            let l, c, _ = positions[node]
            raise (CompileErrorPos(l, c, msg))

    let colOf (node: obj) =
        match positions.TryGetValue node with
        | true, (_, c, _) -> c
        | _ -> 0

    /// Parameters that are plain names, with their types.
    let recordParams (orig: Param list) (pars: (string * string * Ty) list) =
        if orig.Length = pars.Length then
            List.iter2
                (fun (p: Pat, ann: SType option) (_, u, t) ->
                    match p with
                    | PIdent(x, None) -> recordKey p x t ann.IsNone u true
                    | _ -> ())
                orig
                pars
    let clayouts = HashSet<string>() // [<CLayout>] records
    let exports = ResizeArray<Export>()
    let tests = ResizeArray<string>()
    let consts = Dictionary<string, Expr>() // C constants from import c
    let currentModule = ref (None: string option)
    let opens = ref ([]: string list) // most recent first
    let privates = Dictionary<string, string option>() // qualified name -> owning module
    let moduleNames = modules |> List.choose (fun (_, m, _) -> m) |> Set.ofList

    /// The name a declaration gets in the current module.
    let qualify (name: string) =
        match currentModule.Value with
        | Some m -> m + "." + name
        | None -> name

    /// Unqualified names resolve in the current module, then opened modules, then globally.
    let resolveWith (exists: string -> bool) (x: string) : string option =
        let candidates =
            [ match currentModule.Value with
              | Some m -> yield m + "." + x
              | None -> ()
              for o in opens.Value do
                  yield o + "." + x
              yield x ]

        candidates
        |> List.tryFind exists
        |> Option.map (fun q ->
            match privates.TryGetValue q with
            | true, owner when owner <> currentModule.Value ->
                fail 0 (sprintf "'%s' is private to module %s" x (defaultArg owner "?"))
            | _ -> q)

    types["list"] <-
        { npars = 1
          def = UnionDef [ "[]", []; "::", [ TGen 0; TCon("list", [ TGen 0 ]) ] ] }

    ctors["[]"] <- ("list", 0)
    ctors["::"] <- ("list", 1)
    ctorFieldNames["[]"] <- []
    ctorFieldNames["::"] <- [ Some "head"; Some "tail" ]

    let uniq (x: string) =
        counter.Value <- counter.Value + 1
        sprintf "%s.%d" x counter.Value

    let mk k ty = { k = k; ty = ty }

    /// tparams: Some names inside a type definition (they become TGen), None in a function.
    let rec toTy (tparams: string list option) st =
        match st with
        | STVar v ->
            match tparams with
            | Some ps ->
                match List.tryFindIndex ((=) v) ps with
                | Some i -> TGen i
                | None -> fail 0 (sprintf "unknown type parameter '%s" v)
            | None ->
                match tyvars.TryGetValue v with
                | true, t -> t
                | _ ->
                    let t = fresh kAny
                    tyvars[v] <- t
                    t
        | STName(n, args) ->
            let n =
                match typeAliases.TryGetValue n with
                | true, c -> c
                | _ -> n

            let n =
                resolveWith (fun q -> prims.Contains q || builtinCons.ContainsKey q || types.ContainsKey q) n
                |> Option.defaultValue n

            let arity =
                if nums.Contains n && (match args with
                                       | [ STMeasure _ ] -> true
                                       | _ -> false) then 1
                elif prims.Contains n then 0
                elif builtinCons.ContainsKey n then builtinCons[n]
                elif types.ContainsKey n then types[n].npars
                else fail 0 (sprintf "unknown type '%s'" n)

            if arity <> args.Length then
                fail 0 (sprintf "type '%s' expects %d type argument(s)" n arity)

            match n, args with
            | n, [ m ] when nums.Contains n -> numWith n (toTy tparams m)
            | _ -> TCon(n, List.map (toTy tparams) args)
        | STTuple ts -> TTuple(List.map (toTy tparams) ts)
        | STFun(a, b) -> TFun(toTy tparams a, toTy tparams b)
        | STMeasure terms ->
            let units, vars = terms |> List.partition (fun (_, isVar, _) -> not isVar)

            for u, _, _ in units do
                if not (measures.Contains u) then
                    fail 0 (sprintf "unknown unit of measure '%s'; declare it with [<Measure>] type %s" u u)

            TMeas(
                normMeas (
                    TMeas(
                        units |> List.map (fun (u, _, e) -> u, e),
                        vars |> List.map (fun (v, _, e) -> toTy tparams (STVar v), e)
                    )
                )
            )

    let annot ann =
        match ann with
        | Some st -> toTy None st
        | None -> fresh kAny

    let instantiate (kinds: Kind list) (t: Ty) =
        let vars = kinds |> List.map fresh
        substGen vars t, vars

    /// A user type applied to fresh type arguments.
    let instType name =
        let args = List.init types[name].npars (fun _ -> fresh kAny)
        TCon(name, args), args

    let ctorName (c: string) = resolveWith ctors.ContainsKey c
    let isCtor (c: string) = (ctorName c).IsSome

    let caseFields u tag args =
        match types[u].def with
        | UnionDef cs -> snd cs[tag] |> List.map (substGen args)
        | RecordDef _ -> []

    let unionCases u =
        match types[u].def with
        | UnionDef cs -> cs |> List.map (fun (n, ts) -> n, ts.Length)
        | RecordDef _ -> []

    let recordOf (t: Ty) (field: string) =
        match prune t with
        | TCon(n, _) when (match types.TryGetValue n with
                           | true, { def = RecordDef _ } -> true
                           | _ -> false) -> n
        | _ ->
            match fieldOwner.TryGetValue field with
            | true, r -> r
            | _ -> fail 0 (sprintf "no record has a field '%s'" field)

    let fieldsOf r =
        match types[r].def with
        | RecordDef fs -> fs
        | UnionDef _ -> []

    /// Matches a constructor's arguments to its payload fields: `C`, `C x`, `C (x, y)`.
    let ctorArgs c (args: 'a list) (fields: Ty list) (tuple: 'a -> 'a list option) (wild: 'a option) =
        match args, fields with
        | [], [] -> []
        | [ a ], fs when fs.Length > 1 && (tuple a |> Option.exists (fun xs -> xs.Length = fs.Length)) -> (tuple a).Value
        | [ a ], fs when fs.Length > 1 && wild = Some a -> List.map (fun _ -> a) fs
        | [ a ], [ _ ] -> [ a ]
        | _ -> fail 0 (sprintf "constructor '%s' expects %d argument(s)" c fields.Length)

    /// Non-variable parameters become fresh names matched against their pattern in the body.
    let lowerParams (ps: Param list) (body: Expr) =
        let named =
            ps
            |> List.mapi (fun i (p, ann) ->
                match p with
                | PIdent(x, None) when not (isCtor x) -> (x, ann), None
                | _ ->
                    let x = sprintf "$p%d" i
                    (x, ann), Some(x, p))

        let body =
            List.foldBack
                (fun (_, m) acc ->
                    match m with
                    | Some(x, p) -> Match(Var x, [ p, None, acc ])
                    | None -> acc)
                named
                body

        List.map fst named, body

    let rec pat (names: Dictionary<string, string>) (p: Pat) (ty: Ty) : CPat =
        let name x =
            match names.TryGetValue x with
            | true, u -> u
            | _ ->
                let u = uniq x
                names[x] <- u
                u

        match p with
        | PWild -> CPWild
        | PUnit ->
            expect "pattern" ty tUnit
            CPWild
        | PInt n ->
            expect "pattern" ty (fresh kInt)
            CPInt n
        | PBool b ->
            expect "pattern" ty tBool
            CPBool b
        | PIdent(c, arg) when isCtor c ->
            let c = (ctorName c).Value
            let u, tag = ctors[c]
            let uty, targs = instType u
            expect "pattern" ty uty
            let fields = caseFields u tag targs

            let subs =
                match arg with
                | None when apCtors.Contains c -> [ PWild ]
                | Some(PArgs _) -> fail 0 (sprintf "constructor '%s' takes one argument pattern" c)
                | Some(PNamed named) ->
                    let names = ctorFieldNames[c]

                    for n, _ in named do
                        if not (List.contains (Some n) names) then
                            fail 0 (sprintf "constructor '%s' has no field '%s'" c n)

                    names
                    |> List.map (fun n ->
                        match named |> List.tryFind (fun (m, _) -> Some m = n) with
                        | Some(_, p) -> p
                        | None -> PWild)
                | _ ->
                    ctorArgs c (Option.toList arg) fields (function
                        | PTuple ps -> Some ps
                        | _ -> None) (Some PWild)

            CPCtor(u, tag, List.map2 (pat names) subs fields)
        | PIdent(x, None) ->
            let u = name x
            recordKey p x ty true u true
            CPVar(u, ty)
        | PIdent(c, Some _) -> fail 0 (sprintf "unknown constructor '%s'" c)
        | PTuple ps ->
            let ts = ps |> List.map (fun _ -> fresh kAny)
            expect "pattern" ty (TTuple ts)
            CPTuple(List.map2 (pat names) ps ts)
        | POr(a, b) ->
            let ca, cb = pat names a ty, pat names b ty
            let va, vb = patVars ca, patVars cb

            if List.sort (List.map fst va) <> List.sort (List.map fst vb) then
                fail 0 "both sides of '|' must bind the same variables"

            for x, t in va do
                expect "or-pattern variable" t (vb |> List.find (fst >> (=) x) |> snd)

            CPOr(ca, cb)
        | PAs(p, x) -> CPAs(pat names p ty, name x, ty)
        | PNamed _ -> fail 0 "named field patterns need a constructor: C(field = p)"
        | PArgs _ -> fail 0 "only constructors and active patterns take arguments"

    let rec infer (env: Map<string, Local>) (depth: int) (e: Expr) : CExpr =
        let inf = infer env depth
        let node = e

        match e with
        | At(ln, e) ->
            currentLine.Value <- ln

            try
                let c = infer env depth e
                mk (CLine(ln, c)) c.ty
            with CompileError(0, msg) ->
                raise (CompileErrorPos(ln, colOf node, msg))
        | Lit n -> mk (CInt n) (fresh kInt)
        | FloatLit f -> mk (CFloat f) (fresh kFloat)
        | BoolLit b -> mk (CBool b) tBool
        | StrLit s -> mk (CStr s) (fresh kStrLit)
        | UnitLit -> mk CUnit tUnit
        | Var x ->
            let r = at node (fun () -> value env depth x)
            recordKey node x r.ty false (keyOf env x) false
            r
        | Call("assert", [ c ]) when not (env.ContainsKey "assert") ->
            // the location goes into the message: "assertion failed at file:line"
            let cc = infer env depth c
            expect "assert" tBool cc.ty
            let file = if currentFile.Value = "prelude.zs" then "prelude.zs" else System.IO.Path.GetFileName currentFile.Value
            mk (CPrim(sprintf "assert:%s:%d" file currentLine.Value, [ cc ])) tUnit
        | Call(f, args) ->
            let r = at node (fun () -> call env depth f args)

            let headTy =
                match r.k with
                | CApp(h, _) -> h.ty
                | CExtern(name, _) when externs.ContainsKey name -> // a C function: its declared type
                    let x = externs[name]
                    List.foldBack (fun a acc -> TFun(a, acc)) (if x.pars.IsEmpty then [ tUnit ] else x.pars) x.ret
                | _ -> r.ty

            recordKey node f headTy false (keyOf env f) false
            r
        | App((Field(r, f) as fe), args) ->
            let cr = inf r
            settle cr.ty

            match memberOf cr.ty f with
            | Some(m: MemberInfo) when not m.isStatic && not m.isProperty ->
                let res = memberCall env depth m (Some cr) args f
                recordKey fe f res.ty false m.gname false
                res
            | _ -> apply env depth (field cr f) args None
        | App(h, args) -> apply env depth (inf h) args None
        | Lambda(ps0, body) ->
            let ps, body = lowerParams ps0 body
            let pars = ps |> List.map (fun (x, ann) -> x, uniq x, annot ann)
            recordParams ps0 pars

            let envB =
                pars
                |> List.fold
                    (fun (m: Map<_, _>) (x, u, t) ->
                        m.Add(
                            x,
                            { u = u
                              ty = t
                              mut = false
                              depth = depth + 1 }
                        ))
                    env

            let cb = infer envB (depth + 1) body
            let ptys = pars |> List.map (fun (_, _, t) -> t)
            mk (CLam(pars |> List.map (fun (_, u, t) -> u, t), cb)) (funTy ptys cb.ty)
        | LetFun(name, isRec, ps0, ret, body, rest) ->
            let ps, body = lowerParams ps0 body
            let pars = ps |> List.map (fun (x, ann) -> x, uniq x, annot ann)
            recordParams ps0 pars
            let rty = annot ret
            let fty = funTy (pars |> List.map (fun (_, _, t) -> t)) rty

            let self =
                { u = uniq name
                  ty = fty
                  mut = false
                  depth = depth }

            let envB =
                pars
                |> List.fold
                    (fun (m: Map<_, _>) (x, u, t) ->
                        m.Add(
                            x,
                            { u = u
                              ty = t
                              mut = false
                              depth = depth + 1 }
                        ))
                    (if isRec then env.Add(name, self) else env)

            let cb = infer envB (depth + 1) body
            expect (sprintf "result of '%s'" name) rty cb.ty
            recordKey node name fty false self.u true
            let cr = infer (env.Add(name, self)) depth rest
            mk (CLetFun(self.u, isRec, pars |> List.map (fun (_, u, t) -> u, t), cb, cr)) cr.ty
        | Let(PIdent(x, None) as p, ann, v, rest) when not (isCtor x) ->
            let cv =
                match ann with
                | Some a -> inferHint env depth (toTy None a) v
                | None -> inf v

            let u = uniq x
            recordKey p x cv.ty ann.IsNone u true
            ann |> Option.iter (fun a -> expect (sprintf "value of '%s'" x) (toTy None a) cv.ty)

            let l =
                { u = u
                  ty = cv.ty
                  mut = false
                  depth = depth }

            let cr = infer (env.Add(x, l)) depth rest
            mk (CLet(l.u, cv, cr)) cr.ty
        | Let(p, ann, v, rest) ->
            if ann.IsSome then
                fail 0 "type annotations on patterns are not supported yet"

            inf (Match(v, [ p, None, rest ]))
        | LetMut(x, ann, v, rest) ->
            let cv = inf v
            ann |> Option.iter (fun a -> expect (sprintf "value of '%s'" x) (toTy None a) cv.ty)

            let l =
                { u = uniq x
                  ty = cv.ty
                  mut = true
                  depth = depth }

            let cr = infer (env.Add(x, l)) depth rest
            mk (CLetMut(l.u, cv, cr)) cr.ty
        | Assign(lhs, rhs) ->
            match lhs with
            | Var x ->
                match env.TryFind x with
                | Some l when l.mut ->
                    if l.depth < depth then
                        fail 0 (sprintf "mutable variable '%s' cannot be captured by a closure; use a ref cell" x)

                    let cv = inf rhs
                    expect (sprintf "value assigned to '%s'" x) l.ty cv.ty
                    mk (CAssign(l.u, cv)) tUnit
                | Some _ -> fail 0 (sprintf "'%s' is not mutable; declare it with 'let mutable'" x)
                | None -> fail 0 (sprintf "unknown name '%s'" x)
            | Index(a, i) ->
                let ca = inf a

                match prune ca.ty, a with
                | TCon("Buffer", _), _ ->
                    // a Buffer is a shared reference: the write is seen through every alias
                    let ci = inf i
                    let cv = inf rhs
                    expect "Buffer" (TCon("Buffer", [ cv.ty ])) ca.ty
                    expect "index" tInt ci.ty
                    mk (CPrim("array.set", [ ca; ci; cv ])) tUnit
                | _, Var x when (match env.TryFind x with
                                 | Some l -> l.mut
                                 | None -> false) ->
                    let l = env[x]

                    if l.depth < depth then
                        fail 0 (sprintf "mutable variable '%s' cannot be captured by a closure; use a ref cell" x)

                    let ci = inf i
                    let cv = inf rhs
                    expect "array" (TCon("array", [ cv.ty ])) l.ty
                    expect "array index" tInt ci.ty
                    mk (CArraySet(l.u, ci, cv)) tUnit
                | _ ->
                    fail
                        0
                        "arrays are values: to change one, declare it with `let mutable a = …` and write `a.[i] <- x`, or use `Array.set a i x`, which returns the changed array (Buffer<'a> is the shared mutable alternative)"
            | Field(r, "Value") ->
                let cr = inf r
                let cv = inf rhs
                expect "ref cell" (TCon("ref", [ cv.ty ])) cr.ty
                mk (CPrim("ref.set", [ cr; cv ])) tUnit
            | Field _ -> fail 0 "record fields are immutable; use { r with field = ... }"
            | _ -> fail 0 "only mutable variables, array elements and ref cells can be assigned"
        | While(c, b) ->
            let cc = inf c
            expect "condition of 'while'" tBool cc.ty
            let cb = inf b
            expect "body of 'while'" tUnit cb.ty
            mk (CWhile(cc, cb)) tUnit
        | For(x, a, step, b, body) ->
            let it = fresh kInt
            let ca = inf a
            expect "start of 'for' range" it ca.ty
            let cb = inf b
            expect "end of 'for' range" it cb.ty

            let cs =
                match step with
                | Some s ->
                    let cs = inf s
                    expect "step of 'for' range" it cs.ty
                    cs
                | None -> mk (CInt 1L) it

            let l =
                { u = uniq x
                  ty = it
                  mut = false
                  depth = depth }

            let cbody = infer (env.Add(x, l)) depth body
            expect "body of 'for'" tUnit cbody.ty
            mk (CFor(l.u, ca, cs, cb, cbody)) tUnit
        | Index(a, i) ->
            let ca = inf a
            let ci = inf i
            let el = fresh kAny

            let container =
                match prune ca.ty with
                | TCon("Buffer", _) -> "Buffer"
                | _ -> "array"

            expect "indexing" (TCon(container, [ el ])) ca.ty
            expect "array index" tInt ci.ty
            mk (CPrim("array.get", [ ca; ci ])) el
        | ArrayLit xs ->
            let el = fresh kAny

            let cs =
                xs
                |> List.map (fun x ->
                    let c = inf x
                    expect "array element" el c.ty
                    c)

            mk (CPrim("array.lit", cs)) (TCon("array", [ el ]))
        | Measured(e, m) ->
            let ce = inf e
            settle ce.ty

            match prune ce.ty with
            | TCon(n, []) when nums.Contains n -> { ce with ty = numWith n (toTy None m) }
            | t -> fail 0 (sprintf "only numbers have units, not %s" (show t))
        | Bin(("*" | "/") as op, a, b) ->
            let ca = inf a
            let cb = inf b

            if measuredOperands ca cb then
                measuredBin op ca cb
            else
                arith op ca cb
        | Bin(op, a, b) -> arith op (inf a) (inf b)
        | Neg a ->
            let ca = inf a
            expect "operand of '-'" (fresh (kTrait "Num")) ca.ty
            mk (CNeg ca) ca.ty
        | Not a ->
            let ca = inf a
            expect "operand of 'not'" tBool ca.ty
            mk (CNot ca) tBool
        | If(c, t, e) ->
            let cc = inf c
            expect "condition of 'if'" tBool cc.ty
            let ct = inf t

            match e with
            | None ->
                expect "'if' without 'else'" tUnit ct.ty
                mk (CIf(cc, ct, mk CUnit tUnit)) tUnit
            | Some e ->
                let ce = inf e
                expect "'else' branch" ct.ty ce.ty
                mk (CIf(cc, ct, ce)) ct.ty
        | Seq(a, b) ->
            let ca = inf a
            let cb = inf b
            mk (CSeq(ca, cb)) cb.ty
        | Tuple xs ->
            let cs = List.map inf xs
            mk (CTuple cs) (TTuple(cs |> List.map (fun c -> c.ty)))
        | RecordLit fields -> recordLit env depth None fields
        | Update(r, fields) ->
            let cr = inf r
            let rname = recordOf cr.ty (fst fields.Head)
            let rty, targs = instType rname
            expect "record update" rty cr.ty
            let tmp = uniq "$r"
            let defs = fieldsOf rname

            let built =
                buildRecord env depth rname targs fields (fun i _ ->
                    mk (CField(mk (CLocal tmp) cr.ty, i)) (substGen targs (snd defs[i])))

            mk (CLet(tmp, cr, built)) built.ty
        | Field(r, f) ->
            let cr = inf r
            let res = at node (fun () -> field cr f)

            let key =
                match memberOf cr.ty f with
                | Some m -> m.gname
                | None -> ""

            recordKey node f res.ty false key false
            res
        | Question _ -> fail 0 "'?' is only supported as `let x = e?` or as a whole statement (for now)"
        | DeriveCtx(ctx, e) ->
            try
                inf e
            with
            | CompileError(l, msg) -> fail l (sprintf "%s: %s" ctx msg)
            | CompileErrorPos(l, c, msg) -> raise (CompileErrorPos(l, c, sprintf "%s: %s" ctx msg))
        | ForIn(x, xs, body) ->
            let cxs = inf xs
            settle cxs.ty

            let coll =
                { u = uniq "$coll"
                  ty = cxs.ty
                  mut = false
                  depth = depth }

            let env' = env.Add("$coll", coll)

            let loop =
                match prune cxs.ty with
                | TCon(("array" | "Buffer") as c, _) ->
                    let len = if c = "array" then "Array.length" else "Buffer.length"
                    For("$i", Lit 0L, None, Bin("-", Call(len, [ Var "$coll" ]), Lit 1L), Let(PIdent(x, None), None, Index(Var "$coll", Var "$i"), body))
                | TCon("list", _) ->
                    // a while loop over a cursor, so the body may assign outer mutable variables
                    LetMut(
                        "$cur",
                        None,
                        Var "$coll",
                        LetMut(
                            "$go",
                            None,
                            BoolLit true,
                            While(
                                Var "$go",
                                Match(
                                    Var "$cur",
                                    [ PIdent("::", Some(PTuple [ PIdent(x, None); PIdent("$rest", None) ])),
                                      None,
                                      Seq(Assign(Var "$cur", Var "$rest"), body)
                                      PIdent("[]", None), None, Assign(Var "$go", BoolLit false) ]
                                )
                            )
                        )
                    )
                | t -> fail 0 (sprintf "'for ... in' needs a list or an array, not %s" (show t))

            let cl = infer env' depth loop
            expect "body of 'for'" tUnit cl.ty
            mk (CLet(coll.u, cxs, cl)) tUnit
        | TryBind(p, e, rest) ->
            // match e with Ok p -> rest | Error err -> Error err
            let ce = inf e
            let okTy, er = fresh kAny, fresh kAny
            let resTy = TCon("result", [ okTy; er ])
            expect "operand of '?'" resTy ce.ty
            let names = Dictionary<string, string>()
            let okTag, errTag = snd ctors["Ok"], snd ctors["Error"]
            let cp = CPCtor("result", okTag, [ pat names p okTy ])
            let vars = patVars cp

            let envOk =
                names
                |> Seq.fold
                    (fun (m: Map<_, _>) kv ->
                        m.Add(
                            kv.Key,
                            { u = kv.Value
                              ty = vars |> List.find (fst >> (=) kv.Value) |> snd
                              mut = false
                              depth = depth }
                        ))
                    env

            let crest = infer envOk depth rest

            try
                unify (TCon("result", [ fresh kAny; er ])) crest.ty
            with Mismatch | NoImpl _ ->
                let ers =
                    match prune er with
                    | TVar _ -> "_"
                    | t -> show t

                fail 0 (sprintf "'?' needs the rest of the block to produce a result<_, %s>, but it produces %s" ers (show crest.ty))

            let eu = uniq "$err"
            let errCase = CPCtor("result", errTag, [ CPVar(eu, er) ]), None, mk (CCtor("result", errTag, [ mk (CLocal eu) er ])) crest.ty
            let cases = [ (cp, None, crest); errCase ]
            Match.check unionCases apCtors.Contains (cases |> List.map (fun (p, _, _) -> p, false))
            mk (CMatch(ce, cases)) crest.ty
        | Match(s, cases) when
            not (isActiveCall s) && cases |> List.exists (fun (p: Pat, _, _) -> (activeOf p).IsSome)
            ->
            inf (desugarActive s cases)
        | Match(s, cases) ->
            let cs = inf s
            let resTy = fresh kAny

            let ccases =
                cases
                |> List.map (fun (p, guard, body) ->
                    let names = Dictionary<string, string>()
                    let cp = pat names p cs.ty
                    let vars = patVars cp

                    if (vars |> List.map fst |> List.distinct).Length <> vars.Length then
                        fail 0 "a variable is bound twice in this pattern"

                    let env =
                        names
                        |> Seq.fold
                            (fun (m: Map<_, _>) kv ->
                                m.Add(
                                    kv.Key,
                                    { u = kv.Value
                                      ty = vars |> List.find (fst >> (=) kv.Value) |> snd
                                      mut = false
                                      depth = depth }
                                ))
                            env

                    let cg =
                        guard
                        |> Option.map (fun g ->
                            let cg = infer env depth g
                            expect "'when' guard" tBool cg.ty
                            cg)

                    let cb = infer env depth body
                    expect "match case" resTy cb.ty
                    cp, cg, cb)

            Match.check unionCases apCtors.Contains (ccases |> List.map (fun (p, g, _) -> p, g.IsSome))
            mk (CMatch(cs, ccases)) resTy

    /// * and / on numbers with units: the units multiply and divide; a unitless literal
    /// operand is dimensionless.
    and measuredBin (op: string) (ca: CExpr) (cb: CExpr) : CExpr =

        let numPart t =
            match prune t with
            | TCon(n, ms) when nums.Contains n -> Some(n, measOf ms)
            | _ -> None

        for x, other in [ ca, cb; cb, ca ] do
            match prune x.ty, numPart other.ty with
            | TVar r, Some(n, _) when (kindOf r).allowed.IsSome -> expect (sprintf "operand of '%s'" op) (TCon(n, [])) x.ty
            | _ -> ()

        match numPart ca.ty, numPart cb.ty with
        | Some(n1, m1), Some(n2, m2) when n1 = n2 ->
            mk (CBin(op, ca, cb)) (numWith n1 (if op = "*" then measMul m1 m2 else measDiv m1 m2))
        | _ -> fail 0 (sprintf "operands of '%s' must be numbers of the same type: %s and %s" op (show ca.ty) (show cb.ty))

    /// An operator through its trait: + Add, - * / % Num, = <> Eq, < > <= >= Ord.
    and arith (op: string) (ca: CExpr) (cb: CExpr) : CExpr =
        let isArith = List.contains op [ "+"; "-"; "*"; "/"; "%" ]

        let tr =
            match op with
            | "+" -> "Add"
            | "-"
            | "*"
            | "/"
            | "%" -> "Num"
            | "="
            | "<>" -> "Eq"
            | _ -> "Ord"

        try
            unify (fresh (kTrait tr)) ca.ty
        with
        | Mismatch
        | NoImpl _ -> fail 0 (sprintf "operator '%s' does not support type %s (it needs %s)" op (show ca.ty) tr)

        expect (sprintf "right operand of '%s'" op) ca.ty cb.ty
        mk (CBin(op, ca, cb)) (if isArith then ca.ty else tBool)

    /// Does either operand carry a unit of measure (so * and / combine units)?
    and measuredOperands (ca: CExpr) (cb: CExpr) =
        let measured t =
            match prune t with
            | TCon(n, [ TMeas _ ]) when nums.Contains n -> true
            | _ -> false

        measured ca.ty || measured cb.ty

    /// A literal-constrained type variable takes its default before a member lookup.
    and settle (t: Ty) =
        match prune t with
        | TVar r when (kindOf r).allowed.IsSome -> resolve t |> ignore
        | _ -> ()

    /// `e.f` once e is typed: ref cell, record field, or property member.
    and field (cr: CExpr) (f: string) : CExpr =
        settle cr.ty

        let isField =
            match prune cr.ty with
            | TCon(n, _) when records.Contains n -> fieldsOf n |> List.exists (fst >> (=) f)
            | _ -> false

        match prune cr.ty, memberOf cr.ty f with
        | TCon("ref", [ a ]), _ when f = "Value" -> mk (CPrim("ref.get", [ cr ])) a
        | _, Some m when not isField ->
            if m.isStatic then
                fail 0 (sprintf "'%s' is a static member; use %s.%s" f (typeName cr.ty) f)
            elif m.isProperty then
                memberCall Map.empty 0 m (Some cr) [] f
            else
                fail 0 (sprintf "method '%s' must be called: x.%s(...)" f f)
        | TVar _, _ when f = "Value" && not (fieldOwner.ContainsKey f) ->
            let a = fresh kAny
            expect "ref cell" (TCon("ref", [ a ])) cr.ty
            mk (CPrim("ref.get", [ cr ])) a
        | TVar _, _ when not (fieldOwner.ContainsKey f) ->
            fail 0 (sprintf "cannot resolve '.%s': the type of this expression isn't known here; add a type annotation" f)
        | _ ->
            let rname = recordOf cr.ty f
            let rty, targs = instType rname
            expect (sprintf "field '%s'" f) rty cr.ty
            let defs = fieldsOf rname

            match defs |> List.tryFindIndex (fst >> (=) f) with
            | Some i -> mk (CField(cr, i)) (substGen targs (snd defs[i]))
            | None -> fail 0 (sprintf "%s has no field or member '%s'" (show cr.ty) f)

    and typeName (t: Ty) =
        match prune t with
        | TCon(n, _) -> n
        | t -> show t

    and memberOf (t: Ty) (f: string) : MemberInfo option =
        match prune t with
        | TCon(n, _) ->
            match members.TryGetValue n with
            | true, table ->
                match table.TryGetValue f with
                | true, m -> Some m
                | _ -> None
            | _ -> None
        | _ -> None

    /// `T.M` names a static member?
    and staticMember (name: string) : MemberInfo option =
        let i = name.LastIndexOf '.'

        if i <= 0 then
            None
        else
            let t = name.Substring(0, i)

            let t =
                match typeAliases.TryGetValue t with
                | true, c -> c
                | _ -> t

            let t = resolveWith members.ContainsKey t |> Option.defaultValue t

            match members.TryGetValue t with
            | true, table ->
                match table.TryGetValue(name.Substring(i + 1)) with
                | true, m when m.isStatic -> Some m
                | _ -> None
            | _ -> None

    /// A member call. Arguments: positional, then `name = value`; missing optional ones take
    /// their default (evaluated here, seeing earlier parameters) or None.
    and memberCall env depth (m: MemberInfo) (self: CExpr option) (args: Expr list) (what: string) : CExpr =
        let g = globals[m.gname]

        let head =
            if g.defining then
                mk (CGlobal(m.gname, None)) g.ty
            else
                let t, inst = instantiate g.kinds g.ty
                mk (CGlobal(m.gname, Some inst)) t

        let nself = if self.IsSome then 1 else 0
        let arity = max 1 (nself + m.mpars.Length)
        let ptys, resTy = peel arity head.ty
        let mptys = ptys |> List.skip nself

        match self with
        | Some c -> expect (sprintf "receiver of '%s'" what) (List.head ptys) c.ty
        | None -> ()

        let args =
            match args with
            | [ Tuple xs ] -> xs
            | [ UnitLit ] -> []
            | xs -> xs

        let paramIndex n = m.mpars |> List.tryFindIndex (fun p -> p.mname = n)

        let isNamed a =
            match a with
            | Bin("=", Var n, _) -> (paramIndex n).IsSome
            | _ -> false

        let positional = args |> List.takeWhile (isNamed >> not)
        let named = args |> List.skip positional.Length

        if named |> List.exists (isNamed >> not) then
            fail 0 (sprintf "in a call to '%s', positional arguments must come before named ones" what)

        if positional.Length > m.mpars.Length then
            fail 0 (sprintf "'%s' takes %d argument(s), got %d" what m.mpars.Length positional.Length)

        let bindings = ResizeArray<string * CExpr>()
        let given = Dictionary<string, string * Ty>()

        let bindTemp (ce: CExpr) =
            let tmp = uniq "$m"
            bindings.Add(tmp, ce)
            tmp

        let selfArg = self |> Option.map (fun c -> mk (CLocal(bindTemp c)) c.ty)

        let bind i (a: Expr) =
            let p = List.item i m.mpars
            let pt = List.item i mptys

            if given.ContainsKey p.mname then
                fail 0 (sprintf "argument '%s' of '%s' is given twice" p.mname what)

            let ce =
                if p.optional && p.mdefault.IsNone then
                    // the body sees option<T>; a given argument arrives as Some
                    let inner =
                        match prune pt with
                        | TCon("option", [ t ]) -> t
                        | _ -> fresh kAny

                    let c = inferHint env depth inner a
                    expect (sprintf "argument '%s' of '%s'" p.mname what) inner c.ty
                    let u, tag = ctors["Some"]
                    mk (CCtor(u, tag, [ c ])) pt
                else
                    let c = inferHint env depth pt a
                    expect (sprintf "argument '%s' of '%s'" p.mname what) pt c.ty
                    c

            given[p.mname] <- (bindTemp ce, ce.ty)

        positional |> List.iteri bind

        for a in named do
            match a with
            | Bin(_, Var n, v) -> bind (paramIndex n).Value v
            | _ -> ()

        let mutable scope = Map.empty

        let argTemps =
            m.mpars
            |> List.mapi (fun i p ->
                let pt = List.item i mptys

                let tmp, ty =
                    match given.TryGetValue p.mname with
                    | true, v -> v
                    | _ ->
                        let ce =
                            match p.optional, p.mdefault with
                            | true, Some d ->
                                let c = inferHint scope 0 pt d
                                expect (sprintf "default of '%s'" p.mname) pt c.ty
                                c
                            | true, None ->
                                let u, tag = ctors["None"]
                                mk (CCtor(u, tag, [])) pt
                            | false, _ -> fail 0 (sprintf "'%s' is missing argument '%s'" what p.mname)

                        bindTemp ce, pt

                scope <-
                    scope.Add(
                        p.mname,
                        { u = tmp
                          ty = ty
                          mut = false
                          depth = 0 }
                    )

                mk (CLocal tmp) ty)

        let callArgs = Option.toList selfArg @ argTemps
        let callArgs = if callArgs.IsEmpty then [ mk CUnit tUnit ] else callArgs
        let call = mk (CApp(head, callArgs)) resTy
        List.foldBack (fun (tmp, ce: CExpr) acc -> mk (CLet(tmp, ce, acc)) acc.ty) (List.ofSeq bindings) call

    /// `A.B.c.d` lexed as one name: the longest prefix that resolves, then field accesses.
    and splitQualified (env: Map<string, Local>) (x: string) : Expr option =
        let parts = x.Split '.'

        let resolves (n: string) =
            env.ContainsKey n || consts.ContainsKey n || (resolveName n).IsSome

        seq { parts.Length - 1 .. -1 .. 1 }
        |> Seq.tryPick (fun k ->
            let prefix = String.concat "." parts[.. k - 1]

            if resolves prefix then
                Some(parts[k..] |> Array.fold (fun e f -> Field(e, f)) (Var prefix))
            else
                None)

    /// A trait method, instantiated; its type parameter must implement the trait.
    and traitMethod (x: string) : CExpr =
        let tm = traitMethods[traitAliases[x]]
        let t, inst = instantiate [ kTrait tm.owner ] tm.ty
        let qname = tm.owner + "." + tm.name

        if tm.isConst then
            mk (CApp(mk (CGlobal(qname, Some inst)) (TFun(tUnit, t)), [ mk CUnit tUnit ])) t
        else
            mk (CGlobal(qname, Some inst)) t

    /// The active pattern a case pattern uses at its top: (function, total?, args, case, value pattern).
    and activeOf (p: Pat) : (string * bool * Expr list * string * Pat option) option =
        let name, arg =
            match p with
            | PIdent(c, arg) -> Some c, arg
            | _ -> None, None

        match name |> Option.bind (resolveWith activePatterns.ContainsKey) with
        | Some c ->
            let fn, total, nargs = activePatterns[c]

            let atoms =
                match arg with
                | Some(PArgs ps) -> ps
                | Some p -> [ p ]
                | None -> []

            if atoms.Length < nargs then
                fail 0 (sprintf "active pattern '%s' needs %d argument(s)" c nargs)

            let toExpr p =
                match p with
                | PInt n -> Lit n
                | PBool b -> BoolLit b
                | PUnit -> UnitLit
                | PIdent(x, None) -> Var x
                | _ -> fail 0 "active pattern arguments must be literals or names"

            let args = atoms |> List.take nargs |> List.map toExpr

            let value =
                match List.skip nargs atoms with
                | [] -> None
                | [ v ] -> Some v
                | _ -> fail 0 (sprintf "too many patterns after active pattern '%s'" c)

            Some(fn, total, args, c, value)
        | None -> None

    /// A match whose cases use active patterns becomes a chain of plain matches, in case order:
    /// a run of ordinary cases matches the value; a run of one total active pattern matches its
    /// result; a partial one matches Some value. Each falls through (`_`) to the rest.
    and desugarActive (s: Expr) cases : Expr =
        let sv = uniq "$ap"

        let rec chain cases =
            let fallback rest =
                if List.isEmpty rest then [] else [ PWild, None, chain rest ]

            match cases with
            | [] -> failwith "unreachable"
            | (p, _, _) :: _ when (activeOf p).IsNone ->
                let group = cases |> List.takeWhile (fun (p, _, _) -> (activeOf p).IsNone)
                let rest = List.skip group.Length cases
                Match(Var sv, group @ fallback rest)
            | (p, g, b) :: rest ->
                let fn, total, args, c, value = (activeOf p).Value
                let call = Call(fn, args @ [ Var sv ])

                if total then
                    let same (p, _, _) =
                        match activeOf p with
                        | Some(fn2, true, args2, _, _) -> fn2 = fn && args2 = args
                        | _ -> false

                    let group = cases |> List.takeWhile same
                    let rest = List.skip group.Length cases

                    let cases' =
                        group
                        |> List.map (fun (p, g, b) ->
                            let _, _, _, c, value = (activeOf p).Value
                            PIdent(c, value), g, b)

                    Match(call, cases' @ fallback rest)
                else
                    if rest.IsEmpty then
                        fail 0 (sprintf "active pattern '%s' can fail; add a case after it" c)

                    Match(call, [ PIdent("Some", Some(defaultArg value PWild)), g, b ] @ fallback rest)

        Let(PIdent(sv, None), None, s, chain cases)

    /// A match on an active pattern function's result (made by desugarActive) uses its cases directly.
    and isActiveCall (e: Expr) =
        match e with
        | Call(f, _) -> activePatterns.Values |> Seq.exists (fun (fn, _, _) -> fn = f)
        | _ -> false

    /// What a name refers to, for go-to-definition: a local's unique name or a global's.
    and keyOf (env: Map<string, Local>) (x: string) =
        match env.TryFind x with
        | Some l -> l.u
        | None -> resolveName x |> Option.defaultValue ""

    and resolveName (x: string) : string option =
        resolveWith
            (fun q ->
                globals.ContainsKey q || ctors.ContainsKey q || traitAliases.ContainsKey q || builtins.ContainsKey q
                || externs.ContainsKey q || (staticMember q).IsSome)
            x

    and value env depth x : CExpr =
        match env.TryFind x, resolveName x with
        | None, Some q when q <> x -> value' env depth q
        | _ -> value' env depth x

    and value' env depth x : CExpr =
        match env.TryFind x with
        | None when consts.ContainsKey x -> infer env depth consts[x]
        | Some l ->
            if l.mut && l.depth < depth then
                fail 0 (sprintf "mutable variable '%s' cannot be captured by a closure; use a ref cell" x)

            mk (CLocal l.u) l.ty
        | None ->
            match globals.TryGetValue x with
            | _ when not (globals.ContainsKey x) && (staticMember x).IsSome ->
                let m = (staticMember x).Value

                if m.isProperty then
                    memberCall env depth m None [] x
                else
                    fail 0 (sprintf "static method '%s' must be called: %s(...)" x x)
            | true, g when g.defining -> mk (CGlobal(x, None)) g.ty
            | true, g ->
                let t, inst = instantiate g.kinds g.ty
                mk (CGlobal(x, Some inst)) t
            | _ ->
                if ctors.ContainsKey x then
                    let u, tag = ctors[x]
                    let uty, targs = instType u

                    match caseFields u tag targs with
                    | [] -> mk (CCtor(u, tag, [])) uty
                    | [ ft ] when apCtors.Contains x ->
                        expect (sprintf "'%s' without a value" x) tUnit ft
                        mk (CCtor(u, tag, [ mk CUnit tUnit ])) uty
                    | [ ft ] ->
                        let p = uniq "$v"
                        mk (CLam([ p, ft ], mk (CCtor(u, tag, [ mk (CLocal p) ft ])) uty)) (TFun(ft, uty))
                    | _ -> fail 0 (sprintf "constructor '%s' takes several fields; apply it as %s (a, b)" x x)
                elif traitAliases.ContainsKey x then
                    traitMethod x
                elif builtins.ContainsKey x then
                    builtinCall env depth x []
                elif externs.ContainsKey x then
                    fail 0 (sprintf "C function '%s' must be called directly" x)
                else
                    match splitQualified env x with
                    | Some e -> infer env depth e
                    | None when skippedC.ContainsKey x -> fail 0 (sprintf "C name '%s' wasn't imported: %s" x skippedC[x])
                    | None -> fail 0 (sprintf "unknown name '%s'" x)

    and call env depth f args : CExpr =
        match env.TryFind f, resolveName f with
        | None, Some q when q <> f -> call' env depth q args
        | _ -> call' env depth f args

    and call' env depth f args : CExpr =
        if not (env.ContainsKey f || globals.ContainsKey f) && (staticMember f).IsSome then
            memberCall env depth (staticMember f).Value None args f
        elif env.ContainsKey f || globals.ContainsKey f then
            apply env depth (value env depth f) args (Some f)
        elif ctors.ContainsKey f then
            ctor env depth f args
        elif traitAliases.ContainsKey f then
            apply env depth (traitMethod f) args (Some f)
        elif builtins.ContainsKey f then
            builtinCall env depth f args
        elif externs.ContainsKey f then
            externCall env depth f args
        else
            match splitQualified env f with
            | Some e -> infer env depth (App(e, args))
            | None when skippedC.ContainsKey f -> fail 0 (sprintf "C function '%s' wasn't imported: %s" f skippedC[f])
            | None -> fail 0 (sprintf "unknown function '%s'" f)

    /// Type-checks arguments against a (curried) function type; returns them and the result type.
    and checkArgs env depth (fty: Ty) (args: Expr list) (name: string option) =
        let t = ref fty

        let cargs =
            args
            |> List.mapi (fun i a ->
                let ca =
                    match prune t.Value with
                    | TFun(p, _) -> inferHint env depth p a
                    | _ -> infer env depth a

                let what =
                    match name with
                    | Some f -> sprintf "argument %d of '%s'" (i + 1) f
                    | None -> sprintf "argument %d" (i + 1)

                match prune t.Value with
                | TFun(p, r) ->
                    expect what p ca.ty
                    t.Value <- r
                | TVar _ ->
                    let r = fresh kAny
                    expect "function" t.Value (TFun(ca.ty, r))
                    t.Value <- r
                | ty ->
                    match name with
                    | Some f -> fail 0 (sprintf "'%s' is applied to too many arguments" f)
                    | None -> fail 0 (sprintf "this value is not a function; it has type %s" (show ty))

                ca)

        cargs, t.Value

    and apply env depth (ch: CExpr) (args: Expr list) (name: string option) : CExpr =
        let cargs, t = checkArgs env depth ch.ty args name
        mk (CApp(ch, cargs)) t

    and builtinCall env depth name (args: Expr list) : CExpr =
        let b = builtins[name]
        let t, _ = instantiate b.kinds b.ty
        let cargs, finalTy = checkArgs env depth t args (Some name)
        let ptys, resTy = peel b.arity t

        if cargs.Length >= b.arity then
            let first, rest = List.splitAt b.arity cargs
            let prim = mk (CPrim(b.prim, first)) resTy
            if rest.IsEmpty then prim else mk (CApp(prim, rest)) finalTy
        else
            // partial application: bind the given arguments, then a lambda over the rest
            let given = cargs |> List.map (fun c -> uniq "$a", c)
            let ps = ptys |> List.skip given.Length |> List.map (fun pt -> uniq "$b", pt)
            let callArgs = (given |> List.map (fun (u, c) -> mk (CLocal u) c.ty)) @ (ps |> List.map (fun (u, t) -> mk (CLocal u) t))
            let lam = mk (CLam(ps, mk (CPrim(b.prim, callArgs)) resTy)) (funTy (List.map snd ps) resTy)
            List.foldBack (fun (u, c) acc -> mk (CLet(u, c, acc)) acc.ty) given lam

    and externCall env depth f (args: Expr list) : CExpr =
        let s = externs[f]
        let args = if s.pars.IsEmpty && args = [ UnitLit ] then [] else args
        let n = s.pars.Length

        if args.Length < n || (args.Length > n && not s.variadic) then
            fail 0 (sprintf "'%s' expects %d argument(s), got %d" f n args.Length)

        let cargs =
            args
            |> List.mapi (fun i a ->
                let ca = infer env depth a

                if i < n then
                    let what = sprintf "argument %d of '%s'" (i + 1) f
                    // a string is passed to C as a pointer to its bytes; a closure as callback + user data
                    match s.pars[i] with
                    | t when t = tCStr -> expect what (fresh kStrLit) ca.ty
                    | TCon("callback", [ f ]) -> expect what f ca.ty
                    | t -> expect what t ca.ty

                ca)

        mk (CExtern(f, cargs)) s.ret

    and ctor env depth c (args: Expr list) : CExpr =
        let u, tag = ctors[c]
        let uty, targs = instType u
        let fields = caseFields u tag targs

        let isNamed a =
            match a with
            | Bin("=", Var n, _) -> List.contains (Some n) ctorFieldNames[c]
            | _ -> false

        let named =
            match args with
            | [ a ] when isNamed a -> Some [ a ]
            | [ Tuple xs ] when List.forall isNamed xs -> Some xs
            | _ -> None

        let args =
            match named with
            | Some xs ->
                // Circle(radius = 2.0): every field by name, in any order
                let given = xs |> List.map (function
                    | Bin(_, Var n, v) -> n, v
                    | _ -> failwith "unreachable")

                if (given |> List.map fst |> List.distinct).Length <> given.Length then
                    fail 0 (sprintf "a field of '%s' is given twice" c)

                ctorFieldNames[c]
                |> List.map (fun n ->
                    match given |> List.tryFind (fun (m, _) -> Some m = n) with
                    | Some(_, v) -> v
                    | None ->
                        match n with
                        | Some n -> fail 0 (sprintf "constructor '%s' is missing field '%s'" c n)
                        | None -> fail 0 (sprintf "constructor '%s' has unnamed fields; pass them by position" c))
            | None ->
                ctorArgs c args fields (function
                    | Tuple xs -> Some xs
                    | _ -> None) None

        let cargs =
            List.map2
                (fun a ft ->
                    let ca = inferHint env depth ft a
                    expect (sprintf "argument of '%s'" c) ft ca.ty
                    ca)
                args
                fields

        mk (CCtor(u, tag, cargs)) uty

    /// Like infer, but a record literal may use the expected type to pick its record.
    and inferHint env depth (hint: Ty) (e: Expr) : CExpr =
        match e with
        | At(ln, inner) ->
            try
                let c = inferHint env depth hint inner
                mk (CLine(ln, c)) c.ty
            with CompileError(0, msg) ->
                raise (CompileErrorPos(ln, colOf e, msg))
        | RecordLit fields -> recordLit env depth (Some hint) fields
        | _ -> infer env depth e

    /// The record a literal builds: the expected type if it is a record; otherwise the only
    /// record whose fields fit (all given fields exist, all missing ones have defaults).
    and recordLit env depth (hint: Ty option) (fields: (string * Expr) list) : CExpr =
        let given = fields |> List.map fst

        let fits r =
            let defs = List.zip (fieldsOf r) recordDefaults[r]

            given |> List.forall (fun f -> defs |> List.exists (fun ((g, _), _) -> g = f))
            && defs |> List.forall (fun ((g, _), d) -> d.IsSome || List.contains g given)

        let rname =
            match hint |> Option.map prune with
            | Some(TCon(n, _)) when records.Contains n -> n
            | _ ->
                match records |> Seq.filter fits |> List.ofSeq with
                | [ r ] -> r
                | [] -> recordOf (fresh kAny) given.Head // the precise error comes from buildRecord
                | many ->
                    let exact = many |> List.filter (fun r -> (fieldsOf r).Length = given.Length)

                    if exact.IsEmpty then
                        fail 0 (sprintf "record literal could be any of %s; add a type annotation" (String.concat ", " many))
                    else
                        List.last exact

        let rty, targs = instType rname
        let defaults = recordDefaults[rname]

        let built =
            buildRecord env depth rname targs fields (fun i scope ->
                let f, ft = List.item i (fieldsOf rname)
                let ft = substGen targs ft

                match defaults[i] with
                | Some d ->
                    let ce = inferHint scope 0 ft d
                    expect (sprintf "default of field '%s'" f) ft ce.ty
                    ce
                | None -> fail 0 (sprintf "record '%s' is missing field '%s'" rname f))

        built

    /// Binds each given field to a temporary in source order (preserving evaluation order),
    /// then each missing field, in declaration order, to fallback i scope, where scope holds
    /// the fields declared before it. Builds the record from the temporaries.
    and buildRecord env depth rname targs (fields: (string * Expr) list) (fallback: int -> Map<string, Local> -> CExpr) : CExpr =
        let defs = fieldsOf rname

        let named =
            fields
            |> List.map (fun (f, e) ->
                match defs |> List.tryFindIndex (fst >> (=) f) with
                | None -> fail 0 (sprintf "record '%s' has no field '%s'" rname f)
                | Some i ->
                    let ft = substGen targs (snd defs[i])
                    let ce = inferHint env depth ft e
                    expect (sprintf "field '%s'" f) ft ce.ty
                    f, ce, uniq "$f")

        if (named |> List.map (fun (f, _, _) -> f) |> List.distinct).Length <> named.Length then
            fail 0 "a field is given twice"

        let mutable scope = Map.empty
        let filled = ResizeArray()

        let temps =
            defs
            |> List.mapi (fun i (f, _) ->
                let tmp, ty =
                    match named |> List.tryFind (fun (g, _, _) -> g = f) with
                    | Some(_, ce, tmp) -> tmp, ce.ty
                    | None ->
                        let ce = fallback i scope
                        let tmp = uniq "$f"
                        filled.Add(tmp, ce)
                        tmp, ce.ty

                scope <-
                    scope.Add(
                        f,
                        { u = tmp
                          ty = ty
                          mut = false
                          depth = 0 }
                    )

                mk (CLocal tmp) ty)

        let body = mk (CTuple temps) (TCon(rname, targs))
        let body = List.foldBack (fun (tmp, ce: CExpr) acc -> mk (CLet(tmp, ce, acc)) acc.ty) (List.ofSeq filled) body
        List.foldBack (fun (_, ce, tmp) acc -> mk (CLet(tmp, ce, acc)) acc.ty) named body

    /// Type-checks functions that may refer to each other (pre-registered when isRec),
    /// then generalizes each.
    let defineGroupWith
        (items: (int * string * bool * Param list * SType option * Expr * (unit -> Ty) option) list)
        : (Global * Dictionary<string, Ty>) list =
        let prepared =
            items
            |> List.map (fun (ln, name, isRec, ps0, ret, body, expected) ->
                try
                    tyvars.Clear()
                    let ps, body = lowerParams ps0 body
                    let pars = ps |> List.map (fun (x, ann) -> x, uniq x, annot ann)
                    recordParams ps0 pars
                    let rty = annot ret
                    let fty = funTy (pars |> List.map (fun (_, _, t) -> t)) rty

                    match expected with
                    | Some f -> expect (sprintf "'%s' does not match the trait's signature" name) (f ()) fty
                    | None -> ()

                    let g =
                        { ty = fty
                          kinds = []
                          arity = pars.Length
                          defining = true }

                    if isRec then
                        globals[name] <- g

                    ln, name, pars, rty, fty, g, body, Dictionary<string, Ty>(tyvars)
                with CompileError(0, msg) ->
                    fail ln msg)

        let bodies =
            prepared
            |> List.map (fun (ln, name, pars, rty, _, _, body, tvs) ->
                try
                    tyvars.Clear()

                    for kv in tvs do
                        tyvars[kv.Key] <- kv.Value

                    let env =
                        pars
                        |> List.fold
                            (fun (m: Map<_, _>) (x, u, t) ->
                                m.Add(
                                    x,
                                    { u = u
                                      ty = t
                                      mut = false
                                      depth = 0 }
                                ))
                            Map.empty

                    let cb = inferHint env 0 rty body
                    expect (sprintf "result of '%s'" name) rty cb.ty
                    cb
                with CompileError(0, msg) ->
                    fail ln msg)

        [ for (_, name, pars, rty, fty, g, _, tvs), cb in List.zip prepared bodies do
              if name = "main" then
                  resolve fty |> ignore

              g.kinds <- generalize fty
              g.defining <- false
              globals[name] <- g

              funs.Add
                  { name = name
                    pars = pars |> List.map (fun (_, u, t) -> u, t)
                    ret = rty
                    body = cb
                    ngen = g.kinds.Length }

              yield g, tvs ]

    let defineGroup items =
        defineGroupWith (items |> List.map (fun (ln, n, r, ps, ret, b) -> ln, n, r, ps, ret, b, None)) |> ignore

    /// Members become functions `Type#Name`: self first (instance members), then parameters;
    /// an optional parameter without a default is an option in the body.
    let declareMembers (tname: string) (tparams: string list) (ms: Member list) =
        let table =
            match members.TryGetValue tname with
            | true, t -> t
            | _ ->
                let t = Dictionary<string, MemberInfo>()
                members[tname] <- t
                t

        let items =
            ms
            |> List.map (fun m ->
                if table.ContainsKey m.name then
                    fail m.mline (sprintf "'%s' already has a member '%s'" tname m.name)

                if not m.isStatic && List.contains m.name (match types.TryGetValue tname with
                                                           | true, { def = RecordDef fs } -> List.map fst fs
                                                           | _ -> []) then
                    fail m.mline (sprintf "member '%s' has the same name as a field of '%s'" m.name tname)

                let gname = tname + "#" + m.name
                let ps = m.mpars |> Option.defaultValue []

                let mps =
                    ps
                    |> List.map (fun p ->
                        let ann =
                            match p.optional, p.mdefault with
                            | true, None -> Some(STName("option", [ defaultArg p.mty (STVar("$opt." + p.mname)) ]))
                            | _ -> p.mty

                        PIdent(p.mname, None), ann)

                let selfPar =
                    m.self
                    |> Option.map (fun v -> PIdent(v, None), Some(STName(tname, tparams |> List.map STVar)))
                    |> Option.toList

                let allPars = selfPar @ mps
                let allPars = if allPars.IsEmpty then [ PUnit, None ] else allPars

                table[m.name] <-
                    { gname = gname
                      isStatic = m.isStatic
                      isProperty = m.mpars.IsNone
                      mpars = ps }

                m.mline, gname, true, allPars, m.mret, m.mbody)

        defineGroup items

    /// Types that can cross the C boundary: numbers, bool, cstr, unit and [<CLayout>] records.
    let rec checkCType (what: string) (t: Ty) =
        match prune t with
        | TCon(n, []) when nums.Contains n || n = "bool" || n = "cstr" || n = "cptr" || n = "unit" -> ()
        | TCon(n, []) when clayouts.Contains n -> ()
        | t -> fail 0 (sprintf "%s: type %s cannot cross the C boundary (mark records [<CLayout>])" what (show t))

    /// callback<A -> R>: C sees (R (*)(void* user, A), void* user); A and R are C types.
    let checkCallback (what: string) (f: Ty) =
        match prune f with
        | TFun(a, r) ->
            checkCType what a
            checkCType what r
        | t -> fail 0 (sprintf "%s: callback<%s> needs a function type such as callback<int -> unit>" what (show t))

    /// Registers an impl and type-checks its methods. The impl is registered before its
    /// bodies so they may use it recursively; its requirements on type arguments are inferred.
    let declareImpl (tr: string) (head: SType) (defs: (int * string * Param list * SType option * Expr) list) =
        let methods =
            traitMethods.Values |> Seq.filter (fun m -> m.owner = tr) |> Seq.map (fun m -> m.name) |> Set.ofSeq

        if methods.IsEmpty then
            fail 0 (sprintf "unknown trait '%s'" tr)

        let hn, hargs =
            match head with
            | STName(n, args) ->
                (match typeAliases.TryGetValue n with
                 | true, c -> c
                 | _ -> n),
                args
            | _ -> fail 0 "an impl is for a named type, such as Show<Point> or Show<list<'a>>"

        let hvars =
            hargs
            |> List.map (function
                | STVar v -> v
                | _ -> fail 0 "impl type arguments must be type variables: impl Show<list<'a>>")

        if (List.distinct hvars).Length <> hvars.Length then
            fail 0 "impl type variables must be distinct"

        if impls.ContainsKey((tr, hn)) then
            fail 0 (sprintf "%s<%s> is already implemented" tr hn)

        let given = defs |> List.map (fun (_, n, _, _, _) -> n)

        for m in methods do
            if not (List.contains m given) then
                fail 0 (sprintf "impl %s<%s> is missing '%s'" tr hn m)

        for m in given do
            if not (methods.Contains m) then
                fail 0 (sprintf "trait %s has no method '%s'" tr m)

        // registered before the bodies, so they may use the impl recursively
        let table = Dictionary<string, string>()
        impls[(tr, hn)] <- table
        implRequires[(tr, hn)] <- List.map (fun _ -> Set.empty) hvars

        let items =
            defs
            |> List.map (fun (dl, m, ps, ret, body) ->
                let tm = traitMethods[tr + "." + m]
                let fname = sprintf "%s<%s>#%s" tr hn m
                table[m] <- fname
                let ps = if ps.IsEmpty then [ PUnit, None ] else ps

                let expected () =
                    let t = substGen [ toTy None head ] tm.ty
                    if tm.isConst then TFun(tUnit, t) else t

                dl, fname, true, ps, ret, body, Some expected)

        let results = defineGroupWith items

        // what the impl needs from each type argument: the union over its methods
        implRequires[(tr, hn)] <-
            hvars
            |> List.map (fun v ->
                results
                |> List.collect (fun (g, tvs) ->
                    match tvs.TryGetValue v with
                    | true, t ->
                        match prune t with
                        | TGen i -> (List.item i g.kinds).traits |> Set.toList
                        | _ -> []
                    | _ -> [])
                |> Set.ofList)

    let shapeOf (tname: string) : Derive.ShapeInfo =
        match types[tname].def with
        | RecordDef fs -> Derive.RecordShape(List.map fst fs)
        | UnionDef cs ->
            Derive.UnionShape(
                cs
                |> List.map (fun (c, fts) ->
                    c,
                    List.mapi
                        (fun j n -> defaultArg n (sprintf "item%d" (j + 1)))
                        (match ctorFieldNames.TryGetValue c with
                         | true, ns -> ns
                         | _ -> List.map (fun _ -> None) fts))
            )

    /// Implements trait `tr` for type `tname` by expanding `derive tr`.
    let deriveImpl (context: string) (tr: string) (tname: string) =
        if not (derives.ContainsKey tr) then
            fail 0 (sprintf "no derive named '%s'" tr)

        let head = STName(tname, List.init types[tname].npars (fun i -> STVar(sprintf "t%d" i)))
        // hygiene: a trait method named in a derive (show, compare, hash…) means the trait's,
        // even where the program defines a function of the same name
        // ponytail: a local in a derive body named like a trait method would be rewritten too
        let rec hygienic (e: Expr) =
            match e with
            | Var x when traitAliases.ContainsKey x && not (x.Contains ".") -> Var traitAliases[x]
            | Call(x, args) when traitAliases.ContainsKey x && not (x.Contains ".") -> Call(traitAliases[x], List.map hygienic args)
            | _ -> mapExpr hygienic e

        let defs =
            Derive.expand tr tname head (shapeOf tname) derives[tr]
            |> List.map (fun (l, n, ps, r, body) -> l, n, ps, r, hygienic body)

        let saved = Dictionary<string, Ty>(tyvars) // may run in the middle of another function

        try
            try
                declareImpl tr head defs
            with
            | CompileError(l, msg) -> fail l (sprintf "%s: %s" context msg)
            | CompileErrorPos(l, c, msg) -> raise (CompileErrorPos(l, c, sprintf "%s: %s" context msg))
        finally
            tyvars.Clear()

            for kv in saved do
                tyvars[kv.Key] <- kv.Value

    // Eq, Ord, Hash and Show come from the prelude's derives, the first time they're needed
    autoDerive <-
        fun tr n ->
            let ok =
                List.contains tr [ "Eq"; "Ord"; "Hash"; "Show" ]
                && derives.ContainsKey tr
                && not (manualImpls.Contains((tr, n)) || optOut.Contains((tr, n)))
                && (match types.TryGetValue n with
                    | true, { def = RecordDef _ } -> true
                    | true, { def = UnionDef cs } -> not cs.IsEmpty
                    | _ -> false)

            if ok then
                deriveImpl (sprintf "automatic %s for %s" tr n) tr n

            ok

    // explicit impls anywhere in the program win over automatic derives
    for _, d in decls do
        match d with
        | Impl(tr, STName(n, _), _) -> manualImpls.Add((tr, n)) |> ignore
        | _ -> ()

    let rec declare (ln: int) (d: Decl) =
            match d with
            | TypeDecl(name, tps, body, ms) ->
                let name = qualify name

                if prims.Contains name || builtinCons.ContainsKey name || types.ContainsKey name then
                    fail 0 (sprintf "type '%s' is already defined" name)

                // registered first so the body can refer to the type itself
                types[name] <- { npars = tps.Length; def = UnionDef [] }
                let tt = toTy (Some tps)

                match body with
                | RecordTy fields ->
                    let fs = fields |> List.map (fun (f, st, _) -> f, tt st)

                    let rec contains t =
                        match t with
                        | TCon(n, args) -> n = name || List.exists contains args
                        | TTuple ts -> List.exists contains ts
                        | _ -> false

                    if fs |> List.exists (snd >> contains) then
                        fail 0 (sprintf "record '%s' cannot contain itself; use a union" name)

                    if (fs |> List.map fst |> List.distinct).Length <> fs.Length then
                        fail 0 "duplicate field name"

                    types[name] <- { npars = tps.Length; def = RecordDef fs }
                    records.Add name
                    recordDefaults[name] <- fields |> List.map (fun (_, _, d) -> d)

                    for f, _ in fs do
                        fieldOwner[f] <- name
                | UnionTy cases ->
                    types[name] <-
                        { npars = tps.Length
                          def = UnionDef(cases |> List.map (fun (c, fs) -> qualify c, fs |> List.map (snd >> tt))) }

                    cases
                    |> List.iteri (fun i (c, fs) ->
                        let c = qualify c

                        if ctors.ContainsKey c then
                            fail 0 (sprintf "constructor '%s' is already defined" c)

                        ctors[c] <- (name, i)
                        ctorFieldNames[c] <- List.map fst fs)

                declareMembers name tps ms
            | Extern(name, args, variadic, ret) ->
                if externs.ContainsKey name || globals.ContainsKey name then
                    fail 0 (sprintf "'%s' is already defined" name)

                let cty (isParam: bool) st =
                    let t = toTy (Some []) st

                    match t with
                    | TCon("callback", [ f ]) when isParam -> checkCallback (sprintf "extern '%s'" name) f
                    | _ -> checkCType (sprintf "extern '%s'" name) t

                    t

                externs[name] <-
                    { pars = List.map (cty true) args
                      ret = cty false ret
                      variadic = variadic }
            | Fun(name, isRec, ps, ret, body) when name.StartsWith "|" ->
                // active pattern: cases become constructors of a hidden union (total) or option (partial)
                let names = name.Trim('|').Split('|') |> List.ofArray
                let fn = qualify name
                let partial = List.last names = "_"

                if partial then
                    if names.Length <> 2 then
                        fail 0 "a partial active pattern has one case: (|Name|_|)"

                    activePatterns[qualify names.Head] <- (fn, false, ps.Length - 1)
                else
                    let u = qualify ("$AP" + name)
                    types[u] <- { npars = names.Length; def = UnionDef(names |> List.mapi (fun i c -> qualify c, [ TGen i ])) }

                    names
                    |> List.iteri (fun i c ->
                        let qc = qualify c

                        if ctors.ContainsKey qc then
                            fail 0 (sprintf "constructor '%s' is already defined" c)

                        ctors[qc] <- (u, i)
                        ctorFieldNames[qc] <- [ None ]
                        apCtors.Add qc |> ignore
                        activePatterns[qc] <- (fn, true, ps.Length - 1))

                defineGroup [ ln, fn, isRec, ps, ret, body ]
            | Fun(name, isRec, ps, ret, body) ->
                let name = qualify name

                if globals.ContainsKey name || externs.ContainsKey name then
                    fail 0 (sprintf "'%s' is already defined" name)

                try
                    defineGroup [ ln, name, isRec, ps, ret, body ]
                with _ ->
                    globals.Remove name |> ignore // keep later declarations from seeing a half-defined function
                    reraise ()

                recordKey d name globals[name].ty false name true

                if hovers.Count > 0 && hovers[hovers.Count - 1].name = name then
                    hovers[hovers.Count - 1] <- { hovers[hovers.Count - 1] with decl = true }

                // a generic function's hover shows what its type variables need
                let g = globals[name]

                let needs =
                    g.kinds
                    |> List.indexed
                    |> List.collect (fun (i, k) -> k.traits |> Set.toList |> List.map (fun tr -> sprintf "%s : %s" (show (TGen i)) tr))

                if not needs.IsEmpty && hovers.Count > 0 && hovers[hovers.Count - 1].name = name then
                    hovers[hovers.Count - 1] <- { hovers[hovers.Count - 1] with constraints = String.concat ", " needs }
            | Trait(name, tp, methods) ->
                if traitMethods.Keys |> Seq.exists (fun k -> k.StartsWith(name + ".")) then
                    fail 0 (sprintf "trait '%s' is already defined" name)

                for m, st in methods do
                    let t = toTy (Some [ tp ]) st

                    let isConst =
                        match t with
                        | TFun _ -> false
                        | _ -> true

                    let qname = name + "." + m

                    traitMethods[qname] <-
                        { owner = name
                          name = m
                          ty = t
                          isConst = isConst }

                    traitAliases[qname] <- qname

                    // unqualified names, except for the operator traits (whose methods are the operators)
                    if not (List.contains name [ "Add"; "Num"; "Eq" ]) && not (traitAliases.ContainsKey m) then
                        traitAliases[m] <- qname

                if name = "Show" then
                    traitAliases["string"] <- "Show.show"
            | Impl(tr, head, defs) -> declareImpl tr head defs
            | Derive(name, defs) -> derives[name] <- defs
            | Private inner ->
                declare ln inner

                match inner with
                | Fun(n, _, _, _, _) -> privates[qualify n] <- currentModule.Value
                | TypeDecl(n, _, body, _) ->
                    privates[qualify n] <- currentModule.Value

                    match body with
                    | UnionTy cases ->
                        for c, _ in cases do
                            privates[qualify c] <- currentModule.Value
                    | RecordTy _ -> ()
                | _ -> fail 0 "'private' applies to 'let' and 'type' declarations"
            | Const(name, v) -> consts[name] <- v
            | Open m ->
                if not (moduleNames.Contains m) then
                    fail 0 (sprintf "unknown module '%s'" m)

                opens.Value <- m :: opens.Value
            | ModuleHeader _ -> ()
            | Attrs([ "Measure", [] ], TypeDecl(name, [], UnionTy [], [])) -> measures.Add name |> ignore
            | Attrs([ "Export", cname ], (Fun(name, _, _, _, _) as f)) ->
                declare ln f
                let q = qualify name
                let g = globals[q]

                if not g.kinds.IsEmpty then
                    fail 0 (sprintf "exported function '%s' must not be generic; add type annotations" name)

                let cname =
                    match cname with
                    | [ c ] -> c
                    | _ -> name

                let ptys, ret = peel g.arity g.ty
                let what = sprintf "export '%s'" cname

                for t in ptys do
                    checkCType what t

                checkCType what ret

                exports.Add
                    { cname = cname
                      fname = q
                      pars = ptys |> List.filter (fun t -> prune t <> tUnit)
                      ret = resolve ret }
            | Attrs([ "Test", [] ], (Fun(name, _, _, _, _) as f)) ->
                declare ln f
                let q = qualify name

                try
                    unify (TFun(tUnit, tUnit)) globals[q].ty
                with Mismatch ->
                    fail 0 (sprintf "test '%s' must be a function of type unit -> unit, such as: let %s () = assert (...)" name name)

                tests.Add q
            | Attrs([ "CLayout", [] ], (TypeDecl(name, tps, RecordTy fields, _) as d)) ->
                declare ln d
                let q = qualify name

                if not tps.IsEmpty then
                    fail 0 "a [<CLayout>] record can't be generic"

                clayouts.Add q |> ignore

                for f, ft in (match types[q].def with
                              | RecordDef fs -> fs
                              | UnionDef _ -> []) do
                    match prune ft with
                    | TCon("unit", []) -> fail 0 (sprintf "[<CLayout>] field '%s' can't be unit" f)
                    | _ -> checkCType (sprintf "[<CLayout>] field '%s'" f) ft
            | Attrs(attrs, inner) ->
                declare ln inner

                match inner with
                | TypeDecl(name, _, _, _) ->
                    let name = qualify name

                    for a, args in attrs do
                        match a with
                        | "Derive" ->
                            for tr in args do
                                deriveImpl (sprintf "Derive(%s) on %s" tr name) tr name
                        | "NoEquality" ->
                            optOut.Add(("Eq", name)) |> ignore
                            optOut.Add(("Hash", name)) |> ignore
                        | "NoComparison" -> optOut.Add(("Ord", name)) |> ignore
                        | _ -> fail 0 (sprintf "unknown attribute '%s'" a)
                | _ -> fail 0 "attributes are only supported on type declarations yet"
            | TypeExt(name, tps, ms) ->
                let name =
                    match typeAliases.TryGetValue name with
                    | true, c -> c
                    | _ -> name

                let name =
                    resolveWith (fun q -> prims.Contains q || builtinCons.ContainsKey q || types.ContainsKey q) name
                    |> Option.defaultValue name

                if not (prims.Contains name || builtinCons.ContainsKey name || types.ContainsKey name) then
                    fail 0 (sprintf "unknown type '%s'" name)

                declareMembers name tps ms

    let checkMain () =
        match globals.TryGetValue "main" with
        | true, g ->
            match g.arity, prune g.ty with
            | 1, TFun(p, r) when prune p = tUnit ->
                match resolve r with
                | TCon(("int" | "i32" | "unit"), []) -> ()
                | t -> fail 0 (sprintf "'main' must return int, c_int or unit, not %s" (show t))
            | _ -> fail 0 "'main' must take one unit parameter: let main () = ..."
        | _ -> fail 0 "no 'main' function"

    // errors that mention a declaration that already failed are just its consequences
    let failed = HashSet<string>()

    let report (dg: Diagnostic) =
        if not collect then
            raise (CompileErrorAt(dg.file, dg.line, dg.col, dg.msg))
        elif not (failed |> Seq.exists (fun n -> dg.msg.Contains("'" + n + "'"))) then
            diagnostics.Add dg

    let declaredNames (d: Decl) =
        let rec go d =
            match d with
            | Fun(n, _, _, _, _)
            | TypeDecl(n, _, _, _) -> [ n ]
            | Attrs(_, d)
            | Private d -> go d
            | _ -> []

        go d

    for file, modName, decls in modules do
        currentModule.Value <- modName
        opens.Value <- []
        currentFile.Value <- file

        for ln, d in decls do
            let diag l c msg =
                { file = file
                  line = l
                  col = c
                  msg = msg }

            try
                declare ln d
            with
            | CompileError(l, msg) ->
                report (diag (if l = 0 then ln else l) 0 msg)

                for n in declaredNames d do
                    failed.Add n |> ignore
                    failed.Add(qualify n) |> ignore
            | CompileErrorPos(l, c, msg) ->
                report (diag l c msg)

                for n in declaredNames d do
                    failed.Add n |> ignore
                    failed.Add(qualify n) |> ignore

    currentModule.Value <- None
    let mainFile, _, _ = List.last modules

    try
        if (requireMain && tests.Count = 0) || globals.ContainsKey "main" then // a test file needs no main
            checkMain ()
    with CompileError(_, msg) ->
        report
            { file = mainFile
              line = 0
              col = 0
              msg = msg }

    { types = types
      externs = externs
      funs = List.ofSeq funs
      traitMethods = traitMethods
      impls = impls
      exports = List.ofSeq exports
      tests = List.ofSeq tests
      clayouts = clayouts
      errors = List.ofSeq diagnostics
      hovers = List.ofSeq hovers
      memberNames =
        let d = Dictionary<string, string list>()

        for KeyValue(t, table) in members do
            d[t] <- List.ofSeq table.Keys

        d }
