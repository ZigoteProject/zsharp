/// Derive expansion (DESIGN §3.1): rewrites a `derive` definition for one record or union
/// into ordinary impl definitions, before type checking. The shape constructs are replaced:
///   match Shape.of x with Record r -> .. | Union c -> ..   a match over the type's cases
///   match Shape.pair a b with Same c -> .. | Different (i, j) -> ..   both values at once
///   match Shape.kind with RecordKind -> .. | UnionKind -> ..   picked statically
///   for f in c.fields do body   one copy of body per field (each typed at that field's type)
///   f.name f.index f.value f.left f.right  c.name c.index c.count   field and case facts
///   Shape.build (fun f -> e)   a record from per-field results (stops at the first Error)
///   Shape.buildCase name (fun f -> e)   the named union case from per-field results, or None
module Derive

open Syntax

type ShapeInfo =
    | RecordShape of string list // field names
    | UnionShape of (string * string list) list // case names and their field names

type private FieldInfo =
    { name: string
      index: int
      value: Expr option
      left: Expr option
      right: Expr option }

type private CaseInfo =
    { cname: string
      cindex: int
      fields: FieldInfo list }

type private Bound =
    | Case of CaseInfo
    | FieldB of FieldInfo

type Def = int * string * Param list * SType option * Expr

