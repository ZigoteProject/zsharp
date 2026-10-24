/// Declarations (the F# compiler's Typer.declare and what it calls): functions and their groups,
/// generalized; types, members, aliases; traits, impls and derives; effects; C's boundary;
/// top-level values and constants; modules and opens; attributes. Each declaration is checked on
/// its own: a failure in one is its error, and the next goes on (declareOne).
open Types.Ty
open Types.Vars
open Types.Norm
open Types.Fail
open Core.Ir
open Syntax.Ast
open Diag.Diagnostic
open Cx

/// The warning kinds (0021's table): the names `[<NoWarn "…">]` takes.
let warningKinds : list<string> = [ "unused-value" ]

// a top-level function to define: its place (its first token), its full name, whether it may call
// itself, its parameters, result and body, and the type a trait gives it (an impl's method)
type private Item =
  { itemAt: int
    iname: string
    isRec: bool
    ips: list<Param>
    iret: option<SType>
    ibody: Expr
    expected: option<unit -> Ty / <Fails, Mismatched>> }

// a function of a group, before its body is checked
type private Ready =
  { rat: int
    rname: string
    rpars: list<string * string * Ty>
    rty: Ty
    fty: Ty
    rbody: Expr
    tvs: Map<string, Ty>
    row: Ty
    what: string }

// a function of a `let rec … and …` group: its declaration, its name, its parameters, result and
// body, the declaration that has it (inside a Private), and whether it's private
type private GroupFun =
  { recDecl: Decl
    recName: string
    recPs: list<Param>
    recRet: option<SType>
    recBody: Expr
    recNode: Decl
    recPrivate: bool }

let private item (at: int) (name: string) (isRec: bool) (ps: list<Param>) (ret: option<SType>) (body: Expr) : Item =
  { itemAt = at; iname = name; isRec = isRec; ips = ps; iret = ret; ibody = body; expected = None }

let private unitParam : Param = { param = plainPat PUnit; ann = None }

/// Type-checks functions that may refer to each other (registered first when isRec), then
/// generalizes each; with joint (let rec … and …), all of them together, so they share one
/// numbering of their type variables (a call between them uses the caller's instantiation).
let private defineGroupWith (cx: Cx) (joint: bool) (items: list<Item>) : list<Global * Map<string, Ty>> =
  let v = cx.v
  let prepare (it: Item) : Ready =
    let run () =
      cx.tyvars.Value <- Map.empty
      let (ps, body) = lowerParams cx it.ips it.ibody
      let pars = List.map (fun (x, ann) -> (x, uniq cx x, annot cx ann)) ps
      recordParams cx it.ips pars
      let (rty, declared) = annotRet cx it.iret
      // the body's effects (a function without parameters performs none)
      let row =
        if List.isEmpty pars then
          rowEmpty
        else
          match declared with
          | Some r -> r
          | None -> fresh v kRow
      let name = it.iname
      let what =
        match (declared, it.expected) with
        | _ when cx.exporting.Value -> $"'{name}', which C calls (the C-callback rule),"
        | (_, Some _) -> $"'{name}', a trait's method,"
        | (Some r, _) when isRowEmpty v r -> $"'{name}', declared to perform nothing,"
        | (Some r, _) -> $"'{name}', declared to perform {effectsText cx r},"
        | (None, _) when List.isEmpty pars -> $"'{name}', which takes no parameters,"
        | (None, _) -> ""
      let fty = funTyRow (List.map (fun (_, _, t) -> t) pars) rty row
      // an export's functions, and those it takes and gives, have no effects (the C-callback
      // rule): its rows are closed before its body is checked
      if cx.exporting.Value then
        let rec close (t: Ty) =
          match prune v t with
          | TFun(a, b, r) ->
            close a
            close b
            match prune v (snd (rowParts v r)) with
            | TVar i -> bind v i rowEmpty
            | _ -> ()
          | TCon(_, ts)
          | TTuple ts -> List.iter close ts
          | _ -> ()
        close fty
      match it.expected with
      | Some f -> expect cx $"'{name}' does not match the trait's signature" (f ()) fty
      | None -> ()
      if it.isRec then
        cx.globals.Value <- Map.add name { ty = fty; kinds = []; arity = List.length pars; defining = true } cx.globals.Value
      { rat = it.itemAt; rname = name; rpars = pars; rty = rty; fty = fty; rbody = body; tvs = cx.tyvars.Value; row = row; what = what }
    located cx it.itemAt true run
  let checkBody (p: Ready) : CExpr =
    let run () =
      cx.tyvars.Value <- p.tvs
      let env = List.fold (fun m (x, u, t) -> Map.add x ({ u = u; ty = t; mut = false; depth = 0 } : Local) m) Map.empty p.rpars
      cx.currentDef.Value <- p.rname
      let cb = withRowAs cx p.row p.what (fun () -> Exprs.inferHint cx env 0 p.rty p.rbody)
      cx.currentDef.Value <- ""
      expect cx $"result of '{p.rname}'" p.rty cb.ty
      cb
    located cx p.rat true run
  let prepared = List.map prepare items
  let bodies = List.map checkBody prepared
  let jointKinds = if joint then Some(generalize cx (TTuple(List.map (fun (p: Ready) -> p.fty) prepared))) else None
  let finish (p: Ready) (cb: CExpr) =
    if p.rname = "main" then
      resolve v p.fty |> ignore
      cx.mainAt.Value <- Some(spanOf cx p.rat true)
    let kinds =
      match jointKinds with
      | Some ks -> ks
      | None -> generalize cx p.fty
    let g = { ty = p.fty; kinds = kinds; arity = List.length p.rpars; defining = false }
    cx.globals.Value <- Map.add p.rname g cx.globals.Value
    let f : FunDef =
      { name = p.rname
        pars = List.map (fun (_, u, t) -> (u, t)) p.rpars
        ret = p.rty
        row = p.row
        body = cb
        ngen = List.length kinds
        rows = List.length (List.filter isRowKind kinds)
        file = cx.file.Value.source.path
        line = lineOf cx p.rat }
    Buffer.push f cx.funs
    (g, p.tvs)
  List.map2 finish prepared bodies

let private defineGroup (cx: Cx) (items: list<Item>) = defineGroupWith cx false items |> ignore

let private defineRecGroup (cx: Cx) (items: list<Item>) = defineGroupWith cx true items |> ignore

/// Members become functions `Type#Name`: self first (instance members), then parameters; an
/// optional parameter without a default is an option in the body.
let private declareMembers (cx: Cx) (tname: string) (tparams: list<string>) (ms: list<Member>) =
  if not (Map.containsKey tname cx.members.Value) then
    cx.members.Value <- Map.add tname [] cx.members.Value
    cx.memberTypeNames.Value <- Set.add (afterLastDot tname) cx.memberTypeNames.Value
  let fieldNames =
    match Map.tryFind tname cx.types.Value with
    | Some { def = RecordDef fs } -> List.map fst fs
    | _ -> []
  let one (m: Member) =
    let existing = Map.find tname cx.members.Value
    if List.exists (fun (n, _) -> n = m.memberName) existing then
      failLine m.mat $"'{tname}' already has a member '{m.memberName}'"
    if not m.isStatic && List.contains m.memberName fieldNames then
      failLine m.mat $"member '{m.memberName}' has the same name as a field of '{tname}'"
    let gname = tname + "#" + m.memberName
    let ps = Option.defaultValue [] m.mpars
    let mparam (p: MemberParam) : Param =
      let ann =
        match (p.optional, p.mdefault) with
        | (true, None) -> Some(STName("option", [ Option.defaultValue (STVar("$opt." + p.mname)) p.mty ]))
        | _ -> p.mty
      { param = plainPat (PIdent(p.mname, None)); ann = ann }
    let selfPar =
      match m.self with
      | Some s -> [ { param = plainPat (PIdent(s, None)); ann = Some(STName(tname, List.map STVar tparams)) } ]
      | None -> []
    let all = List.append selfPar (List.map mparam ps)
    let info = { gname = gname; isStatic = m.isStatic; isProperty = Option.isNone m.mpars; mpars = ps }
    // a new list: a module extending another's type writes the type's members anew
    cx.members.Value <- Map.add tname (List.append existing [ (m.memberName, info) ]) cx.members.Value
    item m.mat gname true (if List.isEmpty all then [ unitParam ] else all) m.mret m.mbody
  defineGroup cx (List.map one ms)

