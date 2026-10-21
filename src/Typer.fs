module Typer

open System.Collections.Generic
open Syntax

// ---------------------------------------------------------------- types

/// What a type variable may become: Eq = int, c_int or bool; Num = int or c_int.
type Kind =
    | Any
    | Eq
    | Num

type Ty =
    | TCon of string // int, c_int, bool, cstr, unit, or a user record/union
    | TTuple of Ty list
    | TVar of TV ref

and TV =
    | Unbound of int * Kind
    | Link of Ty

type TypeDef =
    | RecordDef of (string * Ty) list
    | UnionDef of (string * Ty list) list

let private prims = set [ "int"; "c_int"; "bool"; "cstr"; "unit" ]
let private tInt, tBool, tUnit, tStr = TCon "int", TCon "bool", TCon "unit", TCon "cstr"
let mutable private nextVar = 0

let private fresh kind =
    nextVar <- nextVar + 1
    TVar(ref (Unbound(nextVar, kind)))

let rec prune t =
    match t with
    | TVar r ->
        match r.Value with
        | Link t -> prune t
        | Unbound _ -> t
    | _ -> t

let rec show t =
    match prune t with
    | TCon n -> n
    | TTuple ts ->
        ts
        |> List.map (fun t ->
            match prune t with
            | TTuple _ -> "(" + show t + ")"
            | _ -> show t)
        |> String.concat " * "
    | TVar r ->
        match r.Value with
        | Unbound(_, Num) -> "int"
        | Unbound(id, _) -> sprintf "'t%d" id
        | Link t -> show t

// ponytail: no let-polymorphism; type variables are shared program-wide and anything left
// unconstrained becomes int. Generalization arrives with monomorphization in phase 2.
/// Fully resolves a type, defaulting unconstrained variables to int.
let rec resolve t =
    match prune t with
    | TVar r ->
        r.Value <- Link tInt
        tInt
    | TTuple ts -> TTuple(List.map resolve ts)
    | t -> t

exception private Mismatch

let private kindOf (r: TV ref) =
    match r.Value with
    | Unbound(_, k) -> k
    | Link _ -> Any

let rec private occurs r t =
    match prune t with
    | TVar r2 -> obj.ReferenceEquals(r, r2)
    | TTuple ts -> List.exists (occurs r) ts
    | TCon _ -> false

let private satisfies kind t =
    match kind, t with
    | Any, _ -> true
    | Eq, TCon("int" | "c_int" | "bool") -> true
    | Num, TCon("int" | "c_int") -> true
    | _ -> false

let rec private unify a b =
    match prune a, prune b with
    | TVar r1, TVar r2 ->
        if not (obj.ReferenceEquals(r1, r2)) then
            let k = max (kindOf r1) (kindOf r2)

            match r2.Value with
            | Unbound(id, _) -> r2.Value <- Unbound(id, k)
            | Link _ -> ()

            r1.Value <- Link(TVar r2)
    | TVar r, t
    | t, TVar r ->
        if occurs r t || not (satisfies (kindOf r) t) then
            raise Mismatch

        r.Value <- Link t
    | TCon a, TCon b when a = b -> ()
    | TTuple xs, TTuple ys when xs.Length = ys.Length -> List.iter2 unify xs ys
    | _ -> raise Mismatch

let private expect what expected actual =
    try
        unify expected actual
    with Mismatch ->
        fail 0 (sprintf "%s: expected %s, got %s" what (show expected) (show actual))

// ---------------------------------------------------------------- core IR

type CPat =
    | CPWild
    | CPVar of string * Ty
    | CPInt of int64
    | CPBool of bool
    | CPTuple of CPat list
    | CPCtor of union: string * tag: int * CPat list
    | CPOr of CPat * CPat
    | CPAs of CPat * string * Ty

type CExpr = { k: CKind; ty: Ty }

