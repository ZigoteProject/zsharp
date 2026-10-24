/// zs check: a program's modules checked in order, the library's first, and its diagnostics shown
/// as the terminal shows them, with how many of each (the F# compiler's Driver.checkModules and
/// Main's report).
open Diag.Diagnostic

/// A module as a check left it: its file and key (what its checked result is made from), whether
/// it's the library's, the functions it defines (each with how many type variables it's generic
/// over in its types), their Core (read when needed: a result restored from the cache keeps them
/// apart), and the modules before it whose interface it sees (by index).
type Unit = { file: string; key: string; library: bool; names: list<string * int>; funs: unit -> list<Core.Ir.FunDef>; sees: int -> bool }

/// A program checked: its modules (the library's, then the program's), each as the check left it,
/// the checker's context (its tables and diagnostics), what the packages give the link, and which
/// of the program's modules were checked rather than restored, with how long each took.
type Checked =
  { modules: list<Modules.Loaded>
    units: list<Unit>
    cx: Infer.Cx.Cx
    linked: Modules.Linked
    checkedNames: list<string>
    checkedCount: int
    restoreMs: float
    checkMs: float }

let private late : Infer.Cx.Late = { autoDerive = Infer.Decls.autoDerive }

let private inFile (m: Modules.Loaded) : Infer.Cx.InFile = { index = m.source.file; source = m.source; tokens = m.tree.tokens }

// ---- the checked modules' cache (0007): each module's result under a key of its source and of
// what it sees of the modules before it, in the user's cache directory

let private checkedFile (key: string) = Path.combine (Path.combine (Tools.cacheRoot ()) "checked") (key + ".bin")

let private funsFile (key: string) = Path.combine (Path.combine (Tools.cacheRoot ()) "checked") (key + ".funs.bin")

// a module's result under its key, when the cache has a whole one
let private loadChecked (key: string) : option<Infer.Snapshot.Saved> =
  match File.readAllBytes (checkedFile key) with
  | Ok bytes ->
    let read : result<Infer.Snapshot.Saved, string> = Binary.ofBytes bytes
    match read with
    | Ok saved when saved.key = key ->
      File.touch (checkedFile key) |> ignore
      Some saved
    | _ -> None
  | Error _ -> None

// a module's functions, as its result keeps them apart
let private loadFuns (key: string) : list<Core.Ir.FunDef> =
  match File.readAllBytes (funsFile key) with
  | Ok bytes ->
    let read : result<list<Core.Ir.FunDef>, string> = Binary.ofBytes bytes
    Result.defaultValue [] read
  | Error _ -> []

// the functions a module defines, by how many type variables each is generic over in its types
let private namesOf (funs: list<Core.Ir.FunDef>) : list<string * int> = List.map (fun (f: Core.Ir.FunDef) -> (f.name, f.ngen - f.rows)) funs

