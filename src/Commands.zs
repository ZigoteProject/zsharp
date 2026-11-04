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

// a workspace's members, each read from its zs.toml (0018 item 8); a project on its own is its
// one member
let private membersOf (m: Project.Manifest) : list<Project.Manifest> =
  if List.isEmpty m.members then
    [ m ]
  else
    List.choose (fun (d: string) ->
      match Project.readManifest d with
      | Ok x -> Some x
      | Error p ->
        showProblem p
        None) m.members

// a workspace root (members, no program of its own): the members' names, for an error
let private membersText (m: Project.Manifest) : string =
  String.join ", " (List.map (fun (d: string) -> Path.getRelativePath m.root d) m.members)

// fetches the git dependencies of the project around dir (if any) before a build; false on
// failure, with the reasons shown
let private fetched (offline: bool) (dir: string) : bool =
  match Project.findProject dir with
  | Some(Ok m) ->
    let errors = Project.fetchDeps m false offline
    for e in errors do
      eprintln $"zs: {e}"
    List.isEmpty errors
  | Some(Error p) ->
    showProblem p
    false
  | None -> true

// a path for something made for one command (an executable run once), removed after; not a
// fixed name in a shared temporary directory, where another user could put one there first
let private scratchExe () : string =
  match File.createTemp "zs-" with
  | Ok p -> p
  | Error _ -> Path.combine (Tools.cacheRoot ()) "zs-run"

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
        let one (p: Project.Manifest) : int =
          if not (fetched o.offline p.root) then
            1
          else
            let dir = Path.combine p.root "build"
            Tools.makeDirectory dir
            let out = if o.out <> "" && List.isEmpty m.members then o.out else Path.combine dir p.name
            let code = Make.build { (projectTarget p args o) with main = p.main; out = out } false
            if code = 0 then
              println $"built {Path.getRelativePath (Environment.currentDirectory ()) out}"
            code
        if List.isEmpty m.members then
          one m
        else
          // a workspace: every member with a main; a library member is skipped
          let codes =
            List.map (fun (p: Project.Manifest) ->
              let rel = Path.getRelativePath (Environment.currentDirectory ()) p.root
              match File.readAllText p.main with
              | Ok text when String.contains "let main" text ->
                println $"member {rel}"
                one p
              | _ ->
                println $"member {rel}: a library, not built on its own"
                0) (membersOf m)
          List.fold max 0 codes
    | file :: _ ->
      if not (fetched o.offline (dirOf file)) then 1 else Make.build { o with main = file; out = (if o.out = "" then Path.getFileNameWithoutExtension file else o.out) } false

/// zs run [file.zs] … [-- arguments]: the program built and run with the arguments; its exit code.
let run (args: list<string>) : int =
  match Options.parse args with
  | Error e ->
    eprintln e
    2
  | Ok(o0, files) ->
    let main =
      match List.filter isFile files with
      | file :: _ -> if fetched o0.offline (dirOf file) then Ok(file, o0) else Error ""
      | [] ->
        match project () with
        | Error msg -> Error msg
        | Ok m when not (List.isEmpty m.members) -> Error $"zs run: a workspace; run a member ({membersText m}), or a file"
        | Ok m -> if fetched o0.offline m.root then Ok(m.main, projectTarget m args o0) else Error ""
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
let check (path: string) (strict: bool) : int = if fetched false (dirOf path) then Check.run path strict else 1

/// zs fetch, zs update: the project's git dependencies checked out at their locked commits, or
/// moved to the newest of their revs (zs.lock rewritten).
let fetch (update: bool) : int =
  match project () with
  | Error msg ->
    eprintln $"zs: {msg}"
    1
  | Ok m ->
    let errors = List.collect (fun (p: Project.Manifest) -> Project.fetchDeps p update false) (membersOf m)
    for e in errors do
      eprintln $"zs: {e}"
    if List.isEmpty errors then 0 else 1

// ------------------------------------------------------------ zs add, zs remove, zs tree

// zs.toml's lines with a dependency's line written in [dependencies] (the section added at the
// end when there's none), or taken out; Error when there's no such dependency to take out
let private editDependencies (lines: list<string>) (name: string) (value: option<string>) : result<list<string>, string> =
  let isHeader (l: string) = String.startsWith "[" (String.trim l)
  let isEntry (l: string) =
    match String.indexOf "=" l with
    | Some eq -> String.trim (String.sub l 0 eq) = name
    | None -> false
  let rec go (acc: list<string>) (rest: list<string>) (inDeps: bool) (done: bool) : list<string> * bool =
    match rest with
    | [] -> (List.rev acc, done)
    | l :: more ->
      if isHeader l then
        let here = String.trim l = "[dependencies]"
        // the section ends: a new entry goes last in it
        let acc2 = if inDeps && not done && not here && Option.isSome value then l :: Option.get value :: acc else l :: acc
        go acc2 more here (done || (inDeps && not done && not here && Option.isSome value))
      else if inDeps && not done && isEntry l then
        match value with
        | Some v -> go (v :: acc) more inDeps true
        | None -> go acc more inDeps true
      else
        go (l :: acc) more inDeps done
  let (edited, done) = go [] lines false false
  if done then
    Ok edited
  else
    match value with
    | Some v ->
      // not written yet: after an open [dependencies] at the end, else a section of its own
      let hasSection = List.exists (fun (l: string) -> String.trim l = "[dependencies]") lines
      let rec dropBlank (ls: list<string>) : list<string> =
        match ls with
        | l :: more when String.trim l = "" -> dropBlank more
        | _ -> ls
      let trimmed = List.rev (dropBlank (List.rev edited))
      Ok(if hasSection then List.append trimmed [ v ] else List.concat [ trimmed; [ ""; "[dependencies]"; v ] ])
    | None ->
      let names = List.choose (fun (l: string) -> match String.indexOf "=" l with | Some eq when not (isHeader l) -> Some(String.trim (String.sub l 0 eq)) | _ -> None) (snd (List.fold (fun (inDeps, acc) (l: string) -> if isHeader l then (String.trim l = "[dependencies]", acc) else if inDeps && String.contains "=" l then (inDeps, List.append acc [ l ]) else (inDeps, acc)) (false, []) lines))
      Error(if List.isEmpty names then "zs.toml has no dependencies" else $"zs.toml has no dependency '{name}' (it has {String.join ", " names})")

