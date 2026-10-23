/// zs check: a program's modules checked in order, the library's first, and its diagnostics shown
/// as the terminal shows them, with how many of each (the F# compiler's Driver.checkModules and
/// Main's report).
open Diag.Diagnostic

/// A program checked: its modules (the library's, then the program's) and the checker's context
/// (its tables, the functions' Core and the diagnostics).
type Checked = { modules: list<Modules.Loaded>; cx: Infer.Cx.Cx; linked: Modules.Linked }

let private late : Infer.Cx.Late = { autoDerive = Infer.Decls.autoDerive }

let private inFile (m: Modules.Loaded) : Infer.Cx.InFile = { index = m.source.file; source = m.source; tokens = m.tree.tokens }

/// Checks the program whose main file is mainPath, an editor's open file from its text in texts;
/// what stops it before checking (a file it can't read, an import cycle, syntax errors) is Error,
/// with the sources the errors are in. chip: a microcontroller's build (no Std); hostBuild: a
/// build for this machine (pkg-config's flags).
let programWith (texts: Map<string, string>) (mainPath: string) (requireMain: bool) (collect: bool) (chip: bool) (hostBuild: bool) : result<Checked, array<Diagnostic> * list<Syntax.Source.Source>> =
  let noPlace : Span = { file = -1; offset = -1; length = -1 }
  // a file of a library itself: that library, checked on its own
  let ownLibrary = Modules.libraryRootOf mainPath
  match Modules.library texts (Option.defaultValue (Modules.libraryDir ()) ownLibrary) (not chip) with
  | Error e -> Error([| error noPlace e |], [])
  | Ok lib ->
    let none : Modules.Linked = { cflags = []; links = [] }
    let loaded = if Option.isSome ownLibrary then Ok([], none) else Modules.program texts (List.length lib) mainPath hostBuild
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
        for m in lib do
          Infer.Decls.check cx (inFile m) m.modName m.decls |> ignore
        // the program's modules and explicit impls, as at the start
        for n in names prog do
          for e in Infer.Cx.withEnclosing n do
            cx.moduleNames.Value <- Set.add e cx.moduleNames.Value
        cx.manualImpls.Value <- Set.union cx.manualImpls.Value (Set.ofList (impls prog))
        for m in prog do
          for (n, why) in m.skippedC do
            cx.skippedC.Value <- Map.add n why cx.skippedC.Value
        for m in prog do
          Infer.Decls.check cx (inFile m) m.modName m.decls |> ignore
        Infer.Decls.finish cx
        Ok { modules = all; cx = cx; linked = linked }

/// Checks the program whose main file is mainPath, from the files on disk.
let program (mainPath: string) (requireMain: bool) (collect: bool) (chip: bool) (hostBuild: bool) = programWith Map.empty mainPath requireMain collect chip hostBuild

/// The program the passes after checking take: the context's tables, with every type settled (a
/// variable bound in the context followed, a free one defaulted, rows in canonical order).
let programOf (cx: Infer.Cx.Cx) : Core.Program.Program =
  let v = cx.v
  let settle (t: Types.Ty.Ty) = Types.Norm.resolve v t
  let pars (ps: list<string * Types.Ty.Ty>) = List.map (fun (x, t) -> (x, settle t)) ps
  let fn (f: Core.Ir.FunDef) : Core.Ir.FunDef =
    { f with pars = pars f.pars; ret = settle f.ret; row = Types.Norm.resolveRow v f.row; body = Core.Ir.mapTypes settle f.body }
  let ex (e: Core.Ir.Export) : Core.Ir.Export = { e with pars = List.map settle e.pars; ret = settle e.ret }
  let ext (x: Core.Ir.ExternSig) : Core.Ir.ExternSig = { x with pars = List.map settle x.pars; ret = settle x.ret }
  { types = cx.types.Value
    externs = Map.map (fun _ x -> ext x) cx.externs.Value
    funs = List.map fn (Array.toList (Buffer.toArray cx.funs))
    traitMethods = cx.traitMethods.Value
    effects = cx.effects.Value
    impls = cx.impls.Value
    exports = List.map ex (Array.toList (Buffer.toArray cx.exports))
    values = Array.toList (Buffer.toArray cx.valueList)
    tests = Array.toList (Buffer.toArray cx.tests)
    clayouts = cx.clayouts.Value
    targets = cx.targets.Value
    memberNames = Map.map (fun _ (ms: list<string * Infer.Cx.MemberInfo>) -> List.map fst ms) cx.members.Value }

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
  match program mainPath true true false true with
  | Error(ds, sources) -> if report sources ds strict then 0 else 1
  | Ok c ->
    let sources = List.map (fun (m: Modules.Loaded) -> m.source) c.modules
    if report sources (Buffer.toArray c.cx.diagnostics) strict then 0 else 1