// checks the modules in order (the library's, then the program's), each from the cache when its
// key is there and no module before it had an error
let private checkModules (cx: Infer.Cx.Cx) (lib: list<Modules.Loaded>) (prog: list<Modules.Loaded>) : list<Unit> * list<string> * int * float * float =
  let all = Array.ofList (List.append lib prog)
  let libCount = List.length lib
  let names (ms: list<Modules.Loaded>) = List.choose (fun (m: Modules.Loaded) -> m.modName) ms
  let impls (ms: list<Modules.Loaded>) = List.collect (fun (m: Modules.Loaded) -> m.impls) ms
  // what every program module's key has: the program's modules and explicit impls
  let programKey = Tools.hashOf (List.concat [ [ "program" ]; names prog; List.map (fun (t, n) -> t + " " + n) (impls prog) ])
  let compiler = Tools.compilerId ()
  let use = Tools.cacheOn ()
  // each program module sees the library and the modules it uses, directly or not
  let indexOf = Map.ofList (List.mapi (fun i (m: Modules.Loaded) -> (Path.getFullPath m.path, i)) (Array.toList all))
  let seenBy = Buffer.create (Array.length all) Set.empty
  for i in libCount .. Array.length all - 1 do
    let m = all.[i]
    let reach (acc: Set<int>) (u: string) =
      match Map.tryFind (Path.getFullPath u) indexOf with
      | Some j -> Set.union (Set.add j acc) seenBy.[j]
      | None -> acc
    seenBy.[i] <- List.fold reach Set.empty m.uses
  let ifaces = Buffer.create (Array.length all) ""
  let seens = Buffer.create (Array.length all) ""
  let units = Buffer.empty
  let fresh = Buffer.empty
  let ok = ref true
  let mutable restoreNs = u64 0
  let mutable checkNs = u64 0
  for i in 0 .. Array.length all - 1 do
    let m = all.[i]
    let library = i < libCount
    let sees (j: int) = library || j < libCount || Set.contains j seenBy.[i]
    if i = libCount then
      // the program's modules and explicit impls, as at the start
      for n in names prog do
        for e in Infer.Cx.withEnclosing n do
          cx.moduleNames.Value <- Set.add e cx.moduleNames.Value
      cx.manualImpls.Value <- Set.union cx.manualImpls.Value (Set.ofList (impls prog))
      for p in prog do
        for (n, why) in p.skippedC do
          cx.skippedC.Value <- Map.add n why cx.skippedC.Value
    let before = List.init i (fun j -> if sees j then "I" + ifaces.[j] else "G" + seens.[j])
    let key = Tools.hashOf (List.concat [ [ compiler; "check"; Path.getFullPath m.path; Option.defaultValue "" m.modName; m.source.text; m.imported; (if library then "library" else programKey) ]; before ])
    let start = Diagnostics.Stopwatch.startNew ()
    match (if use && ok.Value then loadChecked key else None) with
    | Some saved ->
      Infer.Snapshot.restore cx saved.iface
      let now = m.source.file
      for h in saved.hovers do
        Buffer.push (Infer.Snapshot.movedHover saved.index now h) cx.hovers
      for d in saved.warnings do
        Buffer.push (Infer.Snapshot.movedDiagnostic saved.index now d) cx.diagnostics
      match saved.mainAt with
      | Some at -> cx.mainAt.Value <- Some(Infer.Snapshot.moved saved.index now at)
      | None -> ()
      ifaces.[i] <- saved.ifaceHash
      seens.[i] <- saved.seenHash
      Buffer.push { file = m.path; key = key; library = library; names = saved.names; funs = (fun () -> loadFuns key); sees = sees } units
      restoreNs <- restoreNs + start.ElapsedNanoseconds
    | None ->
      Buffer.push m fresh
      let marks = Infer.Snapshot.marks cx
      let mainBefore = cx.mainAt.Value
      let errorsBefore = Array.length (Array.filter (fun (d: Diagnostic) -> d.severity = Err) (Buffer.toArray cx.diagnostics))
      Infer.Decls.check cx (inFile m) m.modName m.decls |> ignore
      let errorsAfter = Array.length (Array.filter (fun (d: Diagnostic) -> d.severity = Err) (Buffer.toArray cx.diagnostics))
      // no errors so far: results are kept
      ok.Value <- ok.Value && errorsAfter = errorsBefore
      let own = List.init (Buffer.length cx.funs - marks.mfuns) (fun k -> cx.funs.[marks.mfuns + k])
      match (if ok.Value then Infer.Snapshot.written cx marks else None) with
      | Some(iface, funs, hovers, warnings) ->
        let ifaceHash = Xxhash.hex (Binary.toBytes iface)
        let seenHash = Xxhash.hex (Binary.toBytes (Infer.Snapshot.seen iface))
        ifaces.[i] <- ifaceHash
        seens.[i] <- seenHash
        let mainAt = if cx.mainAt.Value <> mainBefore then cx.mainAt.Value else None
        let saved : Infer.Snapshot.Saved = { key = key; iface = iface; ifaceHash = ifaceHash; seenHash = seenHash; names = namesOf funs; hovers = hovers; warnings = warnings; mainAt = mainAt; index = m.source.file }
        if use then
          Tools.writeWhole (funsFile key) (Binary.toBytes funs)
          Tools.writeWhole (checkedFile key) (Binary.toBytes saved)
        Buffer.push { file = m.path; key = key; library = library; names = namesOf funs; funs = (fun () -> funs); sees = sees } units
      | None ->
        // not kept, nor anything after it: hashes no key can match
        ok.Value <- false
        ifaces.[i] <- "never " + key
        seens.[i] <- "never " + key
        Buffer.push { file = m.path; key = key; library = library; names = namesOf own; funs = (fun () -> own); sees = sees } units
      checkNs <- checkNs + start.ElapsedNanoseconds
  // which of the program's modules were checked (by file name), so a test can tell
  let progPaths = Set.ofList (List.map (fun (m: Modules.Loaded) -> m.path) prog)
  let checkedNames = List.choose (fun (m: Modules.Loaded) -> if Set.contains m.path progPaths then Some(Path.getFileName m.path) else None) (Array.toList (Buffer.toArray fresh))
  let ms (ns: u64) = float (int ns) / 1000000.0
  (Array.toList (Buffer.toArray units), checkedNames, Buffer.length fresh, ms restoreNs, ms checkNs)

