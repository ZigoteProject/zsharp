/// Derive expansion (DESIGN §3.1): a `derive` definition rewritten for one record or union into
/// ordinary impl definitions, before checking. The shape constructs are replaced:
///   match Shape.of x with Record r -> .. | Union c -> ..   a match over the type's cases
///   match Shape.pair a b with Same c -> .. | Different (i, j) -> ..   both values at once
///   match Shape.kind with RecordKind -> .. | UnionKind -> ..   picked statically
///   for f in c.fields do body   one copy of body per field (each typed at that field's type)
///   f.name f.index f.value f.left f.right f.default  c.name c.index c.count   field and case facts
///     (f.default: Some of a record field's default, None for a field without one)
///   Shape.build (fun f -> e)   a record from per-field results (stops at the first Error)
///   Shape.buildCase name (fun f -> e)   the named union case from per-field results, or None
/// The expansion has no places: the derive is written in another module, so an error in it is at
/// the use (the type declaration) instead.
open Types.Fail
open Syntax.Ast

/// A type's shape, as a derive sees it.
type ShapeInfo =
  /// a record: its fields' names, and their defaults
  | RecordShape of list<string * option<Expr>>
  /// a union: its cases' names and their fields' names
  | UnionShape of list<string * list<string>>

type private FieldInfo =
  { fname: string
    findex: int
    fvalue: option<Expr>
    left: option<Expr>
    right: option<Expr>
    fdefault: option<Expr> }

type private CaseInfo = { cname: string; cindex: int; cfields: list<FieldInfo> }

type private Bound =
  | CaseB of CaseInfo
  | FieldB of FieldInfo

let private field (name: string) (index: int) (value: option<Expr>) (l: option<Expr>) (r: option<Expr>) : FieldInfo =
  { fname = name; findex = index; fvalue = value; left = l; right = r; fdefault = None }

let private var (x: string) : Expr = plain (Var x)

let private bindPat (x: string) : Pat = plainPat (PIdent(x, None))

let private clause (p: Pat) (body: Expr) : Clause = { pattern = p; guard = None; body = body }

let private ctorPat (cn: string) (vars: list<Pat>) : Pat =
  match vars with
  | [] -> plainPat (PIdent(cn, None))
  | [ v ] -> plainPat (PIdent(cn, Some v))
  | vs -> plainPat (PIdent(cn, Some(plainPat (PTuple vs))))

let private ctorApp (cn: string) (args: list<Expr>) : Expr =
  match args with
  | [] -> var cn
  | [ a ] -> plain (Call(cn, [ a ]))
  | xs -> plain (Call(cn, [ plain (Tuple xs) ]))

// the case index of a union value
let private tagOf (x: Expr) (cases: list<string * list<string>>) : Expr =
  let one (i: int) (c: string * list<string>) =
    let (cn, fs) = c
    clause (ctorPat cn (List.map (fun _ -> plainPat PWild) fs)) (plain (Lit(i64 i)))
  plain (Match(x, List.mapi one cases))

// the clause of a derive's match for a case: its variable ("_" when it binds none), its pattern
// when it's more than a variable, and its body
let private branch (ctor: string) (cases: list<Clause>) : option<string * option<Pat> * Expr> =
  let one (c: Clause) =
    match c.pattern.pat with
    | PIdent(x, Some { pat = PIdent(v, None) }) when x = ctor -> Some(v, None, c.body)
    | PIdent(x, Some { pat = PWild }) when x = ctor -> Some("_", None, c.body)
    | PIdent(x, None) when x = ctor -> Some("_", None, c.body)
    | PIdent(x, Some q) when x = ctor -> Some("_", Some q, c.body)
    | _ -> None
  List.tryPick one cases

let private seqOf (es: list<Expr>) : Expr =
  match es with
  | [] -> plain UnitLit
  | _ -> List.reduce (fun a b -> plain (Seq(a, b))) es