let expand (deriveName: string) (tname: string) (head: SType) (shape: ShapeInfo) (defs: Def list) : Def list =
    let failD msg =
        fail 0 msg

    let count = ref 0

    let fresh (p: string) =
        count.Value <- count.Value + 1
        sprintf "$%s%d" p count.Value

    let rec substTy st =
        match st with
        | STVar "self" -> head
        | STName(n, args) -> STName(n, List.map substTy args)
        | STTuple ts -> STTuple(List.map substTy ts)
        | STFun(a, b) -> STFun(substTy a, substTy b)
        | STVar _ -> st

    let substParam ((p, ann): Param) : Param = p, Option.map substTy ann

    let ctorPat (cn: string) (vars: Pat list) =
        match vars with
        | [] -> PIdent(cn, None)
        | [ v ] -> PIdent(cn, Some v)
        | vs -> PIdent(cn, Some(PTuple vs))

    let ctorApp (cn: string) (args: Expr list) =
        match args with
        | [] -> Var cn
        | [ a ] -> Call(cn, [ a ])
        | xs -> Call(cn, [ Tuple xs ])

    let field name index value left right =
        { name = name
          index = index
          value = value
          left = left
          right = right }

    /// The case index of a union value.
    let tagOf (x: Expr) cases =
        Match(x, cases |> List.mapi (fun i (cn, fs: string list) -> ctorPat cn (fs |> List.map (fun _ -> PWild)), None, Lit(int64 i)))

    let branch (ctor: string) cases =
        cases
        |> List.tryPick (fun (p, _, b) ->
            match p with
            | PIdent(c, Some(PIdent(v, None))) when c = ctor -> Some(v, None, b)
            | PIdent(c, Some PWild)
            | PIdent(c, None) when c = ctor -> Some("_", None, b)
            | PIdent(c, Some p) when c = ctor -> Some("_", Some p, b)
            | _ -> None)

    let seqOf (es: Expr list) =
        match es with
        | [] -> UnitLit
        | es -> List.reduce (fun a b -> Seq(a, b)) es

    /// match e with Ok v -> rest | Error err -> Error err
    let bindOk (e: Expr) (v: string) (rest: Expr) =
        let err = fresh "e"

        Match(
            e,
            [ PIdent("Ok", Some(PIdent(v, None))), None, rest
              PIdent("Error", Some(PIdent(err, None))), None, Call("Error", [ Var err ]) ]
        )

    let rec ex (env: Map<string, Bound>) (e: Expr) : Expr =
        match e with
        | At(_, a) -> ex env a // errors surface at the use site or the type declaration
        | Match(Call("Shape.of", [ x ]), cases) ->
            match shape with
            | RecordShape fields ->
                match branch "Record" cases with
                | Some(v, _, b) ->
                    let ci =
                        { cname = tname
                          cindex = 0
                          fields = fields |> List.mapi (fun i f -> field f i (Some(Field(x, f))) None None) }

                    ex (env.Add(v, Case ci)) b
                | None -> failD "the derive has no `Record` case"
            | UnionShape cases' ->
                match branch "Union" cases with
                | Some(v, _, b) ->
                    Match(
                        x,
                        cases'
                        |> List.mapi (fun i (cn, fnames) ->
                            let vars = fnames |> List.map (fun _ -> fresh "v")

                            let ci =
                                { cname = cn
                                  cindex = i
                                  fields = List.mapi2 (fun j f var -> field f j (Some(Var var)) None None) fnames vars }

                            ctorPat cn (vars |> List.map (fun v -> PIdent(v, None))), None, ex (env.Add(v, Case ci)) b)
                    )
                | None -> failD "the derive has no `Union` case"
        | Match(Call("Shape.pair", [ a; b ]), cases) ->
            let same =
                match branch "Same" cases with
                | Some(v, _, body) -> v, body
                | None -> failD "Shape.pair needs a `Same` case"

            match shape with
            | RecordShape fields ->
                let ci =
                    { cname = tname
                      cindex = 0
                      fields = fields |> List.mapi (fun i f -> field f i None (Some(Field(a, f))) (Some(Field(b, f)))) }

                ex (env.Add(fst same, Case ci)) (snd same)
            | UnionShape cases' ->
                let sameCases =
                    cases'
                    |> List.mapi (fun i (cn, fnames) ->
                        let ls = fnames |> List.map (fun _ -> fresh "l")
                        let rs = fnames |> List.map (fun _ -> fresh "r")

                        let ci =
                            { cname = cn
                              cindex = i
                              fields =
                                List.mapi (fun j f -> field f j None (Some(Var(List.item j ls))) (Some(Var(List.item j rs)))) fnames }

                        let pat vs = ctorPat cn (vs |> List.map (fun v -> PIdent(v, None)))
                        PTuple [ pat ls; pat rs ], None, ex (env.Add(fst same, Case ci)) (snd same))

                let different =
                    if cases'.Length < 2 then
                        []
                    else
                        let body =
                            match branch "Different" cases with
                            | Some(_, Some(PTuple [ pi; pj ]), body) -> Let(pi, None, tagOf a cases', Let(pj, None, tagOf b cases', ex env body))
                            | Some("_", None, body) -> ex env body
                            | Some(v, None, body) -> Let(PIdent(v, None), None, Tuple [ tagOf a cases'; tagOf b cases' ], ex env body)
                            | _ -> failD "Shape.pair needs a `Different` case"

                        [ PWild, None, body ]

                Match(Tuple [ a; b ], sameCases @ different)
        | Match((Var "Shape.kind" | Call("Shape.kind", _)), cases) ->
            let want =
                match shape with
                | RecordShape _ -> "RecordKind"
                | UnionShape _ -> "UnionKind"

            match cases |> List.tryFind (fun (p, _, _) -> p = PIdent(want, None)) with
            | Some(_, _, b) -> ex env b
            | None -> failD (sprintf "the derive has no `%s` case" want)
        | ForIn(f, Field(Var c, "fields"), body) when env.ContainsKey c ->
            match env[c] with
            | Case ci ->
                ci.fields
                |> List.map (fun fi -> DeriveCtx(sprintf "field %s" fi.name, ex (env.Add(f, FieldB fi)) body))
                |> seqOf
            | FieldB _ -> failD (sprintf "'%s' is a field, not a record or case" c)
        | Field(Var v, prop) when env.ContainsKey v ->
            match env[v], prop with
            | Case ci, "name" -> StrLit ci.cname
            | Case ci, "index" -> Lit(int64 ci.cindex)
            | Case ci, "count" -> Lit(int64 ci.fields.Length)
            | FieldB fi, "name" -> StrLit fi.name
            | FieldB fi, "index" -> Lit(int64 fi.index)
            | FieldB fi, ("value" | "left" | "right") ->
                let pick =
                    match prop with
                    | "value" -> fi.value
                    | "left" -> fi.left
                    | _ -> fi.right

                match pick with
                | Some x -> x
                | None -> failD (sprintf "%s.%s is not available here" v prop)
            | _ -> failD (sprintf "unknown shape property '%s.%s'" v prop)
        | Call("Shape.build", [ Lambda([ (PIdent(f, None), _) ], body) ]) ->
            match shape with
            | RecordShape fields ->
                let vars = fields |> List.map (fun _ -> fresh "b")
                let inner = Call("Ok", [ RecordLit(List.zip fields (vars |> List.map Var)) ])

                List.foldBack
                    (fun (i, fname, var) acc ->
                        let fi = field fname i None None None
                        bindOk (DeriveCtx(sprintf "field %s" fname, ex (env.Add(f, FieldB fi)) body)) var acc)
                    (List.zip3 [ 0 .. fields.Length - 1 ] fields vars)
                    inner
            | UnionShape _ -> failD "Shape.build needs a record; use Shape.buildCase for unions"
        | Call("Shape.buildCase", [ nameE; Lambda([ (PIdent(f, None), _) ], body) ]) ->
            match shape with
            | UnionShape cases' ->
                let nm = fresh "n"

                let chain (cn, fnames: string list) =
                    let vars = fnames |> List.map (fun _ -> fresh "b")
                    let inner = Call("Ok", [ ctorApp cn (vars |> List.map Var) ])

                    List.foldBack
                        (fun (i, fname, var) acc ->
                            let fi = field fname i None None None
                            bindOk (DeriveCtx(sprintf "field %s" fname, ex (env.Add(f, FieldB fi)) body)) var acc)
                        (List.zip3 [ 0 .. fnames.Length - 1 ] fnames vars)
                        inner

                let ifs =
                    List.foldBack
                        (fun (cn, fnames) acc -> If(Bin("=", Var nm, StrLit cn), Call("Some", [ chain (cn, fnames) ]), Some acc))
                        cases'
                        (Var "None")

                Let(PIdent(nm, None), None, ex env nameE, ifs)
            | RecordShape _ -> failD "Shape.buildCase needs a union; use Shape.build for records"
        | Lambda(ps, b) -> Lambda(List.map substParam ps, ex env b)
        | LetFun(n, r, ps, t, b, rest) -> LetFun(n, r, List.map substParam ps, Option.map substTy t, ex env b, ex env rest)
        | Let(p, t, v, b) -> Let(p, Option.map substTy t, ex env v, ex env b)
        | LetMut(x, t, v, b) -> LetMut(x, Option.map substTy t, ex env v, ex env b)
        | _ -> mapExpr (ex env) e

    defs
    |> List.map (fun (_, name, ps, ret, body) -> 0, name, List.map substParam ps, Option.map substTy ret, ex Map.empty body)