/// Checks the program whose main file is mainPath, an editor's open file from its text in texts;
/// what stops it before checking (a file it can't read, an import cycle, syntax errors) is Error,
/// with the sources the errors are in. chip: a microcontroller's build (no Std); hostBuild: a
/// build for this machine (pkg-config's flags).
let programWith (texts: Map<string, string>) (mainPath: string) (requireMain: bool) (collect: bool) (chip: bool) (target: string) : result<Checked, array<Diagnostic> * list<Syntax.Source.Source>> =
  let noPlace : Span = { file = -1; offset = -1; length = -1 }
  // a file of a library itself: that library, checked on its own
  let ownLibrary = Modules.libraryRootOf mainPath
  match Modules.library texts (Option.defaultValue (Modules.libraryDir ()) ownLibrary) (not chip) with
  | Error e -> Error([| error noPlace e |], [])
  | Ok lib ->
    let none : Modules.Linked = { cflags = []; links = [] }
    let loaded = if Option.isSome ownLibrary then Ok([], none) else Modules.program texts (List.length lib) mainPath target
    match loaded with
    | Error(d, src) -> Error([| d |], Option.toList src)
    | Ok(prog, linked) ->
      let all = List.append lib prog
      let sources = List.map (fun (m: Modules.Loaded) -> m.source) all
      // a syntax error stops before checking: the first one, as the F# compiler's parser stops
      // there (the ones after it may be its consequences)
      match List.tryFind (fun (m: Modules.Loaded) -> Array.length m.errors > 0) all with
      | Some m -> Error([| m.errors.[0] |], sources)
      | None ->
        let names (ms: list<Modules.Loaded>) = List.choose (fun (m: Modules.Loaded) -> m.modName) ms
        let impls (ms: list<Modules.Loaded>) = List.collect (fun (m: Modules.Loaded) -> m.impls) ms
        // a microcontroller has no operating system, so no Std
        let unavailable = if chip then Set.ofList (List.map (fun (f: string) -> String.replace f "/" ".") Modules.stdFiles) else Set.empty
        let cx = Infer.Cx.create (requireMain && Option.isNone ownLibrary) collect (names lib) (impls lib) unavailable late (inFile (List.head lib))
        let (units, checkedNames, checkedCount, restoreMs, checkMs) = checkModules cx lib prog
        Infer.Decls.finish cx
        Ok { modules = all; units = units; cx = cx; linked = linked; checkedNames = checkedNames; checkedCount = checkedCount; restoreMs = restoreMs; checkMs = checkMs }

/// Checks the program whose main file is mainPath, from the files on disk.
let program (mainPath: string) (requireMain: bool) (collect: bool) (chip: bool) (target: string) = programWith Map.empty mainPath requireMain collect chip target