// ------------------------------------------------------------ C's boundary

/// Types that can cross the C boundary: numbers, bool, cstr, cptr, unit, [<CLayout>] records,
/// typed pointers to those (ptr<T>) and C function pointers (fnptr<A -> R>).
let rec private checkCType (cx: Cx) (what: string) (t: Ty) : unit / Fails =
  match prune cx.v t with
  | TCon(n, []) when Set.contains n nums || n = "bool" || n = "cstr" || n = "cptr" || n = "unit" -> ()
  | TCon(n, []) when Set.contains n cx.clayouts.Value -> ()
  | TCon("ptr", [ p ]) ->
    match prune cx.v p with
    | TCon("unit", []) -> ()
    | q -> checkCType cx what q
  | TCon("fnptr", [ f ]) -> checkFnPtr cx what f
  // C's T[N]
  | TCon("fixed", [ el; _ ]) when String.startsWith "[<CLayout>] field" what -> checkCType cx what el
  | TCon("fixed", _) ->
    fail $"{what}: a fixed-size array crosses to C in a [<CLayout>] record's field; C takes an array parameter as a pointer to its first element"
  | x -> fail $"{what}: type {show cx x} cannot cross the C boundary (mark records [<CLayout>])"

/// fnptr<A -> B -> R>: a C function pointer R (*)(A, B), its parameters and result C types (unit
/// -> R takes none).
and private checkFnPtr (cx: Cx) (what: string) (f: Ty) : unit / Fails =
  match prune cx.v f with
  | TFun(a, r, _) ->
    checkCType cx what a
    match prune cx.v r with
    | TFun _ -> checkFnPtr cx what r
    | x -> checkCType cx what x
  | x -> fail $"{what}: fnptr<{show cx x}> needs a function type such as fnptr<i32 -> i32>"

/// A Z# value C holds as an opaque handle (zs_handle, with zs_retain and zs_release): a
/// reference-counted object such as a union's cell, an array, a ref, a closure or a dyn value.
/// Strings cross as their bytes instead, and records and tuples are values.
let private isHandle (cx: Cx) (t: Ty) : bool =
  match prune cx.v t with
  | TCon("string", _)
  | TTuple _ -> false
  | TCon(n, _) when isRecord cx n -> false
  | x -> Types.Repr.needsRc cx.v cx.types.Value x

/// A parameter or result of an extern or an export: a C type, or a handle.
let private checkCArg (cx: Cx) (what: string) (t: Ty) : unit / Fails =
  match prune cx.v t with
  | TCon("span", _) -> fail $"{what}: a span can't come from C: it needs an owner"
  | _ -> if not (isHandle cx t) then checkCType cx what t

/// callback<A -> R>: C sees (R (*)(void* user, A), void* user); A and R are C types.
/// callback<share<A -> R>>: C may call it on any thread (a share<A -> R> is given).
let rec private checkCallback (cx: Cx) (what: string) (f: Ty) : unit / Fails =
  match prune cx.v f with
  | TCon("share", [ g ]) -> checkCallback cx what g
  | TFun(a, r, _) ->
    checkCType cx what a
    checkCType cx what r
  | x -> fail $"{what}: callback<{show cx x}> needs a function type such as callback<int -> unit>"

// ------------------------------------------------------------ impls and derives

/// Registers an impl and type-checks its methods. The impl is registered before its bodies so they
/// may use it recursively; its requirements on type arguments are inferred.
/// An impl registered, its methods' bodies not checked yet: impls declared together (a derive
/// over types that hold each other) may use one another. What finishImpl checks.
type private Started = { strait: string; shead: string; hvars: list<string>; items: list<Item> }

let private startImpl (cx: Cx) (tr0: string) (head: SType) (others: list<SType>) (defs: list<Definition>) : Started =
  let v = cx.v
  let tr = Option.defaultValue tr0 (resolveWith cx (fun q -> Set.contains q cx.traitNames.Value) tr0)
  let owned = List.filter (fun (tm: TraitMethod) -> tm.owner = tr) (List.map snd (Map.toList cx.traitMethods.Value))
  if List.isEmpty owned then
    fail $"unknown trait '{tr}'"
  let methods = Set.ofList (List.map (fun (tm: TraitMethod) -> tm.name) owned)
  let arity = (List.head owned).nparams
  let (hn, hargs) =
    match head with
    | STName(n0, args) ->
      let n1 =
        match typeAlias n0 with
        | Some c -> c
        | None -> n0
      // the type's full name, as annotations resolve it (Set in Collections: Collections.Set)
      let exists (q: string) = Set.contains q prims || Option.isSome (builtinCons q) || Map.containsKey q cx.types.Value
      (Option.defaultValue n1 (resolveWith cx exists n1), args)
    // a tuple of type variables: the impl for every tuple of that size (*2 for 'a * 'b)
    | STTuple ts -> (tupleHead (List.length ts), ts)
    | _ -> fail "an impl is for a named type or a tuple, such as Show<Point>, Show<list<'a>> or Binary<'a * 'b>"
  let hvar (st: SType) =
    match st with
    | STVar x -> x
    | _ -> fail "impl type arguments must be type variables: impl Show<list<'a>>"
  let hvars = List.map hvar hargs
  if List.length (List.distinct hvars) <> List.length hvars then
    fail "impl type variables must be distinct"
  if Map.containsKey (tr, hn) cx.impls.Value then
    fail $"{tr}<{hn}> is already implemented"
  if List.length others <> arity - 1 then
    fail $"{shortName tr} takes {arity} type parameters, and this impl gives {List.length others + 1}"
  // the other parameters are made of the head's variables: the head's type determines them
  let rec varsOf (st: SType) : list<string> =
    match st with
    | STVar x -> [ x ]
    | STName(_, args)
    | STTuple args -> List.collect varsOf args
    | STFun(a, b) -> List.append (varsOf a) (varsOf b)
    | _ -> []
  let other (o: SType) =
    match List.tryFind (fun x -> not (List.contains x hvars)) (varsOf o) with
    | Some x ->
      let theirs = if List.isEmpty hvars then "it has none" else String.join ", " (List.map (fun h -> "'" + h) hvars)
      fail $"impl {shortName tr}: '{x} isn't a type variable of {shortName hn}; the other parameters are made of the head's ({theirs}), such as 'a * int or list<'a>"
    | None -> toTy cx (Some hvars) o
  cx.implOthers.Value <- Map.add (tr, hn) (List.map other others) cx.implOthers.Value
  let given = List.map (fun (d: Definition) -> d.dname) defs
  for m in Set.toList methods do
    if not (List.contains m given) then
      fail $"impl {tr}<{hn}> is missing '{m}'"
  for m in given do
    if not (Set.contains m methods) then
      fail $"trait {tr} has no method '{m}'"
  // registered before the bodies, so they may use the impl recursively
  let fname (m: string) = $"{tr}<{hn}>#{m}"
  cx.impls.Value <- Map.add (tr, hn) (Map.ofList (List.map (fun m -> (m, fname m)) given)) cx.impls.Value
  cx.implRequires.Value <- Map.add (tr, hn) (List.map (fun _ -> Set.empty) hvars) cx.implRequires.Value
  let methodItem (d: Definition) : Item =
    let tm = Map.find (tr + "." + d.dname) cx.traitMethods.Value
    let expected () =
      let h = toTy cx None head
      let t = substGen v (List.concat [ [ h ]; List.map (toTy cx None) others; [ fresh v kRow ] ]) tm.ty
      if tm.isConst then tfun tUnit t else t
    let ps = if List.isEmpty d.dpars then [ unitParam ] else d.dpars
    { itemAt = d.defAt; iname = fname d.dname; isRec = true; ips = ps; iret = d.dret; ibody = d.dbody; expected = Some expected }
  { strait = tr; shead = hn; hvars = hvars; items = List.map methodItem defs }