and CKind =
    | CInt of int64
    | CBool of bool
    | CStr of string
    | CUnit
    | CLocal of string
    | CCall of string * CExpr list
    | CBin of string * CExpr * CExpr
    | CNeg of CExpr
    | CNot of CExpr
    | CIf of CExpr * CExpr * CExpr
    | CLet of string * CExpr * CExpr
    | CSeq of CExpr * CExpr
    | CTuple of CExpr list // tuples and records (fields in declaration order)
    | CField of CExpr * int
    | CCtor of union: string * tag: int * CExpr list
    | CMatch of CExpr * (CPat * CExpr option * CExpr) list
    | CLine of int * CExpr

type FunSig =
    { pars: Ty list
      ret: Ty
      variadic: bool
      sym: string
      isExtern: bool }

type Program =
    { types: Dictionary<string, TypeDef>
      sigs: Dictionary<string, FunSig>
      funs: (string * string list * CExpr) list }

/// Variables bound by a pattern.
let rec patVars p =
    match p with
    | CPWild
    | CPInt _
    | CPBool _ -> []
    | CPVar(x, t) -> [ x, t ]
    | CPAs(p, x, t) -> (x, t) :: patVars p
    | CPTuple ps
    | CPCtor(_, _, ps) -> List.collect patVars ps
    | CPOr(a, _) -> patVars a

// ---------------------------------------------------------------- exhaustiveness
// Maranget, "Warnings for pattern matching" (2007): usefulness, returning a witness.

type private Con =
    { name: string
      arity: int
      all: (string * int) list option } // every constructor of the type; None = infinite (ints)

type private Space =
    | SWild
    | SCon of Con * Space list

let rec private cart xss =
    match xss with
    | [] -> [ [] ]
    | xs :: rest ->
        [ for x in xs do
              for r in cart rest do
                  yield x :: r ]

/// A pattern as the list of spaces it covers (or-patterns expand).
let rec private spaces (cases: string -> (string * int) list) p =
    let con c ps = [ for args in cart (List.map (spaces cases) ps) -> SCon(c, args) ]

    match p with
    | CPWild
    | CPVar _ -> [ SWild ]
    | CPAs(p, _, _) -> spaces cases p
    | CPInt n -> [ SCon({ name = string n; arity = 0; all = None }, []) ]
    | CPBool b ->
        let all = Some [ "true", 0; "false", 0 ]
        [ SCon({ name = (if b then "true" else "false"); arity = 0; all = all }, []) ]
    | CPTuple ps -> con { name = ","; arity = ps.Length; all = Some [ ",", ps.Length ] } ps
    | CPCtor(u, tag, ps) ->
        let all = cases u
        con { name = fst all[tag]; arity = ps.Length; all = Some all } ps
    | CPOr(a, b) -> spaces cases a @ spaces cases b

let rec private render s =
    let atomic s =
        match s with
        | SCon(c, _ :: _) when c.name <> "," -> "(" + render s + ")"
        | _ -> render s

    match s with
    | SWild -> "_"
    | SCon({ name = "," }, args) -> "(" + (args |> List.map render |> String.concat ", ") + ")"
    | SCon(c, []) -> c.name
    | SCon(c, [ a ]) -> c.name + " " + atomic a
    | SCon(c, args) -> c.name + " (" + (args |> List.map render |> String.concat ", ") + ")"

let private wilds n = List.replicate n SWild

let private specialize (c: Con) rows =
    rows
    |> List.choose (fun row ->
        match row with
        | SCon(c2, args) :: rest when c2.name = c.name -> Some(args @ rest)
        | SWild :: rest -> Some(wilds c.arity @ rest)
        | _ -> None)

let private defaults rows =
    rows
    |> List.choose (fun row ->
        match row with
        | SWild :: rest -> Some rest
        | _ -> None)

let private rebuild (c: Con) w =
    SCon(c, List.take c.arity w) :: List.skip c.arity w