// a pass's error as a diagnostic: at its line of its file ("" for the main one), or at the file
let private passError (sources: list<Syntax.Source.Source>) (mainPath: string) (e: Core.Program.PassError) : Diagnostic =
  let path = if e.file = "" then mainPath else e.file
  match List.tryFind (fun (s: Syntax.Source.Source) -> s.path = path) sources with
  | Some s ->
    let offset = if e.line > 0 && e.line <= Array.length s.lines then s.lines.[e.line - 1] else -1
    error { file = s.file; offset = offset; length = -1 } e.message
  | None -> error { file = -1; offset = -1; length = -1 } e.message

/// zs build: the check, with a build's report (its errors when it has any, its warnings then not
/// shown; else its warnings), then the build; testBuild: the file's test entry for main (zs test).
/// What a build left: whether it made the output, and its diagnostics (its errors when it failed,
/// with the warnings before them; else its warnings), with the sources they're in.
type Built = { made: bool; diagnostics: array<Diagnostic>; sources: list<Syntax.Source.Source> }

/// zs build without printing: the check, then (with no errors, and no warnings under --strict) the
/// build; testBuild: the file's test entry for main (zs test).
let make (o: Options.Options) (testBuild: bool) : Built =
  match Compile.timed o.time "parse + check" (fun () -> program o.main (not o.isLib) true (Option.isSome o.mcu) (o.target = "")) with
  | Error(ds, sources) -> { made = false; diagnostics = ds; sources = sources }
  | Ok c ->
    let sources = List.map (fun (m: Modules.Loaded) -> m.source) c.modules
    let all = Buffer.toArray c.cx.diagnostics
    let errors = Array.filter (fun (d: Diagnostic) -> d.severity = Err) all
    if Array.length errors > 0 then
      { made = false; diagnostics = errors; sources = sources }
    else if o.strict && Array.length all > 0 then
      { made = false; diagnostics = all; sources = sources }
    else
      match Compile.make o (programOf c.cx) c.linked testBuild with
      | Ok () -> { made = true; diagnostics = all; sources = sources }
      | Error(Compile.InPass e) -> { made = false; diagnostics = Array.append all [| passError sources o.main e |]; sources = sources }
      | Error(Compile.InTool m) -> { made = false; diagnostics = Array.append all [| passError sources o.main { file = ""; line = 0; message = m } |]; sources = sources }

let build (o0: Options.Options) (testBuild: bool) : int =
  // ZS_TIME=1 is --time for every build
  let o = if Option.isSome (Environment.getVariable "ZS_TIME") then { o0 with time = true } else o0
  let total = Diagnostics.Stopwatch.startNew ()
  let b = make o testBuild
  let code = if report b.sources b.diagnostics o.strict && b.made then 0 else 1
  if o.time then
    eprintln (Compile.timeLine (if o.served then "total (build server)" else "total") (float (int total.ElapsedNanoseconds) / 1000000.0))
  code