// an impl's methods checked, and what it needs from each type argument
let private finishImpl (cx: Cx) (st: Started) =
  let v = cx.v
  let tr = st.strait
  let hn = st.shead
  let hvars = st.hvars
  let results = defineGroupWith cx false st.items
  // what the impl needs from each type argument: the union over its methods
  let needs (x: string) =
    let fromResult (r: Global * Map<string, Ty>) =
      let (g, tvs) = r
      match Map.tryFind x tvs with
      | Some t ->
        match prune v t with
        | TGen i -> Set.toList (List.item i g.kinds).traits
        | _ -> []
      | None -> []
    Set.ofList (List.collect fromResult results)
  cx.implRequires.Value <- Map.add (tr, hn) (List.map needs hvars) cx.implRequires.Value

let private declareImpl (cx: Cx) (tr0: string) (head: SType) (others: list<SType>) (defs: list<Definition>) = finishImpl cx (startImpl cx tr0 head others defs)

// a type's shape, as a derive sees it
let private shapeOf (cx: Cx) (tname: string) : Derive.ShapeInfo =
  match (Map.find tname cx.types.Value).def with
  | RecordDef fs ->
    let defaults =
      match Map.tryFind tname cx.recordDefaults.Value with
      | Some ds when List.length ds = List.length fs -> ds
      | _ -> List.map (fun _ -> None) fs
    Derive.RecordShape(List.zip (List.map fst fs) defaults)
  | UnionDef cs ->
    let names (c: string) (fts: list<Ty>) =
      let given =
        match Map.tryFind c cx.ctorFieldNames.Value with
        | Some ns -> ns
        | None -> List.map (fun _ -> None) fts
      List.mapi (fun j (n: option<string>) -> Option.defaultValue $"item{j + 1}" n) given
    Derive.UnionShape(List.map (fun (c, fts) -> (c, names c fts)) cs)

// runs f, a failure in it said to be in the context first
let private explained (context: string) (f: unit -> 'r / <Fails | 'e>) : 'r / <Fails | 'e> =
  handle f () with
  | Fails.fail x, _ -> Fails.fail { x with message = context + ": " + x.message }
  | Fails.report x, k -> k (Fails.report { x with message = context + ": " + x.message })

/// Implements trait `tr` for the types `tnames` (declared together, so they may hold each other)
/// by expanding `derive tr` for each: every impl is registered before any body is checked. An
/// error in one says so first (context of the type: "Derive(Json) on Callback").
let private deriveImpls (cx: Cx) (context: string -> string) (tr: string) (tnames: list<string>) =
  if not (Map.containsKey tr cx.derives.Value) then
    fail $"no derive named '{tr}'"
  // hygiene: a trait method named in a derive (show, compare, hash…) means the trait's, as the
  // derive's module sees it, even where the program defines a function of the same name
  // ponytail: a local in a derive body named like a trait method would be rewritten too
  let home = Map.find tr cx.deriveModules.Value
  let methodOf (x: string) : option<string> =
    if String.contains "." x then
      None
    else
      let inHome =
        match home with
        | Some m -> m + "." + x
        | None -> x
      match List.tryFind (fun a -> Map.containsKey a cx.traitAliases.Value) [ inHome; x ] with
      | Some a -> Some(Map.find a cx.traitAliases.Value)
      | None -> None
  let rec hygienic (e: Expr) : Expr =
    match e.e with
    | Var x ->
      match methodOf x with
      | Some m -> { e with e = Var m }
      | None -> e
    | Call(x, args) ->
      match methodOf x with
      | Some m -> { e with e = Call(m, List.map hygienic args) }
      | None -> mapExpr hygienic e
    | _ -> mapExpr hygienic e
  // may run in the middle of another function
  let saved = cx.tyvars.Value
  let start (tname: string) : Started =
    let npars = (Map.find tname cx.types.Value).npars
    let head = STName(tname, List.init npars (fun i -> STVar $"t{i}"))
    let defs = List.map (fun (d: Definition) -> { d with dbody = hygienic d.dbody }) (Derive.expand tname head (shapeOf cx tname) (Map.find tr cx.derives.Value))
    explained (context tname) (fun () -> startImpl cx tr head [] defs)
  let started = List.map (fun (n: string) -> (n, start n)) tnames
  for (tname, st) in started do
    explained (context tname) (fun () -> finishImpl cx st)
  cx.tyvars.Value <- saved

/// Implements trait `tr` for type `tname` by expanding `derive tr`; an error in it says so first
/// (context: "Derive(Json) on Callback").
let private deriveImpl (cx: Cx) (context: string) (tr: string) (tname: string) = deriveImpls cx (fun _ -> context) tr [ tname ]

/// Eq, Ord, Hash and Show come from the prelude's derives, the first time they're needed: a type's
/// automatic impl, unless it has its own or opts out.
let autoDerive (cx: Cx) (tr: string) (n: string) : bool / <Fails, Mismatched> =
  let derivable =
    match Map.tryFind n cx.types.Value with
    | Some { def = RecordDef _ } -> true
    | Some { def = UnionDef cs } -> not (List.isEmpty cs)
    | _ -> false
  let wanted = List.contains tr [ "Eq"; "Ord"; "Hash"; "Show"; "Diff" ] && Map.containsKey tr cx.derives.Value
  let ok = wanted && not (Set.contains (tr, n) cx.manualImpls.Value || Set.contains (tr, n) cx.optOut.Value) && derivable
  if ok then
    cx.autoDerived.Value <- Set.add (tr, n) cx.autoDerived.Value
    deriveImpl cx $"automatic {tr} for {n}" tr n
  ok

// ------------------------------------------------------------ constants

/// A constant expression: literals, operators, conditionals, tuples, records, constructors and
/// number conversions over constants. Its uses are the expression itself. Arrays, lists and calls
/// make a top-level value computed once at startup instead.
let rec private isConstant (cx: Cx) (e: Expr) : bool =
  let conversion (f: string) = Set.contains f nums || List.contains f [ "float"; "c_int"; "double" ]
  match e.e with
  | Lit _
  | FloatLit _
  | StrLit _
  | CharLit _
  | BoolLit _
  | UnitLit -> true
  | At a
  | AtLine a
  | Neg a
  | Not a
  | Measured(a, _)
  | Typed(a, _) -> isConstant cx a
  | Var x ->
    // a case without fields, [] too (a static cell; a list of elements allocates, so it's a value
    // computed at startup)
    match Exprs.resolveName cx x with
    | Some q -> Map.containsKey q cx.consts.Value || Map.containsKey q cx.ctors.Value
    | None -> false
  | Bin(_, a, b) -> isConstant cx a && isConstant cx b
  | If(c, t, Some f) -> isConstant cx c && isConstant cx t && isConstant cx f
  | Tuple xs -> List.forall (isConstant cx) xs
  // an empty array (HashMap.empty's buckets)
  | ArrayLit [] -> true
  | RecordLit fs -> List.forall (fun (f: FieldValue) -> isConstant cx f.value) fs
  | Call(f, args) ->
    let isCtorCall =
      match Exprs.resolveName cx f with
      | Some q -> Map.containsKey q cx.ctors.Value && q <> "::"
      | None -> false
    // a Buffer of constants: a constant's uses are its expression, so each use is a new Buffer
    // (Buffer.empty)
    let freshBuffer = Exprs.resolveName cx f = Some "Collections.Buffer.ofArray"
    // whether the build is for Windows: the code generator's constant (Path's separator)
    let perTarget = Exprs.resolveName cx f = Some "Native.isWindows"
    (isCtorCall || conversion f || freshBuffer || perTarget) && List.forall (isConstant cx) args
  | _ -> false