// what zs add writes for a dependency as given: ../text (a path; its name from its zs.toml, else
// the directory's), or a git URL, with @1.2 a release or @v1 a rev (the name from the URL's last
// part)
let private dependencyLine (root: string) (spec: string) (rev: option<string>) : result<string * string, string> =
  let isGit = String.contains "://" spec || String.startsWith "git@" spec || String.endsWith ".git" spec
  if not isGit then
    let dir = Path.getFullPath (Path.combine root spec)
    if not (File.exists (Path.combine dir "zs.toml")) then
      Error $"zs add {spec}: no zs.toml in {dir} (a path dependency is a package; a git one is a URL)"
    else
      let name =
        match Project.findProject dir with
        | Some(Ok m) when m.name <> "" -> m.name
        | _ -> Path.getFileName dir
      Ok(name, $"{name} = {{ path = \"{spec}\" }}")
  else
    // the version or rev after the last @ that isn't the URL's user (git@host:…)
    let (url, tag) =
      match String.lastIndexOf "@" spec with
      | Some i when i > 0 && not (String.contains "/" (String.sub spec (i + 1) (String.length spec - i - 1))) && not (String.contains ":" (String.sub spec (i + 1) (String.length spec - i - 1))) -> (String.sub spec 0 i, Some(String.sub spec (i + 1) (String.length spec - i - 1)))
      | _ -> (spec, None)
    let last = List.last (List.filter (fun (s: string) -> s <> "") (String.split "/" (String.replace url ":" "/")))
    let name = if String.endsWith ".git" last then String.sub last 0 (String.length last - 4) else last
    let how =
      match (tag, rev) with
      | (_, Some r) -> $", rev = \"{r}\""
      | (Some t, None) -> if Option.isSome (Project.parseVersion t) then $", version = \"{t}\"" else $", rev = \"{t}\""
      | (None, None) -> ""
    Ok(name, $"{name} = {{ git = \"{url}\"{how} }}")

/// zs add <path | url[@version]> [--rev <rev>]: the dependency written into zs.toml's
/// [dependencies] and fetched; zs remove <name>: taken out, the lock rewritten (0018 item 7).
let add (remove: bool) (args: list<string>) : int =
  match project () with
  | Error msg ->
    eprintln $"zs: {msg}"
    1
  | Ok m when not (List.isEmpty m.members) ->
    eprintln $"zs {(if remove then "remove" else "add")}: a workspace; run it in a member ({membersText m})"
    1
  | Ok m ->
    let file = Path.combine m.root "zs.toml"
    let edit (name: string) (value: option<string>) : int =
      match File.readAllLines file with
      | Error e ->
        eprintln $"zs: can't read {file}: {e}"
        1
      | Ok lines ->
        match editDependencies lines name value with
        | Error e ->
          eprintln $"zs {(if remove then "remove" else "add")} {name}: {e}"
          1
        | Ok edited ->
          match File.writeAllText file (String.join "\n" edited + "\n") with
          | Error e ->
            eprintln $"zs: can't write {file}: {e}"
            1
          | Ok _ ->
            match value with
            | Some v -> println $"added {v}"
            | None -> println $"removed {name}"
            match project () with
            | Ok m2 ->
              let errors = Project.fetchDeps m2 false false
              for e in errors do
                eprintln $"zs: {e}"
              if List.isEmpty errors then 0 else 1
            | Error e ->
              eprintln $"zs: {e}"
              1
    match (remove, args) with
    | (true, [ name ]) -> edit name None
    | (false, [ spec ])
    | (false, [ spec; "--rev"; _ ]) ->
      let rev = match args with | [ _; "--rev"; r ] -> Some r | _ -> None
      match dependencyLine m.root spec rev with
      | Ok(name, line) -> edit name (Some line)
      | Error e ->
        eprintln $"zs: {e}"
        1
    | _ ->
      eprintln (if remove then "usage: zs remove <name>" else "usage: zs add <path | url[@version]> [--rev <rev>]")
      2

/// zs vendor: the git dependencies copied into vendor/, where the project reads them from, never
/// fetching (0018 item 6).
let vendor () : int =
  match project () with
  | Error msg ->
    eprintln $"zs: {msg}"
    1
  | Ok m ->
    let errors = List.collect Project.vendor (membersOf m)
    for e in errors do
      eprintln $"zs: {e}"
    if List.isEmpty errors then 0 else 1

/// zs tree: the project's dependencies as resolved, each with its version and where it comes
/// from, its own dependencies under it (0018 item 7).
let tree () : int =
  match project () with
  | Error msg ->
    eprintln $"zs: {msg}"
    1
  | Ok m0 ->
    // a workspace: each member's tree
    let codes = List.map (fun (m: Project.Manifest) ->
    if not (fetched false m.root) then
      1
    else
      match Project.packageOf m.main with
      | Error p ->
        showProblem p
        1
      | Ok top ->
        let shown = ref Set.empty
        let rec show (indent: string) (pkg: Project.Package) =
          let parent = Option.get pkg.manifest
          let n = List.length pkg.deps
          List.iteri (fun (i: int) (pd: Project.PackageDep) ->
            match pd with
            | Project.PackageDep(key, d) ->
              let last = i = n - 1
              let (name, dep) =
                match List.tryFind (fun (nd: string * Project.Dep) -> Project.modulePrefix (fst nd) = key) parent.deps with
                | Some nd -> nd
                | None -> (key, Project.PathDep d.root)
              let version = match d.manifest with | Some mf when mf.version <> "" -> " " + mf.version | _ -> ""
              let from =
                match dep with
                | Project.PathDep path -> $"path {Path.getRelativePath m.root path}"
                | Project.GitDep(url, rev) -> $"git {url}{(if rev = "" then "" else ", rev " + rev)}"
                | Project.GitVersion(url, v) -> $"git {url}, at least {Project.showVersion v}"
              let commit =
                match Project.lockedCommit m name with
                | Some c -> $", commit {String.sub c 0 (min 7 (String.length c))}"
                | None -> ""
              let again = Set.contains d.root shown.Value
              println $"{indent}{(if last then "└─ " else "├─ ")}{name}{version} ({from}{commit}){(if again && not (List.isEmpty d.deps) then " (above)" else "")}"
              if not again then
                shown.Value <- Set.add d.root shown.Value
                show (indent + (if last then "   " else "│  ")) d) pkg.deps
        println $"{m.name}{(if m.version = "" then "" else " " + m.version)} ({Path.getRelativePath (Environment.currentDirectory ()) m.root})"
        show "" top
        0) (membersOf m0)
    List.fold max 0 codes

