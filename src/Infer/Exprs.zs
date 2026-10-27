/// Expressions: an AST expression checked in a scope (its locals) and lowered to Core with its
/// type (the F# compiler's Typer.infer and what it calls). The type expected of an expression,
/// when the context knows it, is its hint: it reaches the expressions that produce the value
/// (if and match branches, the tails of let and sequences, tuple, list and array elements) and
/// gives a lambda its parameters' types, a record literal its record, a number with a unit its
/// type; and a value of another type is made the dyn, span or share expected of it.
open Types.Ty
open Types.Vars
open Types.Norm
open Types.Fail
open Core.Ir
open Syntax.Ast
open Builtins
open Cx

// a local variable
let private localOf (u: string) (t: Ty) (isMut: bool) (depth: int) : Local = { u = u; ty = t; mut = isMut; depth = depth }

// the locals a pattern bound (each name's unique one, with its type) added to env
let private withVars (env: Map<string, Local>) (names: Map<string, string>) (vars: list<string * Ty>) (depth: int) : Map<string, Local> =
  let typeOf (u: string) = snd (List.find (fun (y, _) -> y = u) vars)
  Map.fold (fun m x u -> Map.add x (localOf u (typeOf u) false depth) m) env names

// parameters (name, unique name, type) as locals at a depth, added to env
let private withPars (env: Map<string, Local>) (pars: list<string * string * Ty>) (depth: int) : Map<string, Local> =
  List.fold (fun m (x, u, t) -> Map.add x (localOf u t false depth) m) env pars

let private parsOf (pars: list<string * string * Ty>) : list<string * Ty> = List.map (fun (_, u, t) -> (u, t)) pars

let private parTypes (pars: list<string * string * Ty>) : list<Ty> = List.map (fun (_, _, t) -> t) pars

// an expression without its statement marks
let rec private unAt (e: Expr) : Expr =
  match e.e with
  | At a
  | AtLine a -> unAt a
  | _ -> e

/// Operators on numbers and booleans: pure, as fusion takes them.
let pureOps : Set<string> =
  Set.ofList [ "+"; "-"; "*"; "/"; "%"; "="; "<>"; "<"; ">"; "<="; ">="; "&&"; "||"; "&&&"; "|||"; "^^^"; "<<<"; ">>>" ]

// whether a hint goes past the expression to what gives its value (its branches and tails)
let private passesHint (e: Expr) : bool =
  match e.e with
  | At _
  | AtLine _
  | If(_, _, Some _)
  | Match _
  | Seq _
  | Let _
  | LetMut _
  | LetFun _
  | LetRecGroup _
  | Unsafe _ -> true
  | _ -> false

/// A called name as the source would write it.
let shownName (f: string) : string = if String.startsWith "global::" f then skipChars 8 f else f