/// A written type with its names resolved where it is written (a constant's annotation).
let rec private qualifyType (cx: Cx) (st: SType) : SType =
  match st with
  | STName("dyn", [ STName(tr, []) ]) -> STName("dyn", [ STName(Option.defaultValue tr (resolveWith cx (fun q -> Set.contains q cx.traitNames.Value) tr), []) ])
  | STName(n, args) ->
    let resolved =
      match resolveWith cx (fun q -> Map.containsKey q cx.aliases.Value) n with
      | Some q when not (Map.containsKey q cx.types.Value) -> q
      | _ ->
        let c =
          match typeAlias n with
          | Some a -> a
          | None -> n
        let exists (q: string) = Set.contains q prims || Option.isSome (builtinCons q) || Map.containsKey q cx.types.Value
        Option.defaultValue n (resolveWith cx exists c)
    STName(resolved, List.map (qualifyType cx) args)
  | STTuple ts -> STTuple(List.map (qualifyType cx) ts)
  | STFun(a, b) -> STFun(qualifyType cx a, qualifyType cx b)
  | STRow(t, ls, tail) -> STRow(qualifyType cx t, List.map (qualifyType cx) ls, tail)
  | _ -> st

/// The expression with every name resolved where it is written (for inlining elsewhere).
let rec private qualifyNames (cx: Cx) (e: Expr) : Expr =
  match e.e with
  | Typed(a, t) -> { e with e = Typed(qualifyNames cx a, qualifyType cx t) }
  | Var x ->
    match Exprs.resolveName cx x with
    | Some q -> { e with e = Var q }
    | None -> e
  | Call(f, args) -> { e with e = Call(Option.defaultValue f (Exprs.resolveName cx f), List.map (qualifyNames cx) args) }
  | _ -> mapExpr (qualifyNames cx) e

// ------------------------------------------------------------ declarations

// the name of a function declaration
let private funName (d: Decl) : option<string> =
  match d.d with
  | Fun(n, _, _, _, _) -> Some n
  | _ -> None

// the name and type parameters of a record's declaration
let private recordDeclOf (d: Decl) : option<string * list<string>> =
  match d.d with
  | TypeDecl(n, tps, RecordTy _, _) -> Some(n, tps)
  | _ -> None

// the name of a top-level value's declaration
let private valueName (d: Decl) : option<string> =
  match d.d with
  | Value(n, _, _) -> Some n
  | _ -> None

let rec private declaredNames (d: Decl) : list<string> =
  match d.d with
  | Value(n, _, _)
  | Fun(n, _, _, _, _)
  | TypeDecl(n, _, _, _)
  | TypeAlias(n, _, _) -> [ n ]
  | FunGroup items
  | TypeGroup items -> List.collect declaredNames items
  | Attrs(_, x)
  | Private x -> declaredNames x
  | _ -> []

// the trait methods called through dyn with an ambient row (0025): their arguments must perform
// nothing, checked once the value's type is known
let private closeDynCalls (cx: Cx) =
  let v = cx.v
  let calls = Array.toList (Buffer.toArray cx.dynCalls)
  Buffer.clear cx.dynCalls
  for (t, row, tr, m, tok) in calls do
    match prune v t with
    | TCon(d, []) when String.startsWith "dyn:" d ->
      if not (unifies cx rowEmpty row) then
        let performs = String.join ", " (List.map (show cx) (fst (rowParts v row)))
        failLine tok $"this performs {performs}, but {m} is called through dyn {shortName tr}, where its arguments must perform nothing: call it on the value's own type, or handle it inside"
    | _ -> ()

// the values the declaration's statements dropped, now their types are settled (unused-value)
let private warnDiscarded (cx: Cx) =
  let v = cx.v
  for (t, at) in Array.toList (Buffer.toArray cx.discarded) do
    let shown =
      match prune v t with
      | TCon("unit", [])
      | TGen _ -> None
      | TVar r ->
        // a literal's type not settled: int if it can be, else its float
        match (kindOf v r).allowed with
        | None -> None
        | Some ts when Set.contains "int" ts -> Some "int"
        | Some ts when Set.contains "f64" ts -> Some "f64"
        | Some _ -> Some "a number"
      | x -> Some(show cx x)
    match shown with
    | Some s -> warnAt cx "unused-value" at $"this statement's value ({s}) is discarded: use it, or pipe it to ignore"
    | None -> ()
  Buffer.clear cx.discarded

/// An error found, unless it mentions a declaration that already failed (it's that one's
/// consequence).
let private report (cx: Cx) (dg: Diagnostic) =
  if not (List.exists (fun n -> String.contains ("'" + n + "'") dg.message) (Set.toList cx.failed.Value)) then
    Buffer.push dg cx.diagnostics