// ------------------------------------------------------------ zs test

// a test of a built test binary (0009): its path, focus, time limit (ms) and sequenced group
type private Leaf = { path: string; focus: string; timeout: int; sequence: string; kind: string }

// a test binary's --list line: path, focus, time limit, sequenced group and kind (test or bench)
let private leafOf (line: string) : option<Leaf> =
  match String.split "\t" line with
  | [ p; f; t; s; k ] ->
    let ms : option<int> = Int.parse t
    Some { path = p; focus = f; timeout = Option.defaultValue 10000 ms; sequence = s; kind = k }
  | _ -> None

// runs a test binary on one test, killed after its time limit: the exit code (None when it timed
// out) and its output (standard output, then standard error)
let private runLeafWith (exe: string) (l: Leaf) (extra: list<string>) : option<int> * string =
  let secs = float l.timeout / 1000.0
  match Tools.runSplit "timeout" (List.concat [ [ "--kill-after=1"; $"{secs}"; exe; l.path ]; extra ]) with
  | Ok r -> ((if r.code = 124 || r.code = 137 then None else Some r.code), r.out + r.err)
  | Error e -> (Some 1, e)

// a property's side files, beside the binary: the case being run (its seed, size and index) and
// its bytes as drawn; named by the path, so the stress runs don't share them
let private propertyFiles (exe: string) (l: Leaf) : string * string =
  let key = Tools.hashOf [ l.path ]
  ($"{exe}.{key}.case", $"{exe}.{key}.record")

let private runLeaf (exe: string) (l: Leaf) : option<int> * string =
  if l.kind = "property" then
    let (caseFile, recordFile) = propertyFiles exe l
    runLeafWith exe l [ "--record"; caseFile; recordFile ]
  else
    runLeafWith exe l []

// bytes as hex and back (the record files', and the saved failures')
let private hexOf (bytes: array<u8>) : string =
  let digits = "0123456789abcdef"
  String.concat (List.map (fun (b: u8) -> String.sub digits (int (b >>> u8 4)) 1 + String.sub digits (int (b &&& u8 15)) 1) (Array.toList bytes))

let private unhex (s: string) : option<array<u8>> =
  let t = String.trim s
  let digit (c: u8) : int =
    if c >= u8 48 && c <= u8 57 then int c - 48
    else if c >= u8 97 && c <= u8 102 then int c - 87
    else if c >= u8 65 && c <= u8 70 then int c - 55
    else -1
  if String.length t % 2 <> 0 then
    None
  else
    let n = String.length t / 2
    let mutable out = Array.create n (u8 0)
    let mutable ok = true
    for i in 0 .. n - 1 do
      let hi = digit (String.byte t (2 * i))
      let lo = digit (String.byte t (2 * i + 1))
      if hi < 0 || lo < 0 then
        ok <- false
      else
        out.[i] <- u8 (hi * 16 + lo)
    if ok then Some out else None

// a test's path as a file name: letters, digits, '-', '_' and '.', the rest made '-'
let private safeName (path: string) : string =
  let safe (c: u8) =
    if (c >= u8 48 && c <= u8 57) || (c >= u8 65 && c <= u8 90) || (c >= u8 97 && c <= u8 122) || c = u8 45 || c = u8 95 || c = u8 46 then String.ofByte c else "-"
  String.concat (List.init (String.length path) (fun i -> safe (String.byte path i)))

// a property's key under .zs-cache: the test file's name, then its path made a file name, with a
// short hash of the path itself (p/a b and p/a-b are two properties)
let private cacheKey (src: string) (path: string) : string =
  Path.combine (Path.getFileNameWithoutExtension src) $"{safeName path}-{String.sub (Tools.hashOf [ path ]) 0 8}"

// where a property's shrunk failing case is saved, beside the test file, to be replayed first
// the next time (0010): .zs-cache/failures/<file>/<path>
let private failureFile (src: string) (path: string) : string =
  Path.combine (Path.combine (Path.combine (dirOf src) ".zs-cache") "failures") (cacheKey src path)

// a replay of one case of a property: its exit code and output; the case still fails when the
// code isn't 0 and the case wasn't discarded
let private replayCase (exe: string) (l: Leaf) (file: string) (size: int) : option<int> * string =
  runLeafWith exe l [ "--replay"; file; string size ]

let private replayFails (r: option<int> * string) : bool =
  let (code, output) = r
  code <> Some 0 && not (String.contains "zs-discarded" output)

// a property's case that panicked, shrunk by replays of the test binary (0010): its bytes, as
// recorded, made shorter first (a block at a time, the largest first), then smaller (each byte
// zeroed, halved or one less), each candidate a run of the case, kept while it still panics; up
// to 300 runs
let private shrinkByReplay (exe: string) (l: Leaf) (size: int) (bytes0: array<u8>) (file: string) : array<u8> * int =
  let bytes = ref bytes0
  let runs = ref 0
  let progress = ref true
  let accept (candidate: array<u8>) : bool =
    if runs.Value >= 300 || Array.toList candidate = Array.toList bytes.Value then
      false
    else
      runs.Value <- runs.Value + 1
      File.writeAllText file (hexOf candidate) |> ignore
      if replayFails (replayCase exe l file size) then
        bytes.Value <- candidate
        progress.Value <- true
        true
      else
        false
  while progress.Value && runs.Value < 300 do
    progress.Value <- false
    let mutable block = Array.length bytes.Value / 2
    while block >= 1 do
      let mutable at = 0
      while at + block <= Array.length bytes.Value do
        let now = bytes.Value
        if not (accept (Array.append (Array.sub now 0 at) (Array.sub now (at + block) (Array.length now - at - block)))) then
          at <- at + block
      block <- block / 2
    for i in 0 .. Array.length bytes.Value - 1 do
      if i < Array.length bytes.Value then
        let b = bytes.Value.[i]
        let tryWith (v: u8) =
          let mutable candidate = Array.copy bytes.Value
          candidate.[i] <- v
          accept candidate
        if b > u8 0 then
          if not (tryWith (u8 0)) then
            if not (tryWith (b / u8 2)) then
              tryWith (b - u8 1) |> ignore
  (bytes.Value, runs.Value)

