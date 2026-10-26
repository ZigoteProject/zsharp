/// The commands that build (zs build, run, test) and those that keep a project's dependencies (zs
/// fetch, update): the F# compiler's Main for these.
open Build

let private isFile (a: string) = String.endsWith ".zs" a

let private dirOf (src: string) = Path.getDirectoryName (Path.getFullPath src)

// a project's problem, shown as a build's errors are
let private showProblem (p: Project.Problem) =
  let (d, src) = Modules.problem 0 p
  Check.report (Option.toList src) [| d |] false |> ignore

// the project around the current directory, or why there's none
let private project () : result<Project.Manifest, string> =
  match Project.findProject (Environment.currentDirectory ()) with
  | Some(Ok m) -> Ok m
  | Some(Error p) ->
    showProblem p
    Error "invalid zs.toml"
  | None -> Error "no file given and no zs.toml here or above (zs new <name> creates a project)"

// fetches the git dependencies of the project around dir (if any) before a build; false on
// failure, with the reasons shown
let private fetched (dir: string) : bool =
  match Project.findProject dir with
  | Some(Ok m) ->
    let errors = Project.fetchDeps m false
    for e in errors do
      eprintln $"zs: {e}"
    List.isEmpty errors
  | Some(Error p) ->
    showProblem p
    false
  | None -> true

// a path for something made for one command (an executable run once), removed after
let private scratchExe () : string =
  match File.createTemp "zs-" with
  | Ok p -> p
  | Error _ -> Path.combine (Directory.temp ()) "zs-run"

// the options with the project's target when the command line names none, and the project's
// settings for the target built for ([target.<name>])
let private projectTarget (m: Project.Manifest) (args: list<string>) (o0: Options.Options) : Options.Options =
  let o = if m.target <> "" && not (List.contains "--target" args) then Options.withTarget o0 m.target else o0
  match Map.tryFind (Options.targetName o.mcu o.target) m.targets with
  | Some t -> { o with heap = t.heap }
  | None -> o

/// zs build [file.zs] …: the file, or the project's main as build/<name>; served: by the build
/// server.
let build (served: bool) (args: list<string>) : int =
  match Options.parse args with
  | Error e ->
    eprintln e
    2
  | Ok(o0, files) ->
    let o = { o0 with served = served }
    match List.filter isFile files with
    | [] ->
      match project () with
      | Error msg ->
        eprintln $"zs: {msg}"
        1
      | Ok m ->
        if not (fetched m.root) then
          1
        else
          let dir = Path.combine m.root "build"
          Tools.makeDirectory dir
          let out = if o.out <> "" then o.out else Path.combine dir m.name
          let code = Make.build { (projectTarget m args o) with main = m.main; out = out } false
          if code = 0 then
            println $"built {Path.getRelativePath (Environment.currentDirectory ()) out}"
          code
    | file :: _ ->
      if not (fetched (dirOf file)) then 1 else Make.build { o with main = file; out = (if o.out = "" then Path.getFileNameWithoutExtension file else o.out) } false

/// zs run [file.zs] … [-- arguments]: the program built and run with the arguments; its exit code.
let run (args: list<string>) : int =
  match Options.parse args with
  | Error e ->
    eprintln e
    2
  | Ok(o0, files) ->
    let main =
      match List.filter isFile files with
      | file :: _ -> if fetched (dirOf file) then Ok(file, o0) else Error ""
      | [] ->
        match project () with
        | Error msg -> Error msg
        | Ok m -> if fetched m.root then Ok(m.main, projectTarget m args o0) else Error ""
    match main with
    | Error msg ->
      if msg <> "" then
        eprintln $"zs: {msg}"
      1
    | Ok(file, o) ->
      let exe = scratchExe ()
      // a project's program takes the arguments after its name too
      let programArgs = if List.isEmpty o.rest then List.filter (fun a -> not (isFile a)) files else o.rest
      // a chip's image runs by its runner (QEMU, or probe-rs flashing a board), a WebAssembly
      // module under Node
      let (program, pargs) =
        match o.mcu with
        | Some m when m.board <> "" -> (List.head m.runner, List.append (List.tail m.runner) [ exe ])
        | Some _ -> ("node", [ Path.combine (Options.runtimeDir ()) "run-wasm.mjs"; exe ])
        | None -> (exe, programArgs)
      if Make.build { o with main = file; out = exe } false = 0 then
        let code =
          match Tools.runInherited program pargs with
          | Ok c -> c
          | Error e ->
            let hint =
              match o.mcu with
              | Some m -> $" (zs run --target {m.name} needs {program}; zs build -o {m.name}.elf builds the image without it)"
              | None -> ""
            eprintln $"zs: {e}{hint}"
            1
        File.delete exe |> ignore
        code
      else
        File.delete exe |> ignore
        1