/// An expression as text, near enough to what was written: a failed assert's operands (0009).
let rec exprText (e: Expr) : string =
  let atom (x: Expr) =
    match x.e with
    | Var _
    | Lit _
    | CharLit _
    | FloatLit _
    | BoolLit _
    | StrLit _
    | UnitLit
    | Tuple _
    | Field _
    | Index _
    | ArrayLit _
    | RecordLit _
    | Call(_, [])
    | LayoutOf _
    | At _
    | AtLine _ -> exprText x
    | _ -> "(" + exprText x + ")"
  // a list literal's elements, when it is one
  let rec items (x: Expr) : option<list<Expr>> =
    match x.e with
    | Var "[]" -> Some []
    | Call("::", [ { e = Tuple [ y; rest ] } ]) -> Option.map (fun ys -> y :: ys) (items rest)
    | _ -> None
  match e.e with
  | Var x -> x
  | Lit n -> $"{n}"
  | CharLit c -> "'" + String.ofChar (char c) + "'"
  | FloatLit f -> $"{f}"
  | BoolLit b -> if b then "true" else "false"
  | StrLit s -> "\"" + String.replace (String.replace (String.replace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n" + "\""
  | UnitLit -> "()"
  | Call("::", _) when Option.isSome (items e) -> "[ " + String.join "; " (List.map exprText (Option.get (items e))) + " ]"
  | Call("::", [ { e = Tuple [ x; rest ] } ]) -> atom x + " :: " + exprText rest
  | Call(f, []) -> shownName f
  | Call(f, args) -> shownName f + " " + String.join " " (List.map atom args)
  | App(f, args) -> atom f + " " + String.join " " (List.map atom args)
  | Bin(op, a, b) -> exprText a + " " + op + " " + exprText b
  // what the parser makes of a || b and a && b
  | If(a, { e = BoolLit true }, Some b) -> exprText a + " || " + exprText b
  | If(a, b, Some { e = BoolLit false }) -> exprText a + " && " + exprText b
  | Neg a -> "-" + atom a
  | Not a -> "not " + atom a
  | Tuple xs -> "(" + String.join ", " (List.map exprText xs) + ")"
  | ArrayLit xs -> "[| " + String.join "; " (List.map exprText xs) + " |]"
  | RecordLit fs -> "{ " + String.join "; " (List.map (fun (f: FieldValue) -> f.field + " = " + exprText f.value) fs) + " }"
  | Field(r, f) -> atom r + "." + f
  | Index(a, i) -> atom a + ".[" + exprText i + "]"
  | LayoutOf(kind, t, field) -> kind + "<" + stypeText t + ">" + (if field = "" then "" else " \"" + field + "\"")
  | Typed(x, _)
  | At x
  | AtLine x -> exprText x
  | _ -> "…"

// the element type and lanes of a SIMD vector type
let private vectorElem (n: string) : string =
  match vectorInfo n with
  | Some(e, _) -> e
  | None -> ""

// a lambda of one parameter
let private lam (x: string) (e: Expr) : Expr = plain (Lambda([ { param = plainPat (PIdent(x, None)); ann = None } ], e))

// the expression under one statement mark
let private unAtOnce (e: Expr) : Expr =
  match e.e with
  | At a
  | AtLine a -> a
  | _ -> e

// whether an assert's condition is a comparison (its sides shown when it fails)
let private isComparison (e: Expr) : bool =
  match (unAtOnce e).e with
  | Bin("=", _, _)
  | Bin("<>", _, _)
  | Bin("<", _, _)
  | Bin("<=", _, _)
  | Bin(">", _, _)
  | Bin(">=", _, _) -> true
  | _ -> false

// the element type expected of a list literal, when a list's is
let private listElement (cx: Cx) (hint: option<Ty>) : option<Ty> =
  match Option.map (prune cx.v) hint with
  | Some(TCon("list", [ el ])) -> Some el
  | _ -> None

// the file's name, for messages (assert's)
let private fileName (cx: Cx) : string =
  let path = cx.file.Value.source.path
  Option.defaultValue path (List.tryLast (String.split "/" path))

// a local function of a `let rec … and …` group, before its body is checked
type private Prepared =
  { pnode: Expr
    pname: string
    ppars: list<string * string * Ty>
    prty: Ty
    pfty: Ty
    pself: Local
    pbody: Expr
    prow: Ty }

/// A layout fact's type (0004), and for offsetof its field's index among the record's fields.
let layoutType (cx: Cx) (kind: string) (st: SType) (field: string) : Ty * int =
  let t = toTy cx None st
  if kind <> "offsetof" then
    (t, 0)
  else
    let notRecord () = fail $"offsetof names a record's field, and {show cx t} isn't a record"
    match prune cx.v t with
    | TCon(n, _) ->
      match Map.tryFind n cx.types.Value with
      | Some { def = RecordDef fs } ->
        match List.tryFind (fun (_, (f, _)) -> f = field) (List.mapi (fun i x -> (i, x)) fs) with
        | Some(i, _) -> (t, i)
        | None -> fail $"{shortName n} has no field '{field}': its fields are {String.join ", " (List.map fst fs)}"
      | _ -> notRecord ()
    | _ -> notRecord ()

/// What a layout fact gives on this target: sizeof's size, alignof's alignment, offsetof's
/// field's offset; None while a type variable is in the type (a generic function's, known after
/// monomorphization).
let layoutValue (cx: Cx) (kind: string) (t: Ty) (index: int) : option<int> =
  let types = cx.types.Value
  match kind with
  | "sizeof" -> Option.map fst (Types.Repr.layout cx.v types cx.word t)
  | "alignof" -> Option.map snd (Types.Repr.layout cx.v types cx.word t)
  | _ -> Types.Repr.offsetOf cx.v types cx.word t index

/// An expression's Core, with the type expected of it, if known.
let rec inferWith (cx: Cx) (env: Map<string, Local>) (depth: int) (hint: option<Ty>) (e: Expr) : CExpr =
  match hint with
  | None -> inferNode cx env depth None e
  | Some h when passesHint e -> inferNode cx env depth hint e
  | Some h ->
    match prune cx.v h with
    | TCon(n, []) when isDynName n -> toDyn cx (inferNode cx env depth None e) h
    | TCon("span", [ _ ]) -> toSpan cx (inferNode cx env depth None e) h
    // a lambda's parameters get their types
    | TCon("share", [ f ]) -> toShare cx (inferNode cx env depth (Some f) e) h
    | _ -> inferNode cx env depth hint e

/// An expression's Core.
and infer (cx: Cx) (env: Map<string, Local>) (depth: int) (e: Expr) : CExpr = inferWith cx env depth None e

/// An expression's Core, with the type expected of it.
and inferHint (cx: Cx) (env: Map<string, Local>) (depth: int) (hint: Ty) (e: Expr) : CExpr = inferWith cx env depth (Some hint) e

/// An array or a Buffer where a span is expected: a span over all of it.
and toSpan (cx: Cx) (c: CExpr) (hint: Ty) : CExpr =
  match (prune cx.v c.ty, prune cx.v hint) with
  | (TCon("array", [ el ]), TCon("span", [ h ])) ->
    expect cx "span" h el
    mk (CPrim("span.ofArray", [ c ])) (TCon("span", [ el ]))
  | (TCon("Buffer", [ el ]), TCon("span", [ h ])) ->
    expect cx "span" h el
    mk (CPrim("span.ofBuffer", [ c ])) (TCon("span", [ el ]))
  | _ -> c

/// A function where a share<F> is expected (it crosses threads): as it is when it's one already
/// (or its type isn't known yet), else checked that what it captures can be shared, and marked
/// (share.fn) for the check of what it calls.
and toShare (cx: Cx) (c: CExpr) (hint: Ty) : CExpr =
  match (prune cx.v c.ty, prune cx.v hint) with
  | (TFun _, TCon("share", [ f ])) ->
    let rule (s: string) = "a function run on another thread must have no effects: this one performs " + s + "; handle it inside"
    expectNoEffects cx rule "function crossing threads" f c.ty
    checkCaptures cx c
    mk (CPrim("share.fn", [ c ])) hint
  | _ -> c

/// What a function crossing threads captures must be Share: each local it refers to, and through
/// a local function it refers to, what that one captures.
and checkCaptures (cx: Cx) (c: CExpr) =
  let seen = ref Set.empty
  let rec go (e: CExpr) (via: list<string>) =
    let bound = Set.ofList (binders e)
    for (x, t) in refs e do
      if not (Set.contains x bound) && not (Set.contains x seen.Value) then
        seen.Value <- Set.add x seen.Value
        let name =
          match beforeLastDot x with
          | Some n -> n
          | None -> x
        match (prune cx.v t, Map.tryFind x cx.localValues.Value) with
        | (TFun _, Some def) -> go def (name :: via)
        | _ ->
          let through =
            match via with
            | [] -> ""
            | fs -> " (through " + quoted (List.rev fs) + ")"
          let blocked =
            handle
              unify cx (fresh cx.v (kTrait "Share")) t
              None
            with
            | Mismatched.throw m, _ -> Some m
          match blocked with
          | Some(NoImpl(_, part0)) ->
            let part =
              match Types.Repr.shareBlocker cx.v (fun _ -> ()) cx.types.Value Set.empty t with
              | Some p -> p
              | None -> part0
            let holds = if prune cx.v part = prune cx.v t then "" else $", which holds {show cx part}"
            match prune cx.v t with
            | TFun _ ->
              fail $"this function crosses threads, but it captures '{name}'{through}, a function that may capture what can't be shared: declare it share<{show cx t}>"
            | _ ->
              fail $"this function crosses threads, but it captures '{name}'{through} : {show cx t}{holds}, which can't be shared between threads; share state through Atomic, Mutex or Channel, or return a result per job"
          | Some Differ ->
            fail $"this function crosses threads, but it captures '{name}'{through} : {show cx t}, which can't be shared between threads; share state through Atomic, Mutex or Channel, or return a result per job"
          | None -> ()
  go c []

/// A value where a dyn Trait is expected: as it is when it's one already (or its type isn't known
/// yet), else with its type's impl of the trait.
and toDyn (cx: Cx) (c: CExpr) (hint: Ty) : CExpr =
  match (prune cx.v c.ty, prune cx.v hint) with
  | (TCon(n, []), _) when isDynName n -> c
  | (TVar r, _) when Option.isSome (kindOf cx.v r).allowed ->
    // a literal: its own type (int, f64, string), made a dyn
    settle cx c.ty
    toDyn cx c hint
  | (TVar _, _) -> c
  | (t, TCon(d, [])) ->
    let tr = skipChars 4 d
    expect cx $"value for a dyn {shortName tr}" (fresh cx.v (kTrait tr)) t
    mk (CPrim("dyn.box:" + tr, [ c ])) hint
  | _ -> c

/// An expression's Core; `hint` is the type expected of it when it's a lambda, a record literal,
/// a number with a unit, or what gives such a value (passesHint).
and inferNode (cx: Cx) (env: Map<string, Local>) (depth: int) (hint: option<Ty>) (node: Expr) : CExpr =
  let v = cx.v
  let inf (x: Expr) = infer cx env depth x
  match node.e with
  | At inner ->
    cx.currentStmt.Value <- node.at
    let c = located cx node.at false (fun () -> inferWith cx env depth hint inner)
    mk (CLine(lineOf cx node.at, c)) c.ty
  | AtLine inner ->
    cx.currentStmt.Value <- node.at
    let c = located cx node.at true (fun () -> inferWith cx env depth hint inner)
    mk (CLine(lineOf cx node.at, c)) c.ty
  | Lit n -> mk (CInt n) (fresh v kInt)
  | CharLit c -> mk (CInt(i64 c)) tChar
  | FloatLit f -> mk (CFloat f) (fresh v kFloat)
  | BoolLit b -> mk (CBool b) tBool
  | StrLit s -> mk (CStr s) (fresh v kStrLit)
  | UnitLit -> mk CUnit tUnit
  | Var x ->
    let r = located cx node.at false (fun () -> value cx env depth x)
    // a generic constant (Map.empty) shows its scheme, as F# does: an instance of its own, not
    // the one this use settles
    let shown =
      match (if Map.containsKey x env then None else resolveName cx x) with
      | Some q when Map.containsKey q cx.consts.Value ->
        let own = valueQ cx Map.empty depth q
        let s = schemed cx own.ty
        if s <> own.ty then s else r.ty
      | _ -> r.ty
    recordKey cx node.at x shown false (keyOf cx env x) false
    r
  | Call("$task", [ { e = Lambda([ { param = { pat = PUnit } } ], body) } ]) -> taskExpr cx env depth body
  | Call("$await", [ x ]) -> awaitExpr cx env depth false x
  | Call("$awaitLast", [ x ]) -> awaitExpr cx env depth true x
  | Call("$seq", [ body ]) ->
    // seq { }: a Seq of the body, a function performing Yield of the elements
    let a = fresh v kAny
    let bodyTy = TFun(tUnit, tUnit, rowExt (TCon("Yield", [ a ])) rowEmpty)
    let cl = inferHint cx env depth bodyTy body
    let explain () =
      match prune v cl.ty with
      | TFun(_, r, row) when prune v r = tUnit ->
        let others = List.filter (fun l -> labelName v l <> "Yield") (fst (rowParts v row))
        fail $"a seq {{ }} only yields: this one performs {String.join ", " (List.map (show cx) others)} too; handle it inside"
      | TFun(_, r, _) -> fail $"a seq {{ }}'s body yields its elements and gives unit, not {show cx r}"
      | _ -> fail "a seq { } needs a body"
    if not (unifies cx bodyTy cl.ty) then
      explain ()
    match Map.tryFind "Collections.Seq" cx.ctors.Value with
    | Some(u, tag) -> mk (CCtor(u, tag, [ cl ])) (TCon(u, [ a ]))
    | None -> fail "seq { } needs the library's Seq"
  | Call("$format", [ x; { e = StrLit spec } ]) -> formatExpr cx env depth x spec
  | Call("$yield", [ x ]) -> perform cx env depth "Yield.yield" [ x ]
  | Call("$yieldAll", [ x ]) -> call cx env depth "Collections.Seq.yieldAll" [ x ]
  | Handle(body, ops, ret) -> handleExpr cx env depth body ops ret
  | Call("assert", [ c ]) when not (Map.containsKey "assert" env) && isComparison c -> assertCompare cx env depth (unAtOnce c)
  | Call("assert", [ c ]) when not (Map.containsKey "assert" env) ->
    // the location goes into the message: "assertion failed at file:line"
    let cc = inf c
    expect cx "assert" tBool cc.ty
    mk (CPrim($"assert:{fileName cx}:{lineOf cx cx.currentStmt.Value}", [ cc ])) tUnit
  | Call("::", [ { e = Tuple [ hd; tl ] } ]) when Option.isSome (listElement cx hint) ->
    // a list literal: its elements get the element type expected of them
    let el = Option.get (listElement cx hint)
    callNode cx env depth node "::" [ plain (Tuple [ hd; tl ]) ] [ Some el; hint ]
  | Call(f, args) ->
    let isExpect =
      match args with
      | [ _; _ ] -> not (Map.containsKey f env) && resolveName cx f = Some "Testing.expect"
      | _ -> false
    if isExpect then
      // an expect test: its place goes in, so zs test --update can find its literal (0009)
      let x = List.item 0 args
      let lit = List.item 1 args
      match (unAtOnce lit).e with
      | StrLit _ -> call cx env depth "Testing.expectAt" [ x; lit; plain (StrLit(fileName cx)); plain (Lit(i64 (lineOf cx cx.currentStmt.Value))) ]
      | _ -> fail "expect's expected text is a string literal, which zs test --update can rewrite"
    else
      callNode cx env depth node f args []
  | App({ e = Field(r, f); at = fat }, args) ->
    match caseThrough cx env r f with
    | Some c -> apply cx env depth (inf { e = Var c; at = fat }) args None
    | None ->
      let cr = inf r
      settle cx cr.ty
      match memberOf cx cr.ty f with
      | Some m when not m.isStatic && not m.isProperty ->
        let res = memberCall cx env depth m (Some cr) args f
        recordKey cx fat f res.ty false m.gname false
        res
      | _ -> apply cx env depth (field cx cr f) args None
  | App(h, args) -> apply cx env depth (inf h) args None
  | Lambda(ps0, body0) ->
    let (ps, body) = lowerParams cx ps0 body0
    let pars = List.map (fun (x, ann) -> (x, uniq cx x, annot cx ann)) ps
    recordParams cx ps0 pars
    // the function type expected of it gives the unannotated parameters their types before the
    // body is typed: in xs |> List.map (fun s -> s.Length), s is known
    match hint with
    | Some h ->
      match prune v h with
      | TFun _ ->
        let rec give (t: Ty) (pars: list<string * string * Ty>) (ps: list<string * option<SType>>) =
          match (prune v t, pars, ps) with
          | (TFun(p, r, _), (_, _, pt) :: parsRest, (_, ann) :: psRest) ->
            if Option.isNone ann then
              unify cx pt p
            give r parsRest psRest
          | _ -> ()
        give h pars ps
      | _ -> ()
    | None -> ()
    let envB = withPars env pars (depth + 1)
    let row = fresh v kRow
    let cb = withRow cx row (fun () -> infer cx envB (depth + 1) body)
    mk (CLam(parsOf pars, cb)) (funTyRow (parTypes pars) cb.ty row)
  | LetFun(name, isRec, ps0, ret, body0, rest) ->
    let (ps, body) = lowerParams cx ps0 body0
    let pars = List.map (fun (x, ann) -> (x, uniq cx x, annot cx ann)) ps
    recordParams cx ps0 pars
    let (rty, declared) = annotRet cx ret
    let row =
      match declared with
      | Some r -> r
      | None -> fresh v kRow
    let fty = funTyRow (parTypes pars) rty row
    let self = localOf (uniq cx name) fty false depth
    let envB = withPars (if isRec then Map.add name self env else env) pars (depth + 1)
    let checkBody () =
      let c = withRow cx row (fun () -> infer cx envB (depth + 1) body)
      expect cx $"result of '{name}'" rty c.ty
      c
    let cb = recovered cx (fun () -> rty) checkBody
    recordKey cx node.at name fty false self.u true
    cx.localValues.Value <- Map.add self.u (mk (CLam(parsOf pars, cb)) fty) cx.localValues.Value
    let cr = inferWith cx (Map.add name self env) depth hint rest
    mk (CLetFun(self.u, isRec, parsOf pars, cb, cr)) cr.ty
  | LetRecGroup(members, rest) -> letRecGroup cx env depth hint members rest
  | Let(p, ann, value0, rest) ->
    let plainVar =
      match p.pat with
      | PIdent(x, None) -> if isCtor cx x then None else Some x
      | _ -> None
    match plainVar with
    | Some x ->
      let pat = p.patAt
      let declared =
        match ann with
        | Some a -> Some(toTy cx None a)
        | None -> None
      let value () =
        match declared with
        | Some t ->
          let c = inferHint cx env depth t value0
          expect cx $"value of '{x}'" t c.ty
          c
        | None -> inf value0
      let fallback () =
        match declared with
        | Some t -> t
        | None -> fresh v kAny
      let cv = recovered cx fallback value
      let u = uniq cx x
      recordKey cx pat x cv.ty (Option.isNone ann) u true
      cx.localValues.Value <- Map.add u cv cx.localValues.Value
      let l = localOf u cv.ty false depth
      let cr = inferWith cx (Map.add x l env) depth hint rest
      mk (CLet(l.u, cv, cr)) cr.ty
    | None ->
      // let (a, b): int * string = …: the annotation is the value's
      let value =
        match ann with
        | Some t -> plain (Typed(value0, t))
        | None -> value0
      let clause = { pattern = p; guard = None; body = rest }
      if not (isActiveCall cx value) && Option.isSome (activeOf cx p) then
        inferWith cx env depth hint (desugarActive cx value [ clause ])
      else
        matchWith Patterns.letMissing cx env depth hint value [ clause ]
  | LetMut(x, ann, value0, rest) ->
    let declared =
      match ann with
      | Some a -> Some(toTy cx None a)
      | None -> None
    let value () =
      let c = inf value0
      match declared with
      | Some t -> expect cx $"value of '{x}'" t c.ty
      | None -> ()
      c
    let fallback () =
      match declared with
      | Some t -> t
      | None -> fresh v kAny
    let cv = recovered cx fallback value
    let l = localOf (uniq cx x) cv.ty true depth
    let cr = inferWith cx (Map.add x l env) depth hint rest
    mk (CLetMut(l.u, cv, cr)) cr.ty
  | Assign(lhs, rhs) -> assign cx env depth lhs rhs
  | While(c, b) ->
    let cc = inf c
    expect cx "condition of 'while'" tBool cc.ty
    let cb = inf b
    expect cx "body of 'while'" tUnit cb.ty
    mk (CWhile(cc, cb)) tUnit
  | For(x, a, step, b, body) ->
    let it = fresh v kInt
    let ca = inf a
    expect cx "start of 'for' range" it ca.ty
    let cb = inf b
    expect cx "end of 'for' range" it cb.ty
    let cs =
      match step with
      | Some s ->
        let cs = inf s
        expect cx "step of 'for' range" it cs.ty
        cs
      | None -> mk (CInt(i64 1)) it
    let l = localOf (uniq cx x) it false depth
    let cbody = infer cx (Map.add x l env) depth body
    expect cx "body of 'for'" tUnit cbody.ty
    mk (CFor(l.u, ca, cs, cb, cbody)) tUnit
  | Index(a, i) ->
    let ca = inf a
    let ci = inf i
    let el = fresh v kAny
    match prune v ca.ty with
    | TCon("fixed", [ fel; _ ]) ->
      expect cx "array index" tInt ci.ty
      mk (CPrim("fixed.get", [ ca; ci ])) fel
    | t ->
      let container =
        match t with
        | TCon("Buffer", _) -> "Buffer"
        | TCon("span", _) -> "span"
        | _ -> "array"
      expect cx "indexing" (TCon(container, [ el ])) ca.ty
      expect cx "array index" tInt ci.ty
      mk (CPrim("array.get", [ ca; ci ])) el
  | ArrayLit xs ->
    let el = fresh v kAny
    let elHint =
      match Option.map (prune v) hint with
      | Some(TCon("array", [ h ]))
      | Some(TCon("Buffer", [ h ])) -> Some h
      | _ -> None
    let one (x: Expr) =
      let c = inferWith cx env depth elHint x
      expect cx "array element" el c.ty
      c
    mk (CPrim("array.lit", List.map one xs)) (TCon("array", [ el ]))
  | Typed(x, st) ->
    let t = toTy cx None st
    let c = inferHint cx env depth t x
    expect cx "annotated expression" t c.ty
    c
  | LayoutOf(kind, st, field) ->
    let (t, index) = layoutType cx kind st field
    match layoutValue cx kind t index with
    | Some n -> mk (CInt(i64 n)) tInt
    | None ->
      // a type variable in it: monomorphization settles the type (a null ptr<T> carries it), and
      // code generation the number
      let witness = mk (CPrim("ptr.null", [ mk CUnit tUnit ])) (TCon("ptr", [ t ]))
      mk (CPrim("layout." + kind, [ witness; mk (CInt(i64 index)) tInt ])) tInt
  | Measured(x, m) ->
    let ce = inf x
    // a number with a unit is the number type expected of it (5<ns> as an i64<ns>)
    match Option.map (prune v) hint with
    | Some(TCon(n, _)) when Set.contains n nums -> unifies cx ce.ty (TCon(n, [])) |> ignore
    | _ -> ()
    settle cx ce.ty
    match prune v ce.ty with
    | TCon(n, []) when Set.contains n nums -> { ce with ty = numWith v n (toTy cx None m) }
    | t -> fail $"only numbers have units, not {show cx t}"
  | Bin("*", a, b)
  | Bin("/", a, b) ->
    let op =
      match node.e with
      | Bin(o, _, _) -> o
      | _ -> "*"
    let ca = inf a
    // a literal with a unit on the right: the left's number type
    let cb = inferHint cx env depth ca.ty b
    if measuredOperands cx ca cb then measuredBin cx op ca cb else arith cx op ca cb
  | Bin(op, a, b) ->
    let ca = inf a
    arith cx op ca (inferHint cx env depth ca.ty b)
  | Neg a ->
    let ca = inferWith cx env depth hint a
    expect cx "operand of '-'" (fresh v (kTrait "Num")) ca.ty
    mk (CNeg ca) ca.ty
  | Not a ->
    let ca = inf a
    expect cx "operand of 'not'" tBool ca.ty
    mk (CNot ca) tBool
  | If(c, t, None) ->
    let cc = inf c
    expect cx "condition of 'if'" tBool cc.ty
    let ct = inf t
    expect cx "'if' without 'else'" tUnit ct.ty
    mk (CIf(cc, ct, mk CUnit tUnit)) tUnit
  | If(c, t, Some f) ->
    let cc = inf c
    expect cx "condition of 'if'" tBool cc.ty
    let ct = inferWith cx env depth hint t
    let cf = inferWith cx env depth hint f
    expect cx "'else' branch" ct.ty cf.ty
    mk (CIf(cc, ct, cf)) ct.ty
  | Seq(a, b) ->
    // C's `x = 5` as a statement: a comparison whose value is dropped
    let assigned =
      match (unAt a).e with
      | Bin("=", l, _)
      | Call("=", [ l; _ ]) ->
        match (unAt l).e with
        | Var x ->
          match Map.tryFind x env with
          | Some loc when loc.mut -> Some x
          | _ -> None
        | _ -> None
      | _ -> None
    let statement () =
      match assigned with
      | Some x -> fail $"'=' compares; to assign to '{x}' write {x} <- …"
      | None -> inf a
    let ca = recovered cx (fun () -> tUnit) statement
    // a statement is unit: a type still open here becomes unit (a panic's, a callback's in
    // List.iter, as F#'s rule), and any other is a dropped value: unused-value (0021), warned
    // about at the end of the declaration, when its type is settled
    match prune v ca.ty with
    | TVar r when Option.isNone (kindOf v r).allowed && Set.isEmpty (kindOf v r).traits -> unifies cx ca.ty tUnit |> ignore
    | _ -> ()
    if not (Set.contains "unused-value" cx.silenced.Value) then
      let at =
        match a.e with
        | AtLine _ -> spanOf cx a.at true
        | _ when a.at >= 0 -> spanOf cx a.at false
        | _ -> spanOf cx cx.currentStmt.Value true
      Buffer.push (ca.ty, at) cx.discarded
    let cb = inferWith cx env depth hint b
    mk (CSeq(ca, cb)) cb.ty
  | Tuple xs ->
    let hints =
      match Option.map (prune v) hint with
      | Some(TTuple ts) when List.length ts = List.length xs -> List.map Some ts
      | _ -> List.map (fun _ -> None) xs
    let cs = List.map2 (fun (x: Expr) (h: option<Ty>) -> inferWith cx env depth h x) xs hints
    mk (CTuple cs) (TTuple(List.map (fun (c: CExpr) -> c.ty) cs))
  | RecordLit fields ->
    // only a record type helps (a generic 'a from a constructor mustn't replace it)
    let recordHint =
      match hint with
      | Some h ->
        match prune v h with
        | TCon(n, _) when isRecord cx n -> Some h
        | _ -> None
      | None -> None
    recordLit cx env depth recordHint node fields
  | Update(r, fields) ->
    let cr = inf r
    let rname = recordOf cx cr.ty (List.head fields).field
    fieldUses cx rname (List.map (fun (f: FieldValue) -> (f.field, f.nameAt)) fields) false
    let (rty, targs) = instType cx rname
    expect cx "record update" rty cr.ty
    let tmp = uniq cx "$r"
    let defs = fieldsOf cx rname
    if Option.isSome (bitsLayout cx rname) then
      // a [<Bits>] record: each field given written over its bits, the others and the gaps kept
      // (0013)
      let one (acc: CExpr) (fv: FieldValue) =
        match List.tryFindIndex (fun (g, _) -> g = fv.field) defs with
        | Some i ->
          let ft = substGen v targs (snd (List.item i defs))
          let cv = inferHint cx env depth ft fv.value
          expect cx $"field '{fv.field}'" ft cv.ty
          mk (CPrim("bits.set", [ acc; cv; mk (CInt(i64 i)) tInt ])) cr.ty
        | None -> fail $"{show cx cr.ty} has no field '{fv.field}'"
      mk (CLet(tmp, cr, List.fold one (mk (CLocal tmp) cr.ty) fields)) cr.ty
    else
      let old (i: int) (_: Map<string, Local>) = mk (CField(mk (CLocal tmp) cr.ty, i)) (substGen v targs (snd (List.item i defs)))
      let built = buildRecord cx env depth rname targs fields old
      mk (CLet(tmp, cr, built)) built.ty
  | Field(r, f) ->
    match caseThrough cx env r f with
    | Some c -> inf { node with e = Var c }
    | None ->
      let cr = inf r
      let res = located cx node.at false (fun () -> field cx cr f)
      let key =
        match (memberOf cx cr.ty f, prune v cr.ty) with
        | (Some m, _) -> m.gname
        | (None, TCon(n, _)) when isRecord cx n -> $"field:{n}.{f}"
        | _ -> ""
      recordKey cx node.at f res.ty false key false
      res
  | Question _ -> fail "'?' is only supported as `let x = e?` or as a whole statement (for now)"
  | Unsafe a ->
    let outer = cx.unsafeOn.Value
    cx.unsafeOn.Value <- true
    let c = inferWith cx env depth hint a
    cx.unsafeOn.Value <- outer
    c
  | DeriveCtx(ctx, a) -> saying ctx (fun () -> inf a)
  | ListComp(isArray, body) -> listExpression cx env depth isArray body
  | Slice(a, i, j) -> slice cx env depth a i j
  | Yield _
  | YieldAll _ -> fail "yield belongs in [ … ], [| … |] or seq { }"
  | ForIn(x, xs, body) -> forIn cx env depth x xs body
  | TryBind(p, x, rest) -> tryBind cx env depth node p x rest
  | Match(s, cases) ->
    if not (isActiveCall cx s) && List.exists (fun (c: Clause) -> Option.isSome (activeOf cx c.pattern)) cases then
      inferWith cx env depth hint (desugarActive cx s cases)
    else
      matchExpr cx env depth hint s cases

/// A match: the scrutinee, then each clause's pattern, guard and body (the bodies get the type
/// expected of the match), then its exhaustiveness.
and matchExpr (cx: Cx) (env: Map<string, Local>) (depth: int) (hint: option<Ty>) (s: Expr) (cases: list<Clause>) : CExpr =
  matchWith Patterns.matchMissing cx env depth hint s cases

/// A match whose missing case is worded by `missing` (a match's, or a let's pattern's).
and matchWith (missing: string -> string) (cx: Cx) (env: Map<string, Local>) (depth: int) (hint: option<Ty>) (s: Expr) (cases: list<Clause>) : CExpr =
    let v = cx.v
    let cs = infer cx env depth s
    let resTy = fresh v kAny
    let one (c: Clause) =
      let names = ref Map.empty
      let cp = Patterns.pattern cx names c.pattern cs.ty
      let vars = patVars cp
      if List.length (List.distinct (List.map fst vars)) <> List.length vars then
        fail "a variable is bound twice in this pattern"
      let envC = withVars env names.Value vars depth
      let cg =
        match c.guard with
        | Some g ->
          // a guard performs nothing: a function it calls is its pure instance, and an effect is
          // an error here
          let cg = withRowAs cx rowEmpty guardWhat (fun () -> infer cx envC depth g)
          expect cx "'when' guard" tBool cg.ty
          Some cg
        | None -> None
      let cb = inferWith cx envC depth hint c.body
      expect cx "match case" resTy cb.ty
      (cp, cg, cb)
    let ccases = List.map one cases
    Patterns.checkWith missing (unionCases cx) (fun c -> Set.contains c cx.apCtors.Value) (List.map (fun (p, g, _) -> (p, Option.isSome g)) ccases)
    mk (CMatch(cs, ccases)) resTy

/// task { }: a Task whose work is the body, in direct style ($cancel is the task's cancellation,
/// $await a wait); the code generator makes a state machine of the work (an LLVM coroutine), so a
/// wait allocates nothing.
and taskExpr (cx: Cx) (env: Map<string, Local>) (depth: int) (body: Expr) : CExpr =
  let v = cx.v
  let a = fresh v kAny
  let cancelTy = tcon "Threading.Cancel"
  let kTy = tfun a tUnit
  let cl = localOf (uniq cx "$cancel") cancelTy false (depth + 1)
  let ku = uniq cx "$k"
  let ru = uniq cx "$result"
  // the work runs from the event loop, where no handler is: it performs nothing
  let what = "a task's body (it runs from the event loop, where no handler is)"
  let cb = withRowAs cx rowEmpty what (fun () -> infer cx (Map.add "$cancel" cl env) (depth + 1) body)
  expect cx "the task's result" a cb.ty
  let complete = value cx env depth "Threading.Task.complete"
  expect cx "the task's result" (tfun kTy (tfun a tUnit)) complete.ty
  let kE = mk (CLocal ku) kTy
  let cancelE = mk (CLocal cl.u) cancelTy
  // a return! that isn't last (in a use's scope): a wait as any other
  let rec plainWaits (e: CExpr) : CExpr =
    match e.k with
    | CPrim("task.last", [ wait; _ ]) -> plainWaits wait
    | k -> { e with k = mapChildren plainWaits k }
  let unitOf (k: CKind) = mk k tUnit
  // what waits for the task gets the body's value: each value the body may end with, given to
  // it; a return! at the end, its task handed this task's cancellation and waiter, so a task
  // looping through return! keeps one state machine, not one per round
  let rec finish (e: CExpr) : CExpr =
    match e.k with
    | CLine(l, b) -> unitOf (CLine(l, finish b))
    | CLet(x, w, b) -> unitOf (CLet(x, plainWaits w, finish b))
    | CLetMut(x, w, b) -> unitOf (CLetMut(x, plainWaits w, finish b))
    | CSeq(p, b) -> unitOf (CSeq(plainWaits p, finish b))
    | CIf(c, t, f) -> unitOf (CIf(plainWaits c, finish t, finish f))
    | CMatch(sc, cases) -> unitOf (CMatch(plainWaits sc, List.map (fun (p, g, b) -> (p, Option.map plainWaits g, finish b)) cases))
    | CLetFun(n, r, ps, b, rest) -> unitOf (CLetFun(n, r, ps, plainWaits b, finish rest))
    | CLetRec(fs, rest) -> unitOf (CLetRec(List.map (fun (n, ps, b) -> (n, ps, plainWaits b)) fs, finish rest))
    | CPrim("task.last", [ _; t ]) ->
      let handOff = value cx env depth "Threading.Task.handOff"
      expect cx "the task return! gives" (tfun t.ty (tfun cancelTy (tfun kTy tUnit))) handOff.ty
      unitOf (CApp(handOff, [ t; cancelE; kE ]))
    | _ -> unitOf (CApp(complete, [ kE; plainWaits e ]))
  // whether a return! ends the body (on some path): if not, it ends as it always has
  let rec last (e: CExpr) : bool =
    match e.k with
    | CLine(_, b)
    | CLet(_, _, b)
    | CLetMut(_, _, b)
    | CSeq(_, b)
    | CLetFun(_, _, _, _, b)
    | CLetRec(_, b) -> last b
    | CIf(_, t, f) -> last t || last f
    | CMatch(_, cases) -> List.exists (fun (_, _, b) -> last b) cases
    | CPrim("task.last", _) -> true
    | _ -> false
  let workBody =
    if last cb then
      finish cb
    else
      // the result first, then what waits for it (which waits held meanwhile)
      mk (CLet(ru, plainWaits cb, mk (CApp(complete, [ kE; mk (CLocal ru) a ])) tUnit)) tUnit
  let work = mk (CLam([ (cl.u, cancelTy); (ku, kTy) ], workBody)) (tfun cancelTy (tfun kTy tUnit))
  let (_, noneTag) = Map.find "None" cx.ctors.Value
  mk (CTuple [ mk (CCtor("option", noneTag, [])) (TCon("option", [ a ])); work ]) (TCon("Threading.Task", [ a ]))

/// let!, do!, return! in a task: the task's ready result, or a wait (task.suspend) for its work's
/// (none if the task is cancelled already: task.abandon); a return!'s marked (task.last), so at the
/// end of the body its task gets this one's waiter.
and awaitExpr (cx: Cx) (env: Map<string, Local>) (depth: int) (isLast: bool) (x: Expr) : CExpr =
  match Map.tryFind "$cancel" env with
  | Some cl when cl.depth = depth ->
    let v = cx.v
    let ce = infer cx env depth x
    let t = fresh v kAny
    expect cx "the task let! waits for" (TCon("Threading.Task", [ t ])) ce.ty
    let tv = uniq cx "$task"
    let xr = uniq cx "$ready"
    let tvE = mk (CLocal tv) ce.ty
    let cE = mk (CLocal cl.u) cl.ty
    let (_, someTag) = Map.find "Some" cx.ctors.Value
    let (_, noneTag) = Map.find "None" cx.ctors.Value
    let cancelled = List.findIndex (fun (f, _) -> f = "cancelled") (fieldsOf cx "Threading.Cancel")
    let flag = mk (CPrim("ref.get", [ mk (CField(cE, cancelled)) (TCon("ref", [ tBool ])) ])) tBool
    let workTy = tfun cl.ty (tfun (tfun t tUnit) tUnit)
    let wait = mk (CPrim("task.suspend", [ mk (CField(tvE, 1)) workTy; cE ])) t
    let notReady = mk (CIf(flag, mk (CPrim("task.abandon", [])) t, wait)) t
    let someCase = (CPCtor("option", someTag, [ CPVar(xr, t) ]), None, mk (CLocal xr) t)
    let noneCase = (CPCtor("option", noneTag, []), None, notReady)
    let ready = mk (CMatch(mk (CField(tvE, 0)) (TCon("option", [ t ])), [ someCase; noneCase ])) t
    let waited = if isLast then mk (CPrim("task.last", [ ready; tvE ])) t else ready
    mk (CLet(tv, ce, waited)) t
  | Some _ -> fail "let!, do! and return! wait in the task's own body, not in a function inside it"
  | None -> fail "let!, do! and return! are for a task { }"

/// {e:spec}: Format.format e "spec", and a number's specifier checked (0024): F and N for every
/// number, D, X and B for integers, E and G for floats.
and formatExpr (cx: Cx) (env: Map<string, Local>) (depth: int) (x: Expr) (spec: string) : CExpr =
  let hole = uniq cx "$hole"
  let formatted = plain (Call(libraryName "Format.format", [ plain (Var hole); plain (StrLit spec) ]))
  let c = infer cx env depth (plain (Let(plainPat (PIdent(hole, None)), None, x, formatted)))
  let isInt (k: Kind) = Option.exists (fun a -> Set.contains "int" a) k.allowed
  let isFloat (k: Kind) = Option.exists (fun a -> Set.contains "f64" a) k.allowed
  let kind =
    match c.k with
    | CLet(_, w, _) ->
      match prune cx.v w.ty with
      | TCon(n, _) when Set.contains n ints -> "an integer"
      | TCon(n, _) when Set.contains n floats -> "a float"
      | TVar r -> if isInt (kindOf cx.v r) then "an integer" else if isFloat (kindOf cx.v r) then "a float" else ""
      | _ -> ""
    | _ -> ""
  let letters =
    match kind with
    | "an integer" -> "FNDXxBb"
    | "a float" -> "FNEG"
    | _ -> ""
  let first = if String.length spec > 0 then String.sub spec 0 1 else ""
  if letters <> "" && not (String.contains first letters) then
    let each = String.join ", " (List.map String.ofChar (String.chars letters))
    fail $"'{first}' isn't a format specifier for {kind}: it takes {each}"
  c

/// assert on a comparison: its sides are evaluated once, and when it fails the message shows
/// them (through Show, or as written) and where they first differ (Diff) (0009).
and assertCompare (cx: Cx) (env: Map<string, Local>) (depth: int) (c: Expr) : CExpr =
  let (op, a, b) =
    match c.e with
    | Bin(o, l, r) -> (o, l, r)
    | _ -> panic "assert"
  let file = fileName cx
  let line = lineOf cx cx.currentStmt.Value
  let ca = infer cx env depth a
  let cb = infer cx env depth b
  let l = localOf (uniq cx "$side") ca.ty false depth
  let r = localOf (uniq cx "$side") cb.ty false depth
  let env2 = Map.add "$right" r (Map.add "$left" l env)
  let cond = infer cx env2 depth (plain (Bin(op, plain (Var "$left"), plain (Var "$right"))))
  // whether a type has a trait (what binding a check did stays, as in the F# compiler)
  let has (tr: string) (t: Ty) =
    let attempt () =
      unify cx (fresh cx.v (kTrait tr)) t
      true
    let matched () =
      handle attempt () with
      | Mismatched.throw _, _ -> false
    handle matched () with
    | Fails.fail _, _ -> false
    | Fails.report x, k -> k (Fails.report x)
  let side (name: string) (e: Expr) (t: Ty) =
    if has "Show" t then plain (Call(libraryName "Show.show", [ plain (Var name) ])) else plain (StrLit(exprText e))
  let atPart =
    if op = "=" && has "Diff" ca.ty then
      let diff = plain (Call(libraryName "Diff.diff", [ plain (Var "$left"); plain (Var "$right") ]))
      let startsDot = plain (Call(libraryName "Text.String.startsWith", [ plain (StrLit "."); plain (Var "$at") ]))
      let shownAt = plain (If(startsDot, plain (Bin("+", plain (StrLit "\n  at "), plain (Var "$at"))), Some(plain (StrLit ""))))
      let someCase = { pattern = plainPat (PIdent("Some", Some(plainPat (PIdent("$at", None))))); guard = None; body = shownAt }
      let noneCase = { pattern = plainPat (PIdent("None", None)); guard = None; body = plain (StrLit "") }
      [ plain (Match(diff, [ someCase; noneCase ])) ]
    else
      []
  let head = plain (StrLit $"assertion failed at {file}:{line}: {exprText c}\n  left:  ")
  let parts = List.append [ head; side "$left" a ca.ty; plain (StrLit "\n  right: "); side "$right" b cb.ty ] atPart
  let message = List.reduce (fun x y -> plain (Bin("+", x, y))) parts
  let failed = infer cx env2 depth (plain (Call("panic", [ message ])))
  expect cx "assert" tUnit failed.ty
  mk (CLet(l.u, ca, mk (CLet(r.u, cb, mk (CIf(cond, mk CUnit tUnit, failed)) tUnit)) tUnit)) tUnit

/// A call by name, its place the node's: the name's hover, with the type of what's called.
and callNode (cx: Cx) (env: Map<string, Local>) (depth: int) (node: Expr) (f: string) (args: list<Expr>) (argHints: list<option<Ty>>) : CExpr =
  let r = located cx node.at false (fun () -> callWith cx env depth f args argHints)
  let headTy =
    match r.k with
    | CApp(h, _) -> h.ty
    | CPerform(l, _, cargs) -> funTyRow (List.map (fun (c: CExpr) -> c.ty) cargs) r.ty (rowExt l rowEmpty)
    | CExtern(name, _) when Map.containsKey name cx.externs.Value ->
      // a C function: its declared type
      let x = Map.find name cx.externs.Value
      funTy (if List.isEmpty x.pars then [ tUnit ] else x.pars) x.ret
    | _ -> r.ty
  recordKey cx node.at f headTy false (keyOf cx env f) false
  r

/// Local functions that call each other: all names are in scope in every body.
and letRecGroup (cx: Cx) (env: Map<string, Local>) (depth: int) (hint: option<Ty>) (members: list<Expr>) (rest: Expr) : CExpr =
  let v = cx.v
  let prepare (m: Expr) : Prepared =
    match m.e with
    | LetFun(name, _, ps0, ret, body0, _) ->
      let (ps, body) = lowerParams cx ps0 body0
      let pars = List.map (fun (x, ann) -> (x, uniq cx x, annot cx ann)) ps
      recordParams cx ps0 pars
      let (rty, declared) = annotRet cx ret
      let row =
        match declared with
        | Some r -> r
        | None -> fresh v kRow
      let fty = funTyRow (parTypes pars) rty row
      { pnode = m; pname = name; ppars = pars; prty = rty; pfty = fty; pself = localOf (uniq cx name) fty false depth; pbody = body; prow = row }
    | _ -> panic "LetRecGroup member"
  let prepared = List.map prepare members
  let envGroup = List.fold (fun e (p: Prepared) -> Map.add p.pname p.pself e) env prepared
  let define (p: Prepared) =
    let envB = withPars envGroup p.ppars (depth + 1)
    let cb = withRow cx p.prow (fun () -> infer cx envB (depth + 1) p.pbody)
    expect cx $"result of '{p.pname}'" p.prty cb.ty
    recordKey cx p.pnode.at p.pname p.pfty false p.pself.u true
    cx.localValues.Value <- Map.add p.pself.u (mk (CLam(parsOf p.ppars, cb)) p.pfty) cx.localValues.Value
    (p.pself.u, parsOf p.ppars, cb)
  let defs = List.map define prepared
  let cr = inferWith cx envGroup depth hint rest
  mk (CLetRec(defs, cr)) cr.ty

/// An assignment: to a `let mutable`, an element of an array or Buffer (a `let mutable` array in
/// place), a ref's Value, or a field of a `let mutable` record (the record rebuilt).
and assign (cx: Cx) (env: Map<string, Local>) (depth: int) (lhs: Expr) (rhs: Expr) : CExpr =
  let v = cx.v
  let inf (x: Expr) = infer cx env depth x
  let isMutLocal (x: string) =
    match Map.tryFind x env with
    | Some l -> l.mut
    | None -> false
  // the let mutable a place is a field (of a field…) of
  let rec mutableRoot (e: Expr) : option<string> =
    match e.e with
    | Var x -> if isMutLocal x then Some x else None
    | Field(r, _) -> mutableRoot r
    | _ -> None
  let captured (x: string) : unit / Fails =
    fail $"mutable variable '{x}' cannot be captured by a closure; use a ref cell (let x = ref …; x.Value <- …)"
  let isRef (c: CExpr) =
    match prune v c.ty with
    | TCon("ref", _) -> true
    | _ -> false
  let mutVar (a: Expr) : option<string> =
    match a.e with
    | Var x -> if isMutLocal x then Some x else None
    | _ -> None
  match lhs.e with
  | Var x ->
    match Map.tryFind x env with
    | Some l when l.mut ->
      if l.depth < depth then
        captured x
      let cv = inf rhs
      expect cx $"value assigned to '{x}'" l.ty cv.ty
      mk (CAssign(l.u, cv)) tUnit
    | Some _ -> fail $"'{x}' is not mutable; declare it with 'let mutable'"
    | None -> fail $"unknown name '{x}'"
  | Index(a, i) ->
    let ca = inf a
    let inPlace =
      match a.e with
      | Var x -> isMutLocal x
      | _ -> Option.isSome (mutableRoot a)
    let inPlaceVar = mutVar a
    let inRecord = mutableRoot a
    match prune v ca.ty with
    | TCon("span", _) -> fail "a span is read-only: slice the Buffer (b.[i..j]) for a window you can write to"
    | TCon("fixed", _) when inPlace ->
      // an element of a fixed-size array in a let mutable, or in its record: the place gets the
      // changed value
      inf (plain (Assign(a, plain (Call(libraryName "Collections.Fixed.set", [ a; i; rhs ])))))
    | TCon("fixed", _) ->
      fail "a fixed-size array is a value: declare it (or the record holding it) with `let mutable` to assign an element, or use Fixed.set, which returns the changed one"
    | TCon("Buffer", _) ->
      // a Buffer is a shared reference: the write is seen through every alias
      let ci = inf i
      let cv = inf rhs
      expect cx "Buffer" (TCon("Buffer", [ cv.ty ])) ca.ty
      expect cx "index" tInt ci.ty
      mk (CPrim("array.set", [ ca; ci; cv ])) tUnit
    | _ when Option.isSome inPlaceVar ->
      let x = Option.get inPlaceVar
      let l = Map.find x env
      if l.depth < depth then
        captured x
      let ci = inf i
      let cv = inf rhs
      expect cx "array" (TCon("array", [ cv.ty ])) l.ty
      expect cx "array index" tInt ci.ty
      mk (CArraySet(l.u, ci, cv)) tUnit
    | _ when Option.isSome inRecord ->
      // an element of an array in a let mutable record's field: the record with the array
      // changed (in place when both are unique)
      inf (plain (Assign(a, plain (Call(libraryName "Collections.Array.set", [ a; i; rhs ])))))
    | _ ->
      fail "arrays are values: to change one, declare it with `let mutable a = …` and write `a.[i] <- x`, or use `Array.set a i x`, which returns the changed array (Buffer<'a> is the shared mutable alternative)"
  | Field(r, f) ->
    let refSet () =
      let cr = inf r
      let cv = inf rhs
      expect cx "ref cell" (TCon("ref", [ cv.ty ])) cr.ty
      mk (CPrim("ref.set", [ cr; cv ])) tUnit
    // a ref's Value; or a ref held by a let mutable (or in its record): the ref's Value, not the
    // holder
    if f = "Value" && Option.isNone (mutableRoot r) then
      refSet ()
    else if f = "Value" && isRef (inf r) then
      refSet ()
    else if Option.isSome (mutableRoot lhs) then
      // a field of a let mutable record, nested or not: p.pos.x <- v is
      // p <- { p with pos = { p.pos with x = v } }
      let rec rebuild (place: Expr) (w: Expr) : Expr =
        match place.e with
        | Field(q, g) -> rebuild q (plain (Update(q, [ { field = g; nameAt = -1; value = w } ])))
        | _ -> w
      inf (plain (Assign(plain (Var(Option.get (mutableRoot lhs))), rebuild lhs rhs)))
    else
      fail "record fields are immutable: declare the record with `let mutable` to assign one of its fields, or use { r with field = … }"
  | _ -> fail "only mutable variables, their fields and elements, and ref cells can be assigned"

/// A window (a span, or a Buffer of a Buffer) of elements i to j, or a string's copy; a bound left
/// out is the start or the end.
and slice (cx: Cx) (env: Map<string, Local>) (depth: int) (a: Expr) (i: option<Expr>) (j: option<Expr>) : CExpr =
  let ca = infer cx env depth a
  settle cx ca.ty
  let (kind, resTy) =
    match prune cx.v ca.ty with
    | TCon("array", [ el ]) -> (0, TCon("span", [ el ]))
    | TCon("Buffer", [ _ ]) -> (1, ca.ty)
    | TCon("span", [ _ ]) -> (2, ca.ty)
    | TCon("string", []) -> (3, tStr)
    | t -> fail $"a slice needs an array, a Buffer, a span or a string, not {show cx t}"
  let bound (e: Expr) =
    let c = infer cx env depth e
    expect cx "slice bound" tInt c.ty
    c
  let s = uniq cx "$sliced"
  let sv = mk (CLocal s) ca.ty
  let lo =
    match i with
    | Some e -> bound e
    | None -> mk (CInt(i64 0)) tInt
  let hi =
    match j with
    | Some e -> bound e
    | None ->
      let len = mk (CPrim((if kind = 3 then "String.length" else "Array.length"), [ sv ])) tInt
      mk (CBin("-", len, mk (CInt(i64 1)) tInt)) tInt
  let sliced = if kind = 3 then CPrim("String.slice", [ sv; lo; hi ]) else CPrim("window.slice", [ sv; lo; hi; mk (CInt(i64 kind)) tInt ])
  mk (CLet(s, ca, mk sliced resTy)) resTy

/// for x in c do body: Iter.forEach c (fun x -> body; true) (0017), c evaluated once, before the
/// loop. The lambda is the compiler's: its body is typed at the function's depth, so it may assign
/// the function's mutables (the impl's forEach is inlined and the lambda applied in place; Lift
/// gives an assigned variable a cell otherwise).
and forIn (cx: Cx) (env: Map<string, Local>) (depth: int) (x: string) (xs: Expr) (body: Expr) : CExpr =
  let cxs = infer cx env depth xs
  let fe = infer cx env depth (plain (Var "Iter.forEach"))
  let (collTy, elTy, row) =
    match prune cx.v fe.ty with
    | TFun(c, TFun(TFun(a, _, _), _, r), _) -> (c, a, r)
    | t -> panic $"Iter.forEach : {show cx t}"
  expect cx "for needs a collection" collTy cxs.ty
  let coll = localOf (uniq cx "$coll") cxs.ty false depth
  let xu = uniq cx x
  let envB = Map.add x (localOf xu elTy false depth) (Map.add "$coll" coll env)
  let cb = withRow cx row (fun () -> infer cx envB depth body)
  expect cx "the body of 'for'" tUnit cb.ty
  let lamE = mk (CLam([ (xu, elTy) ], mk (CSeq(cb, mk (CBool true) tBool)) tBool)) (TFun(elTy, tBool, row))
  useRow cx row
  let callE = mk (CApp(fe, [ mk (CLocal coll.u) cxs.ty; lamE ])) tBool
  mk (CLet(coll.u, cxs, mk (CSeq(callE, mk CUnit tUnit)) tUnit)) tUnit

/// let p = e? and the rest: match e with Ok p -> rest | Error err -> Error err, or, on an option,
/// match e with Some p -> rest | None -> None: the rest of the block (the function's result, or the
/// lambda's) gives what the early return does. Its errors point at the `?`.
and tryBind (cx: Cx) (env: Map<string, Local>) (depth: int) (node: Expr) (p: Pat) (x: Expr) (rest: Expr) : CExpr =
  let v = cx.v
  let ce = infer cx env depth x
  let onOption =
    match prune v ce.ty with
    | TCon("option", _) -> true
    | _ -> false
  let (wrap, payload, other) =
    if onOption then
      let a = fresh v kAny
      (TCon("option", [ a ]), a, None)
    else
      let okTy = fresh v kAny
      let er = fresh v kAny
      (TCon("result", [ okTy; er ]), okTy, Some er)
  located cx node.at false (fun () -> expect cx "operand of '?'" wrap ce.ty)
  let names = ref Map.empty
  let caseOf (c: string) = snd (Map.find c cx.ctors.Value)
  let union = if onOption then "option" else "result"
  let cp = CPCtor(union, caseOf (if onOption then "Some" else "Ok"), [ Patterns.pattern cx names p payload ])
  let vars = patVars cp
  let envOk = withVars env names.Value vars depth
  let crest = infer cx envOk depth rest
  let gives () =
    let g =
      match other with
      | Some er -> TCon("result", [ fresh v kAny; er ])
      | None -> TCon("option", [ fresh v kAny ])
    if not (unifies cx g crest.ty) then
      match (prune v crest.ty, other) with
      | (TCon("result", _), None) -> fail "? on an option in a function returning result<_, _>: use Option.toResult, or option { }"
      | (TCon("option", _), Some _) -> fail "? on a result in a function returning option<_>: use Result.toOption, or result { }"
      | (TCon("unit", []), _) ->
        fail "? needs the function to return a result or an option; this one returns unit: match on the value instead, or make the function return a result"
      | (t, Some er) ->
        let ers =
          match prune v er with
          | TVar _ -> "_"
          | e -> show cx e
        fail $"'?' needs the rest of the block to produce a result<_, {ers}>, but it produces {show cx t}"
      | (t, None) -> fail $"'?' needs the rest of the block to produce an option, but it produces {show cx t}"
  located cx node.at false gives
  let failCase =
    match other with
    | Some er ->
      let eu = uniq cx "$err"
      (CPCtor("result", caseOf "Error", [ CPVar(eu, er) ]), None, mk (CCtor("result", caseOf "Error", [ mk (CLocal eu) er ])) crest.ty)
    | None -> (CPCtor("option", caseOf "None", []), None, mk (CCtor("option", caseOf "None", [])) crest.ty)
  let cases = [ (cp, None, crest); failCase ]
  Patterns.check (unionCases cx) (fun c -> Set.contains c cx.apCtors.Value) (List.map (fun (q, _, _) -> (q, false)) cases)
  mk (CMatch(ce, cases)) crest.ty

/// * and / on numbers with units: the units multiply and divide; a unitless literal operand is
/// dimensionless.
and measuredBin (cx: Cx) (op: string) (ca: CExpr) (cb: CExpr) : CExpr =
  let v = cx.v
  let numPart (t: Ty) =
    match prune v t with
    | TCon(n, ms) when Set.contains n nums -> Some(n, measOf ms)
    | _ -> None
  let literalTakes (x: CExpr) (other: CExpr) =
    match (prune v x.ty, numPart other.ty) with
    | (TVar r, Some(n, _)) when Option.isSome (kindOf v r).allowed -> expect cx $"operand of '{op}'" (TCon(n, [])) x.ty
    | _ -> ()
  literalTakes ca cb
  literalTakes cb ca
  match (numPart ca.ty, numPart cb.ty) with
  | (Some(n1, m1), Some(n2, m2)) when n1 = n2 ->
    mk (CBin(op, ca, cb)) (numWith v n1 (if op = "*" then measMul v m1 m2 else measDiv v m1 m2))
  | _ -> fail $"operands of '{op}' must be numbers of the same type: {show cx ca.ty} and {show cx cb.ty}"

/// An operator through its trait: + Add, - * / % Num, = <> Eq, < > <= >= Ord.
and arith (cx: Cx) (op: string) (ca: CExpr) (cb: CExpr) : CExpr =
  let v = cx.v
  let isArith = List.contains op [ "+"; "-"; "*"; "/"; "%" ]
  let bitOps = [ "&&&"; "|||"; "^^^"; "<<<"; ">>>" ]
  let simdBits =
    match prune v ca.ty with
    | TCon(n, []) when isMaskName n -> List.contains op [ "&&&"; "|||"; "^^^" ]
    | TCon(n, []) when isVectorName n -> Set.contains (vectorElem n) ints && List.contains op bitOps
    | _ -> false
  if simdBits then
    // lane by lane, on integer vectors and masks; a vector's shift takes one int amount
    let rt = if op = "<<<" || op = ">>>" then tInt else ca.ty
    expect cx $"right operand of '{op}'" rt cb.ty
    mk (CBin(op, ca, cb)) ca.ty
  else if List.contains op bitOps then
    // bitwise: both operands the same integer type (a shift amount too)
    if not (unifies cx (fresh v kInt) ca.ty) then
      fail $"operator '{op}' needs an integer, not {show cx ca.ty}"
    expect cx $"right operand of '{op}'" ca.ty cb.ty
    mk (CBin(op, ca, cb)) ca.ty
  else
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
    if not (unifies cx (fresh v (kTrait tr)) ca.ty) then
      fail $"operator '{op}' does not support type {show cx ca.ty} (it needs {tr})"
    expect cx $"right operand of '{op}'" ca.ty cb.ty
    // in a [<Wrapping>] function, + - * on integers wrap around (decided once the operand type is
    // known: on floats and strings they stay the usual ones); in a [<FastMath>] function, + - * /
    // on floats are LLVM's fast ones (Mono keeps the mark only on floats and float vectors)
    let wrapped = if cx.wrapping.Value && List.contains op [ "+"; "-"; "*" ] then "wrap" + op else op
    let fast = if cx.fastMath.Value && List.exists (fun (o: string) -> String.endsWith o wrapped) [ "+"; "-"; "*"; "/" ] then "fast" + wrapped else wrapped
    mk (CBin(fast, ca, cb)) (if isArith then ca.ty else tBool)

/// Does either operand carry a unit of measure (so * and / combine units)?
and measuredOperands (cx: Cx) (ca: CExpr) (cb: CExpr) : bool =
  let measured (t: Ty) =
    match prune cx.v t with
    | TCon(n, [ TMeas _ ]) when Set.contains n nums -> true
    | _ -> false
  measured ca.ty || measured cb.ty

/// A literal-constrained type variable takes its default before a member lookup.
and settle (cx: Cx) (t: Ty) =
  match prune cx.v t with
  | TVar r when Option.isSome (kindOf cx.v r).allowed -> resolve cx.v t |> ignore
  | _ -> ()

/// `e.f` once e is typed: ref cell, record field, or property member.
and field (cx: Cx) (cr: CExpr) (f: string) : CExpr =
  let v = cx.v
  settle cx cr.ty
  let isField =
    match prune v cr.ty with
    | TCon(n, _) when isRecord cx n -> List.exists (fun (g, _) -> g = f) (fieldsOf cx n)
    | _ -> false
  match (prune v cr.ty, memberOf cx cr.ty f) with
  | (TCon("ref", [ a ]), _) when f = "Value" -> mk (CPrim("ref.get", [ cr ])) a
  | (_, Some m) when not isField ->
    if m.isStatic then
      fail $"'{f}' is a static member; use {typeName cx cr.ty}.{f}"
    else if m.isProperty then
      memberCall cx Map.empty 0 m (Some cr) [] f
    else
      fail $"method '{f}' must be called: x.{f}(...)"
  | (TVar _, _) when f = "Value" && Option.isNone (fieldRecord cx f) ->
    let a = fresh v kAny
    expect cx "ref cell" (TCon("ref", [ a ])) cr.ty
    mk (CPrim("ref.get", [ cr ])) a
  | (TVar _, _) when Option.isNone (fieldRecord cx f) ->
    fail $"cannot resolve '.{f}': the type of this expression isn't known here; add a type annotation"
  | (TCon(n, []), _) when Option.isSome (cUnionCases cx n) ->
    // a C union's case (0004): its bytes as the case's field
    match List.tryFind (fun (c, _) -> afterLastDot c = f) (Option.get (cUnionCases cx n)) with
    | Some(_, ft) ->
      if not cx.unsafeOn.Value then
        fail $"reading a case of a C union needs unsafe: {show cx cr.ty} has no tag"
      mk (CPrim("cunion.get", [ cr ])) ft
    | None -> fail $"{show cx cr.ty} has no case or member '{f}'"
  | _ ->
    let rname = recordOf cx cr.ty f
    fieldsVisible cx rname
    let (rty, targs) = instType cx rname
    expect cx $"field '{f}'" rty cr.ty
    let defs = fieldsOf cx rname
    match List.tryFindIndex (fun (g, _) -> g = f) defs with
    | Some i -> mk (CField(cr, i)) (substGen v targs (snd (List.item i defs)))
    | None -> fail $"{show cx cr.ty} has no field or member '{f}'"

/// `x.f` naming a case through a union whose name isn't capitalized, so it isn't one qualified
/// name (import c's epoll_data.fd), unless a value is named x.
and caseThrough (cx: Cx) (env: Map<string, Local>) (r: Expr) (f: string) : option<string> =
  match r.e with
  | Var x when not (Map.containsKey x env) -> if Option.isNone (resolveName cx x) && isCtor cx (x + "." + f) then Some(x + "." + f) else None
  | _ -> None

and typeName (cx: Cx) (t: Ty) : string =
  match prune cx.v t with
  | TCon(n, _) -> n
  | x -> Types.Show.showFull cx.v x

and memberOf (cx: Cx) (t: Ty) (f: string) : option<MemberInfo> =
  match prune cx.v t with
  | TCon(n, _) ->
    match Map.tryFind n cx.members.Value with
    | Some table -> Option.map snd (List.tryFind (fun (g, _) -> g = f) table)
    | None -> None
  | _ -> None

/// `T.M` names a static member?
and staticMember (cx: Cx) (name: string) : option<MemberInfo> =
  match String.lastIndexOf "." name with
  | Some i when i > 0 ->
    let t0 = String.sub name 0 i
    // most names aren't T.M for a type with members (by T's last part, or an alias), so they are
    // rejected before T is resolved
    if Set.contains (afterLastDot t0) cx.memberTypeNames.Value || Option.isSome (typeAlias t0) then
      let t1 =
        match typeAlias t0 with
        | Some c -> c
        | None -> t0
      let t =
        match resolveWith cx (fun q -> Map.containsKey q cx.members.Value) t1 with
        | Some q -> q
        | None -> t1
      let m = skipChars (i + 1) name
      match Map.tryFind t cx.members.Value with
      | Some table -> Option.map snd (List.tryFind (fun (p: string * MemberInfo) -> fst p = m && (snd p).isStatic) table)
      | None -> None
    else
      None
  | _ -> None

/// A member call. Arguments: positional, then `name = value`; missing optional ones take their
/// default (evaluated here, seeing earlier parameters) or None.
and memberCall (cx: Cx) (env: Map<string, Local>) (depth: int) (m: MemberInfo) (self: option<CExpr>) (args0: list<Expr>) (what: string) : CExpr =
  let v = cx.v
  let g = Map.find m.gname cx.globals.Value
  let head =
    if g.defining then
      mk (CGlobal(m.gname, None)) g.ty
    else
      let (t, inst) = instantiate cx g.kinds g.ty
      mk (CGlobal(m.gname, Some inst)) t
  let nself = if Option.isSome self then 1 else 0
  let arity = max 1 (nself + List.length m.mpars)
  let (ptys, resTy) = peel cx arity head.ty
  let mptys = List.skip nself ptys
  match self with
  | Some c -> expect cx $"receiver of '{what}'" (List.head ptys) c.ty
  | None -> ()
  let args =
    match args0 with
    | [ { e = Tuple xs } ] -> xs
    | [ { e = UnitLit } ] -> []
    | xs -> xs
  let paramIndex (n: string) = List.tryFindIndex (fun (p: MemberParam) -> p.mname = n) m.mpars
  let isNamed (a: Expr) =
    match a.e with
    | Bin("=", { e = Var n }, _) -> Option.isSome (paramIndex n)
    | _ -> false
  let positional = List.takeWhile (fun a -> not (isNamed a)) args
  let named = List.skip (List.length positional) args
  if List.exists (fun a -> not (isNamed a)) named then
    fail $"in a call to '{what}', positional arguments must come before named ones"
  if List.length positional > List.length m.mpars then
    fail $"'{what}' takes {List.length m.mpars} argument(s), got {List.length positional}"
  let bindings = Buffer.empty
  let given = ref Map.empty
  let bindTemp (ce: CExpr) =
    let tmp = uniq cx "$m"
    Buffer.push (tmp, ce) bindings
    tmp
  let selfArg = Option.map (fun (c: CExpr) -> mk (CLocal(bindTemp c)) c.ty) self
  let bind (i: int) (a: Expr) =
    let p = List.item i m.mpars
    let pt = List.item i mptys
    if Map.containsKey p.mname given.Value then
      fail $"argument '{p.mname}' of '{what}' is given twice"
    let ce =
      if p.optional && Option.isNone p.mdefault then
        // the body sees option<T>; a given argument arrives as Some
        let inner =
          match prune v pt with
          | TCon("option", [ t ]) -> t
          | _ -> fresh v kAny
        let c = inferHint cx env depth inner a
        expect cx $"argument '{p.mname}' of '{what}'" inner c.ty
        let (u, tag) = Map.find "Some" cx.ctors.Value
        mk (CCtor(u, tag, [ c ])) pt
      else
        let c = inferHint cx env depth pt a
        expect cx $"argument '{p.mname}' of '{what}'" pt c.ty
        c
    given.Value <- Map.add p.mname (bindTemp ce, ce.ty) given.Value
  List.iteri bind positional
  for a in named do
    match a.e with
    | Bin(_, { e = Var n }, w) -> bind (Option.get (paramIndex n)) w
    | _ -> ()
  let scope = ref Map.empty
  let temp (i: int) (p: MemberParam) =
    let pt = List.item i mptys
    let (tmp, ty) =
      match Map.tryFind p.mname given.Value with
      | Some x -> x
      | None ->
        let ce =
          match (p.optional, p.mdefault) with
          | (true, Some d) ->
            let c = foreignly cx (fun () -> inferHint cx scope.Value 0 pt d)
            expect cx $"default of '{p.mname}'" pt c.ty
            c
          | (true, None) ->
            let (u, tag) = Map.find "None" cx.ctors.Value
            mk (CCtor(u, tag, [])) pt
          | (false, _) -> fail $"'{what}' is missing argument '{p.mname}'"
        (bindTemp ce, pt)
    scope.Value <- Map.add p.mname (localOf tmp ty false 0) scope.Value
    mk (CLocal tmp) ty
  let argTemps = List.mapi temp m.mpars
  let callArgs = List.append (Option.toList selfArg) argTemps
  let callE = mk (CApp(head, (if List.isEmpty callArgs then [ mk CUnit tUnit ] else callArgs))) resTy
  List.fold (fun (acc: CExpr) (b: string * CExpr) -> mk (CLet(fst b, snd b, acc)) acc.ty) callE (List.rev (Array.toList (Buffer.toArray bindings)))

/// `A.B.c.d` lexed as one name: the longest prefix that resolves, then field accesses.
and splitQualified (cx: Cx) (env: Map<string, Local>) (x: string) : option<Expr> =
  let parts = String.split "." x
  let resolves (name: string) = Map.containsKey name env || Map.containsKey name cx.consts.Value || Option.isSome (resolveName cx name)
  let rec tryAt (k: int) : option<Expr> =
    if k < 1 then
      None
    else
      let prefix = String.join "." (List.take k parts)
      if resolves prefix then
        Some(List.fold (fun (e: Expr) (f: string) -> plain (Field(e, f))) (plain (Var prefix)) (List.skip k parts))
      else
        tryAt (k - 1)
  tryAt (List.length parts - 1)

/// A trait method, instantiated; its type parameter must implement the trait.
and traitMethod (cx: Cx) (x: string) : CExpr =
  let tm = Map.find (Map.find x cx.traitAliases.Value) cx.traitMethods.Value
  let n = tm.nparams
  // the head needs the trait, with its other parameters (Iter<'a>), which the impl for the head's
  // type determines; then the method's ambient row
  let head =
    let k = kTrait tm.owner
    if n = 1 then k else { k with params = Map.ofList [ (tm.owner, List.init (n - 1) (fun i -> TGen(i + 1))) ] }
  let ambient = hasAmbient cx tm
  let kinds = List.concat [ [ head ]; List.init (n - 1) (fun _ -> kAny); (if ambient then [ kRow ] else []) ]
  let (t, inst) = instantiate cx kinds tm.ty
  let qname = tm.owner + "." + tm.name
  // through dyn, the ambient row is empty: checked once the value's type is known
  if ambient then
    Buffer.push (List.item 0 inst, List.item n inst, tm.owner, tm.name, cx.currentStmt.Value) cx.dynCalls
  if tm.isConst then
    mk (CApp(mk (CGlobal(qname, Some inst)) (tfun tUnit t), [ mk CUnit tUnit ])) t
  else
    mk (CGlobal(qname, Some inst)) t

/// The active pattern a case pattern uses at its top: its function, whether it's total, its
/// arguments, its case and the value's pattern.
and activeOf (cx: Cx) (p: Pat) : option<string * bool * list<Expr> * string * option<Pat>> =
  let (name, arg) =
    match p.pat with
    | PIdent(c, a) -> (Some c, a)
    | _ -> (None, None)
  let found =
    match name with
    | Some c -> resolveWith cx (fun q -> Map.containsKey q cx.activePatterns.Value) c
    | None -> None
  match found with
  | Some c ->
    let (fn, total, nargs) = Map.find c cx.activePatterns.Value
    let atoms =
      match arg with
      | Some { pat = PArgs ps } -> ps
      | Some q -> [ q ]
      | None -> []
    if List.length atoms < nargs then
      fail $"active pattern '{c}' needs {nargs} argument(s)"
    let toExpr (q: Pat) =
      match q.pat with
      | PInt n -> plain (Lit n)
      | PStr s -> plain (StrLit s)
      | PBool b -> plain (BoolLit b)
      | PUnit -> plain UnitLit
      | PIdent(x, None) -> plain (Var x)
      | _ -> fail "active pattern arguments must be literals or names"
    let args = List.map toExpr (List.take nargs atoms)
    let valuePat =
      match List.skip nargs atoms with
      | [] -> None
      | [ w ] -> Some w
      | _ -> fail $"too many patterns after active pattern '{c}'"
    Some(fn, total, args, c, valuePat)
  | None -> None

/// A match whose cases use active patterns becomes a chain of plain matches, in case order: a run
/// of ordinary cases matches the value; a run of one total active pattern matches its result; a
/// partial one matches Some value. Each falls through (`_`) to the rest.
and desugarActive (cx: Cx) (s: Expr) (cases: list<Clause>) : Expr =
  let sv = uniq cx "$ap"
  let rec chain (cases: list<Clause>) : Expr =
    let fallback (rest: list<Clause>) = if List.isEmpty rest then [] else [ { pattern = plainPat PWild; guard = None; body = chain rest } ]
    let first =
      match cases with
      | c :: _ -> activeOf cx c.pattern
      | [] -> panic "unreachable"
    match (cases, first) with
    | ([], _) -> panic "unreachable"
    | (_, None) ->
      // a run of ordinary cases (takeWhile's own test can fail: the cases are walked here)
      let rec plainRun (cs: list<Clause>) : list<Clause> =
        match cs with
        | d :: more ->
          match activeOf cx d.pattern with
          | None -> d :: plainRun more
          | Some _ -> []
        | [] -> []
      let group = plainRun cases
      let rest = List.skip (List.length group) cases
      plain (Match(plain (Var sv), List.append group (fallback rest)))
    | (c :: rest, Some(fn, total, args, cname, valuePat)) ->
      let callE = plain (Call(fn, List.append args [ plain (Var sv) ]))
      if total then
        let same (d: Clause) =
          match activeOf cx d.pattern with
          | Some(fn2, true, args2, _, _) -> fn2 = fn && args2 = args
          | _ -> false
        let rec sameRun (cs: list<Clause>) : list<Clause> =
          match cs with
          | d :: more -> if same d then d :: sameRun more else []
          | [] -> []
        let group = sameRun cases
        let rest2 = List.skip (List.length group) cases
        let recase (d: Clause) =
          match activeOf cx d.pattern with
          | Some(_, _, _, c2, value2) -> { d with pattern = plainPat (PIdent(c2, value2)) }
          | None -> d
        plain (Match(callE, List.append (List.map recase group) (fallback rest2)))
      else
        if List.isEmpty rest then
          fail $"active pattern '{cname}' can fail; add a case after it"
        let someCase = { pattern = plainPat (PIdent("Some", Some(Option.defaultValue (plainPat PWild) valuePat))); guard = c.guard; body = c.body }
        plain (Match(callE, someCase :: fallback rest))
  plain (Let(plainPat (PIdent(sv, None)), None, s, chain cases))

/// A match on an active pattern function's result (made by desugarActive) uses its cases directly.
and isActiveCall (cx: Cx) (e: Expr) : bool =
  match e.e with
  | Call(f, _) -> List.exists (fun (p: string * (string * bool * int)) -> (match snd p with (fn, _, _) -> fn = f)) (Map.toList cx.activePatterns.Value)
  | _ -> false

/// What a name refers to, for go-to-definition: a local's unique name or a global's.
and keyOf (cx: Cx) (env: Map<string, Local>) (x: string) : string =
  match Map.tryFind x env with
  | Some l -> l.u
  | None -> Option.defaultValue "" (resolveName cx x)

/// A name's full name, as the scope resolves it, when something has it (remembered for the
/// declaration: Cx.resolved).
and resolveName (cx: Cx) (x: string) : option<string> =
  match Map.tryFind x cx.resolved.Value with
  | Some r -> r
  | None ->
    let r = resolveAnew cx x
    cx.resolved.Value <- Map.add x r cx.resolved.Value
    r

and resolveAnew (cx: Cx) (x: string) : option<string> =
  let exists (q: string) =
    Map.containsKey q cx.globals.Value || Map.containsKey q cx.ctors.Value || Map.containsKey q cx.traitAliases.Value || Map.containsKey q builtins || Map.containsKey q cx.externs.Value || Map.containsKey q cx.consts.Value || Map.containsKey q cx.globalValues.Value || Map.containsKey q cx.effectOps.Value || Option.isSome (staticMember cx q)
  resolveWith cx exists x

/// A name's value.
and value (cx: Cx) (env: Map<string, Local>) (depth: int) (x: string) : CExpr =
  // a local shadows the names of modules (it's not resolved: a private one would fail)
  match (if Map.containsKey x env then None else resolveName cx x) with
  | Some q when q <> x -> valueQ cx env depth q
  | _ -> valueQ cx env depth x

/// A name's value, the name resolved.
and valueQ (cx: Cx) (env: Map<string, Local>) (depth: int) (x: string) : CExpr =
  let v = cx.v
  match Map.tryFind x env with
  | None when Map.containsKey x cx.consts.Value ->
    // a constant: its expression, typed here (a literal constant takes the type each use needs),
    // its type variables its own (it's generic: Map.empty at any type, twice in one function too)
    if Set.contains x cx.inlining.Value then
      fail $"'{x}' is defined in terms of itself"
    cx.inlining.Value <- Set.add x cx.inlining.Value
    let saved = cx.tyvars.Value
    cx.tyvars.Value <- Map.empty
    let outerConst = cx.inConst.Value
    cx.inConst.Value <- x
    let c = foreignly cx (fun () -> infer cx Map.empty depth (Map.find x cx.consts.Value))
    cx.inConst.Value <- outerConst
    cx.inlining.Value <- Set.remove x cx.inlining.Value
    cx.tyvars.Value <- saved
    c
  | None when Map.containsKey x cx.globalValues.Value -> mk (CGlobalVal x) (Map.find x cx.globalValues.Value)
  | Some l ->
    if l.mut && l.depth < depth then
      fail $"mutable variable '{x}' cannot be captured by a closure; use a ref cell (let x = ref …; x.Value <- …)"
    mk (CLocal l.u) l.ty
  | None ->
    let sm = if Map.containsKey x cx.globals.Value then None else staticMember cx x
    match (Map.tryFind x cx.globals.Value, sm) with
    | (None, Some m) ->
      if m.isProperty then memberCall cx env depth m None [] x else fail $"static method '{x}' must be called: {x}(...)"
    | (Some g, _) when g.defining -> mk (CGlobal(x, None)) g.ty
    | (Some g, _) ->
      let (t, inst) = instantiate cx g.kinds g.ty
      opened cx g.arity (mk (CGlobal(x, Some inst)) t)
    | (None, None) ->
      if Map.containsKey x cx.ctors.Value then
        let (u, tag) = Map.find x cx.ctors.Value
        let (uty, targs) = instType cx u
        match caseFields cx u tag targs with
        | [] -> mk (CCtor(u, tag, [])) uty
        | [ ft ] when Set.contains x cx.apCtors.Value ->
          expect cx $"'{x}' without a value" tUnit ft
          mk (CCtor(u, tag, [ mk CUnit tUnit ])) uty
        | [ ft ] ->
          let p = uniq cx "$v"
          mk (CLam([ (p, ft) ], mk (CCtor(u, tag, [ mk (CLocal p) ft ])) uty)) (TFun(ft, uty, fresh v kRow))
        | _ -> fail $"constructor '{x}' takes several fields; apply it as {x} (a, b)"
      else if Map.containsKey x cx.traitAliases.Value then
        traitMethod cx x
      else if Map.containsKey x cx.effectOps.Value then
        perform cx env depth x []
      else if Map.containsKey x builtins then
        builtinCall cx env depth x []
      else if Map.containsKey x cx.externs.Value then
        fail $"C function '{x}' must be called directly"
      else
        match splitQualified cx env x with
        | Some e -> infer cx env depth e
        | None when Map.containsKey x cx.skippedC.Value -> fail $"C name '{x}' wasn't imported: {Map.find x cx.skippedC.Value}"
        | None -> unknown cx "name" x

/// A call of a name: a function, a constructor, a trait method, a builtin, a C function, an
/// effect's operation, or a static member.
and call (cx: Cx) (env: Map<string, Local>) (depth: int) (f: string) (args: list<Expr>) : CExpr = callWith cx env depth f args []

/// A call; argHints: the type expected of each argument where the callee's says nothing (a list
/// literal's elements).
and callWith (cx: Cx) (env: Map<string, Local>) (depth: int) (f: string) (args: list<Expr>) (argHints: list<option<Ty>>) : CExpr =
  match (if Map.containsKey f env then None else resolveName cx f) with
  | Some q when q <> f -> callQ cx env depth q args argHints
  | _ -> callQ cx env depth f args argHints

and callQ (cx: Cx) (env: Map<string, Local>) (depth: int) (f: string) (args: list<Expr>) (argHints: list<option<Ty>>) : CExpr =
  let inEnv = Map.containsKey f env
  let isGlobal = Map.containsKey f cx.globals.Value
  if not (inEnv || isGlobal) && Option.isSome (staticMember cx f) then
    memberCall cx env depth (Option.get (staticMember cx f)) None args f
  else if inEnv || isGlobal || Map.containsKey f cx.globalValues.Value || Map.containsKey f cx.consts.Value then
    // a function, or a top-level value holding one: let validate = parse >=> check
    apply cx env depth (value cx env depth f) args (Some f)
  else if Map.containsKey f cx.ctors.Value then
    ctor cx env depth f args argHints
  else if Map.containsKey f cx.traitAliases.Value then
    apply cx env depth (traitMethod cx f) args (Some f)
  else if Map.containsKey f builtins then
    builtinCall cx env depth f args
  else if Map.containsKey f cx.externs.Value then
    externCall cx env depth f args
  else if Map.containsKey f cx.effectOps.Value then
    perform cx env depth f args
  else if String.contains ".Builder." f then
    // a computation expression's form, and its builder lacks the function for it
    let i = Option.get (String.lastIndexOf "." f)
    let fn = skipChars (i + 1) f
    let builder = String.sub f 0 i
    let firstDot = Option.get (String.indexOf "." builder)
    let c0 = int (String.byte builder 0)
    let lower = String.ofByte (u8 (if c0 >= 65 && c0 <= 90 then c0 + 32 else c0))
    let w = lower + String.sub builder 1 (firstDot - 1)
    let form =
      match fn with
      | "bind" -> "let! and do!"
      | "ret" -> "return"
      | "zero" -> "an if without else, and a body that ends in a statement"
      | "using" -> "use"
      | "forEach" -> "for"
      | "delay" -> "its body"
      | _ -> fn
    if w = "async" then
      fail "there's no async { }: write task { }, and run it with Task.run"
    fail $"{w} {{ }} needs {builder}.{fn}, for {form}"
  else
    match splitQualified cx env f with
    | Some e -> infer cx env depth (plain (App(e, args)))
    | None when Map.containsKey f cx.skippedC.Value -> fail $"C function '{f}' wasn't imported: {Map.find f cx.skippedC.Value}"
    | None -> unknown cx "function" f

/// Type-checks arguments against a (curried) function type; gives them and the result type.
and checkArgs (cx: Cx) (env: Map<string, Local>) (depth: int) (fty: Ty) (args: list<Expr>) (name: option<string>) : list<CExpr> * Ty =
  let v = cx.v
  let what (i: int) =
    match name with
    | Some f -> $"argument {i + 1} of '{f}'"
    | None -> $"argument {i + 1}"
  // a lambda with an unannotated parameter is typed after the other arguments, which may tell it
  // what it's applied to: List.map (fun s -> s.Length) names, and so names |> List.map (fun s ->
  // s.Length)
  let rec waits (a: Expr) =
    match a.e with
    | At x
    | AtLine x -> waits x
    | Lambda(ps, _) -> List.exists (fun (p: Param) -> Option.isNone p.ann) ps
    | _ -> false
  // the parameter types the arguments meet, and the result (None: too many arguments)
  let rec peelArgs (t: Ty) (k: int) (acc: list<Ty>) : option<list<Ty> * Ty> =
    if k = 0 then
      Some(List.rev acc, t)
    else
      match prune v t with
      | TFun(p, r, row) ->
        useRow cx row
        peelArgs r (k - 1) (p :: acc)
      | TVar i ->
        // a function not known yet: only the last arrow a call takes performs
        let p = fresh v kAny
        let r = fresh v kAny
        let row = if k = 1 then fresh v kRow else rowEmpty
        expect cx "function" (TVar i) (TFun(p, r, row))
        useRow cx row
        peelArgs r (k - 1) (p :: acc)
      | _ -> None
  // a share<F> passed where a plain function is expected is one (share.as keeps the value's own
  // type inside, for the check of what crosses threads)
  let unshare (p: Ty) (ca: CExpr) =
    match (prune v p, prune v ca.ty) with
    | (TFun _, TCon("share", [ f ])) -> mk (CPrim("share.as", [ ca ])) f
    | _ -> ca
  let n = List.length args
  match (if List.exists waits args then peelArgs fty n [] else None) with
  | Some(ps, res) ->
    let typed = Buffer.create n (mk CUnit tUnit)
    let indexed = List.indexed args
    let order = List.append (List.filter (fun (_, a) -> not (waits a)) indexed) (List.filter (fun (_, a) -> waits a) indexed)
    for (i, a) in order do
      let p = List.item i ps
      let ca = unshare p (inferHint cx env depth p a)
      expect cx (what i) p ca.ty
      typed.[i] <- ca
    (Array.toList (Buffer.toArray typed), res)
  | None ->
    let t = ref fty
    let one (i: int) (a: Expr) =
      let ca =
        match prune v t.Value with
        | TFun(p, _, _) -> unshare p (inferHint cx env depth p a)
        | _ -> infer cx env depth a
      match prune v t.Value with
      | TFun(p, r, row) ->
        expect cx (what i) p ca.ty
        useRow cx row
        t.Value <- r
      | TVar x ->
        // a function not known yet: only the last arrow a call takes performs
        let r = fresh v kAny
        let row = if i = n - 1 then fresh v kRow else rowEmpty
        expect cx "function" (TVar x) (TFun(ca.ty, r, row))
        useRow cx row
        t.Value <- r
      | ty ->
        match name with
        | Some f -> fail $"'{f}' is applied to too many arguments"
        | None -> fail $"this value is not a function; it has type {show cx ty}"
      ca
    let cargs = List.mapi one args
    (cargs, t.Value)

/// A value applied to arguments.
and apply (cx: Cx) (env: Map<string, Local>) (depth: int) (ch0: CExpr) (args: list<Expr>) (name: option<string>) : CExpr =
  // a function called is called as it is (its row is met at each arrow the call takes)
  let ch =
    match ch0.k with
    | CPrim("eff.open", [ g ]) -> g
    | _ -> ch0
  match prune cx.v ch.ty with
  | TCon("fnptr", [ f ]) -> fnptrCall cx env depth ch f args
  | TCon("share", [ f ]) ->
    // called as any function (the callee keeps its type: what crosses threads is checked by it)
    let (cargs, t) = checkArgs cx env depth f args name
    mk (CApp(ch, cargs)) t
  | _ ->
    let (cargs, t) = checkArgs cx env depth ch.ty args name
    mk (CApp(ch, cargs)) t

/// A call through a C function pointer (fnptr<A -> B -> R>), inside `unsafe`: with all its
/// arguments at once, passed as to an extern.
and fnptrCall (cx: Cx) (env: Map<string, Local>) (depth: int) (fp: CExpr) (f: Ty) (args0: list<Expr>) : CExpr =
  if not cx.unsafeOn.Value then
    fail "calling a C function pointer is unsafe: call it inside `unsafe`"
  let rec split (t: Ty) : list<Ty> * Ty =
    match prune cx.v t with
    | TFun(a, r, _) ->
      let (ps, res) = split r
      (a :: ps, res)
    | r -> ([], r)
  let (ps0, ret) = split f
  let ps = List.filter (fun p -> prune cx.v p <> tUnit) ps0
  let unitArg =
    match args0 with
    | [ { e = UnitLit } ] -> true
    | _ -> false
  let args = if List.isEmpty ps && unitArg then [] else args0
  if List.length args <> List.length ps then
    fail $"this C function pointer takes {List.length ps} argument(s), got {List.length args}"
  let one (i: int) (pa: Ty * Expr) =
    let (p, a) = pa
    let ca = inferHint cx env depth p a
    let what = $"argument {i + 1} of the C function pointer"
    // a string is passed to C as a pointer to its bytes
    if prune cx.v p = tCStr then expect cx what (fresh cx.v kStrLit) ca.ty else expect cx what p ca.ty
    ca
  mk (CPrim("fnptr.call", fp :: List.mapi one (List.zip ps args))) ret

/// A call of a function built into the compiler.
and builtinCall (cx: Cx) (env: Map<string, Local>) (depth: int) (name: string) (args: list<Expr>) : CExpr =
  if Set.contains name chipOnly && Option.isNone cx.irqs then
    fail $"{name} exists on microcontrollers, and this build isn't for one (zs build --target cortex-m4)"
  if Set.contains name unsafeBuiltins && not cx.unsafeOn.Value then
    if name = "Collections.Span.ofPtr" then
      fail "Span.ofPtr needs unsafe: the memory's lifetime isn't checked"
    fail $"'{name}' is unsafe: use it inside `unsafe`"
  let b = Map.find name builtins
  let (t, _) = instantiate cx b.kinds b.ty
  let (cargs0, finalTy) = checkArgs cx env depth t args (Some name)
  let unwrapped (c: CExpr) =
    match c.k with
    | CPrim("span.ofArray", [ x ])
    | CPrim("span.ofBuffer", [ x ]) -> x
    | _ -> c
  let cargs = if Set.contains b.prim overWindows then List.map unwrapped cargs0 else cargs0
  let (ptys, resTy) = peel cx b.arity t
  if List.length cargs >= b.arity then
    let first = List.take b.arity cargs
    let rest = List.skip b.arity cargs
    let prim = mk (CPrim(b.prim, first)) resTy
    if List.isEmpty rest then prim else mk (CApp(prim, rest)) finalTy
  else
    // partial application: bind the given arguments, then a lambda over the rest
    let given = List.map (fun (c: CExpr) -> (uniq cx "$a", c)) cargs
    let ps = List.map (fun pt -> (uniq cx "$b", pt)) (List.skip (List.length given) ptys)
    let callArgs = List.append (List.map (fun (p: string * CExpr) -> mk (CLocal(fst p)) (snd p).ty) given) (List.map (fun (u, t) -> mk (CLocal u) t) ps)
    let lamE = mk (CLam(ps, mk (CPrim(b.prim, callArgs)) resTy)) (funTy (List.map snd ps) resTy)
    List.fold (fun (acc: CExpr) (p: string * CExpr) -> mk (CLet(fst p, snd p, acc)) acc.ty) lamE (List.rev given)

/// A call of a C function.
and externCall (cx: Cx) (env: Map<string, Local>) (depth: int) (f: string) (args0: list<Expr>) : CExpr =
  let s = Map.find f cx.externs.Value
  let unitArg =
    match args0 with
    | [ { e = UnitLit } ] -> true
    | _ -> false
  let args = if List.isEmpty s.pars && unitArg then [] else args0
  let n = List.length s.pars
  let given = List.length args
  if given < n || (given > n && not s.variadic) then
    fail $"'{f}' expects {n} argument(s), got {given}"
  let one (i: int) (a: Expr) =
    // the declared parameter type guides a record literal ({ x = 1; y = 2 } for Point), and a
    // callback's what it's given (a share<F> one is checked as crossing threads)
    let ca =
      if i >= n then
        infer cx env depth a
      else
        match List.item i s.pars with
        | TCon("callback", [ g ]) -> inferHint cx env depth g a
        | t -> inferHint cx env depth t a
    if i < n then
      let what = $"argument {i + 1} of '{f}'"
      // a string is passed to C as a pointer to its bytes; a closure as callback + user data
      match List.item i s.pars with
      | t when t = tCStr -> expect cx what (fresh cx.v kStrLit) ca.ty
      | TCon("callback", [ g ]) ->
        let rule (x: string) = "a function given to C must have no effects: this one performs " + x + " (the C-callback rule)"
        expectNoEffects cx rule what g ca.ty
      | t -> expect cx what t ca.ty
    ca
  mk (CExtern(f, List.mapi one args)) s.ret

/// A constructor applied: C, C x, C (x, y), or C(field = x, …) with every field by name.
and ctor (cx: Cx) (env: Map<string, Local>) (depth: int) (c: string) (args0: list<Expr>) (argHints: list<option<Ty>>) : CExpr =
  let (u, tag) = Map.find c cx.ctors.Value
  let (uty, targs) = instType cx u
  let fields = caseFields cx u tag targs
  let fieldNames = Map.find c cx.ctorFieldNames.Value
  let isNamed (a: Expr) =
    match a.e with
    | Bin("=", { e = Var n }, _) -> List.contains (Some n) fieldNames
    | _ -> false
  let named =
    match args0 with
    | [ { e = Tuple xs } ] -> if List.forall isNamed xs then Some xs else if isNamed (List.head args0) then Some args0 else None
    | [ a ] -> if isNamed a then Some [ a ] else None
    | _ -> None
  let args =
    match named with
    | Some xs ->
      // Circle(radius = 2.0): every field by name, in any order
      let pair (x: Expr) =
        match x.e with
        | Bin(_, { e = Var n }, w) -> (n, w)
        | _ -> panic "unreachable"
      let given = List.map pair xs
      if List.length (List.distinct (List.map fst given)) <> List.length given then
        fail $"a field of '{c}' is given twice"
      let byName (n: option<string>) =
        match List.tryFind (fun (m, _) -> Some m = n) given with
        | Some(_, w) -> w
        | None ->
          match n with
          | Some name -> fail $"constructor '{c}' is missing field '{name}'"
          | None -> fail $"constructor '{c}' has unnamed fields; pass them by position"
      List.map byName fieldNames
    | None ->
      let tupleOf (x: Expr) =
        match x.e with
        | Tuple xs -> Some xs
        | _ -> None
      ctorArgs c args0 fields tupleOf (fun _ -> false)
  // where the constructor's field type says nothing yet (a new variable, a list of one), the type
  // expected of the argument from around the call (a list literal's element) is its hint
  let rec vague (t: Ty) =
    match prune cx.v t with
    | TVar _ -> true
    | TCon("list", [ x ]) -> vague x
    | _ -> false
  let hintAt (i: int) (ft: Ty) =
    if vague ft then
      match List.tryItem i argHints with
      | Some(Some h) -> h
      | _ -> ft
    else
      ft
  let one (i: int) (p: Expr * Ty) =
    let (a, ft) = p
    let ca = inferHint cx env depth (hintAt i ft) a
    expect cx $"argument of '{c}'" ft ca.ty
    ca
  mk (CCtor(u, tag, List.mapi one (List.zip args fields))) uty

/// E.op args: the operation performed, which puts E in the row of the function it's in; a function
/// performing it when given fewer arguments.
and perform (cx: Cx) (env: Map<string, Local>) (depth: int) (q: string) (args: list<Expr>) : CExpr =
  let v = cx.v
  let (eff, i) = Map.find q cx.effectOps.Value
  let info = Map.find eff cx.effects.Value
  let op = List.item i info.ops
  let targs = List.init info.npars (fun _ -> fresh v kAny)
  let inst = List.append targs (List.init op.own (fun _ -> fresh v kAny))
  let ptys = List.map (substGen v inst) op.pars
  let ret = substGen v inst op.ret
  let label = TCon(eff, targs)
  let np = List.length ptys
  if List.length args >= np then
    let now = List.take np args
    let later = List.skip np args
    let (cargs, _) = checkArgs cx env depth (funTyRow ptys ret (rowExt label rowEmpty)) now (Some q)
    let p = mk (CPerform(label, i, cargs)) ret
    if List.isEmpty later then p else apply cx env depth p later None
  else
    // the operation as a value: a lambda performing it (with the arguments given first)
    let give (j: int) (a: Expr) =
      let pt = List.item j ptys
      let c = inferHint cx env depth pt a
      expect cx $"argument {j + 1} of '{q}'" pt c.ty
      (uniq cx "$a", c)
    let given = List.mapi give args
    let ps = List.map (fun t -> (uniq cx "$b", t)) (List.skip (List.length given) ptys)
    let all = List.append (List.map (fun (p: string * CExpr) -> mk (CLocal(fst p)) (snd p).ty) given) (List.map (fun (u, t) -> mk (CLocal u) t) ps)
    let lamE = mk (CLam(ps, mk (CPerform(label, i, all)) ret)) (funTyRow (List.map snd ps) ret (rowExt label (fresh v kRow)))
    List.fold (fun (acc: CExpr) (p: string * CExpr) -> mk (CLet(fst p, snd p, acc)) acc.ty) lamE (List.rev given)

/// handle body with clauses: the body performs the effect (in front of what the handle's own body
/// may), each clause gives an operation's meaning, its resumption a function from the operation's
/// result to the handle's; the return clause maps the body's result (as it is when left out). The
/// clauses perform in the handle's own row.
and handleExpr (cx: Cx) (env: Map<string, Local>) (depth: int) (body: Expr) (ops: list<OpClause>) (ret: option<Pat * Expr>) : CExpr =
  let v = cx.v
  if List.isEmpty ops then
    fail "a handle has a clause for each operation of its effect: | Effect.op x, k -> …"
  let opOf (q: string) : string =
    match resolveWith cx (fun x -> Map.containsKey x cx.effectOps.Value) q with
    | Some full -> full
    | None ->
      // the effect known, not the operation: name the ones it has
      let known =
        match String.lastIndexOf "." q with
        | Some dot when dot > 0 ->
          match resolveWith cx (fun x -> Map.containsKey x cx.effects.Value) (String.sub q 0 dot) with
          | Some e -> Some(e, skipChars (dot + 1) q)
          | None -> None
        | _ -> None
      match known with
      | Some(e, opName) ->
        let names = List.map (fun (o: EffectOp) -> o.name) (Map.find e cx.effects.Value).ops
        fail $"effect {shortName e} has no operation '{opName}' ({String.join ", " names})"
      | None -> fail $"unknown operation '{q}': a clause names an effect's operation, Effect.op"
  let resolveClause (c: OpClause) =
    let full = opOf c.op
    let (e, i) = Map.find full cx.effectOps.Value
    let info = Map.find e cx.effects.Value
    let o = List.item i info.ops
    let label = TCon(e, List.init info.npars TGen)
    // a reference to the operation, for hover and references
    recordKey cx c.opAt (shortName full) (funTyRow o.pars o.ret (rowExt label rowEmpty)) false full false
    (full, c)
  let clauses = List.map resolveClause ops
  let eff = fst (Map.find (fst (List.head clauses)) cx.effectOps.Value)
  for (q, _) in clauses do
    if fst (Map.find q cx.effectOps.Value) <> eff then
      fail $"a handle is for one effect: {shortName q}'s clause needs a handle of its own (around this one, or inside it)"
  let info = Map.find eff cx.effects.Value
  let qs = List.map fst clauses
  match List.tryFind (fun q -> List.length (List.filter (fun r -> r = q) qs) > 1) qs with
  | Some q -> fail $"operation {shortName q} has two clauses"
  | None -> ()
  let covered = Set.ofList (List.map (fun q -> snd (Map.find q cx.effectOps.Value)) qs)
  let coveredOp (j: int) (o: EffectOp) =
    if not (Set.contains j covered) then
      let opName = shortName eff + "." + o.name
      fail $"this handle of {shortName eff} has no clause for {opName}"
  List.iteri coveredOp info.ops
  let targs = List.init info.npars (fun _ -> fresh v kAny)
  let label = TCon(eff, targs)
  let outer = cx.ctxRow.Value
  let cb = withRowAs cx (rowExt label outer) cx.ctxWhat.Value (fun () -> infer cx env depth body)
  let ans = fresh v kAny
  let rv = uniq cx "$handled"
  let retBody =
    match ret with
    | Some(p, rb) ->
      let names = ref Map.empty
      let cp = Patterns.pattern cx names p cb.ty
      let env2 = withVars env names.Value (patVars cp) depth
      Patterns.check (unionCases cx) (fun c -> Set.contains c cx.apCtors.Value) [ (cp, false) ]
      let crb = infer cx env2 depth rb
      expect cx "the return clause" ans crb.ty
      mk (CMatch(mk (CLocal rv) cb.ty, [ (cp, None, crb) ])) ans
    | None ->
      expect cx "the handled expression" ans cb.ty
      mk (CLocal rv) cb.ty
  let what = if Option.isSome ret then "the return clause" else "the handled expression"
  let checkClause (cl: string * OpClause) =
    let (q, c) = cl
    let i = snd (Map.find q cx.effectOps.Value)
    let op = List.item i info.ops
    // the operation's own type variables stand for any type: a clause can't choose one
    let own = List.init op.own (fun _ -> TCon(uniq cx "$sk", []))
    let inst = List.append targs own
    let ptys = List.map (substGen v inst) op.pars
    let rty = substGen v inst op.ret
    if List.length c.args <> List.length ptys then
      fail $"operation {shortName q} takes {List.length ptys} argument(s), this clause has {List.length c.args}"
    let params = List.map (fun (p: Pat) -> ({ param = p; ann = None } : Param)) c.args
    let (named, clauseBody) = lowerParams cx params c.opBody
    let pars = List.map2 (fun (x, _) t -> (x, uniq cx x, t)) named ptys
    recordParams cx params pars
    let kty = TFun(rty, ans, outer)
    let ku = uniq cx c.k
    let envP = withPars env pars depth
    let envC = if c.k = "_" then envP else Map.add c.k (localOf ku kty false depth) envP
    let cbody = infer cx envC depth clauseBody
    if not (unifies cx ans cbody.ty) then
      fail $"clause {shortName q} gives {show cx cbody.ty}, {what} {show cx ans}"
    (i, parsOf pars, (ku, kty), cbody)
  let cclauses = List.map checkClause clauses
  let rec skolem (t: Ty) =
    match prune v t with
    | TCon(n, ts) -> String.startsWith "$sk" n || List.exists skolem ts
    | TTuple ts -> List.exists skolem ts
    | TFun(a, b, r) -> skolem a || skolem b || skolem r
    | _ -> false
  if skolem ans then
    fail "a handle's result can't have an operation's own type (it stands for any type, chosen where the operation is performed)"
  mk (CHandle(label, cb, cclauses, (rv, cb.ty), retBody)) ans

/// A list or array expression, [ for x in xs do … yield e ]. One `for` over a list, an array or an
/// int range, filtered by `if`s, whose parts are pure as fusion takes it (arithmetic on immutable
/// locals), is the pipeline fusion makes one loop of: List.init over a range, a filter per `if`, a
/// map to what's yielded (no filter for an array). Any other body runs in order: a loop consing
/// what it yields onto a list, reversed in place at the end.
and listExpression (cx: Cx) (env: Map<string, Local>) (depth: int) (isArray: bool) (body: Expr) : CExpr =
  let v = cx.v
  let rec strip (e: Expr) =
    match e.e with
    | At a
    | AtLine a -> strip a
    | _ -> e
  // the filters (outermost first) and the yielded value under the for
  let rec stages (e: Expr) : option<list<Expr> * Expr> =
    match (strip e).e with
    | If(c, t, None) -> Option.map (fun (fs, y) -> (c :: fs, y)) (stages t)
    | Yield y -> Some([], y)
    | _ -> None
  let rec fusible (locals: Set<string>) (e: Expr) : bool =
    match e.e with
    | Lit _
    | FloatLit _
    | BoolLit _
    | CharLit _
    | UnitLit -> true
    | Var x -> Set.contains x locals || Option.exists (fun (l: Local) -> not l.mut) (Map.tryFind x env)
    | Bin(op, a, b) -> Set.contains op pureOps && fusible locals a && fusible locals b
    | Neg a
    | Not a
    | At a
    | AtLine a -> fusible locals a
    | If(c, t, Some f) -> fusible locals c && fusible locals t && fusible locals f
    | Let({ pat = PIdent(x, None) }, None, w, b) -> fusible locals w && fusible (Set.add x locals) b
    | _ -> false
  let cons (y: Expr) = plain (Assign(plain (Var "$acc"), plain (Call("::", [ plain (Tuple [ y; plain (Var "$acc") ]) ]))))
  // the body with each yield consing onto $acc (a rebuilt statement mark is the line's: the
  // statement isn't where it was written any more)
  let rec yields (e: Expr) : Expr =
    match e.e with
    | At a -> { e = AtLine(yields a); at = e.at }
    | AtLine a -> { e = AtLine(yields a); at = e.at }
    | Yield y -> cons y
    | YieldAll ys -> plain (ForIn("$y", ys, cons (plain (Var "$y"))))
    | ForIn(x, xs, b) -> plain (ForIn(x, xs, yields b))
    | For(x, a, s, b, body) -> plain (For(x, a, s, b, yields body))
    | If(c, t, f) -> plain (If(c, yields t, Option.map yields f))
    | Match(s, cases) -> plain (Match(s, List.map (fun (c: Clause) -> { c with body = yields c.body }) cases))
    | Let(p, t, w, b) -> plain (Let(p, t, w, yields b))
    | Seq(a, b) -> plain (Seq(yields a, yields b))
    | _ -> e
  let inOrder (env2: Map<string, Local>) (b: Expr) : bool * CExpr =
    let built = plain (Call(libraryName "Collections.List.rev", [ plain (Var "$acc") ]))
    let result = if isArray then plain (Call(libraryName "Collections.Array.ofList", [ built ])) else built
    (false, infer cx env2 depth (plain (LetMut("$acc", None, plain (Var "[]"), plain (Seq(yields b, result))))))
  // e with c bound to name, inferred once; in a pipeline, c put where it's used (pure, or used
  // once), so the pipeline is one fusion sees whole under a consumer (List.sum [ … ])
  let bound (name: string) (c: CExpr) (putIn: bool) (env2: Map<string, Local>) (k: Map<string, Local> -> bool * CExpr) : bool * CExpr =
    let l = localOf (uniq cx name) c.ty false depth
    let (piped, r) = k (Map.add name l env2)
    let rec put (e: CExpr) : CExpr =
      match e.k with
      | CLocal x when x = l.u -> c
      | k2 -> { e with k = mapChildren put k2 }
    (piped, (if piped && putIn then put r else mk (CLet(l.u, c, r)) r.ty))
  let piped (env2: Map<string, Local>) (x: string) (filters: list<Expr>) (y: Expr) (src: Expr) : bool * CExpr =
    let m = if isArray then "Collections.Array." else "Collections.List."
    let filtered = List.fold (fun (xs: Expr) (c: Expr) -> plain (Call(m + "filter", [ lam x c; xs ]))) src filters
    (true, infer cx env2 depth (plain (Call(m + "map", [ lam x y; filtered ]))))
  let pureStages (x: string) (st: list<Expr> * Expr) =
    let (filters, y) = st
    (not isArray || List.isEmpty filters) && List.forall (fusible (Set.ofList [ x ])) (y :: filters)
  match (strip body).e with
  | ForIn(x, xs, b) when not (String.startsWith "$" x) ->
    let cxs = infer cx env depth xs
    settle cx cxs.ty
    let st0 = stages b
    let fuses =
      match st0 with
      | Some st -> pureStages x st
      | None -> false
    let k (env2: Map<string, Local>) =
      match (prune v cxs.ty, st0) with
      | (TCon("list", _), Some st) when fuses && not isArray -> piped env2 x (fst st) (snd st) (plain (Var "$coll"))
      | (TCon("array", _), Some st) when fuses ->
        let src = if isArray then plain (Var "$coll") else plain (Call(libraryName "Collections.Array.toList", [ plain (Var "$coll") ]))
        piped env2 x (fst st) (snd st) src
      | _ -> inOrder env2 (plain (ForIn(x, plain (Var "$coll"), b)))
    snd (bound "$coll" cxs true env k)
  | For(x, lo, None, hi, b) ->
    let clo = infer cx env depth lo
    let chi = infer cx env depth hi
    expect cx "range" clo.ty chi.ty
    match prune v clo.ty with
    | TVar _ -> expect cx "range" tInt clo.ty
    | _ -> ()
    let st0 = stages b
    let fuses =
      match st0 with
      | Some st -> pureStages x st
      | None -> false
    let inner (env3: Map<string, Local>) =
      match (prune v clo.ty, st0) with
      | (TCon("int", []), Some st) when fuses ->
        let m = if isArray then "Collections.Array." else "Collections.List."
        let n = plain (Bin("+", plain (Bin("-", plain (Var "$hi"), plain (Var "$lo"))), plain (Lit(i64 1))))
        let index = lam "$k" (plain (Bin("+", plain (Var "$lo"), plain (Var "$k"))))
        piped env3 x (fst st) (snd st) (plain (Call(m + "init", [ n; index ])))
      | _ -> inOrder env3 (plain (For(x, plain (Var "$lo"), None, plain (Var "$hi"), b)))
    let outer (env2: Map<string, Local>) = bound "$hi" chi true env2 inner
    snd (bound "$lo" clo (fusible Set.empty lo) env outer)
  | _ -> snd (inOrder env body)

/// The record a literal builds: the expected type if it is a record; otherwise the only record in
/// scope whose fields fit (all given fields exist, all missing ones have defaults). A constant's
/// literal keeps the record it built where it's defined: at a use, it means the record its own
/// module sees.
and recordLit (cx: Cx) (env: Map<string, Local>) (depth: int) (hint: option<Ty>) (node: Expr) (fields: list<FieldValue>) : CExpr =
  let v = cx.v
  let given = List.map (fun (f: FieldValue) -> f.field) fields
  let fits (r: string) =
    let defs = List.zip (fieldsOf cx r) (Map.find r cx.recordDefaults.Value)
    let has (f: string) = List.exists (fun (p: (string * Ty) * option<Expr>) -> fst (fst p) = f) defs
    let filled (p: (string * Ty) * option<Expr>) = Option.isSome (snd p) || List.contains (fst (fst p)) given
    List.forall has given && List.forall filled defs
  // a literal is told apart by its first field name's token (it has no place of its own)
  let litAt =
    match fields with
    | f :: _ -> f.nameAt
    | [] -> -1
  let remembers = cx.inConst.Value <> "" && litAt >= 0
  let key = (cx.inConst.Value, litAt)
  let remembered = if remembers then Map.tryFind key cx.literalRecords.Value else None
  let rname =
    match Option.map (prune v) hint with
    | Some(TCon(n, _)) when isRecord cx n -> n
    | _ when Option.isSome remembered -> Option.get remembered
    | _ ->
      match inScope cx (List.filter fits (Array.toList (Buffer.toArray cx.records))) with
      | [ r ] -> r
      // the precise error comes from buildRecord
      | [] -> recordOf cx (fresh v kAny) (List.head given)
      | many ->
        let exact = List.filter (fun r -> List.length (fieldsOf cx r) = List.length given) many
        if List.isEmpty exact then
          fail $"record literal could be any of {String.join ", " many}; add a type annotation"
        else
          List.last exact
  if remembers then
    cx.literalRecords.Value <- Map.add key rname cx.literalRecords.Value
  fieldUses cx rname (List.map (fun (f: FieldValue) -> (f.field, f.nameAt)) fields) false
  let (_, targs) = instType cx rname
  let defaults = Map.find rname cx.recordDefaults.Value
  let fallback (i: int) (scope: Map<string, Local>) =
    let (f, ft0) = List.item i (fieldsOf cx rname)
    let ft = substGen v targs ft0
    match List.item i defaults with
    | Some d ->
      let ce = foreignly cx (fun () -> inferHint cx scope 0 ft d)
      expect cx $"default of field '{f}'" ft ce.ty
      ce
    | None -> fail $"record '{rname}' is missing field '{f}'"
  buildRecord cx env depth rname targs fields fallback

/// Binds each given field to a temporary in source order (preserving evaluation order), then each
/// missing field, in declaration order, to fallback i scope, where scope holds the fields
/// declared before it. Builds the record from the temporaries.
and buildRecord (cx: Cx) (env: Map<string, Local>) (depth: int) (rname: string) (targs: list<Ty>) (fields: list<FieldValue>) (fallback: int -> Map<string, Local> -> CExpr) : CExpr =
  let v = cx.v
  let defs = fieldsOf cx rname
  let given (f: FieldValue) =
    match List.tryFindIndex (fun (g, _) -> g = f.field) defs with
    | None -> fail $"record '{rname}' has no field '{f.field}'"
    | Some i ->
      let ft = substGen v targs (snd (List.item i defs))
      let ce = inferHint cx env depth ft f.value
      expect cx $"field '{f.field}'" ft ce.ty
      (f.field, ce, uniq cx "$f")
  let named = List.map given fields
  if List.length (List.distinct (List.map (fun (f, _, _) -> f) named)) <> List.length named then
    fail "a field is given twice"
  let scope = ref Map.empty
  let filled = Buffer.empty
  let temp (i: int) (fd: string * Ty) =
    let f = fst fd
    let (tmp, ty) =
      match List.tryFind (fun (g, _, _) -> g = f) named with
      | Some(_, ce, t) -> (t, ce.ty)
      | None ->
        let ce = fallback i scope.Value
        let t = uniq cx "$f"
        Buffer.push (t, ce) filled
        (t, ce.ty)
    scope.Value <- Map.add f (localOf tmp ty false 0) scope.Value
    mk (CLocal tmp) ty
  let temps = List.mapi temp defs
  let body = mk (CTuple temps) (TCon(rname, targs))
  let withFilled = List.fold (fun (acc: CExpr) (p: string * CExpr) -> mk (CLet(fst p, snd p, acc)) acc.ty) body (List.rev (Array.toList (Buffer.toArray filled)))
  let wrapNamed (acc: CExpr) (n: string * CExpr * string) =
    match n with
    | (_, ce, tmp) -> mk (CLet(tmp, ce, acc)) acc.ty
  List.fold wrapNamed withFilled (List.rev named)