// a property's run (0010): a saved failing case is replayed first (one that passes now is
// deleted, the bug fixed); then the random run, its cases recorded; a case that panicked is
// shrunk by replays, shown by a last replay, and saved
let private runProperty (exe: string) (src: string) (l: Leaf) : option<int> * string =
  let saved = failureFile src l.path
  let (caseFile, recordFile) = propertyFiles exe l
  let replayed =
    match File.readAllText saved with
    | Ok text ->
      match String.split "\n" text with
      | sizeText :: hex :: _ ->
        match ((Int.parse (String.trim sizeText) : option<int>), unhex hex) with
        | (Some size, Some bytes) ->
          File.writeAllText recordFile (hexOf bytes) |> ignore
          let (code, output) = replayCase exe l recordFile size
          if replayFails (code, output) then
            Some(code, output + $"\nthe failing case saved last time, replayed first (delete {Path.getRelativePath (Environment.currentDirectory ()) saved} to run afresh)")
          else
            File.delete saved |> ignore
            None
        | _ -> None
      | _ -> None
    | Error _ -> None
  match replayed with
  | Some r -> r
  | None ->
    let (code, output) = runLeaf exe l
    // a panic of the body (not the property's own report of a false or an Error): shrunk here
    // (and not a run that gave up on its discards, which no one case reproduces)
    if code <> Some 0 && Option.isSome code && not (String.contains "panic: falsified" output) && not (String.contains "panic: gave up" output) && File.exists caseFile then
      match (File.readAllText caseFile, File.readAllText recordFile) with
      | (Ok caseText, Ok hex) ->
        match (String.split "\t" (String.trim caseText), unhex hex) with
        | ([ _; sizeText; _ ], Some bytes0) ->
          let size = Option.defaultValue 100 (Int.parse (String.trim sizeText) : option<int>)
          let file = recordFile + ".try"
          // the recorded case alone first: a panic it doesn't reproduce (one that depended on
          // the cases before it) is reported as the run gave it, not shrunk or saved
          File.writeAllText file (hexOf bytes0) |> ignore
          if not (replayFails (replayCase exe l file size)) then
            File.delete file |> ignore
            (code, output + "\n(the case that panicked passes when replayed alone, so it isn't shrunk or saved)")
          else
            let (bytes, runs) = shrinkByReplay exe l size bytes0 file
            File.writeAllText file (hexOf bytes) |> ignore
            let (code2, shown) = replayCase exe l file size
            File.delete file |> ignore
            if not (replayFails (code2, shown)) then
              (code, output)
            else
              let dir = Path.getDirectoryName saved
              Tools.makeDirectory dir
              File.writeAllText saved $"{size}\n{hexOf bytes}\n" |> ignore
              let note = $"\nshrunk from {Array.length bytes0} bytes to {Array.length bytes} in {runs} runs; saved as {Path.getRelativePath (Environment.currentDirectory ()) saved}, replayed first next time"
              (code2, shown + note)
        | _ -> (code, output)
      | _ -> (code, output)
    else
      (code, output)

// whether a test's run passed: exit 0, and no leak reported at its exit (ZS_LEAKCHECK=1: the
// runtime's "leak check: n object(s) still allocated")
let private passedRun (code: option<int>) (output: string) : bool =
  code = Some 0 && not (List.exists (fun (l: string) -> String.startsWith "leak check:" l) (String.splitLines output))

// zs test --stress 10m (0009, D4): the duration, in milliseconds, and the arguments without the
// pair: 30s, 10m, 1h, or plain seconds
let private stressDuration (args: list<string>) : result<option<int> * list<string>, string> =
  let rec go (acc: list<string>) (rest: list<string>) : result<option<int> * list<string>, string> =
    match rest with
    | [ "--stress" ] -> Error "zs test --stress takes a duration: 30s, 10m or 1h"
    | "--stress" :: d :: more ->
      let n = String.length d
      let (digits, scale) =
        if n > 1 && String.endsWith "s" d then (String.sub d 0 (n - 1), 1000)
        else if n > 1 && String.endsWith "m" d then (String.sub d 0 (n - 1), 60000)
        else if n > 1 && String.endsWith "h" d then (String.sub d 0 (n - 1), 3600000)
        else (d, 1000)
      match Int.parse digits with
      | Some k when k > 0 -> Ok(Some(k * scale), List.append (List.rev acc) more)
      | _ -> Error $"zs test --stress takes a duration such as 30s, 10m or 1h, not '{d}'"
    | a :: more -> go (a :: acc) more
    | [] -> Ok(None, List.rev acc)
  go [] args

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

