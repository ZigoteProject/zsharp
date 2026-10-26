/// The checker's context (the F# compiler's Typer session): what checking a program's modules has
/// built so far, which each module after them sees, and what the declaration being checked is in.
/// Its tables are maps in cells, written as declarations are checked. A failure (Fails) ends the
/// declaration, whose boundary (Decls.declareOne) puts back what the declaration had changed of
/// the context; so a function here that sets part of it for a while puts it back only when what it
/// runs returns.
open Types.Ty
open Types.Vars
open Types.Norm
open Types.Fail
open Core.Ir
open Syntax.Ast
open Diag.Diagnostic

/// A local variable: its unique name in Core, its type, whether it's `mutable`, and the closure
/// depth it's bound at.
type Local = { u: string; ty: Ty; mut: bool; depth: int }

/// A member of a type: the function implementing it (`Type#Name`), whether it's static, whether
/// it's a property (no parameters), and its parameters.
[<Derive(Binary)>]
type MemberInfo = { gname: string; isStatic: bool; isProperty: bool; mpars: list<MemberParam> }

/// A top-level function: its type (a scheme once generalized, its TGen variables of these kinds),
/// how many parameters it takes, and whether its group is being checked (not generalized yet).
[<Derive(Binary)>]
type Global = { ty: Ty; kinds: list<Kind>; arity: int; defining: bool }

/// What an identifier at a place is (editor support): a use, or a binder (an inlay hint's place
/// when its type wasn't written). `key` is what it refers to: a local's unique name or a global's
/// qualified name ("": unknown); `isDef` says it's where `key` is defined.
[<Derive(Binary)>]
type Hover =
  { file: int
    token: int
    name: string
    ty: Ty
    /// "'a : Add" for a generic function
    constraints: string
    /// a top-level function's effects in words ("" if none)
    explain: string
    /// a top-level function's name
    decl: bool
    key: string
    isDef: bool
    inlay: bool }

/// The file being checked: its index in the build, its source, and its tree's tokens (an AST
/// node's place is a token's index).
type InFile = { index: int; source: Syntax.Source.Source; tokens: array<Syntax.Token.Token>; typeNames: array<int> }

/// The context: one heap cell, so a closure that uses it holds a pointer, not its fields.
type Cx =
  | Cx of CxData

/// What the context holds.
and CxData =
  { /// the type variables
    v: Vars
    /// what's defined later, in the modules that use this one
    late: Late
    // ---- the program so far: what the modules after each see
    types: ref<Map<string, TypeInfo>>
    /// constructor: its union and tag
    ctors: ref<Map<string, string * int>>
    /// record types, in declaration order
    records: Buffer<string>
    /// record: each field's default
    recordDefaults: ref<Map<string, list<option<Expr>>>>
    /// constructor: its fields' names
    ctorFieldNames: ref<Map<string, list<option<string>>>>
    /// type: its members, in declaration order
    members: ref<Map<string, list<string * MemberInfo>>>
    /// the last part of each type in members, a quick test for staticMember
    memberTypeNames: ref<Set<string>>
    /// "Show.show": the method
    traitMethods: ref<Map<string, TraitMethod>>
    /// "show": "Show.show"; "M.describe": "M.Describe.describe"
    traitAliases: ref<Map<string, string>>
    /// by full name: Show, or M.Describe declared in module M
    traitNames: ref<Set<string>>
    /// by full name
    effects: ref<Map<string, EffectInfo>>
    /// "Yield.yield": the effect, the operation's index
    effectOps: ref<Map<string, string * int>>
    /// (trait, type): method to function
    impls: ref<Map<string * string, Map<string, string>>>
    /// (trait, type): the traits each type argument needs
    implRequires: ref<Map<string * string, list<Set<string>>>>
    /// (trait, type): the trait's other parameters, over the head's variables (0017)
    implOthers: ref<Map<string * string, list<Ty>>>
    /// by full name, as traits
    derives: ref<Map<string, list<Definition>>>
    /// derive Json = ToJson, FromJson: by full name, the members'
    deriveGroups: ref<Map<string, list<string>>>
    /// type Duration = i64<ns>: by full name, its parameters' count and what it names (TGen i the
    /// i-th)
    aliases: ref<Map<string, int * Ty>>
    /// derive: the module declaring it
    deriveModules: ref<Map<string, option<string>>>
    /// an active pattern's case: its function, whether it's total, the parameters before the value
    activePatterns: ref<Map<string, string * bool * int>>
    /// cases of total active patterns: their payload is optional
    apCtors: ref<Set<string>>
    /// the automatic derives made so far
    autoDerived: ref<Set<string * string>>
    /// [<NoEquality>], [<NoComparison>]
    optOut: ref<Set<string * string>>
    globals: ref<Map<string, Global>>
    externs: ref<Map<string, ExternSig>>
    funs: Buffer<FunDef>
    /// for unique names, from 0 in each module (so a module's names are its own)
    counter: ref<int>
    /// [<Measure>] types
    measures: ref<Set<string>>
    /// [<CLayout>] records
    clayouts: ref<Set<string>>
    /// [<Target>] and [<Multiversion>] functions
    targets: ref<Map<string, list<string>>>
    exports: Buffer<Export>
    tests: Buffer<string>
    /// constants (top-level and from import c): their uses are the expression
    consts: ref<Map<string, Expr>>
    /// top-level values computed at startup
    globalValues: ref<Map<string, Ty>>
    /// in initialization order: name, init function
    valueList: Buffer<string * string>
    /// a constant's record literal (the constant, the literal's first field name's token): the
    /// record it built, the same at each use as where it's defined
    literalRecords: ref<Map<string * int, string>>
    /// qualified name: its owning module
    privates: ref<Map<string, option<string>>>
    /// files' and nested modules, and the namespaces they are in
    moduleNames: ref<Set<string>>
    /// modules nested in the main file (it has no module name)
    mainNested: ref<Set<string>>
    /// every `module X =` so far, to catch a second one
    nestedModules: ref<Set<string>>
    /// each module's enclosing modules, innermost first
    enclosingOf: ref<Map<string, list<string>>>
    // ---- the check
    requireMain: bool
    /// every declaration's error (editors), not the first
    collect: bool
    /// the explicit impls of every module, (trait, type as written): they win over automatic derives
    manualImpls: ref<Set<string * string>>
    /// modules the target doesn't have, by full name (Std's on a microcontroller): a name in one is
    /// reported as such rather than as unknown
    unavailable: Set<string>
    /// the target's machine word in bytes, for sizeof<int> (4 on a Cortex-M and wasm32, else 8)
    word: int
    /// 'a in the current function's annotations
    tyvars: ref<Map<string, Ty>>
    /// errors and warnings so far, in order
    diagnostics: Buffer<Diagnostic>
    hovers: Buffer<Hover>
    file: ref<InFile>
    /// the warning kinds the declaration being checked silences ([<NoWarn "…">])
    silenced: ref<Set<string>>
    /// the values statements drop in the declaration being checked, with their places: warned
    /// about at its end, when their types are settled (unused-value)
    discarded: Buffer<Ty * Span>
    /// trait methods called with an ambient row (0025): the value's type, the row, the trait, the
    /// method and the place; through dyn the row must be empty
    dynCalls: Buffer<Ty * Ty * string * string * int>
    /// the [<Tests>] values of the module being checked, and whether each is a list (0009)
    testValues: Buffer<string * bool>
    /// the statement being checked (its token: assert's message, expect's place)
    currentStmt: ref<int>
    /// the effects of the function being checked: what its body performs joins this row; and what
    /// it is, for an error naming it ("" for a function's inferred row)
    ctxRow: ref<Ty>
    ctxWhat: ref<string>
    /// constants being expanded (a cycle is an error)
    inlining: ref<Set<string>>
    /// a let-bound local's Core, by its unique name: what a function crossing threads captures
    /// when it captures a local function
    localValues: ref<Map<string, CExpr>>
    currentModule: ref<option<string>>
    /// most recent first
    opens: ref<list<string>>
    /// checking a [<Wrapping>] function: its integer + - * wrap
    wrapping: ref<bool>
    /// checking a [<FastMath>] function: its float + - * / may be reassociated
    fastMath: ref<bool>
    /// inside `unsafe`
    unsafeOn: ref<bool>
    /// checking an [<Export>] function: C calls it, so nothing in its type performs
    exporting: ref<bool>
    /// the top-level definition being checked, for the error on a function that calls itself
    /// without `rec`
    currentDef: ref<string>
    /// the constant whose body is being checked ("": none), for its record literals
    inConst: ref<string>
    /// checking an expression written elsewhere (a constant's body at a use, a default): its places
    /// aren't this file's, so its errors are at the use and it records no hovers
    foreign: ref<bool>
    /// C names import c skipped: why
    skippedC: ref<Map<string, string>>
    /// the types of a group (type A = … and B = …) declared ahead of their own declarations
    ahead: ref<Set<string>>
    /// an error stopped the check (when not collecting every declaration's)
    stopped: ref<bool>
    /// main's place, once it's defined (its line)
    mainAt: ref<option<Span>>
    /// names resolved in the declaration being checked (Exprs.resolveName), what each is: the
    /// same until a declaration, an open or a module starts
    resolved: ref<Map<string, option<string>>>
    /// declarations that failed: an error mentioning one is a consequence
    failed: ref<Set<string>> }