/// zs check file.zs: its errors and warnings (its project's git dependencies fetched first).
let check (path: string) (strict: bool) : int = if fetched (dirOf path) then Check.run path strict else 1

/// zs fetch, zs update: the project's git dependencies checked out at their locked commits, or
/// moved to the newest of their revs (zs.lock rewritten).
let fetch (update: bool) : int =
  match project () with
  | Error msg ->
    eprintln $"zs: {msg}"
    1
  | Ok m ->
    let errors = Project.fetchDeps m update
    for e in errors do
      eprintln $"zs: {e}"
    if List.isEmpty errors then 0 else 1

// ------------------------------------------------------------ zs test

// a test of a built test binary (0009): its path, focus, time limit (ms) and sequenced group
type private Leaf = { path: string; focus: string; timeout: int; sequence: string }

// runs a test binary on one test, killed after its time limit: the exit code (None when it timed
// out) and its output (standard output, then standard error)
let private runLeaf (exe: string) (l: Leaf) : option<int> * string =
  let secs = float l.timeout / 1000.0
  match Tools.runSplit "timeout" [ "--kill-after=1"; $"{secs}"; exe; l.path ] with
  | Ok r -> ((if r.code = 124 || r.code = 137 then None else Some r.code), r.out + r.err)
  | Error e -> (Some 1, e)

// what expectAt prints for zs test --update: the place, the text, an end line (Testing.zs); the
// output without them
let private expectRecords (output: string) : list<string * int * string> * string =
  let lines = String.split "\n" output
  let rec go (rest: list<string>) (found: list<string * int * string>) (kept: list<string>) : list<string * int * string> * string =
    match rest with
    | [] -> (List.rev found, String.join "\n" (List.rev kept))
    | l :: more ->
      if String.startsWith "zs-expect " l then
        let place = String.sub l 10 (String.length l - 10)
        match String.lastIndexOf ":" place with
        | Some colon ->
          let n : option<int> = Int.parse (String.sub place (colon + 1) (String.length place - colon - 1))
          let rec body (r: list<string>) (acc: list<string>) : list<string> * list<string> =
            match r with
            | [] -> (List.rev acc, [])
            | "zs-expect-end" :: after -> (List.rev acc, after)
            | x :: after -> body after (x :: acc)
          let (text, after) = body more []
          go after ((String.sub place 0 colon, Option.defaultValue 0 n, String.join "\n" text) :: found) kept
        | None -> go more found (l :: kept)
      else
        go more found (l :: kept)
  go lines [] []

let private opening : Set<string> = Set.ofList [ "("; "["; "[|"; "{" ]

let private closing : Set<string> = Set.ofList [ ")"; "]"; "|]"; "}" ]

// rewrites an expect test's literal (the last argument of the `expect` on that line) to the text,
// through the tokens: a plain string when it fits on its line, else a raw string on lines of its
// own
let private updateExpect (file: string) (line: int) (text: string) : bool =
  match File.readAllText file with
  | Error _ -> false
  | Ok source ->
    let src = Syntax.Source.make 0 file source
    let (toks, _) = Diag.Report.collect (fun () -> Syntax.Lexer.lex src)
    let n = Array.length toks
    let tokText (i: int) = Syntax.Token.text src.text toks.[i]
    let lineOf (i: int) = Syntax.Source.lineOf src toks.[i].offset + 1
    let isExpect (i: int) = toks.[i].kind = Syntax.Token.Id && lineOf i = line && (tokText i = "expect" || tokText i = "Testing.expect")
    match List.tryFind isExpect (List.init n (fun i -> i)) with
    | None -> false
    | Some first ->
      // the call's literal: the first string token after the value at the call's depth
      let rec find (j: int) (depth: int) (seen: bool) : option<int> =
        if j >= n then
          None
        else
          let k = toks.[j].kind
          let t = tokText j
          if Set.contains t opening then find (j + 1) (depth + 1) true
          else if Set.contains t closing then find (j + 1) (depth - 1) true
          else if k = Syntax.Token.Str && depth = 0 && seen then Some j
          else if (k = Syntax.Token.Newline || k = Syntax.Token.Eof) && depth = 0 then None
          else find (j + 1) depth true
      match find (first + 1) 0 false with
      | None -> false
      | Some lit ->
        let col = toks.[first].offset - src.lines.[lineOf first - 1]
        let indent = String.repeat (col + 2) " "
        let literal =
          if not (String.contains "\n" text || String.contains "\"" text || String.contains "\\" text) then
            "\"" + text + "\""
          else
            "\"\"\"\n" + String.join "\n" (List.map (fun (l: string) -> if l = "" then l else indent + l) (String.split "\n" text)) + "\n" + indent + "\"\"\""
        let start = toks.[lit].offset
        let stop = start + toks.[lit].length
        File.writeAllText file (String.sub source 0 start + literal + String.sub source stop (String.length source - stop)) |> ignore
        true