// zs test --target <chip> (0009, D11): the file's tests built into one image and run under the
// chip's runner (QEMU's board, or probe-rs on a real one) in one process, its output read: `ok
// path` and `skip path` as the image prints them, and a panic after `test path` failing that test
// and ending the run, the test's own output shown then. The passed, failed and skipped, or None
// when the image didn't build.
let private runOnChip (o: Options.Options) (src: string) (m: Options.Mcu) : option<int * int * int> =
  let exe = scratchExe ()
  if Make.build { o with main = src; out = exe } true <> 0 then
    File.delete exe |> ignore
    None
  else
    let output =
      match Tools.runSplit "timeout" (List.concat [ [ "--kill-after=1"; "120"; List.head m.runner ]; List.tail m.runner; [ exe ] ]) with
      | Ok r -> r.out + "\n" + r.err
      | Error e -> e
    File.delete exe |> ignore
    let passed = ref 0
    let failed = ref 0
    let skipped = ref 0
    // the test running, and what it printed so far (shown only when it fails)
    let current = ref ""
    let said = Buffer.empty
    let fail (why: string) =
      failed.Value <- failed.Value + 1
      println $"FAIL {current.Value}"
      for l in Buffer.toArray said do
        println $"       {l}"
      if why <> "" then
        println $"       {why}"
      current.Value <- ""
      Buffer.clear said
    // a panic's text may span lines (a property's message and its replay seed): they're kept
    // with it until the run's next test, its exit line or its end
    let panicking = ref false
    let endPanic () =
      if panicking.Value then
        panicking.Value <- false
        fail ""
    for line in String.splitLines output do
      if panicking.Value && not (String.startsWith "#zs " line || String.startsWith "test " line || String.trim line = "") then
        Buffer.push line said
      else if String.startsWith "test " line then
        endPanic ()
        current.Value <- String.sub line 5 (String.length line - 5)
        Buffer.clear said
      else if String.startsWith "ok   " line && current.Value <> "" then
        passed.Value <- passed.Value + 1
        println line
        current.Value <- ""
      else if String.startsWith "skip " line then
        skipped.Value <- skipped.Value + 1
        println line
      else if String.startsWith "panic: " line && current.Value <> "" then
        Buffer.push line said
        panicking.Value <- true
      else if String.startsWith "#zs " line || String.endsWith " skipped" line || String.trim line = "" then
        endPanic ()
      else if current.Value <> "" then
        Buffer.push line said
    endPanic ()
    if current.Value <> "" then
      fail "ended without finishing (a hang, or the chip stopped)"
    Some(passed.Value, failed.Value, skipped.Value)

// builds a file's [<Tests>] values and runs each test in its own process (0009), a sequenced
// group's tests one after another, each within its time limit. args: filters (a path ending in /
// is a prefix; else a part of the path), --summary, --fail-on-focused, --update. stress: for that
// many milliseconds, the tests at random on every core, over and over (D4). The passed, failed
// and skipped, or None when it didn't build.
// zs test --coverage (D10): the test binary built with a counter per line of the test's files
// (the test file's directory down), each test's process writing them at exit to <exe>.zscov;
// the lines run and not run per file, and coverage.lcov for genhtml and the tools that read lcov
let private coverageReport (src: string) (exe: string) =
  let path = exe + ".zscov"
  match File.readAllText path with
  | Error _ -> println "coverage: nothing recorded (did every test fail to start?)"
  | Ok text ->
    let add (m: Map<string * int, i64>) (line: string) =
      match String.split "\t" line with
      | [ file; l; c ] ->
        match ((Int.parse l : option<int>), (Int.parse c : option<i64>)) with
        | (Some ln, Some n) ->
          let key = (file, ln)
          Map.add key (n + Option.defaultValue (i64 0) (Map.tryFind key m)) m
        | _ -> m
      | _ -> m
    let counts = List.fold add Map.empty (String.split "\n" text)
    let files = List.distinct (List.map (fun ((f, _), _) -> f) (Map.toList counts))
    // runs of lines not run: 9, 21-23
    let ranges (lines: list<int>) : string =
      let rec go (acc: list<string>) (start: int) (prev: int) (rest: list<int>) =
        match rest with
        | l :: more when l = prev + 1 -> go acc start l more
        | l :: more -> go ((if start = prev then $"{start}" else $"{start}-{prev}") :: acc) l l more
        | [] -> List.rev ((if start = prev then $"{start}" else $"{start}-{prev}") :: acc)
      match lines with
      | first :: more -> String.join ", " (go [] first first more)
      | [] -> ""
    let cwd = Environment.currentDirectory ()
    let lcov = Buffer.empty
    println "coverage:"
    for file in List.sort files do
      let lines = List.sort (List.map (fun ((_, l), _) -> l) (List.filter (fun ((f, _), _) -> f = file) (Map.toList counts)))
      let hit (l: int) = Option.defaultValue (i64 0) (Map.tryFind (file, l) counts) > i64 0
      let covered = List.filter hit lines
      let missed = List.filter (fun l -> not (hit l)) lines
      let total = List.length lines
      let pct = if total = 0 then 100 else (100 * List.length covered) / total
      let shown = Path.getRelativePath cwd (Path.getFullPath file)
      println $"  {shown}: {List.length covered} of {total} lines ({pct}%){(if List.isEmpty missed then "" else $", not run: {ranges missed}")}"
      Buffer.push $"TN:\nSF:{Path.getFullPath file}" lcov
      for l in lines do
        Buffer.push $"DA:{l},{Option.defaultValue (i64 0) (Map.tryFind (file, l) counts)}" lcov
      Buffer.push $"LF:{total}\nLH:{List.length covered}\nend_of_record" lcov
    // appended: a project's test files each add theirs (zs test empties it first)
    match File.appendAllText "coverage.lcov" (String.join "\n" (Array.toList (Buffer.toArray lcov)) + "\n") with
    | Ok _ -> println "coverage written to coverage.lcov (genhtml -o coverage coverage.lcov renders it)"
    | Error e -> println $"coverage.lcov: {e}"
  File.delete path |> ignore