/// What the modules using this one define: Decls's automatic derives, which unification asks for
/// (a type's Eq, made the first time it's needed).
and Late = { autoDerive: Cx -> string -> string -> bool / <Fails, Mismatched> }

/// The context's parts, by name.
type Cx with
  member c.v =
    match c with
    | Cx { v = x } -> x
  member c.late =
    match c with
    | Cx { late = x } -> x
  member c.types =
    match c with
    | Cx { types = x } -> x
  member c.ctors =
    match c with
    | Cx { ctors = x } -> x
  member c.records =
    match c with
    | Cx { records = x } -> x
  member c.recordDefaults =
    match c with
    | Cx { recordDefaults = x } -> x
  member c.ctorFieldNames =
    match c with
    | Cx { ctorFieldNames = x } -> x
  member c.members =
    match c with
    | Cx { members = x } -> x
  member c.memberTypeNames =
    match c with
    | Cx { memberTypeNames = x } -> x
  member c.traitMethods =
    match c with
    | Cx { traitMethods = x } -> x
  member c.traitAliases =
    match c with
    | Cx { traitAliases = x } -> x
  member c.traitNames =
    match c with
    | Cx { traitNames = x } -> x
  member c.effects =
    match c with
    | Cx { effects = x } -> x
  member c.effectOps =
    match c with
    | Cx { effectOps = x } -> x
  member c.impls =
    match c with
    | Cx { impls = x } -> x
  member c.implRequires =
    match c with
    | Cx { implRequires = x } -> x
  member c.implOthers =
    match c with
    | Cx { implOthers = x } -> x
  member c.derives =
    match c with
    | Cx { derives = x } -> x
  member c.deriveGroups =
    match c with
    | Cx { deriveGroups = x } -> x
  member c.aliases =
    match c with
    | Cx { aliases = x } -> x
  member c.deriveModules =
    match c with
    | Cx { deriveModules = x } -> x
  member c.activePatterns =
    match c with
    | Cx { activePatterns = x } -> x
  member c.apCtors =
    match c with
    | Cx { apCtors = x } -> x
  member c.autoDerived =
    match c with
    | Cx { autoDerived = x } -> x
  member c.optOut =
    match c with
    | Cx { optOut = x } -> x
  member c.globals =
    match c with
    | Cx { globals = x } -> x
  member c.externs =
    match c with
    | Cx { externs = x } -> x
  member c.funs =
    match c with
    | Cx { funs = x } -> x
  member c.counter =
    match c with
    | Cx { counter = x } -> x
  member c.measures =
    match c with
    | Cx { measures = x } -> x
  member c.clayouts =
    match c with
    | Cx { clayouts = x } -> x
  member c.targets =
    match c with
    | Cx { targets = x } -> x
  member c.exports =
    match c with
    | Cx { exports = x } -> x
  member c.tests =
    match c with
    | Cx { tests = x } -> x
  member c.consts =
    match c with
    | Cx { consts = x } -> x
  member c.globalValues =
    match c with
    | Cx { globalValues = x } -> x
  member c.valueList =
    match c with
    | Cx { valueList = x } -> x
  member c.literalRecords =
    match c with
    | Cx { literalRecords = x } -> x
  member c.privates =
    match c with
    | Cx { privates = x } -> x
  member c.moduleNames =
    match c with
    | Cx { moduleNames = x } -> x
  member c.mainNested =
    match c with
    | Cx { mainNested = x } -> x
  member c.nestedModules =
    match c with
    | Cx { nestedModules = x } -> x
  member c.enclosingOf =
    match c with
    | Cx { enclosingOf = x } -> x
  member c.requireMain =
    match c with
    | Cx { requireMain = x } -> x
  member c.collect =
    match c with
    | Cx { collect = x } -> x
  member c.manualImpls =
    match c with
    | Cx { manualImpls = x } -> x
  member c.unavailable =
    match c with
    | Cx { unavailable = x } -> x
  member c.word =
    match c with
    | Cx { word = x } -> x
  member c.tyvars =
    match c with
    | Cx { tyvars = x } -> x
  member c.diagnostics =
    match c with
    | Cx { diagnostics = x } -> x
  member c.hovers =
    match c with
    | Cx { hovers = x } -> x
  member c.file =
    match c with
    | Cx { file = x } -> x
  member c.silenced =
    match c with
    | Cx { silenced = x } -> x
  member c.discarded =
    match c with
    | Cx { discarded = x } -> x
  member c.dynCalls =
    match c with
    | Cx { dynCalls = x } -> x
  member c.testValues =
    match c with
    | Cx { testValues = x } -> x
  member c.currentStmt =
    match c with
    | Cx { currentStmt = x } -> x
  member c.ctxRow =
    match c with
    | Cx { ctxRow = x } -> x
  member c.ctxWhat =
    match c with
    | Cx { ctxWhat = x } -> x
  member c.inlining =
    match c with
    | Cx { inlining = x } -> x
  member c.localValues =
    match c with
    | Cx { localValues = x } -> x
  member c.currentModule =
    match c with
    | Cx { currentModule = x } -> x
  member c.opens =
    match c with
    | Cx { opens = x } -> x
  member c.wrapping =
    match c with
    | Cx { wrapping = x } -> x
  member c.fastMath =
    match c with
    | Cx { fastMath = x } -> x
  member c.unsafeOn =
    match c with
    | Cx { unsafeOn = x } -> x
  member c.exporting =
    match c with
    | Cx { exporting = x } -> x
  member c.currentDef =
    match c with
    | Cx { currentDef = x } -> x
  member c.inConst =
    match c with
    | Cx { inConst = x } -> x
  member c.foreign =
    match c with
    | Cx { foreign = x } -> x
  member c.skippedC =
    match c with
    | Cx { skippedC = x } -> x
  member c.ahead =
    match c with
    | Cx { ahead = x } -> x
  member c.stopped =
    match c with
    | Cx { stopped = x } -> x
  member c.mainAt =
    match c with
    | Cx { mainAt = x } -> x
  member c.resolved =
    match c with
    | Cx { resolved = x } -> x
  member c.failed =
    match c with
    | Cx { failed = x } -> x

/// The type a span is after monomorphization, and a Buffer (in a ref), built in.
let private builtInTypes () : Map<string, TypeInfo> =
  let list = { npars = 1; def = UnionDef [ ("[]", []); ("::", [ TGen 0; TCon("list", [ TGen 0 ]) ]) ] }
  Map.ofList [ (windowType, windowDef); (bufferType, bufferDef); ("list", list) ]

/// The module and the namespaces it's in: A.B.C, A.B, A in that order's reverse (A, A.B, A.B.C).
let withEnclosing (m: string) : list<string> =
  let parts = String.split "." m
  List.init (List.length parts) (fun k -> String.join "." (List.take (k + 1) parts))

