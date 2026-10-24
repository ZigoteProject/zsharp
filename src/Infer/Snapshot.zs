/// A module's checked result, for the cache that keeps each module between builds (0007): what
/// checking it wrote to the context's tables (their new entries, and the members it gave types),
/// its functions' Core, its hovers and its warnings, every type in them settled. A module whose
/// interface still has a free type variable (one a later module may decide) isn't kept.
open Types.Ty
open Core.Ir
open Syntax.Ast
open Diag.Diagnostic
open Infer.Cx

/// What the modules after a module see of it: the entries it wrote, table by table.
[<Derive(Binary)>]
type Iface =
  { types: list<string * TypeInfo>
    ctors: list<string * (string * int)>
    records: list<string>
    recordDefaults: list<string * list<option<Expr>>>
    ctorFieldNames: list<string * list<option<string>>>
    members: list<string * list<string * MemberInfo>>
    memberTypeNames: list<string>
    traitMethods: list<string * TraitMethod>
    traitAliases: list<string * string>
    traitNames: list<string>
    effects: list<string * EffectInfo>
    effectOps: list<string * (string * int)>
    impls: list<(string * string) * Map<string, string>>
    implRequires: list<(string * string) * list<Set<string>>>
    implOthers: list<(string * string) * list<Ty>>
    derives: list<string * list<Definition>>
    deriveGroups: list<string * list<string>>
    aliases: list<string * (int * Ty)>
    deriveModules: list<string * option<string>>
    activePatterns: list<string * (string * bool * int)>
    apCtors: list<string>
    autoDerived: list<string * string>
    optOut: list<string * string>
    globals: list<string * Global>
    externs: list<string * ExternSig>
    measures: list<string>
    clayouts: list<string>
    targets: list<string * list<string>>
    exports: list<Export>
    tests: list<string>
    consts: list<string * Expr>
    globalValues: list<string * Ty>
    valueList: list<string * string>
    literalRecords: list<(string * int) * string>
    privates: list<string * option<string>>
    moduleNames: list<string>
    mainNested: list<string>
    nestedModules: list<string>
    enclosingOf: list<string * list<string>> }

/// What the modules that don't name a module still see of it: its impls and automatic derives
/// for traits and types neither of which are its own, and the members it gave others' types.
[<Derive(Binary)>]
type Seen =
  { simpls: list<(string * string) * Map<string, string>>
    srequires: list<(string * string) * list<Set<string>>>
    sothers: list<(string * string) * list<Ty>>
    sderived: list<string * string>
    smembers: list<string * list<string * MemberInfo>> }

/// A module's result as the cache keeps it: under its key; its interface and the hashes of what
/// the modules after it see (all of it, or only what's seen without naming it); its functions'
/// names with how many type variables each is generic over in its types; its hovers, warnings
/// and main's place, in the file it was checked as (`index`).
[<Derive(Binary)>]
type Saved =
  { key: string
    iface: Iface
    ifaceHash: string
    seenHash: string
    names: list<string * int>
    hovers: list<Hover>
    warnings: list<Diagnostic>
    mainAt: option<Span>
    index: int }

/// What the context held before a module: its tables, and how long its lists were.
type Marks =
  { mtypes: Map<string, TypeInfo>
    mctors: Map<string, string * int>
    mrecords: int
    mrecordDefaults: Map<string, list<option<Expr>>>
    mctorFieldNames: Map<string, list<option<string>>>
    mmembers: Map<string, list<string * MemberInfo>>
    mmemberTypeNames: Set<string>
    mtraitMethods: Map<string, TraitMethod>
    mtraitAliases: Map<string, string>
    mtraitNames: Set<string>
    meffects: Map<string, EffectInfo>
    meffectOps: Map<string, string * int>
    mimpls: Map<string * string, Map<string, string>>
    mimplRequires: Map<string * string, list<Set<string>>>
    mimplOthers: Map<string * string, list<Ty>>
    mderives: Map<string, list<Definition>>
    mderiveGroups: Map<string, list<string>>
    maliases: Map<string, int * Ty>
    mderiveModules: Map<string, option<string>>
    mactivePatterns: Map<string, string * bool * int>
    mapCtors: Set<string>
    mautoDerived: Set<string * string>
    moptOut: Set<string * string>
    mglobals: Map<string, Global>
    mexterns: Map<string, ExternSig>
    mfuns: int
    mmeasures: Set<string>
    mclayouts: Set<string>
    mtargets: Map<string, list<string>>
    mexports: int
    mtests: int
    mconsts: Map<string, Expr>
    mglobalValues: Map<string, Ty>
    mvalueList: int
    mliteralRecords: Map<string * int, string>
    mprivates: Map<string, option<string>>
    mmoduleNames: Set<string>
    mmainNested: Set<string>
    mnestedModules: Set<string>
    menclosingOf: Map<string, list<string>>
    mhovers: int
    mdiagnostics: int }