let private runTests (o: Options.Options) (src: string) (args: list<string>) (stress: option<int>) : option<int * int * int> =
  match o.mcu with
  | Some m when not (List.isEmpty m.runner) -> runOnChip o src m
  | Some m ->
    eprintln $"zs test --target {m.name}: tests run on a chip's board (QEMU's, or a real one through probe-rs) or on this machine"
    None
  | None ->
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
      // every test, property and benchmark (run once, as a test of its body; zs bench times it)
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
        let updates = Buffer.empty
        // a failure shown: its output, and its time limit when it hit it; the expect records kept
        // for --update
        let showFailure (l: Leaf) (code: option<int>) (output0: string) =
          println $"FAIL {l.path}"
          let (records, output) = expectRecords output0
          for r in records do
            Buffer.push r updates
          for line in String.split "\n" (String.trim output) do
            if line <> "" then
              println $"       {line}"
          if Option.isNone code then
            println $"       timed out after {float l.timeout / 1000.0} s"
        let failed = ref 0
        let skipped = ref 0
        let passed = ref 0
        match stress with
        | Some ms when List.exists runs chosen ->
          // over and over at random, a worker per core, each run its own process as always: what
          // one run hides (a race, a leak on a rare path, a timeout under load) shows; each failing
          // test is shown once, with its first failure
          let arr = Array.ofList (List.filter runs chosen)
          let n = Array.length arr
          let workers = max 1 (Parallel.workers ())
          let started = Runtime.ticks ()
          let deadline = started + u64 ms * u64 1000000
          // stage 0's library is what src/ compiles with: a xorshift of its own, not Random
          let worker (w: int) : int * array<Leaf * option<int> * string> =
            let mutable s = Int.wrappingAdd started (Int.wrappingMul (u64 (w + 1)) (u64 0x9E3779B97F4A7C15))
            let failures = Buffer.empty
            let mutable count = 0
            while Runtime.ticks () < deadline do
              s <- s ^^^ (s <<< u64 13)
              s <- s ^^^ (s >>> u64 7)
              s <- s ^^^ (s <<< u64 17)
              let l = arr.[int (s % u64 n)]
              let (code, output) = runLeaf exe l
              count <- count + 1
              if not (passedRun code output) then
                Buffer.push (l, code, output) failures
            (count, Buffer.toArray failures)
          let results = Array.Parallel.map worker (Array.init workers (fun w -> w))
          let total = Array.fold (fun acc (c, _) -> acc + c) 0 results
          let shown = ref Set.empty
          for (_, fs) in results do
            for (l, code, output) in fs do
              failed.Value <- failed.Value + 1
              if not (Set.contains l.path shown.Value) then
                shown.Value <- Set.add l.path shown.Value
                showFailure l code output
          passed.Value <- total - failed.Value
          skipped.Value <- List.length chosen - n
          println $"stress: {total} runs of {n} tests on {workers} cores for {ms / 1000} s, {failed.Value} failed"
        | _ ->
          // ponytail: one test at a time; up to the cores at once as tasks when runs get long
          let results = Map.ofList (List.map (fun (l: Leaf) -> (l.path, (if l.kind = "property" then runProperty exe src l else runLeaf exe l))) (List.filter runs chosen))
          for l in chosen do
            match Map.tryFind l.path results with
            | Some(code, output) when passedRun code output ->
              passed.Value <- passed.Value + 1
              println $"ok   {l.path}"
            | Some(code, output) ->
              failed.Value <- failed.Value + 1
              showFailure l code output
            | None ->
              skipped.Value <- skipped.Value + 1
              println $"skip {l.path}{(if l.focus = "pending" then " (pending)" else "")}"
        if List.contains "--update" args then
          for (file, line, text) in Buffer.toArray updates do
            let path = Path.combine (dirOf src) file
            if File.exists path && updateExpect path line text then
              println $"updated {file}:{line}"
        if o.coverage then
          coverageReport src exe
        // each property's side files (its case and its record) go with the binary
        for l in chosen do
          if l.kind = "property" then
            let (caseFile, recordFile) = propertyFiles exe l
            File.delete caseFile |> ignore
            File.delete recordFile |> ignore
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
        // this user's cache, not the shared temporary directory: there another user could put
        // .zs-doctest.zs first and change it between its writing and its build, which runs it
        | _ -> (Path.combine (Tools.cacheRoot ()) "doctest", None)
      Tools.makeDirectory dir
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

// zs bench [file.zs] [filters…] [--runs n] (0009, D9): the file's benchmarks (bench values among
// its [<Tests>]), each timed in a process of its own: three warm-up runs, then n runs (30 unless
// --runs says), whose median and 95% confidence interval (the order statistics) are shown. The
// results are saved beside the file (.zs-cache/bench/<file>.tsv), and a benchmark whose interval
// doesn't overlap the saved one's, by at least 10% (a machine's load moves a median by a few
// percent between runs), is reported slower or faster.
type private Stat = { path: string; median: i64; lo: i64; hi: i64 }

let private statOf (path: string) (samples: list<i64>) : Stat =
  let sorted = List.sort samples
  let n = List.length sorted
  // the value at a 1-based rank, within the samples
  let at (rank: int) = List.item (max 0 (min (n - 1) (rank - 1))) sorted
  let half = 1.96 * Math.sqrt (float n)
  // the ranks, rounded down and up (both positive: a conversion truncates)
  let hiF = 1.0 + (float n + half) / 2.0
  { path = path
    median = (if n % 2 = 1 then at ((n + 1) / 2) else (at (n / 2) + at (n / 2 + 1)) / i64 2)
    lo = at (int ((float n - half) / 2.0))
    hi = at (int hiF + (if float (int hiF) < hiF then 1 else 0)) }

let private shownNs (ns: i64) : string =
  if ns >= i64 1000000000 then $"{float ns / 1000000000.0:F2} s"
  else if ns >= i64 1000000 then $"{float ns / 1000000.0:F2} ms"
  else if ns >= i64 1000 then $"{float ns / 1000.0:F1} µs"
  else $"{ns} ns"

