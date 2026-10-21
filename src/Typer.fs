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
    | TGen _ -> false

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
          b "ref" "ref" [ kAny ] (f a (TCon("ref", [ a ]))) 1
          b "Array.create" "Array.create" [ kAny ] (f tInt (f a (TCon("array", [ a ])))) 2
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

let check (decls: (int * Decl) list) : Program =
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
            | _ -> false
    let globals = Dictionary<string, Global>()
    let externs = Dictionary<string, ExternSig>()
    let funs = ResizeArray<FunDef>()
    let tyvars = Dictionary<string, Ty>() // 'a in the current function's annotations
    let counter = ref 0

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

            let arity =
                if prims.Contains n then 0
                elif builtinCons.ContainsKey n then builtinCons[n]
                elif types.ContainsKey n then types[n].npars
                else fail 0 (sprintf "unknown type '%s'" n)

            if arity <> args.Length then
                fail 0 (sprintf "type '%s' expects %d type argument(s)" n arity)

            TCon(n, List.map (toTy tparams) args)
        | STTuple ts -> TTuple(List.map (toTy tparams) ts)
        | STFun(a, b) -> TFun(toTy tparams a, toTy tparams b)

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
                | PIdent(x, None) when not (ctors.ContainsKey x) -> (x, ann), None
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
        | PIdent(c, arg) when ctors.ContainsKey c ->
            let u, tag = ctors[c]
            let uty, targs = instType u
            expect "pattern" ty uty
            let fields = caseFields u tag targs

            let subs =
                match arg with
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
        | PIdent(x, None) -> CPVar(name x, ty)
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

    let rec infer (env: Map<string, Local>) (depth: int) (e: Expr) : CExpr =
        let inf = infer env depth

        match e with
        | At(ln, e) ->
            try
                let c = infer env depth e
                mk (CLine(ln, c)) c.ty
            with CompileError(0, msg) ->
                fail ln msg
        | Lit n -> mk (CInt n) (fresh kInt)
        | FloatLit f -> mk (CFloat f) (fresh kFloat)
        | BoolLit b -> mk (CBool b) tBool
        | StrLit s -> mk (CStr s) (fresh kStrLit)
        | UnitLit -> mk CUnit tUnit
        | Var x -> value env depth x
        | Call(f, args) -> call env depth f args
        | App(Field(r, f), args) ->
            let cr = inf r
            settle cr.ty

            match memberOf cr.ty f with
            | Some(m: MemberInfo) when not m.isStatic && not m.isProperty -> memberCall env depth m (Some cr) args f
            | _ -> apply env depth (field cr f) args None
        | App(h, args) -> apply env depth (inf h) args None
        | Lambda(ps, body) ->
            let ps, body = lowerParams ps body
            let pars = ps |> List.map (fun (x, ann) -> x, uniq x, annot ann)

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
        | LetFun(name, isRec, ps, ret, body, rest) ->
            let ps, body = lowerParams ps body
            let pars = ps |> List.map (fun (x, ann) -> x, uniq x, annot ann)
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
            let cr = infer (env.Add(name, self)) depth rest
            mk (CLetFun(self.u, isRec, pars |> List.map (fun (_, u, t) -> u, t), cb, cr)) cr.ty
        | Let(PIdent(x, None), ann, v, rest) when not (ctors.ContainsKey x) ->
            let cv =
                match ann with
                | Some a -> inferHint env depth (toTy None a) v
                | None -> inf v
            ann |> Option.iter (fun a -> expect (sprintf "value of '%s'" x) (toTy None a) cv.ty)

            let l =
                { u = uniq x
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
                let ci = inf i
                let cv = inf rhs
                expect "array" (TCon("array", [ cv.ty ])) ca.ty
                expect "array index" tInt ci.ty
                mk (CPrim("array.set", [ ca; ci; cv ])) tUnit
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
            expect "indexing" (TCon("array", [ el ])) ca.ty
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
        | Bin(op, a, b) ->
            let ca = inf a
            let cb = inf b
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
        | Field(r, f) -> field (inf r) f
        | Question _ -> fail 0 "'?' is only supported as `let x = e?` or as a whole statement (for now)"
        | DeriveCtx(ctx, e) ->
            try
                inf e
            with CompileError(l, msg) ->
                fail l (sprintf "%s: %s" ctx msg)
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
                | TCon("array", _) ->
                    For("$i", Lit 0L, None, Bin("-", Call("Array.length", [ Var "$coll" ]), Lit 1L), Let(PIdent(x, None), None, Index(Var "$coll", Var "$i"), body))
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
            Match.check unionCases (cases |> List.map (fun (p, _, _) -> p, false))
            mk (CMatch(ce, cases)) crest.ty
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

            Match.check unionCases (ccases |> List.map (fun (p, g, _) -> p, g.IsSome))
            mk (CMatch(cs, ccases)) resTy

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
            env.ContainsKey n || globals.ContainsKey n || ctors.ContainsKey n || builtins.ContainsKey n
            || traitAliases.ContainsKey n || (staticMember n).IsSome

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

    and value env depth x : CExpr =
        match env.TryFind x with
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
                    | None -> fail 0 (sprintf "unknown name '%s'" x)

    and call env depth f args : CExpr =
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
                    // a string is passed to C as a pointer to its bytes
                    if s.pars[i] = tCStr then
                        expect what (fresh kStrLit) ca.ty
                    else
                        expect what s.pars[i] ca.ty

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
                fail ln msg
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
            |> List.map (fun (ln, name, isRec, ps, ret, body, expected) ->
                try
                    tyvars.Clear()
                    let ps, body = lowerParams ps body
                    let pars = ps |> List.map (fun (x, ann) -> x, uniq x, annot ann)
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
        let defs = Derive.expand tr tname head (shapeOf tname) derives[tr]
        let saved = Dictionary<string, Ty>(tyvars) // may run in the middle of another function

        try
            try
                declareImpl tr head defs
            with CompileError(l, msg) ->
                fail l (sprintf "%s: %s" context msg)
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
                          def = UnionDef(cases |> List.map (fun (c, fs) -> c, fs |> List.map (snd >> tt))) }

                    cases
                    |> List.iteri (fun i (c, fs) ->
                        if ctors.ContainsKey c then
                            fail 0 (sprintf "constructor '%s' is already defined" c)

                        ctors[c] <- (name, i)
                        ctorFieldNames[c] <- List.map fst fs)

                declareMembers name tps ms
            | Extern(name, args, variadic, ret) ->
                if externs.ContainsKey name || globals.ContainsKey name then
                    fail 0 (sprintf "'%s' is already defined" name)

                let cty st =
                    match toTy (Some []) st with
                    | TCon(n, []) as t when nums.Contains n || n = "cstr" || n = "unit" -> t
                    | t -> fail 0 (sprintf "extern '%s': type %s cannot cross the C boundary yet" name (show t))

                externs[name] <-
                    { pars = List.map cty args
                      ret = cty ret
                      variadic = variadic }
            | Fun(name, isRec, ps, ret, body) ->
                if globals.ContainsKey name || externs.ContainsKey name then
                    fail 0 (sprintf "'%s' is already defined" name)

                defineGroup [ ln, name, isRec, ps, ret, body ]
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
            | Attrs(attrs, inner) ->
                declare ln inner

                match inner with
                | TypeDecl(name, _, _, _) ->
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

                if not (prims.Contains name || builtinCons.ContainsKey name || types.ContainsKey name) then
                    fail 0 (sprintf "unknown type '%s'" name)

                declareMembers name tps ms

    for ln, d in decls do
        try
            declare ln d
        with CompileError(0, msg) ->
            fail ln msg

    match globals.TryGetValue "main" with
    | true, g ->
        match g.arity, prune g.ty with
        | 1, TFun(p, r) when prune p = tUnit ->
            match resolve r with
            | TCon(("int" | "i32" | "unit"), []) -> ()
            | t -> fail 0 (sprintf "'main' must return int, c_int or unit, not %s" (show t))
        | _ -> fail 0 "'main' must take one unit parameter: let main () = ..."
    | _ -> fail 0 "no 'main' function"

    { types = types
      externs = externs
      funs = List.ofSeq funs
      traitMethods = traitMethods
      impls = impls }