/// The derive's definitions for one type: its name, the impl's head type (`self` in the derive),
/// its shape.
let expand (tname: string) (head: SType) (shape: ShapeInfo) (defs: list<Definition>) : list<Definition> / Fails =
  let count = ref 0
  let fresh (p: string) =
    count.Value <- count.Value + 1
    $"${p}{count.Value}"
  let rec substTy (st: SType) : SType =
    match st with
    | STVar "self" -> head
    | STName(n, args) -> STName(n, List.map substTy args)
    | STTuple ts -> STTuple(List.map substTy ts)
    | STFun(a, b) -> STFun(substTy a, substTy b)
    | STRow(t, ls, tail) -> STRow(substTy t, List.map substTy ls, tail)
    | other -> other
  let substParam (p: Param) : Param = { param = placelessPat p.param; ann = Option.map substTy p.ann }
  // match e with Ok v -> rest | Error err -> Error err
  let bindOk (e: Expr) (v: string) (rest: Expr) =
    let err = fresh "e"
    let okCase = clause (plainPat (PIdent("Ok", Some(bindPat v)))) rest
    let errCase = clause (plainPat (PIdent("Error", Some(bindPat err)))) (plain (Call("Error", [ var err ])))
    plain (Match(e, [ okCase; errCase ]))
  let rec ex (env: Map<string, Bound>) (e: Expr) : Expr / Fails =
    match e.e with
    // errors surface at the use site or the type declaration
    | At a
    | AtLine a -> ex env a
    | Match({ e = Call("Shape.of", [ x0 ]) }, cases) ->
      let x = ex env x0
      match shape with
      | RecordShape fields ->
        match branch "Record" cases with
        | Some(v, _, b) ->
          let fs = List.mapi (fun i (f, _) -> field f i (Some(plain (Field(x, f)))) None None) fields
          ex (Map.add v (CaseB { cname = tname; cindex = 0; cfields = fs }) env) b
        | None -> fail "the derive has no `Record` case"
      | UnionShape shapes ->
        match branch "Union" cases with
        | Some(v, _, b) ->
          let one (i: int) (c: string * list<string>) =
            let (cn, fnames) = c
            let vars = List.map (fun _ -> fresh "v") fnames
            let fs = List.mapi (fun j (f, w) -> field f j (Some(var w)) None None) (List.zip fnames vars)
            let ci = { cname = cn; cindex = i; cfields = fs }
            clause (ctorPat cn (List.map bindPat vars)) (ex (Map.add v (CaseB ci) env) b)
          plain (Match(x, List.mapi one shapes))
        | None -> fail "the derive has no `Union` case"
    | Match({ e = Call("Shape.pair", [ a0; b0 ]) }, cases) ->
      let a = ex env a0
      let b = ex env b0
      let (sameVar, sameBody) =
        match branch "Same" cases with
        | Some(v, _, body) -> (v, body)
        | None -> fail "Shape.pair needs a `Same` case"
      match shape with
      | RecordShape fields ->
        let fs = List.mapi (fun i (f, _) -> field f i None (Some(plain (Field(a, f)))) (Some(plain (Field(b, f))))) fields
        ex (Map.add sameVar (CaseB { cname = tname; cindex = 0; cfields = fs }) env) sameBody
      | UnionShape shapes ->
        let same (i: int) (c: string * list<string>) =
          let (cn, fnames) = c
          let ls = List.map (fun _ -> fresh "l") fnames
          let rs = List.map (fun _ -> fresh "r") fnames
          let fs = List.mapi (fun j f -> field f j None (Some(var (List.item j ls))) (Some(var (List.item j rs)))) fnames
          let ci = { cname = cn; cindex = i; cfields = fs }
          let p = plainPat (PTuple [ ctorPat cn (List.map bindPat ls); ctorPat cn (List.map bindPat rs) ])
          clause p (ex (Map.add sameVar (CaseB ci) env) sameBody)
        let sameCases = List.mapi same shapes
        let different =
          if List.length shapes < 2 then
            []
          else
            let body =
              match branch "Different" cases with
              | Some(_, Some { pat = PTuple [ pi; pj ] }, body) ->
                plain (Let(pi, None, tagOf a shapes, plain (Let(pj, None, tagOf b shapes, ex env body))))
              | Some("_", None, body) -> ex env body
              | Some(v, None, body) -> plain (Let(bindPat v, None, plain (Tuple [ tagOf a shapes; tagOf b shapes ]), ex env body))
              | _ -> fail "Shape.pair needs a `Different` case"
            [ clause (plainPat PWild) body ]
        plain (Match(plain (Tuple [ a; b ]), List.append sameCases different))
    | Match({ e = Var "Shape.kind" }, cases)
    | Match({ e = Call("Shape.kind", _) }, cases) ->
      let want =
        match shape with
        | RecordShape _ -> "RecordKind"
        | UnionShape _ -> "UnionKind"
      let isWant (c: Clause) =
        match c.pattern.pat with
        | PIdent(n, None) -> n = want
        | _ -> false
      match List.tryFind isWant cases with
      | Some c -> ex env c.body
      | None -> fail $"the derive has no `{want}` case"
    | ForIn(f, { e = Field({ e = Var c }, "fields") }, body) when Map.containsKey c env ->
      match Map.find c env with
      | CaseB ci -> seqOf (List.map (fun fi -> plain (DeriveCtx($"field {fi.fname}", ex (Map.add f (FieldB fi) env) body))) ci.cfields)
      | FieldB _ -> fail $"'{c}' is a field, not a record or case"
    | Field({ e = Var x }, prop) when Map.containsKey x env ->
      match (Map.find x env, prop) with
      | (CaseB ci, "name") -> plain (StrLit ci.cname)
      | (CaseB ci, "index") -> plain (Lit(i64 ci.cindex))
      | (CaseB ci, "count") -> plain (Lit(i64 (List.length ci.cfields)))
      | (FieldB fi, "name") -> plain (StrLit fi.fname)
      | (FieldB fi, "index") -> plain (Lit(i64 fi.findex))
      | (FieldB fi, "default") ->
        match fi.fdefault with
        | Some d -> plain (Call("Some", [ d ]))
        | None -> var "None"
      | (FieldB fi, "value")
      | (FieldB fi, "left")
      | (FieldB fi, "right") ->
        let pick =
          match prop with
          | "value" -> fi.fvalue
          | "left" -> fi.left
          | _ -> fi.right
        match pick with
        | Some y -> y
        | None -> fail $"{x}.{prop} is not available here"
      | _ -> fail $"unknown shape property '{x}.{prop}'"
    | Call("Shape.build", [ { e = Lambda([ { param = { pat = PIdent(f, None) } } ], body) } ]) ->
      match shape with
      | RecordShape fields ->
        let vars = List.map (fun _ -> fresh "b") fields
        let lit = List.map (fun (p: (string * option<Expr>) * string) -> ({ field = fst (fst p); nameAt = -1; value = var (snd p) } : FieldValue)) (List.zip fields vars)
        let inner = plain (Call("Ok", [ plain (RecordLit lit) ]))
        let step (acc: Expr) (item: int * ((string * option<Expr>) * string)) =
          let (i, ((fname, def), w)) = item
          let fi0 = field fname i None None None
          let fi = { fi0 with fdefault = def }
          bindOk (plain (DeriveCtx($"field {fname}", ex (Map.add f (FieldB fi) env) body))) w acc
        List.fold step inner (List.rev (List.indexed (List.zip fields vars)))
      | UnionShape _ -> fail "Shape.build needs a record; use Shape.buildCase for unions"
    | Call("Shape.buildCase", [ nameE; { e = Lambda([ { param = { pat = PIdent(f, None) } } ], body) } ]) ->
      match shape with
      | UnionShape shapes ->
        let nm = fresh "n"
        let chain (cn: string) (fnames: list<string>) =
          let vars = List.map (fun _ -> fresh "b") fnames
          let inner = plain (Call("Ok", [ ctorApp cn (List.map var vars) ]))
          let step (acc: Expr) (item: int * (string * string)) =
            let (i, (fname, w)) = item
            let fi = field fname i None None None
            bindOk (plain (DeriveCtx($"field {fname}", ex (Map.add f (FieldB fi) env) body))) w acc
          List.fold step inner (List.rev (List.indexed (List.zip fnames vars)))
        let ifCase (acc: Expr) (c: string * list<string>) =
          let (cn, fnames) = c
          plain (If(plain (Bin("=", var nm, plain (StrLit cn))), plain (Call("Some", [ chain cn fnames ])), Some acc))
        let ifs = List.fold ifCase (var "None") (List.rev shapes)
        plain (Let(bindPat nm, None, ex env nameE, ifs))
      | RecordShape _ -> fail "Shape.buildCase needs a union; use Shape.build for records"
    | Lambda(ps, b) -> plain (Lambda(List.map substParam ps, ex env b))
    | LetFun(n, r, ps, t, b, rest) -> plain (LetFun(n, r, List.map substParam ps, Option.map substTy t, ex env b, ex env rest))
    | Let(p, t, v, b) -> plain (Let(placelessPat p, Option.map substTy t, ex env v, ex env b))
    | LetMut(x, t, v, b) -> plain (LetMut(x, Option.map substTy t, ex env v, ex env b))
    | Match(sc, cases) ->
      let one (c: Clause) = { pattern = placelessPat c.pattern; guard = Option.map (ex env) c.guard; body = ex env c.body }
      plain (Match(ex env sc, List.map one cases))
    | TryBind(p, a, b) -> plain (TryBind(placelessPat p, ex env a, ex env b))
    | _ ->
      let m = mapExpr (ex env) e
      { m with at = -1 }
  let one (d: Definition) : Definition =
    { defAt = -1
      dname = d.dname
      dpars = List.map substParam d.dpars
      dret = Option.map substTy d.dret
      dbody = ex Map.empty d.dbody }
  List.map one defs