/// A value vector matched by q but by no row, if any.
let rec private useful (rows: Space list list) (q: Space list) : Space list option =
    match q with
    | [] -> if rows.IsEmpty then Some [] else None
    | SCon(c, args) :: rest -> useful (specialize c rows) (args @ rest) |> Option.map (rebuild c)
    | SWild :: rest ->
        let sigma =
            rows
            |> List.choose (fun row ->
                match row with
                | SCon(c, _) :: _ -> Some c
                | _ -> None)
            |> List.distinctBy (fun c -> c.name)

        let all = sigma |> List.tryHead |> Option.bind (fun c -> c.all)
        let seen n = sigma |> List.exists (fun c -> c.name = n)

        match all with
        | Some cs when List.forall (fst >> seen) cs ->
            cs
            |> List.tryPick (fun (n, a) ->
                let c = { name = n; arity = a; all = all }
                useful (specialize c rows) (wilds a @ rest) |> Option.map (rebuild c))
        | _ ->
            useful (defaults rows) rest
            |> Option.map (fun w ->
                let missing =
                    match all with
                    | Some cs ->
                        let n, a = cs |> List.find (fst >> seen >> not)
                        SCon({ name = n; arity = a; all = all }, wilds a)
                    | None -> SWild

                missing :: w)

let private checkMatch cases (clauses: (CPat * bool) list) =
    let mutable rows = []

    for p, guarded in clauses do
        let ps = spaces cases p

        if ps |> List.forall (fun s -> (useful rows [ s ]).IsNone) then
            fail 0 "this match case is never reached"

        if not guarded then
            rows <- rows @ (ps |> List.map (fun s -> [ s ]))

    match useful rows [ SWild ] with
    | Some w -> fail 0 (sprintf "match is not exhaustive; missing case: %s" (render w.Head))
    | None -> ()

// ---------------------------------------------------------------- inference

