/// zs build: the check, then the build: a host executable by module (Units), any other (a
/// library, another target, a microcontroller, --emit-llvm, -g, sanitizers) as one module
/// (Compile); with the build's report, its errors when it has any (its warnings then not shown),
/// else its warnings.
open Diag.Diagnostic

// a pass's error as a diagnostic: at its line of its file ("" for the main one), or at the file
let passError (sources: list<Syntax.Source.Source>) (mainPath: string) (e: Core.Program.PassError) : Diagnostic =
  let path = if e.file = "" then mainPath else e.file
  match List.tryFind (fun (s: Syntax.Source.Source) -> s.path = path) sources with
  | Some s ->
    let offset = if e.line > 0 && e.line <= Array.length s.lines then s.lines.[e.line - 1] else -1
    error { file = s.file; offset = offset; length = -1 } e.message
  | None -> error { file = -1; offset = -1; length = -1 } e.message

/// What a build left: whether it made the output, and its diagnostics (its errors when it failed,
/// with the warnings before them; else its warnings), with the sources they're in.
type Built = { made: bool; diagnostics: array<Diagnostic>; sources: list<Syntax.Source.Source> }

/// zs build without printing: the check, then (with no errors, and no warnings under --strict) the
/// build; testBuild: the file's test entry for main (zs test).
let make (o: Options.Options) (testBuild: bool) : Built =
  match Compile.timed o.time "parse + check" (fun () -> Check.program o.main (not o.isLib) true (Option.isSome o.mcu) (o.target = "")) with
  | Error(ds, sources) -> { made = false; diagnostics = ds; sources = sources }
  | Ok c ->
    if o.time then
      let names = if List.isEmpty c.checkedNames then "none" else String.join " " c.checkedNames
      eprintln (Compile.timeLine "restore" c.restoreMs)
      eprintln (Compile.timeLine $"check ({c.checkedCount} of {List.length c.units}; program: {names})" c.checkMs)
    let sources = List.map (fun (m: Modules.Loaded) -> m.source) c.modules
    let all = Buffer.toArray c.cx.diagnostics
    let errors = Array.filter (fun (d: Diagnostic) -> d.severity = Err) all
    if Array.length errors > 0 then
      { made = false; diagnostics = errors; sources = sources }
    else if o.strict && Array.length all > 0 then
      { made = false; diagnostics = all; sources = sources }
    else if Option.isNone o.mcu && o.target = "" && not o.isLib && not o.emitLlvm && not o.debugInfo && not o.sanitize then
      // a host executable: a module per source file, compiled in parallel and from the cache when
      // unchanged (the other builds are one module)
      let failed (msg: string) = { made = false; diagnostics = Array.append all [| passError sources o.main { file = ""; line = 0; message = msg } |]; sources = sources }
      let show (lines: list<string * float>) =
        if o.time then
          for (name, ms) in lines do
            eprintln (Compile.timeLine name ms)
      let built =
        handle Units.parts o c testBuild (Units.cachedModule o) with
        | Core.Program.Stops.stop e, _ -> Error e
      match built with
      | Error e -> { made = false; diagnostics = Array.append all [| passError sources o.main e |]; sources = sources }
      | Ok b ->
        show b.lines
        match Units.link o b c.linked with
        | Ok lines ->
          show lines
          { made = true; diagnostics = all; sources = sources }
        | Error msg -> failed msg
    else
      match Compile.make o (Check.programOf c) c.linked testBuild with
      | Ok () -> { made = true; diagnostics = all; sources = sources }
      | Error(Compile.InPass e) -> { made = false; diagnostics = Array.append all [| passError sources o.main e |]; sources = sources }
      | Error(Compile.InTool m) -> { made = false; diagnostics = Array.append all [| passError sources o.main { file = ""; line = 0; message = m } |]; sources = sources }

/// zs build: make, and its report; 0 when it made the output.
let build (o0: Options.Options) (testBuild: bool) : int =
  // ZS_TIME=1 is --time for every build
  let o = if Option.isSome (Environment.getVariable "ZS_TIME") then { o0 with time = true } else o0
  let total = Diagnostics.Stopwatch.startNew ()
  let b = make o testBuild
  let code = if Check.report b.sources b.diagnostics o.strict && b.made then 0 else 1
  if o.time then
    eprintln (Compile.timeLine (if o.served then "total (build server)" else "total") (float (int total.ElapsedNanoseconds) / 1000000.0))
  code