// a run's last line: "3 passed, 1 failed, 2 skipped"
let private summaryLine (passed: int) (failed: int) (skipped: int) (broken: int) : string =
  let s = if skipped > 0 then $", {skipped} skipped" else ""
  let b = if broken > 0 then $", {broken} file(s) didn't build" else ""
  $"{passed} passed, {failed} failed{s}{b}"

// builds a file's [<Tests>] values and runs each test in its own process (0009), a sequenced
// group's tests one after another, each within its time limit. args: filters (a path ending in /
// is a prefix; else a part of the path), --summary, --fail-on-focused, --update. The passed,
// failed and skipped, or None when it didn't build.
let private runTests (o: Options.Options) (src: string) (args: list<string>) : option<int * int * int> =
  let filters = List.filter (fun (a: string) -> not (String.startsWith "--" a)) args
  let exe = scratchExe ()
  if Make.build { o with main = src; out = exe } true <> 0 then
    File.delete exe |> ignore
    None
  else
    let listed =
      match Tools.runSplit exe [ "--list" ] with
      | Ok r -> r.out
      | Error _ -> ""
    let leafOf (line: string) : option<Leaf> =
      match String.split "\t" line with
      | [ p; f; t; s ] ->
        let ms : option<int> = Int.parse t
        Some { path = p; focus = f; timeout = Option.defaultValue 10000 ms; sequence = s }
      | _ -> None
    let leaves = List.choose leafOf (List.filter (fun l -> l <> "") (String.split "\n" listed))
    if List.isEmpty leaves then
      eprintln $"{src}: no [<Tests>] values"
      File.delete exe |> ignore
      Some(0, 0, 0)
    else
      let wanted (l: Leaf) = List.isEmpty filters || List.exists (fun (f: string) -> if String.endsWith "/" f then String.startsWith f l.path else String.contains f l.path) filters
      let chosen = List.filter wanted leaves
      if List.isEmpty chosen then
        let roots = String.join ", " (List.distinct (List.map (fun (l: Leaf) -> List.head (String.split "/" l.path) + "/") leaves))
        println $"no test's path matches {String.join " " filters} (they start with {roots})"
      let focused = List.exists (fun (l: Leaf) -> l.focus = "focused") chosen
      let runs (l: Leaf) = l.focus <> "pending" && (not focused || l.focus = "focused")
      // ponytail: one test at a time; up to the cores at once as tasks when runs get long
      let results = Map.ofList (List.map (fun (l: Leaf) -> (l.path, runLeaf exe l)) (List.filter runs chosen))
      let failed = ref 0
      let skipped = ref 0
      let passed = ref 0
      let updates = Buffer.empty
      for l in chosen do
        match Map.tryFind l.path results with
        | Some(Some 0, _) ->
          passed.Value <- passed.Value + 1
          println $"ok   {l.path}"
        | Some(code, output0) ->
          failed.Value <- failed.Value + 1
          println $"FAIL {l.path}"
          let (records, output) = expectRecords output0
          for r in records do
            Buffer.push r updates
          for line in String.split "\n" (String.trim output) do
            if line <> "" then
              println $"       {line}"
          if Option.isNone code then
            println $"       timed out after {float l.timeout / 1000.0} s"
        | None ->
          skipped.Value <- skipped.Value + 1
          println $"skip {l.path}{(if l.focus = "pending" then " (pending)" else "")}"
      if List.contains "--update" args then
        for (file, line, text) in Buffer.toArray updates do
          let path = Path.combine (dirOf src) file
          if File.exists path && updateExpect path line text then
            println $"updated {file}:{line}"
      File.delete exe |> ignore
      if focused && List.contains "--fail-on-focused" args then
        println "focused tests are left (--fail-on-focused)"
        failed.Value <- failed.Value + 1
      Some(passed.Value, failed.Value, skipped.Value)