/// The context's tables now, for what a module checked next writes.
let marks (cx: Cx) : Marks =
  { mtypes = cx.types.Value
    mctors = cx.ctors.Value
    mrecords = Buffer.length cx.records
    mrecordDefaults = cx.recordDefaults.Value
    mctorFieldNames = cx.ctorFieldNames.Value
    mmembers = cx.members.Value
    mmemberTypeNames = cx.memberTypeNames.Value
    mtraitMethods = cx.traitMethods.Value
    mtraitAliases = cx.traitAliases.Value
    mtraitNames = cx.traitNames.Value
    meffects = cx.effects.Value
    meffectOps = cx.effectOps.Value
    mimpls = cx.impls.Value
    mimplRequires = cx.implRequires.Value
    mimplOthers = cx.implOthers.Value
    mderives = cx.derives.Value
    mderiveGroups = cx.deriveGroups.Value
    maliases = cx.aliases.Value
    mderiveModules = cx.deriveModules.Value
    mactivePatterns = cx.activePatterns.Value
    mapCtors = cx.apCtors.Value
    mautoDerived = cx.autoDerived.Value
    moptOut = cx.optOut.Value
    mglobals = cx.globals.Value
    mexterns = cx.externs.Value
    mfuns = Buffer.length cx.funs
    mmeasures = cx.measures.Value
    mclayouts = cx.clayouts.Value
    mtargets = cx.targets.Value
    mexports = Buffer.length cx.exports
    mtests = Buffer.length cx.tests
    mconsts = cx.consts.Value
    mglobalValues = cx.globalValues.Value
    mvalueList = Buffer.length cx.valueList
    mliteralRecords = cx.literalRecords.Value
    mprivates = cx.privates.Value
    mmoduleNames = cx.moduleNames.Value
    mmainNested = cx.mainNested.Value
    mnestedModules = cx.nestedModules.Value
    menclosingOf = cx.enclosingOf.Value
    mhovers = Buffer.length cx.hovers
    mdiagnostics = Buffer.length cx.diagnostics }

// the entries of a table that weren't in it before (a module defines a name once)
let private added (before: Map<'k, 'v>) (after: Map<'k, 'v>) : list<'k * 'v> =
  Map.fold (fun (acc: list<'k * 'v>) k v -> if Map.containsKey k before then acc else (k, v) :: acc) [] after |> List.rev

// the entries that are new or other than before (a type's members grow in later modules)
let private changed (before: Map<'k, 'v>) (after: Map<'k, 'v>) : list<'k * 'v> =
  let differs k v =
    match Map.tryFind k before with
    | Some old -> old <> v
    | None -> true
  Map.fold (fun (acc: list<'k * 'v>) k v -> if differs k v then (k, v) :: acc else acc) [] after |> List.rev

let private newIn (before: Set<'a>) (after: Set<'a>) : list<'a> = Set.toList (Set.difference after before)