let rec private declare (cx: Cx) (d: Decl) : unit / <Fails, Mismatched> =
  let v = cx.v
  // what the attribute cases ask of their attributes (a guard performs nothing)
  let (noWarn, codeAttrs) =
    match d.d with
    | Attrs(attrs, inner) ->
      let code = Option.isSome (funName inner) && List.forall (fun (a, _) -> List.contains a [ "Wrapping"; "FastMath"; "Target"; "Multiversion" ]) attrs
      (List.exists (fun (a, _) -> a = "NoWarn") attrs, code)
    | _ -> (false, false)
  match d.d with
  | TypeDecl(name0, tps, body, ms) ->
    let name = qualify cx name0
    recordKey cx d.named name0 (TCon(name, [])) false ("type:" + name) true
    let defined = Map.containsKey name cx.types.Value
    let wasAhead = Set.contains name cx.ahead.Value
    if defined && wasAhead then
      cx.ahead.Value <- Set.remove name cx.ahead.Value
    if Set.contains name prims || Option.isSome (builtinCons name) || (defined && not wasAhead) then
      fail $"type '{name}' is already defined"
    // registered first so the body can refer to the type itself
    cx.types.Value <- Map.add name { npars = List.length tps; def = UnionDef [] } cx.types.Value
    let tt (st: SType) = toTy cx (Some tps) st
    match body with
    | RecordTy fields ->
      let fs = List.map (fun (f: RecordField) -> (f.name, tt f.ty)) fields
      let rec contains (t: Ty) =
        match t with
        | TCon(n, args) -> n = name || List.exists contains args
        | TTuple ts -> List.exists contains ts
        | _ -> false
      if List.exists (fun (_, t) -> contains t) fs then
        fail $"record '{name}' cannot contain itself; use a union"
      if List.length (List.distinct (List.map fst fs)) <> List.length fs then
        fail "duplicate field name"
      cx.types.Value <- Map.add name { npars = List.length tps; def = RecordDef fs } cx.types.Value
      Buffer.push name cx.records
      fieldUses cx name (List.map (fun (f: RecordField) -> (f.name, f.fieldAt)) fields) true
      cx.recordDefaults.Value <- Map.add name (List.map (fun (f: RecordField) -> f.default) fields) cx.recordDefaults.Value
    | UnionTy cases ->
      let caseOf (c: Case) = (qualify cx c.case, List.map (fun (_, st) -> tt st) c.fields)
      cx.types.Value <- Map.add name { npars = List.length tps; def = UnionDef(List.map caseOf cases) } cx.types.Value
      let register (i: int) (c: Case) =
        let q = qualify cx c.case
        if Map.containsKey q cx.ctors.Value then
          fail $"constructor '{q}' is already defined"
        cx.ctors.Value <- Map.add q (name, i) cx.ctors.Value
        cx.ctorFieldNames.Value <- Map.add q (List.map fst c.fields) cx.ctorFieldNames.Value
      List.iteri register cases
    declareMembers cx name tps ms
  | Extern(name, args, variadic, ret) ->
    if Map.containsKey name cx.externs.Value || Map.containsKey name cx.globals.Value then
      fail $"'{name}' is already defined"
    let what = $"extern '{name}'"
    let cty (isParam: bool) (st: SType) =
      let t = toTy cx (Some []) st
      match t with
      | TCon("callback", [ f ]) when isParam -> checkCallback cx what f
      // a pointer and a length
      | TCon("span", [ el ]) when isParam -> checkCType cx what el
      | _ -> checkCArg cx what t
      t
    let pars = List.map (cty true) args
    let r = cty false ret
    cx.externs.Value <- Map.add name { pars = pars; ret = r; variadic = variadic } cx.externs.Value
  | Fun(name0, isRec, ps, ret, body) when String.startsWith "|" name0 ->
    // active pattern: cases become constructors of a hidden union (total) or option (partial)
    let names = List.filter (fun s -> s <> "") (String.split "|" name0)
    let fn = qualify cx name0
    let partial = List.last names = "_"
    let before = List.length ps - 1
    if partial then
      if List.length names <> 2 then
        fail "a partial active pattern has one case: (|Name|_|)"
      cx.activePatterns.Value <- Map.add (qualify cx (List.head names)) (fn, false, before) cx.activePatterns.Value
    else
      let u = qualify cx ("$AP" + name0)
      let cases = List.mapi (fun i c -> (qualify cx c, [ TGen i ])) names
      cx.types.Value <- Map.add u { npars = List.length names; def = UnionDef cases } cx.types.Value
      let register (i: int) (c: string) =
        let qc = qualify cx c
        if Map.containsKey qc cx.ctors.Value then
          fail $"constructor '{c}' is already defined"
        cx.ctors.Value <- Map.add qc (u, i) cx.ctors.Value
        cx.ctorFieldNames.Value <- Map.add qc [ None ] cx.ctorFieldNames.Value
        cx.apCtors.Value <- Set.add qc cx.apCtors.Value
        cx.activePatterns.Value <- Map.add qc (fn, true, before) cx.activePatterns.Value
      List.iteri register names
    defineGroup cx [ item d.dat fn isRec ps ret body ]
  | Fun(name0, isRec, ps, ret, body) ->
    let name = qualify cx name0
    if Map.containsKey name cx.globals.Value || Map.containsKey name cx.externs.Value then
      fail $"'{name}' is already defined"
    let run () = defineGroup cx [ item d.dat name isRec ps ret body ]
    handle run () with
    | Fails.fail x, _ ->
      // keep later declarations from seeing a half-defined function
      cx.globals.Value <- Map.remove name cx.globals.Value
      Fails.fail x
    | Fails.report x, k -> k (Fails.report x)
    let g = Map.find name cx.globals.Value
    recordKey cx d.named name g.ty false name true
    // its effects in words (0025), with the parameters' names
    let paramName (p: Param) =
      match p.param.pat with
      | PIdent(x, None) when startsLower x -> x
      | _ -> "the argument"
    let names = List.map paramName ps
    let hv = cx.hovers
    if Buffer.length hv > 0 && hv.[Buffer.length hv - 1].name = name then
      let last = hv.[Buffer.length hv - 1]
      hv.[Buffer.length hv - 1] <- { last with decl = true; explain = Types.Show.explain v names g.ty }
    // a generic function's hover shows what its type variables need
    let need (i: int) (k: Kind) =
      let one (tr: string) =
        match Map.tryFind tr k.params with
        | Some ps2 -> $"{show cx (TGen i)} : {tr}<{String.join ", " (List.map (show cx) ps2)}>"
        | None -> $"{show cx (TGen i)} : {tr}"
      List.map one (Set.toList k.traits)
    let needs = List.concat (List.mapi need g.kinds)
    if not (List.isEmpty needs) && Buffer.length hv > 0 && hv.[Buffer.length hv - 1].name = name then
      let last = hv.[Buffer.length hv - 1]
      hv.[Buffer.length hv - 1] <- { last with constraints = String.join ", " needs }
  | Effect(name0, tps, ops) ->
    // effect E<'a> = abstract op : T -> R: performed as E.op, given meaning by a handle
    let name = qualify cx name0
    if Map.containsKey name cx.effects.Value then
      fail $"effect '{name}' is already defined"
    let rec varsOf (st: SType) : list<string> =
      match st with
      | STVar x -> [ x ]
      | STName(_, args)
      | STTuple args -> List.collect varsOf args
      | STFun(a, b) -> List.append (varsOf a) (varsOf b)
      | STRow(t, ls, tail) -> List.concat [ varsOf t; List.collect varsOf ls; Option.toList tail ]
      | STMeasure _ -> []
    let tpsShown = String.join ", " (List.map (fun x -> "'" + x) tps)
    let info (op: string * int * SType) : EffectOp =
      let (opName, _, st) = op
      // the operation's own type variables (throw's 'a) after the effect's
      let own = List.filter (fun x -> not (List.contains x tps)) (List.distinct (varsOf st))
      let t = toTy cx (Some(List.append tps own)) st
      let rec split (x: Ty) : list<Ty> * Ty =
        match x with
        | TFun(a, r, _) ->
          let (ps, res) = split r
          (a :: ps, res)
        | r -> ([], r)
      let (pars, ret) = split t
      if List.isEmpty pars then
        fail $"operation '{opName}' must be a function type: abstract {opName} : unit -> {show cx t} for one that takes nothing"
      let rec mentionsOwn (x: Ty) =
        match x with
        | TGen i -> i >= List.length tps
        | TCon(_, ts)
        | TTuple ts -> List.exists mentionsOwn ts
        | TFun(a, b, r) -> mentionsOwn a || mentionsOwn b || mentionsOwn r
        | _ -> false
      if List.exists mentionsOwn pars then
        fail $"operation '{opName}' has a type variable of its own in a parameter; an operation's own variables are for its result only (abstract throw : 'e -> 'a), the others are the effect's (effect {name}<{tpsShown}>)"
      { name = opName; pars = pars; ret = ret; own = List.length own }
    let infos = List.map info ops
    match List.tryFind (fun (o: EffectOp) -> List.length (List.filter (fun (p: EffectOp) -> p.name = o.name) infos) > 1) infos with
    | Some o -> fail $"effect '{name}' declares '{o.name}' twice"
    | None -> ()
    cx.effects.Value <- Map.add name { npars = List.length tps; ops = infos } cx.effects.Value
    let opRef (i: int) (o: EffectOp) =
      let q = name + "." + o.name
      cx.effectOps.Value <- Map.add q (name, i) cx.effectOps.Value
      // hover and definition: the operation as it's performed
      let label = TCon(name, List.init (List.length tps) TGen)
      let (_, opAt, _) = List.item i ops
      recordKey cx opAt o.name (funTyRow o.pars o.ret (rowExt label rowEmpty)) false q true
    List.iteri opRef infos
  | Trait(name0, tps, methods) ->
    let name = qualify cx name0
    if Set.contains name cx.traitNames.Value then
      fail $"trait '{name}' is already defined"
    cx.traitNames.Value <- Set.add name cx.traitNames.Value
    for (m, st) in methods do
      let t = methodType cx tps st
      let isConst =
        match t with
        | TFun _ -> false
        | _ -> true
      let qname = name + "." + m
      let tm : TraitMethod = { owner = name; name = m; ty = t; nparams = List.length tps; isConst = isConst }
      cx.traitMethods.Value <- Map.add qname tm cx.traitMethods.Value
      cx.traitAliases.Value <- Map.add qname qname cx.traitAliases.Value
      // the method by its own name in the trait's module, except for the operator traits (whose
      // methods are the operators)
      if not (List.contains name [ "Add"; "Num"; "Eq" ]) && not (Map.containsKey (qualify cx m) cx.traitAliases.Value) then
        cx.traitAliases.Value <- Map.add (qualify cx m) qname cx.traitAliases.Value
    if name = "Show" then
      cx.traitAliases.Value <- Map.add "string" "Show.show" cx.traitAliases.Value
  | Impl(tr, head, others, defs) -> declareImpl cx tr head others defs
  | Derive(name0, defs) ->
    cx.derives.Value <- Map.add (qualify cx name0) defs cx.derives.Value
    cx.deriveModules.Value <- Map.add (qualify cx name0) cx.currentModule.Value cx.deriveModules.Value
  | DeriveGroup(name0, members) ->
    let full (m: string) =
      match resolveWith cx (fun q -> Map.containsKey q cx.derives.Value || Map.containsKey q cx.deriveGroups.Value) m with
      | Some q -> q
      | None -> fail $"no derive named '{m}'"
    let fulls = List.map full members
    cx.deriveGroups.Value <- Map.add (qualify cx name0) fulls cx.deriveGroups.Value
  | Private inner ->
    declare cx inner
    let own (n: string) = cx.privates.Value <- Map.add (qualify cx n) cx.currentModule.Value cx.privates.Value
    match inner.d with
    | Fun(n, _, _, _, _)
    | Value(n, _, _) -> own n
    | TypeDecl(n, _, body, _) ->
      own n
      match body with
      | UnionTy cases ->
        for c in cases do
          own c.case
      | RecordTy _ -> ()
    | _ -> fail "'private' applies to 'let' and 'type' declarations"
  | Const(name, value0) -> cx.consts.Value <- Map.add name value0 cx.consts.Value
  | TypeGroup items ->
    // type A = … and B = …: the names first, so each body may name the others
    let named (it: Decl) =
      match it.d with
      | TypeDecl(n, tps, _, _) -> (it, qualify cx n, List.length tps)
      | Private { d = TypeDecl(n, tps, _, _) } -> (it, qualify cx n, List.length tps)
      | _ -> failLine it.dat "'and' joins records and unions"
    let names = List.map named items
    for (it, n, npars) in names do
      if Set.contains n prims || Option.isSome (builtinCons n) || Map.containsKey n cx.types.Value then
        failLine it.dat $"type '{n}' is already defined"
      cx.types.Value <- Map.add n { npars = npars; def = UnionDef [] } cx.types.Value
      cx.ahead.Value <- Set.add n cx.ahead.Value
    for it in items do
      located cx it.dat true (fun () -> declare cx it)
    // a record holds its fields: one of the group reaching itself through records and tuples
    // would be of no size
    let rec reaches (target: string) (seen: Set<string>) (t: Ty) : bool =
      match prune v t with
      | TTuple ts -> List.exists (reaches target seen) ts
      | TCon(n, _) when n = target -> true
      | TCon(n, args) when not (Set.contains n seen) ->
        match Map.tryFind n cx.types.Value with
        | Some { def = RecordDef fs } -> List.exists (fun (_, ft) -> reaches target (Set.add n seen) (substGen v args ft)) fs
        | _ -> false
      | _ -> false
    for (it, n, _) in names do
      match (Map.find n cx.types.Value).def with
      | RecordDef fs ->
        if List.exists (fun (_, ft) -> reaches n Set.empty ft) fs then
          failLine it.dat $"record '{shortName n}' contains itself through another record; make one of them a union"
      | _ -> ()
  | FunGroup items ->
    // let rec f … and g …: checked together, so each may call the others
    let groupFun (it: Decl) : GroupFun =
      match it.d with
      | Fun(n, _, ps, ret, body) -> { recDecl = it; recName = n; recPs = ps; recRet = ret; recBody = body; recNode = it; recPrivate = false }
      | Private inner ->
        match inner.d with
        | Fun(n, _, ps, ret, body) -> { recDecl = it; recName = n; recPs = ps; recRet = ret; recBody = body; recNode = inner; recPrivate = true }
        | _ -> failLine it.dat "'and' joins functions"
      | _ -> failLine it.dat "'and' joins functions"
    let defs = List.map groupFun items
    for m in defs do
      let q = qualify cx m.recName
      if Map.containsKey q cx.globals.Value || Map.containsKey q cx.externs.Value || Map.containsKey q cx.consts.Value || Map.containsKey q cx.globalValues.Value then
        fail $"'{m.recName}' is already defined"
    let run () = defineRecGroup cx (List.map (fun (m: GroupFun) -> item m.recDecl.dat (qualify cx m.recName) true m.recPs m.recRet m.recBody) defs)
    handle run () with
    | Fails.fail x, _ ->
      for m in defs do
        cx.globals.Value <- Map.remove (qualify cx m.recName) cx.globals.Value
      Fails.fail x
    | Fails.report x, k -> k (Fails.report x)
    for m in defs do
      let q = qualify cx m.recName
      recordKey cx m.recNode.named m.recName (Map.find q cx.globals.Value).ty false q true
      if m.recPrivate then
        cx.privates.Value <- Map.add q cx.currentModule.Value cx.privates.Value
  | Value(name0, ann, e) ->
    let q = qualify cx name0
    if Map.containsKey q cx.globals.Value || Map.containsKey q cx.externs.Value || Map.containsKey q cx.consts.Value || Map.containsKey q cx.globalValues.Value then
      fail $"'{name0}' is already defined"
    let body =
      match ann with
      | Some t -> plain (Typed(e, t))
      | None -> e
    cx.tyvars.Value <- Map.empty
    if isConstant cx body then
      // checked here, so errors point at the definition; then inlined at each use, with its names
      // resolved here (a local at the use site can't capture them)
      let qbody = qualifyNames cx body
      let outer = cx.inConst.Value
      cx.inConst.Value <- q
      let c = Exprs.infer cx Map.empty 0 qbody
      cx.inConst.Value <- outer
      cx.consts.Value <- Map.add q qbody cx.consts.Value
      recordKey cx d.named name0 c.ty false q true
    else
      // computed once at startup, in module order; it has one type, so literals settle now
      let what = "a top-level value's initializer (it runs at startup, where no handler is)"
      let c = withRowAs cx rowEmpty what (fun () -> Exprs.infer cx Map.empty 0 body)
      let rec generic (t: Ty) : bool =
        match prune v t with
        | TVar r -> Option.isNone (kindOf v r).allowed
        | TCon(_, ts)
        | TTuple ts -> List.exists generic ts
        | TFun(a, b, _) -> generic a || generic b
        | _ -> false
      if generic c.ty then
        fail $"a top-level value of type {show cx (schemed cx c.ty)} must be a constant to be generic; make it a function, or give it a type"
      resolve v c.ty |> ignore
      let init = "$init." + q
      let f : FunDef =
        { name = init
          pars = []
          ret = c.ty
          row = rowEmpty
          body = c
          ngen = 0
          rows = 0
          file = cx.file.Value.source.path
          line = lineOf cx d.dat }
      Buffer.push f cx.funs
      cx.globalValues.Value <- Map.add q c.ty cx.globalValues.Value
      Buffer.push (q, init) cx.valueList
      recordKey cx d.named name0 c.ty false q true
  | Open m ->
    // a module, or one nested in the current module or a module enclosing it
    match resolveWith cx (fun q -> Set.contains q cx.moduleNames.Value) m with
    | Some full ->
      cx.opens.Value <- full :: cx.opens.Value
      cx.resolved.Value <- Map.empty
    | None -> fail $"unknown module '{m}'"
  | ModuleHeader _ -> ()
  | NestedModule(name0, _) ->
    // module Inner = …: its names are Outer.Inner.x (declareOne goes on to its declarations)
    let full = qualify cx name0
    // a program's module may share a name with a library namespace (Text); the names in both are
    // still distinct
    if Set.contains full cx.nestedModules.Value then
      fail $"module '{full}' is already defined"
    cx.nestedModules.Value <- Set.add full cx.nestedModules.Value
    cx.moduleNames.Value <- Set.add full cx.moduleNames.Value
    if Option.isNone cx.currentModule.Value then
      cx.mainNested.Value <- Set.add full cx.mainNested.Value
  | Attrs(attrs, inner) when noWarn ->
    // [<NoWarn "unused-value">]: the declaration's warnings of those kinds aren't reported (0021)
    let kinds = List.collect snd (List.filter (fun (a, _) -> a = "NoWarn") attrs)
    if List.isEmpty kinds then
      fail "[<NoWarn>] takes the warning's name: [<NoWarn \"unused-value\">]"
    for k in kinds do
      if not (List.contains k warningKinds) then
        fail $"unknown warning '{k}' (the kinds are {String.join ", " warningKinds})"
    let rest = List.filter (fun (a, _) -> a <> "NoWarn") attrs
    let outer = cx.silenced.Value
    cx.silenced.Value <- Set.union outer (Set.ofList kinds)
    declare cx (if List.isEmpty rest then inner else { d with d = Attrs(rest, inner) })
    cx.silenced.Value <- outer
  | Attrs([ ("Measure", []) ], { d = TypeDecl(name, [], UnionTy [], []) }) -> cx.measures.Value <- Set.add name cx.measures.Value
  | Attrs([ ("Export", cnames) ], inner) when Option.isSome (funName inner) ->
    cx.exporting.Value <- true
    declare cx inner
    cx.exporting.Value <- false
    let name = Option.get (funName inner)
    let q = qualify cx name
    let g = Map.find q cx.globals.Value
    if not (List.isEmpty g.kinds) then
      fail $"exported function '{name}' must not be generic; add type annotations"
    // C calls it, and no handler is in C (the C-callback rule)
    if g.arity > 0 then
      let rec rowOfArrow (k: int) (t: Ty) : Ty =
        match prune v t with
        | TFun(_, r, row) -> if k = 1 then row else rowOfArrow (k - 1) r
        | _ -> rowEmpty
      let row = rowOfArrow g.arity g.ty
      if not (isRowEmpty v row) then
        fail $"a function given to C must have no effects: '{name}' performs {effectsText cx row} (the C-callback rule)"
    let cname =
      match cnames with
      | [ c ] -> c
      | _ -> name
    let (ptys, ret) = peel cx g.arity g.ty
    let what = $"export '{cname}'"
    for t in ptys do
      checkCArg cx what t
    checkCArg cx what ret
    let ex : Export = { cname = cname; fname = q; pars = List.filter (fun t -> prune v t <> tUnit) ptys; ret = resolve v ret }
    Buffer.push ex cx.exports
  | Attrs(attrs, inner) when codeAttrs ->
    // [<Wrapping>]: integer + - * in the function, its lambdas included, wrap around instead of
    // panicking on overflow (hashes, checksums). [<FastMath>]: float + - * / may be reassociated
    // (so a reduction vectorizes) and assume no NaNs or infinities
    let has (a: string) = List.exists (fun (b, _) -> b = a) attrs
    cx.wrapping.Value <- has "Wrapping"
    cx.fastMath.Value <- has "FastMath"
    declare cx inner
    cx.wrapping.Value <- false
    cx.fastMath.Value <- false
    let name = qualify cx (Option.get (funName inner))
    // [<Target "avx2,fma">]: compiled for those CPU features; [<Multiversion("avx2", "sse4.2")>]: a
    // version for each, and one for the baseline, chosen at startup
    let features (args: list<string>) =
      if List.exists (fun (f: string) -> f = "" || String.contains " " f) args then
        fail "CPU features are names such as \"avx2\", or several separated by commas: \"avx2,fma\""
      args
    let argsOf (a: string) = snd (List.find (fun (b, _) -> b = a) attrs)
    match (has "Target", has "Multiversion") with
    | (true, true) -> fail "a function is either [<Target>] or [<Multiversion>], not both"
    | (true, _) ->
      match features (argsOf "Target") with
      | [ fs ] -> cx.targets.Value <- Map.add name [ "target"; fs ] cx.targets.Value
      | _ -> fail "[<Target>] takes the features as one string: [<Target \"avx2,fma\">]"
    | (_, true) ->
      match features (argsOf "Multiversion") with
      | [] -> fail "[<Multiversion>] takes a version's features each: [<Multiversion(\"avx2,fma\", \"sse4.2\")>]"
      | versions -> cx.targets.Value <- Map.add name ("multiversion" :: versions) cx.targets.Value
    | _ -> ()
  | Attrs([ ("Test", []) ], inner) when Option.isSome (funName inner) ->
    let n = Option.get (funName inner)
    fail $"tests are values now (0009): [<Tests>] let tests = testList \"{n}\" [ test \"…\" (fun () -> assert (…)) ]"
  | Attrs([ ("Tests", []) ], inner) when Option.isSome (valueName inner) ->
    // a Test or a list of them, which the file's test entry ($tests) runs
    declare cx inner
    let q = qualify cx (Option.get (valueName inner))
    let t = Map.find q cx.globalValues.Value
    let test = TCon("Testing.Test", [])
    let isList =
      if unifies cx test t then
        false
      else if unifies cx (TCon("list", [ test ])) t then
        true
      else
        fail $"a [<Tests>] value is a Test (test, testList, …) or a list of them, not {show cx t}"
    Buffer.push (q, isList) cx.testValues
  | Attrs([ ("Tests", []) ], _) -> fail "[<Tests>] marks a top-level value: [<Tests>] let tests = testList \"…\" [ … ]"
  | Attrs([ ("CLayout", []) ], inner) when Option.isSome (recordDeclOf inner) ->
    declare cx inner
    let (name, tps) = Option.get (recordDeclOf inner)
    let q = qualify cx name
    if not (List.isEmpty tps) then
      fail "a [<CLayout>] record can't be generic"
    cx.clayouts.Value <- Set.add q cx.clayouts.Value
    let fs =
      match (Map.find q cx.types.Value).def with
      | RecordDef fs -> fs
      | UnionDef _ -> []
    for (f, ft) in fs do
      match prune v ft with
      | TCon("unit", []) -> fail $"[<CLayout>] field '{f}' can't be unit"
      | _ -> checkCType cx $"[<CLayout>] field '{f}'" ft
  | Attrs(attrs, inner) ->
    declare cx inner
    match inner.d with
    | TypeDecl(name0, _, _, _) ->
      let name = qualify cx name0
      for (a, args) in attrs do
        match a with
        | "Derive" ->
          // a group's members, in order (a group may name a group)
          let rec expand (tr0: string) : list<string> =
            let tr = Option.defaultValue tr0 (resolveWith cx (fun q -> Map.containsKey q cx.derives.Value || Map.containsKey q cx.deriveGroups.Value) tr0)
            match Map.tryFind tr cx.deriveGroups.Value with
            | Some members -> List.collect expand members
            | None -> [ tr ]
          for tr in List.collect expand args do
            deriveImpl cx $"Derive({tr}) on {name}" tr name
        | "NoEquality" -> cx.optOut.Value <- Set.add ("Hash", name) (Set.add ("Eq", name) cx.optOut.Value)
        | "NoComparison" -> cx.optOut.Value <- Set.add ("Ord", name) cx.optOut.Value
        | _ -> fail $"unknown attribute '{a}'"
    | TypeGroup items ->
      // type A = … and B = …: each derive for every type of the group at once
      let nameOf (it: Decl) =
        match it.d with
        | TypeDecl(n, _, _, _) -> Some(qualify cx n)
        | Private { d = TypeDecl(n, _, _, _) } -> Some(qualify cx n)
        | _ -> None
      let names = List.choose nameOf items
      for (a, args) in attrs do
        match a with
        | "Derive" ->
          let rec expand (tr0: string) : list<string> =
            let tr = Option.defaultValue tr0 (resolveWith cx (fun q -> Map.containsKey q cx.derives.Value || Map.containsKey q cx.deriveGroups.Value) tr0)
            match Map.tryFind tr cx.deriveGroups.Value with
            | Some members -> List.collect expand members
            | None -> [ tr ]
          for tr in List.collect expand args do
            deriveImpls cx (fun n -> $"Derive({tr}) on {n}") tr names
        | "NoEquality" ->
          for name in names do
            cx.optOut.Value <- Set.add ("Hash", name) (Set.add ("Eq", name) cx.optOut.Value)
        | "NoComparison" ->
          for name in names do
            cx.optOut.Value <- Set.add ("Ord", name) cx.optOut.Value
        | _ -> fail $"unknown attribute '{a}'"
    | _ -> fail "attributes are only supported on type declarations yet"
  | TypeAlias(name0, tps, target) ->
    let q = qualify cx name0
    recordKey cx d.named name0 (TCon(q, [])) false ("type:" + q) true
    if Map.containsKey q cx.types.Value || Map.containsKey q cx.aliases.Value then
      fail $"type '{name0}' is already defined"
    cx.aliases.Value <- Map.add q (List.length tps, toTy cx (Some tps) target) cx.aliases.Value
  | TypeExt(name0, tps, ms) ->
    let n1 =
      match typeAlias name0 with
      | Some c -> c
      | None -> name0
    let exists (q: string) = Set.contains q prims || Option.isSome (builtinCons q) || Map.containsKey q cx.types.Value
    let name = Option.defaultValue n1 (resolveWith cx exists n1)
    if not (exists name) then
      fail $"unknown type '{name}'"
    declareMembers cx name tps ms
  | ImportC _ -> fail "import c is replaced by the header's declarations before checking"