/// A context for checking a program whose file modules are allModules.
let create (requireMain: bool) (collect: bool) (allModules: list<string>) (manualImpls: list<string * string>) (unavailable: Set<string>) (word: int) (late: Late) (first: InFile) : Cx =
  let moduleNames = Set.ofList (List.collect withEnclosing allModules)
  let data : CxData =
    { v = Types.Vars.make ()
      late = late
      types = ref (builtInTypes ())
      ctors = ref (Map.ofList [ ("[]", ("list", 0)); ("::", ("list", 1)) ])
      records = Buffer.empty
      recordDefaults = ref Map.empty
      ctorFieldNames = ref (Map.ofList [ ("[]", []); ("::", [ Some "head"; Some "tail" ]) ])
      members = ref Map.empty
      memberTypeNames = ref Set.empty
      traitMethods = ref Map.empty
      traitAliases = ref Map.empty
      traitNames = ref Set.empty
      effects = ref Map.empty
      effectOps = ref Map.empty
      impls = ref Map.empty
      implRequires = ref Map.empty
      implOthers = ref Map.empty
      derives = ref Map.empty
      deriveGroups = ref Map.empty
      aliases = ref Map.empty
      deriveModules = ref Map.empty
      activePatterns = ref Map.empty
      apCtors = ref Set.empty
      autoDerived = ref Set.empty
      optOut = ref Set.empty
      globals = ref Map.empty
      externs = ref Map.empty
      funs = Buffer.empty
      counter = ref 0
      measures = ref Set.empty
      clayouts = ref Set.empty
      targets = ref Map.empty
      exports = Buffer.empty
      tests = Buffer.empty
      consts = ref Map.empty
      globalValues = ref Map.empty
      valueList = Buffer.empty
      literalRecords = ref Map.empty
      privates = ref Map.empty
      moduleNames = ref moduleNames
      mainNested = ref Set.empty
      nestedModules = ref Set.empty
      enclosingOf = ref Map.empty
      requireMain = requireMain
      collect = collect
      manualImpls = ref (Set.ofList manualImpls)
      unavailable = unavailable
      word = word
      tyvars = ref Map.empty
      diagnostics = Buffer.empty
      hovers = Buffer.empty
      file = ref first
      silenced = ref Set.empty
      discarded = Buffer.empty
      dynCalls = Buffer.empty
      testValues = Buffer.empty
      currentStmt = ref -1
      ctxRow = ref rowEmpty
      ctxWhat = ref "code outside a function"
      inlining = ref Set.empty
      localValues = ref Map.empty
      currentModule = ref None
      opens = ref []
      wrapping = ref false
      fastMath = ref false
      unsafeOn = ref false
      exporting = ref false
      currentDef = ref ""
      inConst = ref ""
      foreign = ref false
      skippedC = ref Map.empty
      ahead = ref Set.empty
      stopped = ref false
      mainAt = ref None
      resolved = ref Map.empty
      failed = ref Set.empty }
  Cx data

// ------------------------------------------------------------ small helpers

/// The text after the last dot (the whole text when it has none).
let afterLastDot (s: string) : string =
  match String.lastIndexOf "." s with
  | Some i -> String.sub s (i + 1) (String.length s - i - 1)
  | None -> s

/// The text before the last dot, if it has one.
let beforeLastDot (s: string) : option<string> =
  match String.lastIndexOf "." s with
  | Some i -> Some(String.sub s 0 i)
  | None -> None

/// The text from an index on.
let skipChars (i: int) (s: string) : string = String.sub s i (String.length s - i)

/// Whether a string's first byte is a lowercase ASCII letter.
let startsLower (s: string) : bool =
  String.length s > 0 && String.byte s 0 >= u8 97 && String.byte s 0 <= u8 122

/// `'x'` for each name, joined: "'a', 'b'".
let quoted (xs: list<string>) : string = String.join ", " (List.map (fun x -> "'" + x + "'") xs)

/// A unique name in Core: x.42.
let uniq (cx: Cx) (x: string) : string =
  cx.counter.Value <- cx.counter.Value + 1
  $"{x}.{cx.counter.Value}"

// ------------------------------------------------------------ places

/// A token's span in the file being checked (a line's, with no column, when lineOnly); a token
/// before the first is no place, the file's.
let spanOf (cx: Cx) (tok: int) (lineOnly: bool) : Span =
  let f = cx.file.Value
  if tok < 0 || tok >= Array.length f.tokens then
    { file = f.index; offset = -1; length = -1 }
  else
    let t = f.tokens.[tok]
    { file = f.index; offset = t.offset; length = if lineOnly then -1 else t.length }

/// A token's line (from 1) in the file being checked; 0 for none.
let lineOf (cx: Cx) (tok: int) : int =
  let f = cx.file.Value
  if tok < 0 || tok >= Array.length f.tokens then 0 else Syntax.Source.lineOf f.source f.tokens.[tok].offset + 1

/// A warning of a kind at a span, unless the declaration silences the kind (0021).
let warnAt (cx: Cx) (kind: string) (at: Span) (msg: string) =
  if not (Set.contains kind cx.silenced.Value) then
    Buffer.push (warning kind at msg) cx.diagnostics

/// What a declaration's check may change of the context: put back when it fails, and when one of
/// its statements does.
type Scope =
  { stv: Map<string, Ty>
    srow: Ty
    swhat: string
    sinlining: Set<string>
    swrapping: bool
    sfast: bool
    sunsafe: bool
    sexporting: bool
    sdef: string
    sconst: string
    sforeign: bool
    ssilenced: Set<string>
    smodule: option<string>
    sopens: list<string> }

let saveScope (cx: Cx) : Scope =
  { stv = cx.tyvars.Value
    srow = cx.ctxRow.Value
    swhat = cx.ctxWhat.Value
    sinlining = cx.inlining.Value
    swrapping = cx.wrapping.Value
    sfast = cx.fastMath.Value
    sunsafe = cx.unsafeOn.Value
    sexporting = cx.exporting.Value
    sdef = cx.currentDef.Value
    sconst = cx.inConst.Value
    sforeign = cx.foreign.Value
    ssilenced = cx.silenced.Value
    smodule = cx.currentModule.Value
    sopens = cx.opens.Value }

let restoreScope (cx: Cx) (s: Scope) =
  cx.tyvars.Value <- s.stv
  cx.ctxRow.Value <- s.srow
  cx.ctxWhat.Value <- s.swhat
  cx.inlining.Value <- s.sinlining
  cx.wrapping.Value <- s.swrapping
  cx.fastMath.Value <- s.sfast
  cx.unsafeOn.Value <- s.sunsafe
  cx.exporting.Value <- s.sexporting
  cx.currentDef.Value <- s.sdef
  cx.inConst.Value <- s.sconst
  cx.foreign.Value <- s.sforeign
  cx.silenced.Value <- s.ssilenced
  cx.currentModule.Value <- s.smodule
  cx.opens.Value <- s.sopens