let check (decls: (int * Decl) list) : Program =
    let types = Dictionary<string, TypeDef>()
    let ctors = Dictionary<string, string * int>() // constructor -> union, tag
    let fieldOwner = Dictionary<string, string>() // field -> last record declaring it
    let sigs = Dictionary<string, FunSig>()
    let funs = ResizeArray()
    let tmpCount = ref 0

    let tmpName () =
        tmpCount.Value <- tmpCount.Value + 1
        sprintf "$%d" tmpCount.Value

    let mk k ty = { k = k; ty = ty }

    let rec toTy st =
        match st with
        | STName n when prims.Contains n || types.ContainsKey n -> TCon n
        | STName n -> fail 0 (sprintf "unknown type '%s'" n)
        | STTuple ts -> TTuple(List.map toTy ts)

    let caseFields u tag =
        match types[u] with
        | UnionDef cs -> snd cs[tag]
        | RecordDef _ -> []

    let unionCases u =
        match types[u] with
        | UnionDef cs -> cs |> List.map (fun (n, ts) -> n, ts.Length)
        | RecordDef _ -> []

    let recordOf (t: Ty) (field: string) =
        match prune t with
        | TCon n when (match types.TryGetValue n with
                       | true, RecordDef _ -> true
                       | _ -> false) -> n
        | _ ->
            match fieldOwner.TryGetValue field with
            | true, r -> r
            | _ -> fail 0 (sprintf "no record has a field '%s'" field)

    let fieldsOf r =
        match types[r] with
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

    let rec pat (p: Pat) (ty: Ty) : CPat =
        match p with
        | PWild -> CPWild
        | PUnit ->
            expect "pattern" ty tUnit
            CPWild
        | PInt n ->
            expect "pattern" ty (fresh Num)
            CPInt n
        | PBool b ->
            expect "pattern" ty tBool
            CPBool b
        | PIdent(c, arg) when ctors.ContainsKey c ->
            let u, tag = ctors[c]
            expect "pattern" ty (TCon u)
            let fields = caseFields u tag

            let subs =
                ctorArgs c (Option.toList arg) fields (function
                    | PTuple ps -> Some ps
                    | _ -> None) (Some PWild)

            CPCtor(u, tag, List.map2 pat subs fields)
        | PIdent(x, None) -> CPVar(x, ty)
        | PIdent(c, Some _) -> fail 0 (sprintf "unknown constructor '%s' (local functions arrive in phase 2)" c)
        | PTuple ps ->
            let ts = ps |> List.map (fun _ -> fresh Any)
            expect "pattern" ty (TTuple ts)
            CPTuple(List.map2 pat ps ts)
        | POr(a, b) ->
            let ca, cb = pat a ty, pat b ty
            let va, vb = patVars ca, patVars cb

            if List.sort (List.map fst va) <> List.sort (List.map fst vb) then
                fail 0 "both sides of '|' must bind the same variables"

            for x, t in va do
                expect (sprintf "variable '%s'" x) t (vb |> List.find (fst >> (=) x) |> snd)

            CPOr(ca, cb)
        | PAs(p, x) -> CPAs(pat p ty, x, ty)

    /// Binds each field expression to a temporary in source order (preserving evaluation
    /// order), then builds the record from them in declaration order.
    let rec buildRecord env rname (fields: (string * Expr) list) (fallback: int -> CExpr) =
        let defs = fieldsOf rname

        let named =
            fields
            |> List.map (fun (f, e) ->
                match defs |> List.tryFindIndex (fst >> (=) f) with
                | None -> fail 0 (sprintf "record '%s' has no field '%s'" rname f)
                | Some i ->
                    let ce = infer env e
                    expect (sprintf "field '%s'" f) (snd defs[i]) ce.ty
                    f, ce, tmpName ())

        if (named |> List.map (fun (f, _, _) -> f) |> List.distinct).Length <> named.Length then
            fail 0 "a field is given twice"

        let body =
            defs
            |> List.mapi (fun i (f, ft) ->
                match named |> List.tryFind (fun (g, _, _) -> g = f) with
                | Some(_, _, tmp) -> mk (CLocal tmp) ft
                | None -> fallback i)

        List.foldBack (fun (_, ce, tmp) acc -> mk (CLet(tmp, ce, acc)) acc.ty) named (mk (CTuple body) (TCon rname))

    and infer (env: Map<string, Ty>) (e: Expr) : CExpr =
        match e with
        | At(ln, e) ->
            try
                let c = infer env e
                mk (CLine(ln, c)) c.ty
            with CompileError(0, msg) ->
                fail ln msg
        | Lit n -> mk (CInt n) (fresh Num)
        | BoolLit b -> mk (CBool b) tBool
        | StrLit s -> mk (CStr s) tStr
        | UnitLit -> mk CUnit tUnit
        | Var x ->
            match env.TryFind x with
            | Some t -> mk (CLocal x) t
            | None when ctors.ContainsKey x -> ctor env x []
            | None when sigs.ContainsKey x -> fail 0 (sprintf "'%s' is a function; call it (no first-class functions yet)" x)
            | None -> fail 0 (sprintf "unknown name '%s'" x)
        | Call("ignore", [ a ]) when not (sigs.ContainsKey "ignore") -> mk (CSeq(infer env a, mk CUnit tUnit)) tUnit
        | Call(c, args) when ctors.ContainsKey c && not (env.ContainsKey c) -> ctor env c args
        | Call(f, args) ->
            if env.ContainsKey f then
                fail 0 (sprintf "'%s' is not a function (no first-class functions yet)" f)

            let s =
                match sigs.TryGetValue f with
                | true, s -> s
                | _ -> fail 0 (sprintf "unknown function '%s'" f)

            let args = if s.pars.IsEmpty && args = [ UnitLit ] then [] else args
            let n = s.pars.Length

            if args.Length < n || (args.Length > n && not s.variadic) then
                fail 0 (sprintf "'%s' expects %d argument(s), got %d" f n args.Length)

            let cargs =
                args
                |> List.mapi (fun i a ->
                    let ca = infer env a

                    if i < n then
                        expect (sprintf "argument %d of '%s'" (i + 1) f) s.pars[i] ca.ty

                    ca)

            mk (CCall(f, cargs)) s.ret
        | Bin(op, a, b) ->
            let ca, cb = infer env a, infer env b
            let isArith = List.contains op [ "+"; "-"; "*"; "/"; "%" ]

            try
                unify (fresh (if op = "=" || op = "<>" then Eq else Num)) ca.ty
            with Mismatch ->
                fail 0 (sprintf "operator '%s' does not support type %s" op (show ca.ty))

            expect (sprintf "right operand of '%s'" op) ca.ty cb.ty
            mk (CBin(op, ca, cb)) (if isArith then ca.ty else tBool)
        | Neg a ->
            let ca = infer env a
            expect "operand of '-'" (fresh Num) ca.ty
            mk (CNeg ca) ca.ty
        | Not a ->
            let ca = infer env a
            expect "operand of 'not'" tBool ca.ty
            mk (CNot ca) tBool
        | If(c, t, e) ->
            let cc = infer env c
            expect "condition of 'if'" tBool cc.ty
            let ct = infer env t

            match e with
            | None ->
                expect "'if' without 'else'" tUnit ct.ty
                mk (CIf(cc, ct, mk CUnit tUnit)) tUnit
            | Some e ->
                let ce = infer env e
                expect "'else' branch" ct.ty ce.ty
                mk (CIf(cc, ct, ce)) ct.ty
        | Let(PIdent(x, None), ann, v, rest) when not (ctors.ContainsKey x) ->
            let cv = infer env v
            ann |> Option.iter (fun a -> expect (sprintf "value of '%s'" x) (toTy a) cv.ty)
            let cr = infer (env.Add(x, cv.ty)) rest
            mk (CLet(x, cv, cr)) cr.ty
        | Let(p, ann, v, rest) ->
            if ann.IsSome then
                fail 0 "type annotations on patterns are not supported yet"

            infer env (Match(v, [ p, None, rest ]))
        | Seq(a, b) ->
            let ca = infer env a
            let cb = infer env b
            mk (CSeq(ca, cb)) cb.ty
        | Tuple xs ->
            let cs = List.map (infer env) xs
            mk (CTuple cs) (TTuple(cs |> List.map (fun c -> c.ty)))
        | RecordLit fields ->
            let rname = recordOf (fresh Any) (fst fields.Head)
            let missing = fieldsOf rname |> List.filter (fun (f, _) -> not (List.exists (fst >> (=) f) fields))

            if not missing.IsEmpty then
                fail 0 (sprintf "record '%s' is missing field '%s'" rname (fst missing.Head))

            buildRecord env rname fields (fun _ -> failwith "unreachable")
        | Update(r, fields) ->
            let cr = infer env r
            let rname = recordOf cr.ty (fst fields.Head)
            expect "record update" (TCon rname) cr.ty
            let tmp = tmpName ()
            let defs = fieldsOf rname
            let built = buildRecord env rname fields (fun i -> mk (CField(mk (CLocal tmp) cr.ty, i)) (snd defs[i]))
            mk (CLet(tmp, cr, built)) built.ty
        | Field(r, f) ->
            let cr = infer env r
            let rname = recordOf cr.ty f
            expect (sprintf "field '%s'" f) (TCon rname) cr.ty
            let defs = fieldsOf rname

            match defs |> List.tryFindIndex (fst >> (=) f) with
            | Some i -> mk (CField(cr, i)) (snd defs[i])
            | None -> fail 0 (sprintf "record '%s' has no field '%s'" rname f)
        | Match(s, cases) ->
            let cs = infer env s
            let resTy = fresh Any

            let ccases =
                cases
                |> List.map (fun (p, guard, body) ->
                    let cp = pat p cs.ty
                    let vars = patVars cp

                    if (vars |> List.map fst |> List.distinct).Length <> vars.Length then
                        fail 0 "a variable is bound twice in this pattern"

                    let env = vars |> List.fold (fun (m: Map<_, _>) (x, t) -> m.Add(x, t)) env

                    let cg =
                        guard
                        |> Option.map (fun g ->
                            let cg = infer env g
                            expect "'when' guard" tBool cg.ty
                            cg)

                    let cb = infer env body
                    expect "match case" resTy cb.ty
                    cp, cg, cb)

            checkMatch unionCases (ccases |> List.map (fun (p, g, _) -> p, g.IsSome))
            mk (CMatch(cs, ccases)) resTy

    and ctor env c args =
        let u, tag = ctors[c]
        let fields = caseFields u tag

        let args =
            ctorArgs c args fields (function
                | Tuple xs -> Some xs
                | _ -> None) None

        let cargs =
            List.map2
                (fun a ft ->
                    let ca = infer env a
                    expect (sprintf "argument of '%s'" c) ft ca.ty
                    ca)
                args
                fields

        mk (CCtor(u, tag, cargs)) (TCon u)

    for ln, d in decls do
        try
            match d with
            | TypeDecl(name, body) ->
                if prims.Contains name || types.ContainsKey name then
                    fail 0 (sprintf "type '%s' is already defined" name)

                types[name] <- UnionDef [] // lets the body refer to the type itself

                match body with
                | RecordTy fields ->
                    let fs = fields |> List.map (fun (f, st) -> f, toTy st)

                    let rec contains t =
                        match t with
                        | TCon n -> n = name
                        | TTuple ts -> List.exists contains ts
                        | TVar _ -> false

                    if fs |> List.exists (snd >> contains) then
                        fail 0 (sprintf "record '%s' cannot contain itself; use a union" name)

                    if (fs |> List.map fst |> List.distinct).Length <> fs.Length then
                        fail 0 "duplicate field name"

                    types[name] <- RecordDef fs

                    for f, _ in fs do
                        fieldOwner[f] <- name
                | UnionTy cases ->
                    types[name] <- UnionDef(cases |> List.map (fun (c, sts) -> c, List.map toTy sts))

                    cases
                    |> List.iteri (fun i (c, _) ->
                        if ctors.ContainsKey c then
                            fail 0 (sprintf "constructor '%s' is already defined" c)

                        ctors[c] <- (name, i))
            | Extern(name, args, variadic, ret) ->
                if sigs.ContainsKey name then
                    fail 0 (sprintf "'%s' is already defined" name)

                let cty st =
                    match toTy st with
                    | TCon("int" | "c_int" | "cstr" | "unit") as t -> t
                    | t -> fail 0 (sprintf "extern '%s': type %s cannot cross the C boundary yet" name (show t))

                sigs[name] <-
                    { pars = List.map cty args
                      ret = cty ret
                      variadic = variadic
                      sym = "@" + name
                      isExtern = true }
            | Fun(name, isRec, pars, ret, body) ->
                if sigs.ContainsKey name then
                    fail 0 (sprintf "'%s' is already defined" name)

                if (pars |> List.map fst |> List.distinct).Length <> pars.Length then
                    fail 0 "duplicate parameter name"

                let ptys = pars |> List.map (snd >> Option.map toTy >> Option.defaultWith (fun () -> fresh Any))

                let s =
                    { pars = ptys
                      ret = ret |> Option.map toTy |> Option.defaultWith (fun () -> fresh Any)
                      variadic = false
                      sym = "@zs." + name
                      isExtern = false }

                if isRec then
                    sigs[name] <- s

                let cb = infer (List.zip (List.map fst pars) ptys |> Map.ofList) body
                expect (sprintf "result of '%s'" name) s.ret cb.ty
                sigs[name] <- s
                funs.Add(name, List.map fst pars, cb)
        with CompileError(0, msg) ->
            fail ln msg

    match sigs.TryGetValue "main" with
    | true, s when not s.isExtern ->
        if not s.pars.IsEmpty then
            fail 0 "'main' must take no parameters: let main () = ..."

        match resolve s.ret with
        | TCon("int" | "c_int" | "unit") -> ()
        | t -> fail 0 (sprintf "'main' must return int, c_int or unit, not %s" (show t))
    | _ -> fail 0 "no 'main' function"

    { types = types
      sigs = sigs
      funs = List.ofSeq funs }