// runs f for a declaration: a failure is the declaration's error (at its first token's line when
// the failure has no place), what it changed of the context is put back, and the names it
// declares are marked failed (an error mentioning one is its consequence); None then
let private guarded (cx: Cx) (d: Decl) (f: unit -> 'a / <Fails, Mismatched>) : option<'a> / <> =
  // names resolve anew in each declaration: the ones before it may have defined them
  cx.resolved.Value <- Map.empty
  let saved = saveScope cx
  // the declaration's errors, in the file's order when it's done: its statements' (the check
  // going on after each) and the one it stopped at
  let errors : Buffer<Diagnostic> = Buffer.empty
  let found (x: Failure) : unit / <> =
    let at = if x.token < 0 then spanOf cx d.dat true else spanOf cx x.token x.lineOnly
    Buffer.push (error at x.message) errors
  let flush () : unit / <> =
    for dg in List.sortBy (fun (dg: Diagnostic) -> dg.at.offset) (Array.toList (Buffer.toArray errors)) do
      report cx dg
    Buffer.clear errors
  let failing () =
    handle Some(f ()) with
    | Fails.fail x, _ ->
      restoreScope cx saved
      Buffer.clear cx.discarded
      Buffer.clear cx.dynCalls
      found x
      flush ()
      for n in declaredNames d do
        cx.failed.Value <- Set.add (qualify cx n) (Set.add n cx.failed.Value)
      if not cx.collect then
        cx.stopped.Value <- true
      None
    | Fails.report x, k ->
      found x
      k ()
  let r =
    handle failing () with
    | Mismatched.throw _, _ ->
      restoreScope cx saved
      flush ()
      report cx (error (spanOf cx d.dat true) "internal error: a type mismatch nothing caught")
      None
  flush ()
  r

/// Declares with error recovery: a failure is the declaration's error, and the next goes on. A
/// nested module's declarations each get their own: it sees the enclosing modules' names, and an
/// open inside it lasts to its end.
let rec declareOne (cx: Cx) (d: Decl) : unit / <> =
  if not cx.stopped.Value then
    match d.d with
    | NestedModule(name0, decls) ->
      let outer = cx.currentModule.Value
      let outerOpens = cx.opens.Value
      match guarded cx d (fun () -> declare cx d) with
      | Some () ->
        cx.currentModule.Value <- Some(qualify cx name0)
        for inner in decls do
          declareOne cx inner
        cx.currentModule.Value <- outer
        cx.opens.Value <- outerOpens
        cx.resolved.Value <- Map.empty
      | None -> ()
    | _ ->
      let run () =
        declare cx d
        closeDynCalls cx
        warnDiscarded cx
      guarded cx d run |> ignore

// ------------------------------------------------------------ modules

let private errorCount (cx: Cx) : int =
  let mutable n = 0
  for i in 0 .. Buffer.length cx.diagnostics - 1 do
    if cx.diagnostics.[i].severity = Err then
      n <- n + 1
  n

/// Checks a module (its file, its name, its declarations); false if it had errors. The prelude and
/// the main file have no module name: their names are global.
let check (cx: Cx) (file: InFile) (modName: option<string>) (decls: list<Decl>) : bool =
  // its names are numbered from 0, so they don't depend on the modules before it
  cx.counter.Value <- 0
  cx.localValues.Value <- Map.empty
  cx.currentModule.Value <- modName
  cx.opens.Value <- []
  cx.resolved.Value <- Map.empty
  cx.file.Value <- file
  let errorsBefore = errorCount cx
  match modName with
  | Some m ->
    for n in withEnclosing m do
      cx.moduleNames.Value <- Set.add n cx.moduleNames.Value
  | None -> ()
  Buffer.clear cx.testValues
  for d in decls do
    declareOne cx d
  // the program's [<Tests>] values, run by the test binary's entry (0009)
  if Option.isNone modName && Buffer.length cx.testValues > 0 then
    let one (t: string * bool) =
      let (q, isList) = t
      if isList then plain (Var q) else plain (Call("::", [ plain (Tuple [ plain (Var q); plain (Var "[]") ]) ]))
    let all = List.map one (Array.toList (Buffer.toArray cx.testValues))
    let cons (acc: Expr) (a: Expr) = plain (Call("::", [ plain (Tuple [ a; acc ]) ]))
    let joined = plain (Call(libraryName "Collections.List.concat", [ List.fold cons (plain (Var "[]")) (List.rev all) ]))
    let entry = plain (Call(libraryName "Testing.Runner.main", [ joined ]))
    declareOne cx (decl (Fun("$tests", false, [ unitParam ], None, entry)) -1)
    Buffer.push "$tests" cx.tests
  // the types its annotations name, for the editor: a type's key is type:Its.Name
  // ponytail: resolved as the file's top level sees them, so a nested module's own type is found only qualified
  let isType (q: string) = Map.containsKey q cx.types.Value || Map.containsKey q cx.aliases.Value || Set.contains q cx.traitNames.Value
  for tok in file.typeNames do
    let t = file.tokens.[tok]
    let n = String.sub file.source.text t.offset t.length
    // a private type of another module isn't its
    let found =
      handle resolveWith cx isType n with
      | Fails.fail _, _ -> None
      | Fails.report _, k -> k ()
    match found with
    | Some q -> recordKey cx tok n (TCon(q, [])) false ("type:" + q) false
    | None -> ()
  cx.currentModule.Value <- None
  errorCount cx = errorsBefore

// main must take unit, give int, c_int or unit, and perform nothing (nothing handles it)
let private checkMain (cx: Cx) : unit / Fails =
  let v = cx.v
  match Map.tryFind "main" cx.globals.Value with
  | Some g ->
    match (g.arity, prune v g.ty) with
    | (1, TFun(p, r, row)) when prune v p = tUnit ->
      match resolve v r with
      | TCon("int", [])
      | TCon("i32", [])
      | TCon("unit", []) -> ()
      | t -> fail $"'main' must return int, c_int or unit, not {show cx t}"
      // nothing handles what main performs
      match fst (rowParts v row) with
      | [] -> ()
      | ls ->
        let consume = if List.exists (fun l -> labelName v l = "Yield") ls then ", or consume the Seq" else ""
        fail $"main performs {String.join ", " (List.map (show cx) ls)} and nothing handles it: wrap the call in handle … with{consume}"
    | _ -> fail "'main' must take one unit parameter: let main () = ..."
  | None -> fail "no 'main' function"

/// After every module: `main` checked (when required, or there is one), at main's line.
let finish (cx: Cx) : unit =
  // a test file needs no main
  if (cx.requireMain && Buffer.length cx.tests = 0) || Map.containsKey "main" cx.globals.Value then
    // at main when it was checked here; else no place yet (the driver gives main's, when the
    // main module came from the cache)
    let at =
      match cx.mainAt.Value with
      | Some s -> s
      | None -> { file = -1; offset = -1; length = -1 }
    handle checkMain cx with
    | Fails.fail x, _ -> report cx (error at x.message)
    | Fails.report x, k ->
      report cx (error at x.message)
      k ()