/// zs test [file.zs] [filters…]: a file's tests, or every file of the project's src/ and tests/
/// that has [<Tests>].
// zs test --doc (0009, D8): the fenced zsharp blocks in the files' /// comments, each built as a
// program and run, what it prints checked against its // => lines; with --update, a failing
// block's lines are rewritten to what it printed
let private docTests (o: Options.Options) (files: list<string>) (update: bool) : int =
  let passed = ref 0
  let failed = ref 0
  for file in files do
    match File.readAllText file with
    | Error _ -> ()
    | Ok text ->
      // where the program goes, and the module it opens: beside the package's main, so the file's
      // module is named as the program names it; the library's names are global, so none there
      let (dir, opens) =
        match (Modules.libraryRootOf file, Project.packageOf file) with
        | (None, Ok p) ->
          let full = Path.getFullPath file
          let isMain =
            match p.manifest with
            | Some m -> Path.getFullPath m.main = full
            | None -> false
          let rel = Path.getRelativePath p.root full
          let upper (s: string) = if s = "" then s else String.toUpper (String.sub s 0 1) + String.sub s 1 (String.length s - 1)
          let name = String.join "." (List.map upper (String.split "/" (String.sub rel 0 (String.length rel - 3))))
          (p.root, if isMain then None else Some name)
        | _ -> (Directory.temp (), None)
      let shown = Path.getRelativePath (Environment.currentDirectory ()) file
      let changed = Buffer.empty
      for b in Build.DocTest.blocks text do
        let src = Path.combine dir ".zs-doctest.zs"
        let exe = scratchExe ()
        File.writeAllText src (Build.DocTest.program opens b) |> ignore
        let built = Make.build { o with main = src; out = exe } false = 0
        let ran = if built then Tools.runSplit exe [] else Error "it doesn't build"
        File.delete src |> ignore
        File.delete exe |> ignore
        let printed =
          match ran with
          | Ok r -> List.filter (fun (l: string) -> l <> "") (String.split "\n" r.out)
          | Error _ -> []
        let name = $"{shown}:{b.line} {b.decl}"
        match ran with
        | Ok r when r.code = 0 && printed = List.filter (fun (l: string) -> l <> "") b.expected ->
          passed.Value <- passed.Value + 1
          println $"ok   {name}"
        | _ ->
          failed.Value <- failed.Value + 1
          println $"FAIL {name}"
          match ran with
          | Ok r ->
            println $"  expected: {String.join " | " b.expected}"
            println $"  printed:  {String.join " | " printed}"
            if r.code <> 0 then
              println $"  and exited with {r.code}: {String.trim r.err}"
            else if update then
              Buffer.push (b, printed) changed
          | Error e -> println $"  {e}"
      // bottom up, so each block's lines are where it found them
      if Buffer.length changed > 0 then
        let rewrite (t: string) (bp: Build.DocTest.Block * list<string>) = Build.DocTest.update t (fst bp) (snd bp)
        File.writeAllText file (List.fold rewrite text (List.rev (Array.toList (Buffer.toArray changed)))) |> ignore
        println $"updated {shown}"
  println (summaryLine passed.Value failed.Value 0 0)
  if failed.Value = 0 then 0 else 1

let test (args: list<string>) : int =
  match Options.parse args with
  | Error e ->
    eprintln e
    2
  | Ok(o, rest) when List.contains "--doc" rest ->
    // the files named, else the project's (its main's directory down)
    let named = List.filter isFile rest
    let files =
      if not (List.isEmpty named) then
        named
      else
        match project () with
        | Ok m ->
          let dir = Path.getDirectoryName (Path.combine m.root m.main)
          match Directory.listRecursive dir with
          | Ok rels -> List.map (fun r -> Path.combine dir r) (List.filter isFile rels)
          | Error _ -> []
        | Error msg ->
          eprintln $"zs: {msg}"
          []
    docTests o files (List.contains "--update" rest)
  | Ok(o, rest) ->
    // the filters, and the flags only zs test takes (--update, --summary, --fail-on-focused)
    let filters = List.filter (fun a -> not (isFile a)) rest
    match List.filter isFile rest with
    | src :: _ ->
      if not (fetched (dirOf src)) then
        1
      else
        match runTests o src filters with
        | None -> 1
        | Some(0, 0, 0) -> 1
        | Some(p, f, s) ->
          println (summaryLine p f s 0)
          if f = 0 then 0 else 1
    | [] ->
      match project () with
      | Error msg ->
        eprintln $"zs: {msg}"
        1
      | Ok m ->
        if not (fetched m.root) then
          1
        else
          let under (d: string) : list<string> =
            let dir = Path.combine m.root d
            if Directory.exists dir then
              match Directory.listRecursive dir with
              | Ok rels -> List.map (fun r -> Path.combine dir r) (List.filter isFile rels)
              | Error _ -> []
            else
              []
          let hasTests (f: string) =
            match File.readAllText f with
            | Ok t -> String.contains "[<Tests>]" t
            | Error _ -> false
          let files = List.filter hasTests (List.append (under "src") (under "tests"))
          let runFile (f: string) =
            println (Path.getRelativePath (Environment.currentDirectory ()) f)
            runTests o f filters
          let results = List.map runFile files
          let sumOf (pick: int * int * int -> int) = List.sumBy (fun (r: option<int * int * int>) -> match r with | Some t -> pick t | None -> 0) results
          let passed = sumOf (fun (p, _, _) -> p)
          let failed = sumOf (fun (_, f, _) -> f)
          let skipped = sumOf (fun (_, _, s) -> s)
          let broken = List.length (List.filter Option.isNone results)
          println (summaryLine passed failed skipped broken)
          if failed = 0 && broken = 0 then 0 else 1