/// Runs a statement's check so that its failure doesn't end the declaration's (0020): reported
/// instead, the context and the types put back as they were before it, and the statement standing
/// for a value of fallback's type (what it declares, or one nothing constrains yet), so the block
/// goes on and each mistake is reported, not only the first. When the checker stops at the first
/// error, a failure goes on up as it is.
let recovered (cx: Cx) (fallback: unit -> Ty) (f: unit -> CExpr / <Fails | 'e>) : CExpr / <Fails | 'e> =
  if not cx.collect then
    f ()
  else
    let scope = saveScope cx
    let trail = mark cx.v
    let discarded = Buffer.length cx.discarded
    let dynCalls = Buffer.length cx.dynCalls
    let attempt () =
      let c = f ()
      commit cx.v trail
      c
    handle attempt () with
    | Fails.fail x, _ ->
      undo cx.v trail
      restoreScope cx scope
      Buffer.truncate discarded cx.discarded
      Buffer.truncate dynCalls cx.dynCalls
      Fails.report x
      mk CUnit (fallback ())
    | Fails.report x, k -> k (Fails.report x)

/// Runs f; a failure in it with no place of its own is at the token (a line's, with no column,
/// when lineOnly). With no token (-1), or in an expression written elsewhere, f as it is.
let located (cx: Cx) (tok: int) (lineOnly: bool) (f: unit -> 'r / <Fails | 'e>) : 'r / <Fails | 'e> =
  if tok < 0 || cx.foreign.Value then
    f ()
  else
    let placed (x: Failure) = if x.token < 0 then { x with token = tok; lineOnly = lineOnly } else x
    handle f () with
    | Fails.fail x, _ -> Fails.fail (placed x)
    | Fails.report x, k -> k (Fails.report (placed x))

/// Runs f on an expression written elsewhere (a constant's body at a use, a default).
let foreignly (cx: Cx) (f: unit -> 'r / 'e) : 'r / 'e =
  let outer = cx.foreign.Value
  cx.foreign.Value <- true
  let r = f ()
  cx.foreign.Value <- outer
  r

/// Runs f; a failure in it says what was being checked first ("field run: …").
let saying (context: string) (f: unit -> 'r / <Fails | 'e>) : 'r / <Fails | 'e> =
  handle f () with
  | Fails.fail x, _ -> Fails.fail { x with message = context + ": " + x.message }
  | Fails.report x, k -> k (Fails.report { x with message = context + ": " + x.message })

/// Runs f; a failure in it is at the token's line when it has no place, and its message follows
/// `context: ` (a derive's).
let inContext (context: string) (tok: int) (f: unit -> 'r / <Fails | 'e>) : 'r / <Fails | 'e> =
  let said (x: Failure) =
    let place = if x.token < 0 then { x with token = tok; lineOnly = true } else x
    { place with message = context + ": " + x.message }
  handle f () with
  | Fails.fail x, _ -> Fails.fail (said x)
  | Fails.report x, k -> k (Fails.report (said x))

/// Remembers the type at a token, and what the name there refers to (editor support).
let recordKey (cx: Cx) (tok: int) (name: string) (t: Ty) (inlay: bool) (key: string) (isDef: bool) =
  if tok >= 0 && not cx.foreign.Value then
    let h : Hover =
      { file = cx.file.Value.index
        token = tok
        name = name
        ty = t
        constraints = ""
        explain = ""
        decl = false
        key = key
        isDef = isDef
        inlay = inlay }
    Buffer.push h cx.hovers

let record (cx: Cx) (tok: int) (name: string) (t: Ty) (inlay: bool) = recordKey cx tok name t inlay "" false

/// Whether code here sees what's private to owner: its module and the modules nested in it do, and
/// so does an expression written elsewhere (a constant's body at a use), whose names were checked
/// where it was written.
let visibleTo (cx: Cx) (owner: option<string>) : bool =
  match (owner, cx.currentModule.Value) with
  | _ when cx.foreign.Value -> true
  | (o, c) when o = c -> true
  | (Some o, Some c) -> String.startsWith (o + ".") c
  | (None, Some c) -> Set.contains c cx.mainNested.Value
  | _ -> false

/// Fails unless code here may use the record's fields: a private record's are for its module,
/// even where one of its values is reached (through a public record's field, say).
let fieldsVisible (cx: Cx) (rname: string) =
  match Map.tryFind rname cx.privates.Value with
  | Some owner when not (visibleTo cx owner) ->
    let o =
      match owner with
      | Some m -> m
      | None -> "?"
    fail $"the fields of '{shortName rname}' are private to module {o}"
  | _ -> ()

/// The field names a record literal, update, pattern or declaration writes (each with its name's
/// token), each a reference to (or with isDef the definition of) the field: key
/// field:<record>.<field> (0019's rename). A private record's fields are for its module.
let fieldUses (cx: Cx) (rname: string) (names: list<string * int>) (isDef: bool) =
  fieldsVisible cx rname
  let types =
    match Map.tryFind rname cx.types.Value with
    | Some { def = RecordDef fs } -> fs
    | _ -> []
  for (f, tok) in names do
    let t =
      match List.tryFind (fun (g, _) -> g = f) types with
      | Some(_, ft) -> ft
      | None -> tUnit
    recordKey cx tok f t false $"field:{rname}.{f}" isDef

/// Parameters that are plain names, with their types (as binders).
let recordParams (cx: Cx) (orig: list<Param>) (pars: list<string * string * Ty>) =
  let one (p: Param) (q: string * string * Ty) =
    match (p.param.pat, q) with
    | (PIdent(x, None), (_, u, t)) -> recordKey cx p.param.patAt x t (Option.isNone p.ann) u true
    | _ -> ()
  if List.length orig = List.length pars then
    List.iter2 one orig pars

/// The type with its variables as a scheme's ('a, 'b, … in order), as a hover or an error shows a
/// generic one; a literal's variable (a number constant's) stays.
let schemed (cx: Cx) (t: Ty) : Ty =
  let vars = Buffer.empty
  let indexOf (i: int) =
    let mutable found = -1
    for j in 0 .. Buffer.length vars - 1 do
      if found < 0 && vars.[j] = i then
        found <- j
    found
  let rec named (t: Ty) =
    match prune cx.v t with
    | TVar i when Option.isNone (kindOf cx.v i).allowed ->
      if indexOf i < 0 then
        Buffer.push i vars
      TGen(indexOf i)
    | TCon(n, ts) -> TCon(n, List.map named ts)
    | TTuple ts -> TTuple(List.map named ts)
    | TFun(a, b, r) -> TFun(named a, named b, named r)
    | x -> x
  named t

// ------------------------------------------------------------ names

/// The name a declaration gets in the current module.
let qualify (cx: Cx) (name: string) : string =
  match cx.currentModule.Value with
  | Some m -> m + "." + name
  | None -> name

/// The current module and the modules it is nested in, innermost first.
let enclosing (cx: Cx) : list<string> =
  match cx.currentModule.Value with
  | Some m ->
    match Map.tryFind m cx.enclosingOf.Value with
    | Some e -> e
    | None ->
      let e = List.rev (withEnclosing m)
      cx.enclosingOf.Value <- Map.add m e cx.enclosingOf.Value
      e
  | None -> []

/// Unqualified names resolve in the current module and the modules it is nested in, then opened
/// modules, then globally, then in the auto-opened namespaces. Candidates are tried in that order
/// and built only as needed: this runs for every name.
let resolveWith (cx: Cx) (exists: string -> bool / <Fails | 'e>) (x: string) : option<string> / <Fails | 'e> =
  if String.startsWith "global::" x then
    // a desugaring's call: the library's name, whatever is opened
    let g = skipChars 8 x
    if exists g then Some g else None
  else
    let rec tryIn (prefixes: list<string>) =
      match prefixes with
      | [] -> None
      | p :: rest ->
        let q = p + "." + x
        if exists q then Some q else tryIn rest
    let found =
      match tryIn (enclosing cx) with
      | Some q -> Some q
      | None ->
        match tryIn cx.opens.Value with
        | Some q -> Some q
        | None -> if exists x then Some x else tryIn autoOpens
    match found with
    | Some q ->
      match Map.tryFind q cx.privates.Value with
      | Some owner ->
        if visibleTo cx owner then
          Some q
        else
          let o =
            match owner with
            | Some m -> m
            | None -> "?"
          fail $"'{x}' is private to module {o}"
      | None -> Some q
    | None -> None

/// The error for a name nothing defines; the names F# and C programmers reach for first say what
/// Z# has instead.
let unknown (cx: Cx) (what: string) (x: string) : 'a / Fails =
  let inModule (m: string) = String.startsWith (m + ".") x || String.startsWith (shortName m + ".") x
  match List.tryFind inModule (Set.toList cx.unavailable) with
  | Some m -> fail $"'{x}' is in {m}, part of Std, which needs an operating system; this target has none"
  | None ->
    if x = "!" then
      fail "'!' isn't an operator: write not x (F#'s !r is r.Value)"
    else if x = "printfn" || x = "printf" || x = "eprintfn" then
      fail ("there's no " + x + ": print with println $\"…{x}…\" (print for no newline, Console.Error.writeLine for errors)")
    else if x = "sprintf" || x = "failwithf" then
      fail ("there's no " + x + ": interpolate, $\"…{x}…\"")
    else if x = "raise" || x = "reraise" then
      fail "there's no raise: return a result (Error e) for the caller to match on, throw a typed exception (Throw.throw e, caught by Throw.catch), or panic for a bug"
    else if x = "null" || x = "NULL" then
      fail "there's no null: a missing value is None, of type option<'a>"
    else if x = "return" then
      fail "return belongs in a computation expression (task { }, result { }); a function's last expression is its result"
    else if x = "async" || String.startsWith "Async." x then
      fail "there's no Async: write task { }, and run it with Task.run"
    else if x = cx.currentDef.Value then
      fail $"'{x}' calls itself: declare it with let rec"
    else if x <> "" && Syntax.Lexer.isOpChar (int (String.byte x 0)) then
      fail $"unknown operator '{x}'; define it with: let ({x}) a b = …"
    else if x = "yield" then
      fail "yield belongs in [ … ], [| … |] or seq { }"
    else
      fail $"unknown {what} '{x}'"

// ------------------------------------------------------------ unification

/// Whether a type has a trait through a user impl, its requirements pushed onto the type's
/// arguments (a type's automatic derive made the first time it's needed).
let rec private userImpl (cx: Cx) (tr: string) (t: Ty) : bool / <Mismatched, Fails> =
  let reqsOf (key: string * string) (args: list<Ty>) =
    match Map.tryFind key cx.implRequires.Value with
    | Some reqs ->
      for (a, trs) in List.zip args reqs do
        for tr2 in Set.toList trs do
          unify cx (fresh cx.v (kTrait tr2)) a
      true
    | None -> false
  match prune cx.v t with
  | x when tr = "Share" ->
    // built in, from the type's parts (its type variables must be Share too)
    let onVar (w: Ty) = unify cx (fresh cx.v (kTrait "Share")) w
    handle Option.isNone (Types.Repr.shareBlocker cx.v onVar cx.types.Value Set.empty x) with
    | Mismatched.throw _, _ -> false
  | TCon(n, []) when isDynName n -> skipChars 4 n = tr
  | TCon(n, args) ->
    // dyn Trait implements its trait; a type's automatic derive is made the first time it's needed
    if not (Map.containsKey (tr, n) cx.implRequires.Value) then
      cx.late.autoDerive cx tr n |> ignore
    reqsOf (tr, n) args
  | TTuple ts when List.contains tr [ "Eq"; "Ord"; "Show"; "Hash" ] ->
    // tuples have structural Eq/Ord/Show/Hash when their components do
    for a in ts do
      unify cx (fresh cx.v (kTrait tr)) a
    true
  | TTuple ts ->
    // an impl for tuples of this size (impl Binary<'a * 'b>), kept under *2
    reqsOf (tr, tupleHead (List.length ts)) ts
  | _ -> false

/// The trait's other parameters as the impl for a type determines them (Iter on list<int>: [int]),
/// when the type's head has an impl of a trait with several (0017).
and private implParams (cx: Cx) (tr: string) (t: Ty) : option<list<Ty>> =
  match prune cx.v t with
  | TCon(n, args) ->
    match Map.tryFind (tr, n) cx.implOthers.Value with
    | Some os -> Some(List.map (substGen cx.v args) os)
    | None -> None
  | TTuple ts ->
    match Map.tryFind (tr, tupleHead (List.length ts)) cx.implOthers.Value with
    | Some os -> Some(List.map (substGen cx.v ts) os)
    | None -> None
  | _ -> None

/// Makes two types the same, with the program's impls.
and unify (cx: Cx) (a: Ty) (b: Ty) : unit / <Mismatched, Fails> =
  Types.Unify.unify cx.v { userImpl = userImpl; implParams = implParams } cx a b

/// Makes two rows the same.
let unifyRow (cx: Cx) (a: Ty) (b: Ty) : unit / <Mismatched, Fails> =
  Types.Unify.unifyRow cx.v { userImpl = userImpl; implParams = implParams } cx a b

/// Whether two types unify (their bindings kept when they do, and what binding was done before a
/// miss kept too, as the F# compiler has it).
let unifies (cx: Cx) (a: Ty) (b: Ty) : bool / Fails =
  let attempt () =
    unify cx a b
    true
  handle attempt () with
  | Mismatched.throw _, _ -> false

let show (cx: Cx) (t: Ty) : string = Types.Show.show cx.v t

/// Effects as text: Yield<int>, Log.
let showEffects (cx: Cx) (ls: list<Ty>) : string = Types.Unify.showEffects cx.v ls

/// A row's effects as text: Yield<int>, Log.
let effectsText (cx: Cx) (row: Ty) : string = String.join ", " (List.map (show cx) (fst (rowParts cx.v row)))

/// Makes the actual type the expected one, or fails saying what (`what: expected T, got U`), with
/// what newcomers write explained.
let expect (cx: Cx) (what: string) (expected: Ty) (actual: Ty) : unit / Fails =
  handle unify cx expected actual with
  | Mismatched.throw m, _ ->
    match m with
    | Differ ->
      // what newcomers write: a literal is a kinded variable, so the names are compared as shown
      let extra = Types.Unify.extraEffects cx.v expected actual
      let hint =
        match (prune cx.v expected, prune cx.v actual) with
        | (TCon("array", _), TCon("span", _)) -> ": Array.ofSpan copies it"
        | _ when not (List.isEmpty extra) -> $": this function performs {showEffects cx extra}, and one without it is expected here"
        | _ ->
          let e = show cx expected
          let a = show cx actual
          if Set.contains e nums && Set.contains a nums then
            $": numbers don't convert on their own; write {e} x"
          else if e = "string" && Set.contains a nums then
            ": interpolate it, $\"{x}\""
          else if e = "char" && a = "string" then
            ": a char literal is 'a', in single quotes"
          else if e = "bool" && Set.contains a nums then
            ": a number isn't a condition; compare it, x <> 0"
          else
            ""
      fail $"{what}: expected {show cx expected}, got {show cx actual}{hint}"
    | NoImpl("Share", t) -> fail $"{what}: {show cx t} can't be shared between threads (it isn't Share)"
    | NoImpl(tr, t) ->
      let tuple =
        match prune cx.v t with
        | TTuple xs when String.startsWith "argument 1 of '" what ->
          let f = String.sub what 15 (String.length what - 16)
          $"; if '{f}' takes its {List.length xs} arguments one by one, write {f} a b, not {f} (a, b)"
        | TCon _ when tr = "Iter" ->
          $"; list, array, Buffer, span, string, option, Map, Set, HashMap, Seq and Range do, and impl Iter<{show cx t}, <element>> = let forEach c f = … adds yours"
        | TCon _ when not (List.contains tr [ "Share"; "Eq"; "Ord"; "Hash"; "Show"; "Add"; "Num" ]) -> $"; write impl {tr}<{show cx t}> = …"
        | _ -> ""
      fail $"{what}: {show cx t} does not implement {tr}{tuple}"

/// The rule a function must keep where none of its effects can be handled (given to C, run on
/// another thread): expected has none, actual is the function; an error says what it performs
/// (the rule's text, the effects after it).
let expectNoEffects (cx: Cx) (rule: string -> string) (what: string) (expected: Ty) (actual: Ty) : unit / Fails =
  match Types.Unify.extraEffects cx.v expected actual with
  | [] -> expect cx what expected actual
  | ls -> fail (rule (showEffects cx ls))

/// The function types along a type's results: its own and, when it returns a function, that one's,
/// and so on (where a row may be closed or opened without changing what's accepted).
let rec spine (cx: Cx) (t: Ty) : list<Ty> =
  match prune cx.v t with
  | TFun(a, b, r) -> TFun(a, b, r) :: spine cx b
  | _ -> []

/// Quantifies the unbound variables of a top-level function's type (binding them to TGen): type
/// variables first, then rows, so 'a, 'b name the types and 'e the effects. First a row variable
/// that only ends one of the rows along the result spine is closed (it stands for no effects
/// there: `unit -> unit / Yield<int>`, not `/ <Yield<int> | 'e>`); a reference opens it again
/// (Koka's close and open).
let generalize (cx: Cx) (t: Ty) : list<Kind> =
  let v = cx.v
  let rec count (i: int) (t: Ty) : int =
    match prune v t with
    | TVar j -> if i = j then 1 else 0
    | TCon(_, ts)
    | TTuple ts -> List.sumBy (count i) ts
    | TFun(a, b, row) -> count i a + count i b + count i row
    | TMeas(_, vs) -> List.sumBy (fun (x, _) -> count i x) vs
    | TGen _ -> 0
  let spines =
    match prune v t with
    | TTuple ts -> List.collect (spine cx) ts // a group of functions calling each other
    | _ -> spine cx t
  for f in spines do
    match f with
    | TFun(_, _, row) ->
      match prune v (snd (rowParts v row)) with
      | TVar i when count i t = 1 -> bind v i rowEmpty
      | _ -> ()
    | _ -> ()
  let found = Buffer.empty
  let foundKinds = Buffer.empty
  let seen (i: int) =
    let mutable s = false
    for j in 0 .. Buffer.length found - 1 do
      if found.[j] = i then
        s <- true
    s
  let rec go (t: Ty) =
    match prune v t with
    | TVar i ->
      if isFree v i && not (seen i) then
        let k = kindOf v i
        Buffer.push i found
        Buffer.push k foundKinds
        // what a trait's other parameters mention is the scheme's too ('c : Iter<'a>)
        for (_, ps) in Map.toList k.params do
          List.iter go ps
    | TCon(_, ts)
    | TTuple ts -> List.iter go ts
    | TFun(a, b, row) ->
      go a
      go b
      go row
    | TMeas(_, vs) -> List.iter (fun (x, _) -> go x) vs
    | TGen _ -> ()
  go t
  let all = List.zip (Array.toList (Buffer.toArray found)) (Array.toList (Buffer.toArray foundKinds))
  let types = List.filter (fun (_, k) -> not (isRowKind k)) all
  let rows = List.filter (fun (_, k) -> isRowKind k) all
  let ordered = List.append types rows
  List.iteri (fun n (i, _) -> bind v i (TGen n)) ordered
  let resolved (p: int * Kind) =
    let k = snd p
    { k with params = Map.map (fun _ ps -> List.map (resolve v) ps) k.params }
  List.map resolved ordered

/// A function type taking ps, without effects.
let funTy (ps: list<Ty>) (ret: Ty) : Ty = List.fold (fun acc p -> tfun p acc) ret (List.rev ps)

/// A function type taking ps whose body performs row: the last arrow has it, the others none
/// (giving a function some of its arguments does nothing).
let funTyRow (ps: list<Ty>) (ret: Ty) (row: Ty) : Ty =
  match List.rev ps with
  | [] -> ret
  | last :: before -> List.fold (fun acc p -> tfun p acc) (TFun(last, ret, row)) before

/// Splits a function type into its first n parameter types and the rest.
let rec peel (cx: Cx) (n: int) (t: Ty) : list<Ty> * Ty =
  match (n, prune cx.v t) with
  | (0, x) -> ([], x)
  | (_, TFun(a, b, _)) ->
    let (ps, r) = peel cx (n - 1) b
    (a :: ps, r)
  | _ -> panic "peel: not a function type"

// ------------------------------------------------------------ rows

/// Checks a body with its own row: a function's, a lambda's, a handled expression's (what it is,
/// for an error naming it).
/// What a when guard is, to the row check: it performs nothing.
let guardWhat = "a when guard"

let withRowAs (cx: Cx) (row: Ty) (what: string) (f: unit -> 'r / 'e) : 'r / 'e =
  let outer = cx.ctxRow.Value
  let outerWhat = cx.ctxWhat.Value
  cx.ctxRow.Value <- row
  cx.ctxWhat.Value <- what
  let r = f ()
  cx.ctxRow.Value <- outer
  cx.ctxWhat.Value <- outerWhat
  r

let withRow (cx: Cx) (row: Ty) (f: unit -> 'r / 'e) : 'r / 'e = withRowAs cx row "" f

/// A call performs what the function's row has: it joins the row of the body the call is in (a
/// closed row opened first: calling a function that performs less is fine).
let useRow (cx: Cx) (row: Ty) : unit / Fails =
  let v = cx.v
  let (ls, tail) = rowParts v row
  // each of the callee's effects met by the first one of its name here
  let within (here: list<Ty>) =
    let left = ref here
    for l in ls do
      match List.tryFindIndex (fun h -> labelName v h = labelName v l) left.Value with
      | Some i ->
        match (prune v l, prune v (List.item i left.Value)) with
        | (TCon(_, xs), TCon(_, ys)) when List.length xs = List.length ys -> List.iter2 (unify cx) xs ys
        | _ -> Mismatched.throw Differ
        left.Value <- List.removeAt i left.Value
      | None -> Mismatched.throw Differ
  let join () =
    match prune v tail with
    | TCon("$total", []) when List.isEmpty ls -> ()
    | TCon("$total", []) -> unifyRow cx (mkRow ls (fresh v kRow)) cx.ctxRow.Value
    | TVar a ->
      let (here, hereTail) = rowParts v cx.ctxRow.Value
      match prune v hereTail with
      // the callee's row ends in this row's own variable (a function calling itself under a
      // handle of an effect it performs): it's included when its effects are here
      | TVar b when a = b -> within here
      | _ -> unifyRow cx row cx.ctxRow.Value
    | _ -> unifyRow cx row cx.ctxRow.Value
  handle join () with
  | Mismatched.throw _, _ ->
    let here = fst (rowParts v cx.ctxRow.Value)
    // the same effect, handled here with other type arguments
    let sameName (l: Ty) =
      match List.tryFind (fun h -> labelName v h = labelName v l) here with
      | Some h -> Some(l, h)
      | None -> None
    match List.tryPick sameName ls with
    | Some(l, h) -> fail $"this performs {show cx l}, but the innermost handler here is for {show cx h}"
    | None when List.isEmpty ls -> fail "this call's effects can't be handled here: write the effects of the function it calls (/ E)"
    | None when cx.ctxWhat.Value = "" -> fail $"this performs {effectsText cx row}, which the function it's in can't (its type says what it performs)"
    | None when cx.ctxWhat.Value = guardWhat -> fail $"this performs {effectsText cx row}, but a when guard can't: match first, then perform in the case"
    | None -> fail $"this performs {effectsText cx row}, but {cx.ctxWhat.Value} can't: handle it inside (handle … with)"

// ------------------------------------------------------------ types as written

/// The type dyn Trait, once the trait's methods are known to allow it: each takes the value first
/// and doesn't mention its type anywhere else (so a call can pass the value it has).
let dynOf (cx: Cx) (tr: string) : Ty / Fails =
  for (_, m) in Map.toList cx.traitMethods.Value do
    if m.owner = tr && m.nparams > 1 then
      fail $"dyn {shortName tr} isn't possible: a trait with several type parameters has no dyn"
    if m.owner = tr then
      let rec mentions (t: Ty) =
        match t with
        | TGen 0 -> true
        | TCon(_, ts)
        | TTuple ts -> List.exists mentions ts
        | TFun(a, b, _) -> mentions a || mentions b
        | _ -> false
      let ok =
        match m.ty with
        | TFun(TGen 0, rest, _) -> not (mentions rest)
        | _ -> false
      if not ok then
        fail $"dyn {shortName tr} isn't possible: method '{m.name}' must take the value first and not mention its type elsewhere ({show cx m.ty})"
  TCon("dyn:" + tr, [])

// a type variable named in a function's annotations: the one the function has, else a new one
let private tyvar (cx: Cx) (name: string) (k: Kind) : Ty =
  match Map.tryFind name cx.tyvars.Value with
  | Some t -> t
  | None ->
    let t = fresh cx.v k
    cx.tyvars.Value <- Map.add name t cx.tyvars.Value
    t

// whether a string is digits only
let private isDigits (d: string) : bool =
  let mutable ok = String.length d > 0
  for i in 0 .. String.length d - 1 do
    if String.byte d i < u8 48 || String.byte d i > u8 57 then
      ok <- false
  ok

/// A written type as a type. tparams: Some names inside a type definition (they become TGen), None
/// in a function. A function type's effects: in a function's annotations, inferred (a row
/// variable); in a type definition, and in what crosses to C or another thread (pureArrows), none.
let rec toTyWith (cx: Cx) (pureArrows: bool) (tparams: option<list<string>>) (st: SType) : Ty / Fails =
  let toTy = toTyWith cx pureArrows
  match st with
  | STVar x ->
    match tparams with
    | Some ps ->
      match List.tryFindIndex (fun p -> p = x) ps with
      | Some i -> TGen i
      | None -> fail $"unknown type parameter '{x}"
    | None -> tyvar cx x kAny
  | STName("dyn", [ STName(tr, []) ]) ->
    match resolveWith cx (fun q -> Set.contains q cx.traitNames.Value) tr with
    | Some full -> dynOf cx full
    | None -> fail $"unknown trait '{tr}' in dyn {tr}"
  | STName("fixed", [ el; len ]) ->
    // fixed<T, N>: N elements of T inline. N is a positive number, part of the type (a type
    // variable only in the Fixed module, whose functions work for every N)
    let n =
      match len with
      | STName(d, []) when isDigits d ->
        let parsed : option<int> = Int.parse d
        match parsed with
        | Some k when k > 0 -> TCon($"{k}", [])
        | _ -> fail "fixed needs a positive number of elements, written as a literal"
      | STVar _ when cx.currentModule.Value = Some "Collections.Fixed" -> toTy tparams len
      | _ -> fail "fixed needs a positive number of elements, written as a literal"
    TCon("fixed", [ toTy tparams el; n ])
  | STName(d, []) when String.length d > 0 && String.byte d 0 >= u8 48 && String.byte d 0 <= u8 57 ->
    fail "only fixed takes a number as a type argument"
  | STName(n, args) ->
    let alias =
      match resolveWith cx (fun q -> Map.containsKey q cx.aliases.Value) n with
      | Some q when not (Map.containsKey q cx.types.Value) -> Some q
      | _ -> None
    match alias with
    | Some q ->
      // an alias: what it names, at these arguments
      let (npars, target) = Map.find q cx.aliases.Value
      if npars <> List.length args then
        fail $"type '{n}' expects {npars} type argument(s)"
      substGen cx.v (List.map (toTy tparams) args) target
    | None ->
      let n =
        match typeAlias n with
        | Some c -> c
        | None -> n
      let exists (q: string) = Set.contains q prims || Option.isSome (builtinCons q) || Map.containsKey q cx.types.Value
      let n =
        match resolveWith cx exists n with
        | Some q -> q
        | None -> n
      let measured =
        match args with
        | [ STMeasure _ ] -> true
        | _ -> false
      let arity =
        if Set.contains n nums && measured then
          1
        else if Set.contains n prims then
          0
        else
          match builtinCons n with
          | Some k -> k
          | None ->
            match Map.tryFind n cx.types.Value with
            | Some info -> info.npars
            | None -> fail $"unknown type '{n}'"
      if arity <> List.length args then
        fail $"type '{n}' expects {arity} type argument(s)"
      match (n, args) with
      | (_, [ m ]) when Set.contains n nums -> numWith cx.v n (toTy tparams m)
      | ("callback", _)
      | ("fnptr", _)
      | ("share", _) -> TCon(n, List.map (toTyWith cx true tparams) args)
      | _ -> TCon(n, List.map (toTy tparams) args)
  | STTuple ts -> TTuple(List.map (toTy tparams) ts)
  | STFun(a, STRow(b, labels, tail)) -> TFun(toTy tparams a, toTy tparams b, rowOf cx tparams labels tail)
  // a -> b -> c: giving a function its first arguments performs nothing; the last arrow has its
  // effects
  | STFun(a, STFun(b1, b2)) -> TFun(toTy tparams a, toTy tparams (STFun(b1, b2)), rowEmpty)
  | STFun(a, b) ->
    let row = if pureArrows || Option.isSome tparams then rowEmpty else fresh cx.v kRow
    TFun(toTy tparams a, toTy tparams b, row)
  | STRow _ -> fail "effects follow a function type's result (int -> unit / Log) or a function's (let f x : int / Log = …)"
  | STMeasure terms ->
    let units = List.filter (fun (_, isVar, _) -> not isVar) terms
    let vars = List.filter (fun (_, isVar, _) -> isVar) terms
    for (u, _, _) in units do
      if not (Set.contains u cx.measures.Value) then
        fail $"unknown unit of measure '{u}'; declare it with [<Measure>] type {u}"
    normal cx.v (TMeas(List.map (fun (u, _, e) -> (u, e)) units, List.map (fun (x, _, e) -> (toTy tparams (STVar x), e)) vars))

/// A written row: its effects (Log, Yield<int>), then the row variable it ends in, if any.
and rowOf (cx: Cx) (tparams: option<list<string>>) (labels: list<SType>) (tail: option<string>) : Ty / Fails =
  let label (l: SType) =
    match l with
    | STName(n, args) ->
      match resolveWith cx (fun q -> Map.containsKey q cx.effects.Value) n with
      | Some full ->
        let info = Map.find full cx.effects.Value
        if info.npars <> List.length args then
          fail $"effect '{n}' expects {info.npars} type argument(s)"
        TCon(full, List.map (toTyWith cx false tparams) args)
      | None when Map.containsKey n cx.types.Value || Set.contains n prims ->
        fail $"'{n}' is a type, not an effect: effects follow a function's result (int -> unit / Log)"
      | None -> fail $"unknown effect '{n}'"
    | _ -> fail "effects are named after a function's result: / Log, / <Log, Yield<int>>"
  let tailTy =
    match (tail, tparams) with
    | (None, _) -> rowEmpty
    | (Some x, Some _) -> fail $"a type's functions can't end their effects in a variable ('{x}) yet: write the effects they perform"
    | (Some x, None) ->
      match Map.tryFind x cx.tyvars.Value with
      | Some t ->
        if not (unifies cx (fresh cx.v kRow) t) then
          fail $"'{x} is a type here, so it can't stand for effects"
        t
      | None -> tyvar cx x kRow
  mkRow (List.map label labels) tailTy

let toTy (cx: Cx) (tparams: option<list<string>>) (st: SType) : Ty / Fails = toTyWith cx false tparams st

/// A trait method's type. One with function arguments (0025) has an ambient row, TGen after the
/// trait's parameters, shared by those arguments' arrows written without a row and by its own last
/// arrow: it performs what the functions it's given perform, and nothing of its own.
let methodType (cx: Cx) (tps: list<string>) (st: SType) : Ty / Fails =
  let rec takesFunction (st: SType) =
    match st with
    | STFun(STFun _, _) -> true
    | STFun(_, b) -> takesFunction b
    | _ -> false
  let ambient = TGen(List.length tps)
  let rec fn (own: bool) (st: SType) =
    match st with
    | STFun(a, STFun(b1, b2)) -> TFun(arg a, fn own (STFun(b1, b2)), rowEmpty)
    | STFun(_, STRow(_, labels, _)) when own && not (List.isEmpty labels) ->
      fail "a trait's method performs nothing of its own; its arguments' effects are its row"
    | STFun(a, STRow(b, labels, tail)) -> TFun(arg a, toTy cx (Some tps) b, rowOf cx (Some tps) labels tail)
    | STFun(a, b) -> TFun(arg a, toTy cx (Some tps) b, ambient)
    | _ -> toTy cx (Some tps) st
  and arg (a: SType) =
    match a with
    | STFun _ -> fn false a
    | _ -> toTy cx (Some tps) a
  if takesFunction st then fn true st else toTy cx (Some tps) st

/// Whether a trait method's type has an ambient row (methodType): TGen after its parameters.
let hasAmbient (cx: Cx) (tm: TraitMethod) : bool =
  let rec go (t: Ty) =
    match t with
    | TGen i when i = tm.nparams -> true
    | TFun(a, b, r) -> go a || go b || go (snd (rowParts cx.v r))
    | TCon(_, ts)
    | TTuple ts -> List.exists go ts
    | _ -> false
  go tm.ty

/// An annotation's type, or a new variable without one.
let annot (cx: Cx) (ann: option<SType>) : Ty / Fails =
  match ann with
  | Some st -> toTy cx None st
  | None -> fresh cx.v kAny

/// A function's annotated result, and its effects when they're written (`: int / Log`).
let annotRet (cx: Cx) (ret: option<SType>) : Ty * option<Ty> / Fails =
  match ret with
  | Some(STRow(t, labels, tail)) -> (toTy cx None t, Some(rowOf cx None labels tail))
  | _ -> (annot cx ret, None)

/// A global function used as a value: its own row (the arity-th arrow's) opened when closed (`/ <E
/// | 'e>` for `/ E`), so it goes where a function performing more is expected. The coercion is
/// marked (eff.open): Mono drops it where the rows came out equal, and Evidence adapts the
/// function to the larger row where they didn't.
let opened (cx: Cx) (arity: int) (c: CExpr) : CExpr =
  let v = cx.v
  let rec go (n: int) (t: Ty) =
    match prune v t with
    | TFun(a, b, row) when n = 1 ->
      let (ls, tail) = rowParts v row
      match prune v tail with
      | TCon("$total", []) -> Some(TFun(a, b, mkRow ls (fresh v kRow)))
      | _ -> None
    | TFun(a, b, row) when n > 1 -> Option.map (fun b2 -> TFun(a, b2, row)) (go (n - 1) b)
    | _ -> None
  match (if arity > 0 then go arity c.ty else None) with
  | Some t -> mk (CPrim("eff.open", [ c ])) t
  | None -> c

/// A scheme's type with new variables of its kinds, and the variables.
let instantiate (cx: Cx) (kinds: list<Kind>) (t: Ty) : Ty * list<Ty> =
  let v = cx.v
  let vars = List.map (fun (k: Kind) -> fresh v { k with params = Map.empty }) kinds
  let withParams (p: Ty * Kind) =
    match p with
    | (TVar i, k) when not (Map.isEmpty k.params) && isFree v i ->
      let k0 = kindOf v i
      setKind v i { k0 with params = Map.map (fun _ ps -> List.map (substGen v vars) ps) k.params }
    | _ -> ()
  // a kind's trait parameters may name the scheme's other variables ('c : Iter<'a>)
  List.iter withParams (List.zip vars kinds)
  (substGen v vars t, vars)

/// A user type applied to new type arguments, and the arguments.
let instType (cx: Cx) (name: string) : Ty * list<Ty> =
  let info = Map.find name cx.types.Value
  let args = List.init info.npars (fun _ -> fresh cx.v kAny)
  (TCon(name, args), args)

// ------------------------------------------------------------ constructors and records

let ctorName (cx: Cx) (c: string) : option<string> / Fails = resolveWith cx (fun q -> Map.containsKey q cx.ctors.Value) c

let isCtor (cx: Cx) (c: string) : bool / Fails = Option.isSome (ctorName cx c)

/// A union case's field types at the union's arguments.
let caseFields (cx: Cx) (u: string) (tag: int) (args: list<Ty>) : list<Ty> =
  match (Map.find u cx.types.Value).def with
  | UnionDef cs -> List.map (substGen cx.v args) (snd (List.item tag cs))
  | CUnionDef cs -> [ snd (List.item tag cs) ]
  | RecordDef _ -> []

/// A union's cases and how many fields each has.
let unionCases (cx: Cx) (u: string) : list<string * int> =
  match (Map.find u cx.types.Value).def with
  | UnionDef cs -> List.map (fun (n, ts) -> (n, List.length ts)) cs
  | CUnionDef cs -> List.map (fun (n, _) -> (n, 1)) cs
  | RecordDef _ -> []

/// A C union's cases ([<CLayout>] union, 0004): each case's name and its one field's type.
let cUnionCases (cx: Cx) (n: string) : option<list<string * Ty>> =
  match Map.tryFind n cx.types.Value with
  | Some { def = CUnionDef cs } -> Some cs
  | _ -> None

/// A record's fields.
let fieldsOf (cx: Cx) (r: string) : list<string * Ty> =
  match (Map.find r cx.types.Value).def with
  | RecordDef fs -> fs
  | UnionDef _
  | CUnionDef _ -> []

/// Whether a type is a record.
let isRecord (cx: Cx) (n: string) : bool =
  match Map.tryFind n cx.types.Value with
  | Some { def = RecordDef _ } -> true
  | _ -> false

let hasFields (cx: Cx) (given: list<string>) (r: string) : bool =
  let fs = fieldsOf cx r
  List.forall (fun f -> List.exists (fun (g, _) -> g = f) fs) given

/// Of the records some field names could mean, those in scope as a name would be (the current and
/// enclosing modules, then opens, global names and the auto-opened namespaces), from the nearest
/// scope that has any, in declaration order.
let inScope (cx: Cx) (candidates: list<string>) : list<string> =
  let order = List.concat [ List.map Some (enclosing cx); List.map Some cx.opens.Value; [ None ]; List.map Some autoOpens ]
  let ranked = List.choose (fun r -> Option.map (fun k -> (k, r)) (List.tryFindIndex (fun m -> m = beforeLastDot r) order)) candidates
  match ranked with
  | [] -> []
  | _ ->
    let nearest = List.min (List.map fst ranked)
    List.map snd (List.filter (fun (k, _) -> k = nearest) ranked)

/// The records with all these fields, in declaration order.
let recordsWith (cx: Cx) (given: list<string>) : list<string> =
  List.filter (hasFields cx given) (Array.toList (Buffer.toArray cx.records))

/// The error for fields that no record in scope has, naming a record out of scope that has them.
let noRecord (cx: Cx) (plainMessage: string) (given: list<string>) : 'a / Fails =
  match List.tryLast (recordsWith cx given) with
  | Some r when String.contains "." r ->
    // out of scope, so in a module
    let m = Option.get (beforeLastDot r)
    let what =
      match given with
      | [ f ] -> $"a field '{f}'"
      | _ -> "the fields " + quoted given
    fail $"no record in scope has {what}; {r} does: open {m}, or annotate (… : {r})"
  | _ -> fail plainMessage

/// The record a field of a value of unknown type belongs to: the latest in scope.
let fieldRecord (cx: Cx) (field: string) : option<string> = List.tryLast (inScope cx (recordsWith cx [ field ]))

/// The record a field read belongs to: the value's type's, else the latest in scope with it.
let recordOf (cx: Cx) (t: Ty) (field: string) : string / Fails =
  match prune cx.v t with
  | _ when field = "ToString" -> fail "there's no .ToString(): interpolate the value, $\"{x}\", which prints it through Show"
  | TCon(n, _) when isRecord cx n -> n
  | TCon("option", _) when field = "Value" ->
    fail "an option has no .Value: match on it (Some x -> …), or use Option.defaultValue d o, or Option.get o, which panics on None"
  | _ ->
    match fieldRecord cx field with
    | Some r -> r
    | None -> noRecord cx $"no record has a field '{field}'" [ field ]

/// Matches a constructor's arguments to its payload fields: `C`, `C x`, `C (x, y)` (tuple: an
/// argument's elements when it's a tuple; wild: an argument that stands for every field).
let ctorArgs (c: string) (args: list<'a>) (fields: list<Ty>) (tuple: 'a -> option<list<'a>>) (wild: 'a -> bool) : list<'a> / Fails =
  let n = List.length fields
  match (args, fields) with
  | ([], []) -> []
  | ([ a ], _) ->
    let parts = if n > 1 then tuple a else None
    match parts with
    | Some xs when List.length xs = n -> xs
    | _ ->
      if n > 1 && wild a then
        List.map (fun _ -> a) fields
      else if n = 1 then
        [ a ]
      else
        fail $"constructor '{c}' expects {n} argument(s)"
  | _ -> fail $"constructor '{c}' expects {n} argument(s)"

/// Non-variable parameters become new names matched against their pattern in the body.
let lowerParams (cx: Cx) (ps: list<Param>) (body: Expr) : list<string * option<SType>> * Expr / Fails =
  let name (i: int) (p: Param) =
    let plainName =
      match p.param.pat with
      | PIdent(x, None) -> if isCtor cx x then None else Some x
      | _ -> None
    match plainName with
    | Some x -> ((x, p.ann), None)
    | None ->
      let x = $"$p{i}"
      ((x, p.ann), Some(x, p.param))
  let named = List.mapi name ps
  let wrap (acc: Expr) (n: (string * option<SType>) * option<string * Pat>) =
    match snd n with
    | Some(x, p) -> plain (Match(plain (Var x), [ { pattern = p; guard = None; body = acc } ]))
    | None -> acc
  (List.map fst named, List.fold wrap body (List.rev named))