/// A function's checked Core with every type settled, as the passes take it (a variable bound in
/// the context followed, a free one defaulted, rows in canonical order).
let settle (cx: Infer.Cx.Cx) (f: Core.Ir.FunDef) : Core.Ir.FunDef =
  let v = cx.v
  let s (t: Types.Ty.Ty) = Types.Norm.resolve v t
  { f with pars = List.map (fun (x, t) -> (x, s t)) f.pars; ret = s f.ret; row = Types.Norm.resolveRow v f.row; body = Core.Ir.mapTypes s f.body }

// the program with these functions
let private programFrom (c: Checked) (all: list<Core.Ir.FunDef>) : Core.Program.Program =
  let cx = c.cx
  let v = cx.v
  let settle (t: Types.Ty.Ty) = Types.Norm.resolve v t
  let pars (ps: list<string * Types.Ty.Ty>) = List.map (fun (x, t) -> (x, settle t)) ps
  let fn (f: Core.Ir.FunDef) : Core.Ir.FunDef =
    { f with pars = pars f.pars; ret = settle f.ret; row = Types.Norm.resolveRow v f.row; body = Core.Ir.mapTypes settle f.body }
  let ex (e: Core.Ir.Export) : Core.Ir.Export = { e with pars = List.map settle e.pars; ret = settle e.ret }
  let ext (x: Core.Ir.ExternSig) : Core.Ir.ExternSig = { x with pars = List.map settle x.pars; ret = settle x.ret }
  { types = cx.types.Value
    externs = Map.map (fun _ x -> ext x) cx.externs.Value
    funs = List.map fn all
    traitMethods = cx.traitMethods.Value
    effects = cx.effects.Value
    impls = cx.impls.Value
    exports = List.map ex (Array.toList (Buffer.toArray cx.exports))
    values = Array.toList (Buffer.toArray cx.valueList)
    tests = Array.toList (Buffer.toArray cx.tests)
    clayouts = cx.clayouts.Value
    targets = cx.targets.Value
    memberNames = Map.map (fun _ (ms: list<string * Infer.Cx.MemberInfo>) -> List.map fst ms) cx.members.Value }

/// The program the passes after checking take: the context's tables and every module's functions,
/// every type settled.
let programOf (c: Checked) : Core.Program.Program = programFrom c (List.collect (fun (u: Unit) -> u.funs ()) c.units)

/// The program's tables without its functions (a build by module reads each module's when it
/// needs them).
let tablesOf (c: Checked) : Core.Program.Program = programFrom c []

/// Prints diagnostics and, when there's more than one, how many of each; false when they fail the
/// command (an error, or a warning under strict).
let report (sources: list<Syntax.Source.Source>) (ds: array<Diagnostic>) (strict: bool) : bool =
  let byIndex = Map.ofList (List.map (fun (s: Syntax.Source.Source) -> (s.file, s)) sources)
  let none = Syntax.Source.make -1 "" ""
  let sourceOf (i: int) =
    match Map.tryFind i byIndex with
    | Some s -> s
    | None -> none
  Diag.Render.print sourceOf ds
  let errors = Array.length (Array.filter (fun (d: Diagnostic) -> d.severity = Err) ds)
  let warnings = Array.length ds - errors
  let count (n: int) (what: string) = if n = 1 then "1 " + what else $"{n} {what}s"
  let counted =
    match (errors, warnings) with
    | (0, 0) -> ""
    | (e, 0) -> if e > 1 then count e "error" else ""
    | (0, w) -> if w > 1 then count w "warning" else ""
    | (e, w) -> count e "error" + ", " + count w "warning"
  if strict && warnings > 0 && errors = 0 then
    eprintln (count warnings "warning" + ", " + (if warnings = 1 then "an error" else "errors") + " under --strict")
  else if counted <> "" then
    eprintln counted
  errors = 0 && not (strict && warnings > 0)

/// zs check file: every error and warning, nothing built; 0 when it passes.
let run (mainPath: string) (strict: bool) : int =
  match program mainPath true true false "" with
  | Error(ds, sources) -> if report sources ds strict then 0 else 1
  | Ok c ->
    let sources = List.map (fun (m: Modules.Loaded) -> m.source) c.modules
    if report sources (Buffer.toArray c.cx.diagnostics) strict then 0 else 1