let private benchFile (o: Options.Options) (src: string) (filters: list<string>) (runs: int) : int =
  let exe = scratchExe ()
  if Make.build { o with main = src; out = exe } true <> 0 then
    File.delete exe |> ignore
    1
  else
    let listed =
      match Tools.runSplit exe [ "--list" ] with
      | Ok r -> r.out
      | Error _ -> ""
    let leaves = List.filter (fun (l: Leaf) -> l.kind = "bench") (List.choose leafOf (List.filter (fun l -> l <> "") (String.split "\n" listed)))
    let wanted (l: Leaf) = List.isEmpty filters || List.exists (fun (f: string) -> String.contains f l.path) filters
    let chosen = List.filter wanted leaves
    if List.isEmpty chosen then
      println (if List.isEmpty leaves then $"{src}: no benchmarks (a bench value among its [<Tests>])" else $"no benchmark's path matches {String.join " " filters}")
      File.delete exe |> ignore
      0
    else
      // the last run's results, by path
      let dir = Path.combine (Path.combine (dirOf src) ".zs-cache") "bench"
      let saved = Path.combine dir (Path.getFileNameWithoutExtension src + ".tsv")
      let last =
        match File.readAllText saved with
        | Ok text ->
          let one (line: string) =
            match String.split "\t" line with
            | [ p; m; l; h ] ->
              match ((Int.parse m : option<i64>), (Int.parse l : option<i64>), (Int.parse h : option<i64>)) with
              | (Some m, Some l, Some h) -> Some(p, { path = p; median = m; lo = l; hi = h })
              | _ -> None
            | _ -> None
          Map.ofList (List.choose one (String.split "\n" text))
        | Error _ -> Map.empty
      let changed = ref 0
      let failed = ref 0
      let results = Buffer.empty
      for l in chosen do
        match Tools.runSplit exe [ "--bench"; l.path; string runs ] with
        | Ok r when r.code = 0 ->
          let samples = List.choose (fun (w: string) -> (Int.parse w : option<i64>)) (String.split " " (String.trim r.out))
          let s = statOf l.path samples
          Buffer.push s results
          let change =
            match Map.tryFind l.path last with
            | Some was ->
              let ratio = float s.median / float (max (i64 1) was.median)
              if s.lo > was.hi && ratio >= 1.1 then
                changed.Value <- changed.Value + 1
                $"  slower by {int ((ratio - 1.0) * 100.0 + 0.5)}% (was {shownNs was.median})"
              else if s.hi < was.lo && ratio <= 0.9 then
                changed.Value <- changed.Value + 1
                $"  faster by {int ((1.0 - ratio) * 100.0 + 0.5)}% (was {shownNs was.median})"
              else
                ""
            | None -> "  new"
          println $"bench {l.path}: {shownNs s.median} [{shownNs s.lo}, {shownNs s.hi}] ({runs} runs){change}"
        | Ok r ->
          failed.Value <- failed.Value + 1
          println $"FAIL {l.path}"
          for line in String.split "\n" (String.trim (r.out + r.err)) do
            if line <> "" then
              println $"       {line}"
        | Error e ->
          failed.Value <- failed.Value + 1
          println $"FAIL {l.path}: {e}"
      File.delete exe |> ignore
      // every benchmark run this time replaces its saved result; the others keep theirs
      let kept = List.filter (fun (p, _) -> not (List.exists (fun (s: Stat) -> s.path = p) (Array.toList (Buffer.toArray results)))) (Map.toList last)
      let lines = List.map (fun (s: Stat) -> $"{s.path}\t{s.median}\t{s.lo}\t{s.hi}") (List.append (List.map snd kept) (Array.toList (Buffer.toArray results)))
      Tools.makeDirectory dir
      File.writeAllText saved (String.join "\n" lines + "\n") |> ignore
      let n = Buffer.length results
      println $"{n} benchmark{(if n = 1 then "" else "s")}, {(if changed.Value = 0 then "none" else string changed.Value)} changed{(if failed.Value = 0 then "" else $", {failed.Value} failed")}"
      if failed.Value = 0 then 0 else 1

let bench (args: list<string>) : int =
  match Options.parse args with
  | Error e ->
    eprintln e
    2
  | Ok(o, rest) ->
    // --runs n: the timed runs per benchmark (30 unless said)
    let rec runsIn (xs: list<string>) : result<int, string> =
      match xs with
      | "--runs" :: n :: _ ->
        match (Int.parse n : option<int>) with
        | Some k when k >= 3 -> Ok k
        | _ -> Error $"zs bench --runs takes a count of 3 or more, not '{n}'"
      | [ "--runs" ] -> Error "zs bench --runs takes a count: --runs 50"
      | _ :: more -> runsIn more
      | [] -> Ok 30
    match runsIn rest with
    | Error e ->
      eprintln e
      2
    | Ok runs ->
      let rec args0 (xs: list<string>) : list<string> =
        match xs with
        | "--runs" :: _ :: more -> args0 more
        | x :: more -> x :: args0 more
        | [] -> []
      let plain = args0 rest
      let filters = List.filter (fun (a: string) -> not (isFile a) && not (String.startsWith "--" a)) plain
      match List.filter isFile plain with
      | src :: _ -> if fetched o.offline (dirOf src) then benchFile o src filters runs else 1
      | [] ->
        eprintln "zs bench takes the file whose benchmarks to run: zs bench tests/perf.zs [filters] [--runs 50]"
        2