/// zs doctor: what builds need, found here or not, with how to get what's missing: the library
/// and runtime zs uses, clang (this machine's builds), zig (other targets', a chip's and
/// WebAssembly's) and libclang (import c), then what some commands need. 1 when a build for this
/// machine can't work.
let doctor () : int =
  let os = Tools.hostOs ()
  let pick (mac: string) (linux: string) (windows: string) = if os = "macos" then mac else if os = "windows" then windows else linux
  // a tool's first line of output, when it runs
  let version (program: string) (args: list<string>) : option<string> =
    match Tools.runSplit program args with
    | Ok r when r.code = 0 ->
      let out = if String.trim r.out = "" then r.err else r.out
      Some(List.head (String.split "\n" (String.trim out)))
    | _ -> None
  let report (found: option<string>) (name: string) (what: string) (get: string) =
    match found with
    | Some v -> println $"ok   {name,-16} {v} ({what})"
    | None -> println $"--   {name,-16} not found ({what}): {get}"
  let lib = Modules.libraryDir ()
  let rt = Options.runtimeDir ()
  let libOk = File.exists (Path.combine lib "prelude.zs")
  let rtOk = File.exists (Path.combine rt "rt.c")
  report (if libOk then Some lib else None) "library" "Core and Std" "reinstall zs, or set ZS_LIB to its lib/"
  report (if rtOk then Some rt else None) "runtime" "rt.c and the boards" "reinstall zs, or set ZS_RUNTIME"
  let clang = version "clang" [ "--version" ]
  let getClang = pick "brew install llvm, with $(brew --prefix llvm)/bin first on PATH" "LLVM's release (apt's clang may be older), first on PATH" "winget install LLVM.LLVM"
  // the IR is LLVM 23's (its coroutine intrinsics): an older clang builds some programs, not tasks
  let major =
    match Option.bind (fun (v: string) -> Option.map (fun (at: int) -> String.sub v (at + 14) (String.length v - at - 14)) (String.indexOf "clang version " v)) clang with
    | Some rest -> Int.parse (List.head (String.split "." rest))
    | None -> None
  let recent = Option.defaultValue 0 major >= 23
  match clang with
  | Some v when not recent -> println $"--   {"clang",-16} {v}: too old, LLVM 23 or later is needed (a task's code uses its coroutines): {getClang}"
  | _ -> report clang "clang" "builds for this machine" getClang
  report (version "zig" [ "version" ]) "zig" "builds for other targets, chips and WebAssembly" (pick "brew install zig" "your distribution's zig, or ziglang.org/download" "winget install zig.zig")
  report (if Libclang.available () then Some "found" else None) "libclang" "import c" (pick "brew install llvm, or set ZS_LIBCLANG to a libclang.dylib" "apt install libclang-dev, or set ZS_LIBCLANG" "LLVM's release has libclang.dll beside clang.exe")
  report (version "git" [ "--version" ]) "git" "git dependencies" (pick "xcode-select --install, or brew install git" "apt install git" "winget install Git.Git")
  report (version "qemu-system-arm" [ "--version" ]) "qemu-system-arm" "zs run on a chip's QEMU board" (pick "brew install qemu" "apt install qemu-system-arm" "winget install SoftwareFreedomConservancy.QEMU")
  report (version "probe-rs" [ "--version" ]) "probe-rs" "zs run on a real board" "https://probe.rs/docs/getting-started/installation"
  report (version "node" [ "--version" ]) "node" "zs run for WebAssembly" (pick "brew install node" "apt install nodejs" "winget install OpenJS.NodeJS")
  let debugger = if os = "macos" then "lldb" else "gdb"
  report (version debugger [ "--version" ]) debugger "zs build -g's debugger" (pick "xcode-select --install" "apt install gdb" "LLVM's release has lldb")
  if libOk && rtOk && recent then 0 else 1