let private since (b: Buffer<'a>) (from: int) : list<'a> = List.init (Buffer.length b - from) (fun i -> b.[from + i])

// ---- types settled

// whether a type still has a free variable
let rec private hasFree (v: Types.Vars.Vars) (t: Ty) : bool =
  match Types.Vars.prune v t with
  | TVar _ -> true
  | TCon(_, args) -> List.exists (hasFree v) args
  | TTuple ts -> List.exists (hasFree v) ts
  | TFun(a, b, r) -> hasFree v a || hasFree v b || hasFree v r
  | TMeas(_, vs) -> List.exists (fun (x, _) -> hasFree v x) vs
  | TGen _ -> false

let private settleKind (s: Ty -> Ty) (k: Kind) : Kind = { k with params = Map.map (fun _ ts -> List.map s ts) k.params }

let private settleInfo (s: Ty -> Ty) (i: TypeInfo) : TypeInfo =
  match i.def with
  | RecordDef fs -> { i with def = RecordDef(List.map (fun (f, t) -> (f, s t)) fs) }
  | UnionDef cs -> { i with def = UnionDef(List.map (fun (c, ts) -> (c, List.map s ts)) cs) }

let private settleGlobal (s: Ty -> Ty) (g: Global) : Global = { g with ty = s g.ty; kinds = List.map (settleKind s) g.kinds }

let private settleEffect (s: Ty -> Ty) (e: EffectInfo) : EffectInfo = { e with ops = List.map (fun (o: EffectOp) -> { o with pars = List.map s o.pars; ret = s o.ret }) e.ops }

/// A function's Core with its types settled.
let settleFun (v: Types.Vars.Vars) (f: FunDef) : FunDef =
  let s (t: Ty) = Types.Norm.resolve v t
  { f with pars = List.map (fun (x, t) -> (x, s t)) f.pars; ret = s f.ret; row = Types.Norm.resolveRow v f.row; body = mapTypes s f.body }

// every type of the interface, so it can be told whether one is still free
let private ifaceTypes (i: Iface) : list<Ty> =
  let ofKind (k: Kind) = List.concat (List.map snd (Map.toList k.params))
  let ofInfo (t: TypeInfo) =
    match t.def with
    | RecordDef fs -> List.map snd fs
    | UnionDef cs -> List.collect snd cs
  let parts =
    [ List.collect (fun (_, t) -> ofInfo t) i.types
      List.map (fun (p: string * TraitMethod) -> (snd p).ty) i.traitMethods
      List.collect (fun (p: string * EffectInfo) -> List.collect (fun (o: EffectOp) -> o.ret :: o.pars) (snd p).ops) i.effects
      List.collect snd i.implOthers
      List.map (fun (p: string * (int * Ty)) -> snd (snd p)) i.aliases
      List.collect (fun (p: string * Global) -> (snd p).ty :: List.collect ofKind (snd p).kinds) i.globals
      List.collect (fun (p: string * ExternSig) -> (snd p).ret :: (snd p).pars) i.externs
      List.collect (fun (e: Export) -> e.ret :: e.pars) i.exports
      List.map snd i.globalValues ]
  List.concat parts

/// What checking a module wrote since marks, its types settled; None when it can't be kept (a type
/// of its interface still free). With its functions' Core and its hovers and warnings.
let written (cx: Cx) (m: Marks) : option<Iface * list<FunDef> * list<Hover> * list<Diagnostic>> =
  let v = cx.v
  let s (t: Ty) = Types.Norm.resolve v t
  let iface0 : Iface =
    { types = added m.mtypes cx.types.Value
      ctors = added m.mctors cx.ctors.Value
      records = since cx.records m.mrecords
      recordDefaults = added m.mrecordDefaults cx.recordDefaults.Value
      ctorFieldNames = added m.mctorFieldNames cx.ctorFieldNames.Value
      members = changed m.mmembers cx.members.Value
      memberTypeNames = newIn m.mmemberTypeNames cx.memberTypeNames.Value
      traitMethods = added m.mtraitMethods cx.traitMethods.Value
      traitAliases = added m.mtraitAliases cx.traitAliases.Value
      traitNames = newIn m.mtraitNames cx.traitNames.Value
      effects = added m.meffects cx.effects.Value
      effectOps = added m.meffectOps cx.effectOps.Value
      impls = added m.mimpls cx.impls.Value
      implRequires = changed m.mimplRequires cx.implRequires.Value
      implOthers = added m.mimplOthers cx.implOthers.Value
      derives = added m.mderives cx.derives.Value
      deriveGroups = added m.mderiveGroups cx.deriveGroups.Value
      aliases = added m.maliases cx.aliases.Value
      deriveModules = added m.mderiveModules cx.deriveModules.Value
      activePatterns = added m.mactivePatterns cx.activePatterns.Value
      apCtors = newIn m.mapCtors cx.apCtors.Value
      autoDerived = newIn m.mautoDerived cx.autoDerived.Value
      optOut = newIn m.moptOut cx.optOut.Value
      globals = changed m.mglobals cx.globals.Value
      externs = added m.mexterns cx.externs.Value
      measures = newIn m.mmeasures cx.measures.Value
      clayouts = newIn m.mclayouts cx.clayouts.Value
      targets = added m.mtargets cx.targets.Value
      exports = since cx.exports m.mexports
      tests = since cx.tests m.mtests
      consts = added m.mconsts cx.consts.Value
      globalValues = added m.mglobalValues cx.globalValues.Value
      valueList = since cx.valueList m.mvalueList
      literalRecords = added m.mliteralRecords cx.literalRecords.Value
      privates = added m.mprivates cx.privates.Value
      moduleNames = newIn m.mmoduleNames cx.moduleNames.Value
      mainNested = newIn m.mmainNested cx.mainNested.Value
      nestedModules = newIn m.mnestedModules cx.nestedModules.Value
      enclosingOf = added m.menclosingOf cx.enclosingOf.Value }
  if List.exists (hasFree v) (ifaceTypes iface0) then
    None
  else
    let iface =
      { iface0 with
          types = List.map (fun (n, t) -> (n, settleInfo s t)) iface0.types
          traitMethods = List.map (fun (p: string * TraitMethod) -> (fst p, { snd p with ty = s (snd p).ty })) iface0.traitMethods
          effects = List.map (fun (n, e) -> (n, settleEffect s e)) iface0.effects
          implOthers = List.map (fun (k, ts) -> (k, List.map s ts)) iface0.implOthers
          aliases = List.map (fun (p: string * (int * Ty)) -> (fst p, (fst (snd p), s (snd (snd p))))) iface0.aliases
          globals = List.map (fun (n, g) -> (n, settleGlobal s g)) iface0.globals
          externs = List.map (fun (p: string * ExternSig) -> (fst p, { snd p with pars = List.map s (snd p).pars; ret = s (snd p).ret })) iface0.externs
          exports = List.map (fun (e: Export) -> { e with pars = List.map s e.pars; ret = s e.ret }) iface0.exports
          globalValues = List.map (fun (n, t) -> (n, s t)) iface0.globalValues }
    let funs = List.map (settleFun v) (since cx.funs m.mfuns)
    let hovers = List.map (fun (h: Hover) -> { h with ty = s h.ty }) (since cx.hovers m.mhovers)
    let warnings = List.filter (fun (d: Diagnostic) -> d.severity <> Err) (since cx.diagnostics m.mdiagnostics)
    Some(iface, funs, hovers, warnings)

/// What a module's interface shows the modules that don't name it.
let seen (i: Iface) : Seen =
  let own = Set.ofList (List.map fst i.types)
  let ownTraits = Set.ofList i.traitNames
  let others (k: string * string) =
    let (tr, t) = k
    not (Set.contains t own || Set.contains tr ownTraits)
  { simpls = List.filter (fun (k, _) -> others k) i.impls
    srequires = List.filter (fun (k, _) -> others k) i.implRequires
    sothers = List.filter (fun (k, _) -> others k) i.implOthers
    sderived = List.filter others i.autoDerived
    smembers = List.filter (fun (t, _) -> not (Set.contains t own)) i.members }

let private into (table: ref<Map<'k, 'v>>) (entries: list<'k * 'v>) = table.Value <- List.fold (fun m (k, v) -> Map.add k v m) table.Value entries

let private union (table: ref<Set<'a>>) (xs: list<'a>) = table.Value <- Set.union table.Value (Set.ofList xs)

let private push (b: Buffer<'a>) (xs: list<'a>) =
  for x in xs do
    Buffer.push x b

/// Puts a module's interface into the context, as checking it did.
let restore (cx: Cx) (i: Iface) : unit =
  into cx.types i.types
  into cx.ctors i.ctors
  push cx.records i.records
  into cx.recordDefaults i.recordDefaults
  into cx.ctorFieldNames i.ctorFieldNames
  into cx.members i.members
  union cx.memberTypeNames i.memberTypeNames
  into cx.traitMethods i.traitMethods
  into cx.traitAliases i.traitAliases
  union cx.traitNames i.traitNames
  into cx.effects i.effects
  into cx.effectOps i.effectOps
  into cx.impls i.impls
  into cx.implRequires i.implRequires
  into cx.implOthers i.implOthers
  into cx.derives i.derives
  into cx.deriveGroups i.deriveGroups
  into cx.aliases i.aliases
  into cx.deriveModules i.deriveModules
  into cx.activePatterns i.activePatterns
  union cx.apCtors i.apCtors
  union cx.autoDerived i.autoDerived
  union cx.optOut i.optOut
  into cx.globals i.globals
  into cx.externs i.externs
  union cx.measures i.measures
  union cx.clayouts i.clayouts
  into cx.targets i.targets
  push cx.exports i.exports
  push cx.tests i.tests
  into cx.consts i.consts
  into cx.globalValues i.globalValues
  push cx.valueList i.valueList
  into cx.literalRecords i.literalRecords
  into cx.privates i.privates
  union cx.moduleNames i.moduleNames
  union cx.mainNested i.mainNested
  union cx.nestedModules i.nestedModules
  into cx.enclosingOf i.enclosingOf

/// A hover, warning or place of a module checked as file `from`, in the file it is now.
let moved (from: int) (now: int) (at: Span) : Span = if at.file = from then { at with file = now } else at

let movedHover (from: int) (now: int) (h: Hover) : Hover = if h.file = from then { h with file = now } else h

let movedDiagnostic (from: int) (now: int) (d: Diagnostic) : Diagnostic =
  { d with at = moved from now d.at; notes = List.map (fun (n: Note) -> { n with at = moved from now n.at }) d.notes }