// zs fuzz file.zs path [--for n] [-- flags…] (0010 step 5, D6): the file's tests built with
// libFuzzer and the sanitizers, and the property named run under it for n seconds (60 unless
// --for says; the flags after -- are libFuzzer's), its inputs the property's bytes (Gen.bytes
// takes an input whole). The corpus is kept beside the file (.zs-cache/fuzz/<path>/), so a run
// resumes. A crash is a failing case: shrunk by replays of the binary, shown, and saved as
// zs test's failure, replayed first
let fuzz (args: list<string>) : int =
  match Options.parse args with
  | Error e ->
    eprintln e
    2
  | Ok(o, rest) ->
    // what follows -- is libFuzzer's (the option parser keeps it apart)
    let ours = rest
    let theirs = o.rest
    let rec timeIn (xs: list<string>) : result<int, string> =
      match xs with
      | "--for" :: n :: _ ->
        match (Int.parse n : option<int>) with
        | Some k when k >= 1 -> Ok k
        | _ -> Error $"zs fuzz --for takes the seconds, not '{n}'"
      | [ "--for" ] -> Error "zs fuzz --for takes the seconds: --for 60"
      | _ :: more -> timeIn more
      | [] -> Ok 60
    let rec withoutTime (xs: list<string>) : list<string> =
      match xs with
      | "--for" :: _ :: more -> withoutTime more
      | x :: more -> x :: withoutTime more
      | [] -> []
    match timeIn ours with
    | Error e ->
      eprintln e
      2
    | Ok seconds ->
      let plain = withoutTime ours
      match (List.filter isFile plain, List.filter (fun (a: string) -> not (isFile a) && not (String.startsWith "--" a)) plain) with
      | (src :: _, wanted :: _) ->
        if not (fetched o.offline (dirOf src)) then
          1
        else
          let exe = scratchExe ()
          if Make.build { o with main = src; out = exe; fuzz = true; sanitize = true } true <> 0 then
            File.delete exe |> ignore
            1
          else
            let listed =
              match Tools.runSplit exe [ "--list" ] with
              | Ok r -> r.out
              | Error _ -> ""
            let leaves = List.filter (fun (l: Leaf) -> l.kind = "property") (List.choose leafOf (List.filter (fun l -> l <> "") (String.split "\n" listed)))
            let exact = List.tryFind (fun (l: Leaf) -> l.path = wanted) leaves
            match (if Option.isSome exact then exact else List.tryFind (fun (l: Leaf) -> String.contains wanted l.path) leaves) with
            | None ->
              println (if List.isEmpty leaves then $"{src}: no properties" else $"no property's path matches {wanted} (they are {String.join ", " (List.map (fun (l: Leaf) -> l.path) leaves)})")
              File.delete exe |> ignore
              1
            | Some l ->
              let corpus = Path.combine (Path.combine (Path.combine (dirOf src) ".zs-cache") "fuzz") (cacheKey src l.path)
              Tools.makeDirectory corpus
              let crashes = exe + ".crashes"
              Tools.makeDirectory crashes
              let flags = List.concat [ [ corpus; $"-max_total_time={seconds}"; $"-artifact_prefix={crashes}/" ]; theirs ]
              println $"fuzzing {l.path} for {seconds} s (corpus: {Path.getRelativePath (Environment.currentDirectory ()) corpus})"
              let ran = Tools.runSplit exe (List.concat [ [ l.path; "--fuzz" ]; flags ])
              let found =
                match Directory.list crashes with
                | Ok names -> List.sort (List.filter (fun (n: string) -> String.startsWith "crash-" n || String.startsWith "timeout-" n || String.startsWith "oom-" n) names)
                | Error _ -> []
              let inputs =
                match Directory.list corpus with
                | Ok names -> List.length names
                | Error _ -> 0
              let code =
                match found with
                | [] ->
                  match ran with
                  | Ok r when r.code = 0 ->
                    println $"no failure in {seconds} s; {inputs} inputs in the corpus"
                    0
                  | Ok r ->
                    println $"libFuzzer stopped with {r.code}:"
                    for line in List.filter (fun (s: string) -> s <> "") (String.split "\n" r.err) do
                      println $"       {line}"
                    1
                  | Error e ->
                    println e
                    1
                | name :: _ ->
                  match File.readAllBytes (Path.combine crashes name) with
                  | Ok bytes0 ->
                    // the input is the case's bytes at size 100, as the runner replays them
                    let size = 100
                    let file = exe + ".try"
                    let (bytes, runs) = shrinkByReplay exe l size bytes0 file
                    File.writeAllText file (hexOf bytes) |> ignore
                    let (_, shown) = replayCase exe l file size
                    File.delete file |> ignore
                    let saved = failureFile src l.path
                    Tools.makeDirectory (Path.getDirectoryName saved)
                    File.writeAllText saved $"{size}\n{hexOf bytes}\n" |> ignore
                    println $"FAIL {l.path}"
                    for line in List.filter (fun (s: string) -> s <> "") (String.split "\n" (String.trim shown)) do
                      println $"       {line}"
                    // the input as bytes: what a property over Gen.bytes saw
                    println $"       input: [| {String.join "; " (List.map (fun (b: u8) -> string (int b)) (Array.toList bytes))} |]"
                    println $"       found by libFuzzer ({inputs} inputs in the corpus); shrunk from {Array.length bytes0} bytes to {Array.length bytes} in {runs} runs; saved as {Path.getRelativePath (Environment.currentDirectory ()) saved}, which zs test replays first"
                    1
                  | Error e ->
                    println $"{name}: {e}"
                    1
              match Directory.list crashes with
              | Ok names ->
                for n in names do
                  File.delete (Path.combine crashes n) |> ignore
              | Error _ -> ()
              Directory.delete crashes |> ignore
              File.delete exe |> ignore
              code
      | (_ :: _, []) ->
        eprintln "zs fuzz takes the property's path too: zs fuzz tests/parse.zs parser/parses"
        2
      | _ ->
        eprintln "zs fuzz takes the file and the property's path: zs fuzz tests/parse.zs parser/parses [--for 60] [-- libFuzzer flags]"
        2

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
  | Ok(o, rest0) ->
    match stressDuration rest0 with
    | Error e ->
      eprintln e
      2
    | Ok(stress, rest) ->
        // each file's tests add their lines to coverage.lcov: this run's, not an earlier one's
        if o.coverage then
          File.delete "coverage.lcov" |> ignore
        // the filters, and the flags only zs test takes (--update, --summary, --fail-on-focused)
        let filters = List.filter (fun a -> not (isFile a)) rest
        match List.filter isFile rest with
        | src :: _ ->
          if not (fetched o.offline (dirOf src)) then
            1
          else
            match runTests o src filters stress with
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
            // a workspace: every member's tests (0018 item 8)
            let projects = membersOf m
            if not (List.forall (fun (p: Project.Manifest) -> fetched o.offline p.root) projects) then
              1
            else
              let under (p: Project.Manifest) (d: string) : list<string> =
                let dir = Path.combine p.root d
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
              let files = List.collect (fun (p: Project.Manifest) -> List.filter hasTests (List.append (under p "src") (under p "tests"))) projects
              // a stress run's time shared among the files
              let each = Option.map (fun ms -> max 1000 (ms / max 1 (List.length files))) stress
              let runFile (f: string) =
                println (Path.getRelativePath (Environment.currentDirectory ()) f)
                runTests o f filters each
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

