/// The compiler front end shared by the command line and the language server: loading the
/// main file's modules (from disk, or from an editor's unsaved buffers), and the full pipeline.
module Driver

open System
open System.Collections.Generic
open System.Diagnostics
open System.IO
open Syntax

let runtimeFile name = Path.Combine(AppContext.BaseDirectory, name)

/// Unsaved editor buffers by full path; read instead of the file on disk.
let overlay = Dictionary<string, string>()

let readSource (path: string) =
    match overlay.TryGetValue(Path.GetFullPath path) with
    | true, text -> text
    | _ -> File.ReadAllText path

let parseFile (path: string) =
    try
        let toks = readSource path |> lex
        toks, parse toks
    with
    | CompileError(l, m) -> raise (CompileErrorAt(path, l, 0, m))
    | CompileErrorPos(l, c, m) -> raise (CompileErrorAt(path, l, c, m))

/// A zs.toml manifest:
///   [package]  name = "wc"  version = "0.1.0"  main = "src/main.zs" (the default)
///   [dependencies]  text = { path = "../text" }  json = { git = "https://…", rev = "v1" }
type Dep =
    | PathDep of string // full path of the dependency's directory
    | GitDep of url: string * rev: string // rev: a tag, branch or commit ("" = the default branch)

type Manifest =
    { root: string // the directory holding zs.toml
      name: string
      version: string
      main: string // full path
      deps: (string * Dep) list }

/// { k = "v", … } as a dictionary, or the problem with it.
let private tableFields (value: string) : Result<Dictionary<string, string>, string> =
    let unquote (v: string) =
        let v = v.Trim()
        if v.Length >= 2 && v.StartsWith "\"" && v.EndsWith "\"" then Some(v.Substring(1, v.Length - 2)) else None

    if not (value.StartsWith "{" && value.EndsWith "}") then
        Error "expected a table such as { path = \"../text\" }"
    else
        let d = Dictionary<string, string>()
        let mutable bad = None

        for f in value.Trim('{', '}').Split ',' do
            if f.Trim() <> "" then
                match f.Split('=', 2) with
                | [| k; v |] when (unquote v).IsSome -> d[k.Trim()] <- (unquote v).Value
                | _ -> bad <- Some f

        match bad with
        | Some f -> Error(sprintf "expected key = \"value\" inside { }, found %s" (f.Trim()))
        | None -> Ok d

/// Reads the subset of TOML a manifest uses: [sections], key = "string", key = { k = "v", … }.
let readManifest (root: string) : Manifest =
    let file = Path.Combine(root, "zs.toml")
    let fail (n: int) msg = raise (CompileErrorAt(file, n, 0, msg))
    let mutable section = ""
    let package = Dictionary<string, string>()
    let deps = ResizeArray<string * Dep>()
    let unquote (n: int) (v: string) =
        let v = v.Trim()
        if v.Length >= 2 && v.StartsWith "\"" && v.EndsWith "\"" then v.Substring(1, v.Length - 2)
        else fail n (sprintf "expected a quoted string, found %s" v)

    File.ReadAllLines file
    |> Array.iteri (fun i raw ->
        let n = i + 1
        let line = (if raw.Contains '#' then raw.Substring(0, raw.IndexOf '#') else raw).Trim()

        if line = "" then ()
        elif line.StartsWith "[" && line.EndsWith "]" then section <- line.Trim('[', ']').Trim()
        else
            match line.IndexOf '=' with
            | -1 -> fail n "expected key = value"
            | eq ->
                let key, value = line.Substring(0, eq).Trim(), line.Substring(eq + 1).Trim()

                match section with
                | "package" -> package[key] <- unquote n value
                | "dependencies" ->
                    let fields =
                        match tableFields value with
                        | Ok f -> f
                        | Error msg -> fail n (sprintf "dependency '%s': %s" key msg)

                    match fields.TryGetValue "path", fields.TryGetValue "git" with
                    | (true, p), _ -> deps.Add(key, PathDep(Path.GetFullPath(Path.Combine(root, p))))
                    | _, (true, url) ->
                        let rev =
                            [ "rev"; "tag"; "branch" ]
                            |> List.tryPick (fun k ->
                                match fields.TryGetValue k with
                                | true, v -> Some v
                                | _ -> None)

                        deps.Add(key, GitDep(url, defaultArg rev ""))
                    | _ -> fail n (sprintf "dependency '%s' needs a path or a git URL" key)
                | s -> fail n (sprintf "unknown section [%s]" s))

    let get k d =
        match package.TryGetValue k with
        | true, v -> v
        | _ -> d

    { root = root
      name = get "name" (Path.GetFileName root)
      version = get "version" "0.1.0"
      main = Path.GetFullPath(Path.Combine(root, get "main" "src/main.zs"))
      deps = List.ofSeq deps }

/// The nearest zs.toml at or above a directory.
let rec findProject (dir: string) : Manifest option =
    if isNull dir then None
    elif File.Exists(Path.Combine(dir, "zs.toml")) then Some(readManifest dir)
    else findProject (Path.GetDirectoryName dir)

/// Where a git dependency is checked out: <project>/.zs-cache/deps/<name>.
let gitDir (top: Manifest) (name: string) = Path.Combine(top.root, ".zs-cache", "deps", name)

let private depPath (top: Manifest) (name: string) (d: Dep) =
    match d with
    | PathDep p -> p
    | GitDep _ -> gitDir top name

/// Where a file's modules are looked up: its own directory, then (inside a project) the
/// source directory (the one holding `main`) of each dependency, transitively. Git
/// dependencies must have been fetched (zs fetch, or any zs build/run/test/check).
let moduleDirs (file: string) : string list =
    let dir = Path.GetDirectoryName(Path.GetFullPath file)

    let rec depDirs (top: Manifest) (seen: Set<string>) (m: Manifest) =
        m.deps
        |> List.fold
            (fun (seen: Set<string>, acc) (name, dep) ->
                let path = depPath top name dep

                if seen.Contains path then
                    seen, acc
                elif not (File.Exists(Path.Combine(path, "zs.toml"))) then
                    let msg =
                        match dep with
                        | GitDep _ when not (Directory.Exists path) -> sprintf "git dependency '%s' isn't fetched yet: run zs fetch" name
                        | _ -> sprintf "dependency '%s': no zs.toml in %s" name path

                    raise (CompileErrorAt(Path.Combine(m.root, "zs.toml"), 0, 0, msg))
                else
                    let dm = readManifest path
                    let seen, more = depDirs top (seen.Add path) dm
                    seen, acc @ [ Path.GetDirectoryName dm.main ] @ more)
            (seen, [])

    match findProject dir with
    | Some m -> dir :: (snd (depDirs m (Set.singleton m.root) m) |> List.filter ((<>) dir)) |> List.distinct
    | None -> [ dir ]

/// Runs git; Ok stdout or Error with its message.
let private git (args: string list) =
    let psi = ProcessStartInfo "git"

    for a in args do
        psi.ArgumentList.Add a

    psi.RedirectStandardOutput <- true
    psi.RedirectStandardError <- true
    psi.Environment["GIT_TERMINAL_PROMPT"] <- "0" // fail instead of asking for a password

    try
        use p = Process.Start psi
        let out = p.StandardOutput.ReadToEndAsync()
        let err = p.StandardError.ReadToEndAsync()
        p.WaitForExit()
        if p.ExitCode = 0 then Ok(out.Result.Trim()) else Error(err.Result.Trim())
    with :? ComponentModel.Win32Exception ->
        Error "git isn't installed"

/// zs.lock: the commit each git dependency resolved to, with the URL and rev it came from.
///   [dependencies]
///   json = { git = "https://…", rev = "v1", commit = "<sha>" }
let private readLock (root: string) =
    let file = Path.Combine(root, "zs.lock")
    let lock = Dictionary<string, string * string * string>()

    if File.Exists file then
        for line in File.ReadAllLines file do
            match line.IndexOf '=' with
            | eq when eq > 0 && not (line.TrimStart().StartsWith "#") ->
                match tableFields (line.Substring(eq + 1).Trim()) with
                | Ok fields when fields.ContainsKey "git" && fields.ContainsKey "commit" ->
                    let rev =
                        match fields.TryGetValue "rev" with
                        | true, r -> r
                        | _ -> ""

                    lock[line.Substring(0, eq).Trim()] <- (fields["git"], rev, fields["commit"])
                | _ -> ()
            | _ -> ()

    lock

let private writeLock (root: string) (entries: (string * (string * string * string)) list) =
    let lines =
        [ "# zs.lock: the exact commits of git dependencies. zs update moves them to the newest"
          "# commit of their rev; commit this file so every build uses the same code."
          "[dependencies]" ]
        @ (entries
           |> List.sortBy fst
           |> List.map (fun (name, (url, rev, commit)) ->
               sprintf "%s = { git = \"%s\", rev = \"%s\", commit = \"%s\" }" name url rev commit))

    File.WriteAllText(Path.Combine(root, "zs.lock"), String.concat "\n" lines + "\n")

/// Checks out every git dependency of the project (and of its dependencies) at the commit in
/// zs.lock. A new dependency, a changed URL or rev, or update = true resolves the rev again
/// (fetching when needed) and records the new commit. Returns error messages.
let fetchDeps (top: Manifest) (update: bool) : string list =
    let lock = readLock top.root
    let resolved = Dictionary<string, string * string * string>()
    let errors = ResizeArray<string>()
    let visited = HashSet<string>()

    let checkout (name: string) (url: string) (rev: string) =
        let dir = gitDir top name

        let locked =
            match lock.TryGetValue name with
            | true, (u, r, c) when u = url && r = rev && not update -> Some c
            | _ -> None

        let head () = git [ "-C"; dir; "rev-parse"; "HEAD" ]

        let cloned =
            if Directory.Exists(Path.Combine(dir, ".git")) then
                Ok()
            else
                if Directory.Exists dir then
                    Directory.Delete(dir, true)

                Directory.CreateDirectory(Path.GetDirectoryName dir) |> ignore
                eprintfn "fetching %s from %s" name url
                git [ "clone"; "--quiet"; "--"; url; dir ] |> Result.map ignore

        let result =
            cloned
            |> Result.bind (fun () ->
                match locked with
                | Some c when head () = Ok c -> Ok c // already checked out: no network
                | Some c ->
                    // the locked commit: fetch only if this clone doesn't have it
                    let have = git [ "-C"; dir; "cat-file"; "-e"; c + "^{commit}" ]
                    let fetched = if Result.isOk have then Ok "" else git [ "-C"; dir; "fetch"; "--quiet"; "--tags"; "origin" ]
                    fetched |> Result.bind (fun _ -> git [ "-C"; dir; "checkout"; "--quiet"; "--detach"; c ]) |> Result.bind (fun _ -> head ())
                | None ->
                    // resolve the rev on the remote's current state: a branch means origin's branch
                    eprintfn "resolving %s %s" name (if rev = "" then "(default branch)" else rev)

                    git [ "-C"; dir; "fetch"; "--quiet"; "--tags"; "--force"; "origin" ]
                    |> Result.bind (fun _ ->
                        let target =
                            if rev = "" then "origin/HEAD"
                            elif Result.isOk (git [ "-C"; dir; "rev-parse"; "--verify"; "--quiet"; "refs/remotes/origin/" + rev ]) then "origin/" + rev
                            else rev

                        git [ "-C"; dir; "checkout"; "--quiet"; "--detach"; target ])
                    |> Result.bind (fun _ -> head ()))

        match result with
        | Ok commit ->
            resolved[name] <- (url, rev, commit)
            true
        | Error e ->
            errors.Add(sprintf "git dependency '%s' (%s%s): %s" name url (if rev = "" then "" else " " + rev) e)
            false

    let rec visit (m: Manifest) =
        for name, dep in m.deps do
            match dep with
            | GitDep(url, rev) ->
                match resolved.TryGetValue name with
                | true, (u, _, _) when u <> url -> errors.Add(sprintf "two git dependencies are named '%s': %s and %s" name u url)
                | true, _ -> ()
                | _ ->
                    let dir = gitDir top name

                    if checkout name url rev && File.Exists(Path.Combine(dir, "zs.toml")) && visited.Add dir then
                        visit (readManifest dir)
            | PathDep p ->
                if File.Exists(Path.Combine(p, "zs.toml")) && visited.Add p then
                    visit (readManifest p)

    visit top

    if errors.Count = 0 && (resolved.Count > 0 || File.Exists(Path.Combine(top.root, "zs.lock"))) then
        writeLock top.root [ for KeyValue(n, v) in resolved -> n, v ]

    List.ofSeq errors

/// What [<Link "...">] on an `import c` asked for: library names (-lname) and C, object or
/// archive files (full paths), collected while loading the program's modules.
let links = ResizeArray<string>()

/// Replaces `import c` declarations with the header's declarations (headers are found next
/// to the importing file, then on the system include path).
let private expandImports (path: string) (decls: (int * Decl) list) =
    let dir = Path.GetDirectoryName(Path.GetFullPath path)

    decls
    |> List.collect (fun (ln, d) ->
        let imported header =
            try
                let root =
                    match findProject dir with
                    | Some m -> m.root
                    | None -> dir

                CImport.importHeader header dir (Path.Combine(root, ".zs-cache", "cimport"))
            with CompileError(_, msg) ->
                raise (CompileErrorAt(path, ln, 0, msg))

        match d with
        | ImportC header -> imported header
        | Attrs(attrs, ImportC header) ->
            for a, args in attrs do
                if a <> "Link" || args.IsEmpty then
                    raise (CompileErrorAt(path, ln, 0, sprintf "unknown attribute '%s' on import c (use [<Link \"lib\">])" a))

                for l in args do
                    let ext = Path.GetExtension l
                    let item = if List.contains ext [ ".c"; ".o"; ".a"; ".so" ] then Path.Combine(dir, l) else l

                    if not (links.Contains item) then
                        links.Add item

            imported header
        | _ -> [ ln, d ])

/// The main file and the modules it uses (`open M` or `M.name`, found as M.zs or m.zs next to
/// it or in a dependency), dependencies first. Each module is named after its file unless it
/// has a `module` header.
let loadModules (mainPath: string) : (string * string option * (int * Decl) list) list =
    let dirs = moduleDirs mainPath
    let order = ResizeArray<string * string option * (int * Decl) list>()
    let finished = Dictionary<string, bool>() // module -> fully loaded?
    let display (p: string) = Path.GetRelativePath(Environment.CurrentDirectory, p)

    let fileOf (m: string) =
        [ for dir in dirs do
              for f in [ m + ".zs"; string (Char.ToLower m[0]) + m.Substring 1 + ".zs" ] -> Path.Combine(dir, f) ]
        |> List.tryFind (fun f -> File.Exists f || overlay.ContainsKey f)

    let rec visit (path: string) (modName: string option) (stack: string list) =
        let toks, decls =
            try
                parseFile path
            with CompileErrorAt(file, l, c, m) when file = path ->
                raise (CompileErrorAt(display path, l, c, m)) // the path as the user knows it, like other errors

        let decls = expandImports path decls

        let modName =
            match decls, modName with
            | (_, ModuleHeader h) :: _, Some _ -> Some h
            | _ -> modName

        let deps =
            [ for _, d in decls do
                  match d with
                  | Open m -> yield m
                  | _ -> ()

              let rec qualified (toks: Token[]) =
                  [ for t in toks do
                        match t.tok with
                        | KId s when s.Contains "." && Char.IsUpper s[0] -> yield s.Substring(0, s.IndexOf '.')
                        | KInterp parts ->
                            for isExpr, text, _ in parts do
                                if isExpr then
                                    yield! qualified (lex text)
                        | _ -> () ]

              yield! qualified toks ]
            |> List.distinct
            |> List.filter (fun m ->
                match fileOf m with
                | Some f -> Some m <> modName && f <> path && f <> Path.GetFullPath mainPath
                | None -> false)

        for m in deps do
            match finished.TryGetValue m with
            | true, true -> ()
            | true, false ->
                raise (CompileErrorAt(display path, 0, 0, sprintf "import cycle: %s" (String.concat " -> " (List.rev (m :: stack)))))
            | _ ->
                finished[m] <- false
                visit (fileOf m).Value (Some m) (m :: stack)
                finished[m] <- true

        order.Add(display path, modName, decls)

    visit (Path.GetFullPath mainPath) None [ Path.GetFileNameWithoutExtension mainPath ]
    // the main file keeps the path the user gave
    let last = order.Count - 1
    let _, m, ds = order[last]
    order[last] <- (mainPath, m, ds)
    List.ofSeq order

/// Parses and type-checks; with collect, every declaration's error is in the result.
let check (mainPath: string) (requireMain: bool) (collect: bool) : Core.Program =
    positions.Clear()
    links.Clear()
    let full = Path.GetFullPath mainPath

    // checking the prelude itself (the installed one, or runtime/prelude.zs in a checkout):
    // it is the prelude, not a program that would define everything a second time
    let isPrelude =
        full = Path.GetFullPath(runtimeFile "prelude.zs")
        || (Path.GetFileName full = "prelude.zs" && Path.GetFileName(Path.GetDirectoryName full) = "runtime")

    if isPrelude then
        let _, decls = parseFile mainPath
        Typer.check false collect [ mainPath, None, decls ]
    else
        let _, prelude = parseFile (runtimeFile "prelude.zs")
        Typer.check requireMain collect (("prelude.zs", None, prelude) :: loadModules mainPath)

/// Source files -> typed Core -> monomorphic -> closure-converted -> RC-annotated -> LLVM IR
/// (and a C header for [<Export>] functions). A library doesn't need `main`.
/// Time spent in each compiler phase of the last build (zs build --time).
let timings = ResizeArray<string * float>()

let private timed (phase: string) (f: unit -> 'a) : 'a =
    let sw = Stopwatch.StartNew()
    let r = f ()
    timings.Add(phase, sw.Elapsed.TotalMilliseconds)
    r

/// zs test: build the [<Test>] functions with a test dispatcher in place of `main`.
let mutable testBuild = false

let compileProgram (mainPath: string) (isLib: bool) =
    timings.Clear()
    let prog = timed "parse + check" (fun () -> check mainPath (not isLib) true)

    let prog =
        if testBuild then { prog with funs = prog.funs |> List.filter (fun f -> f.name <> "main") } else prog

    // a library has no startup to compute values in
    match prog.values with
    | (v, _) :: _ when isLib ->
        raise (CompileErrorAt(mainPath, 0, 0, sprintf "top-level value '%s' is computed at startup, which a library doesn't have; make it a constant or a function" v))
    | _ -> ()

    match prog.errors with
    | first :: _ -> Error prog.errors
    | [] ->
        let funs =
            try
                let mono = timed "monomorphize" (fun () -> Mono.run prog |> Mono.fuse)
                let lifted = timed "lift closures" (fun () -> Lift.run mono)
                timed "reference counting" (fun () -> Rc.run prog.types lifted)
            with CompileError(l, m) ->
                raise (CompileErrorAt(mainPath, l, 0, m))

        Ok(timed "LLVM IR" (fun () -> Codegen.compile prog.types prog.externs prog.exports prog.tests prog.values prog.clayouts funs))

/// Runs a program; with capture, returns its stdout and stderr too (stdin is empty).
let exec (exe: string) (args: string list) (capture: bool) : int * string =
    let psi = ProcessStartInfo exe

    for a in args do
        psi.ArgumentList.Add a

    if capture then
        psi.RedirectStandardOutput <- true
        psi.RedirectStandardError <- true
        psi.RedirectStandardInput <- true

    use p = Process.Start psi

    if capture then
        p.StandardInput.Close()
        let out = p.StandardOutput.ReadToEndAsync()
        let err = p.StandardError.ReadToEndAsync()
        p.WaitForExit()
        p.ExitCode, out.Result + err.Result
    else
        p.WaitForExit()
        p.ExitCode, ""

/// A bare-metal microcontroller target (zs build --target cortex-m4): how clang and zig cc are
/// told about the chip, the QEMU board whose memory map the program is linked for, and the
/// heap size. The program uses runtime/rt-embedded.c instead of the OS runtime.
type Mcu =
    { triple: string // for clang
      cflags: string list
      zigTarget: string
      zigCpu: string
      board: string // runtime/boards/<board>.ld; also the QEMU machine
      heap: int }

let mcus =
    dict
        [ "cortex-m4",
          { triple = "thumbv7em-none-eabihf"
            cflags = [ "-mcpu=cortex-m4"; "-mfpu=fpv4-sp-d16"; "-mfloat-abi=hard" ]
            zigTarget = "thumb-freestanding-eabihf"
            zigCpu = "cortex_m4+vfp4d16sp" // the M4F: Zig's cortex_m4 alone has no FPU
            board = "mps2-an386"
            heap = 64 * 1024 }
          "cortex-m0plus",
          { triple = "thumbv6m-none-eabi"
            cflags = [ "-mcpu=cortex-m0plus"; "-mfloat-abi=soft" ]
            zigTarget = "thumb-freestanding-eabi"
            zigCpu = "cortex_m0plus"
            board = "microbit"
            heap = 8 * 1024 } ]

/// The microcontroller being built for (zs build --target cortex-m4), if any; Codegen.target
/// then holds its triple.
let mutable mcu: Mcu option = None

/// The optimization level for clang: -O2, or -Os (zs build -Os) for size.
let mutable optLevel = "-O2"

/// .zs -> LLVM IR -> clang (with the runtime) -> native executable, or with isLib a static
/// library (.a) plus its header (.h).
let build (src: string) (out: string) (emitLlvm: bool) (sanitize: bool) (isLib: bool) : Result<unit, Core.Diagnostic list> =
    let toolError (msg: string) : Core.Diagnostic list =
        [ { file = src
            line = 0
            col = 0
            msg = msg } ]

    let ir =
        try
            if not (File.Exists src || overlay.ContainsKey(Path.GetFullPath src)) then
                raise (CompileErrorAt(src, 0, 0, "file not found"))

            compileProgram src isLib
        with
        | CompileErrorAt(file, line, col, msg) ->
            Error
                [ { file = file
                    line = line
                    col = col
                    msg = msg } ]
        | CompileError(line, msg) ->
            Error
                [ { file = src
                    line = line
                    col = 0
                    msg = msg } ]

    match ir with
    | Error e -> Error e
    | Ok(ir, header) ->
        let ll =
            if emitLlvm then
                Path.ChangeExtension(out, ".ll")
            else
                Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N") + ".ll")

        File.WriteAllText(ll, ir)
        let san = if sanitize then [ "-fsanitize=address,undefined"; "-g" ] else []
        // -g: unoptimized, so stepping follows the source
        let opt = if Codegen.debugInfo then [ "-O0"; "-g" ] else [ optLevel ]

        let run (exe: string) (args: string list) =
            let code, output = exec exe args true
            if code = 0 then None else Some(sprintf "%s failed: %s" exe (output.Trim()))

        // a cross build (--target): clang compiles the IR for the target, and zig cc compiles the
        // runtime and links against Zig's bundled libc (musl: a static binary, no sysroot needed)
        let cross = Codegen.target <> ""
        let tclang = if cross then [ "--target=" + Codegen.target ] else []
        let cc args = if cross then run "zig" ([ "cc"; "-target"; Codegen.target ] @ args) else run "clang" args

        let failure =
            if mcu.IsSome then
                // bare metal: the IR and the embedded runtime for the chip, linked for the board
                let m = mcu.Value
                let obj = Path.ChangeExtension(ll, ".o")
                let flags = [ "-ffunction-sections"; "-fdata-sections" ]

                // the board's script with the shared Cortex-M layout spliced in (zig cc can't
                // pass the linker a search path for INCLUDE)
                let script = Path.ChangeExtension(ll, ".ld")
                let shared = File.ReadAllText(runtimeFile (Path.Combine("boards", "cortex-m.ld")))
                File.WriteAllText(script, File.ReadAllText(runtimeFile (Path.Combine("boards", m.board + ".ld"))).Replace("INCLUDE cortex-m.ld", shared))

                // ponytail: linking the runtime in as bitcode (whole-program optimization) was
                // measured: larger and slower (output code inlined everywhere); kept separate
                let failure =
                    timed "clang" (fun () -> run "clang" (opt @ [ "--target=" + m.triple ] @ m.cflags @ flags @ [ "-c"; "-Wno-override-module"; ll; "-o"; obj ]))
                    |> Option.orElseWith (fun () ->
                        timed "zig cc" (fun () ->
                            run
                                "zig"
                                ([ "cc"; "-target"; m.zigTarget; "-mcpu=" + m.zigCpu ]
                                 @ opt
                                 @ flags
                                 @ [ sprintf "-DZS_HEAP_SIZE=%d" m.heap
                                     "-T" + script
                                     "-Wl,--gc-sections"
                                     obj
                                     runtimeFile "rt-embedded.c"
                                     "-o"
                                     out ])))

                for f in [ obj; script ] do
                    if File.Exists f then
                        File.Delete f

                failure
            elif cross && not isLib then
                let obj = Path.ChangeExtension(ll, ".o")

                let failure =
                    timed "clang" (fun () -> run "clang" (opt @ tclang @ [ "-c"; "-Wno-override-module" ] @ san @ [ ll; "-o"; obj ]))
                    |> Option.orElseWith (fun () ->
                        let linked = links |> Seq.map (fun l -> if l.Contains "/" then l else "-l" + l) |> List.ofSeq
                        timed "zig cc" (fun () -> cc (opt @ [ obj; runtimeFile "rt.c" ] @ linked @ [ "-o"; out; "-lm" ])))

                if File.Exists obj then
                    File.Delete obj

                failure
            elif isLib then
                // objects for the program and the runtime, archived, plus the header
                let obj = Path.ChangeExtension(ll, ".o")
                let rt = Path.ChangeExtension(ll, ".rt.o")

                let failure =
                    run "clang" (opt @ tclang @ [ "-c"; "-Wno-override-module" ] @ san @ [ ll; "-o"; obj ])
                    |> Option.orElseWith (fun () -> cc (opt @ [ "-c" ] @ san @ [ runtimeFile "rt.c"; "-o"; rt ]))
                    |> Option.orElseWith (fun () ->
                        if File.Exists out then
                            File.Delete out

                        run "llvm-ar" [ "rcs"; out; obj; rt ])

                File.WriteAllText(Path.ChangeExtension(out, ".h"), header)

                for f in [ obj; rt ] do
                    if File.Exists f then
                        File.Delete f

                failure
            else
                let linked = links |> Seq.map (fun l -> if l.Contains "/" then l else "-l" + l) |> List.ofSeq
                timed "clang" (fun () -> run "clang" (opt @ [ "-rdynamic"; "-Wno-override-module" ] @ san @ [ ll; runtimeFile "rt.c" ] @ linked @ [ "-o"; out; "-lm" ]))

        if not emitLlvm then
            File.Delete ll

        match failure with
        | None -> Ok()
        | Some msg -> Error(toolError msg)

/// The `///` comment lines right above a definition (attribute lines in between are skipped),
/// without the slashes; None if there are none. `prelude.zs` means the installed prelude.
let docAbove (file: string) (line: int) : string option =
    let path = if file = "prelude.zs" then runtimeFile "prelude.zs" else file

    let lines =
        try
            (readSource path).Replace("\r\n", "\n").Split '\n'
        with _ ->
            [||]

    let mutable i = line - 2 // the line above, 0-based
    let doc = ResizeArray<string>()

    while i >= 0 && i < lines.Length && (lines[i].TrimStart().StartsWith "///" || lines[i].TrimStart().StartsWith "[<") do
        let t = lines[i].TrimStart()

        if t.StartsWith "///" then
            let text = t.Substring 3
            doc.Insert(0, if text.StartsWith " " then text.Substring 1 else text)

        i <- i - 1

    if doc.Count = 0 then None else Some(String.concat "\n" doc)

/// Docs for functions built into the compiler (they have no definition to read a comment from).
let builtinDocs =
    dict
        [ "print", "Writes the string to standard output, without a newline."
          "println", "Writes the string and a newline to standard output."
          "eprintln", "Writes the string and a newline to standard error."
          "string", "The text form of a value (`Show.show`): numbers, bools, strings, and any type with `Show`."
          "panic", "Stops the program with the message (and a backtrace). For bugs, not for errors a caller should handle."
          "failwith", "Same as `panic`."
          "assert", "Panics with \"assertion failed\" when the condition is false."
          "ignore", "Discards a value."
          "ref", "A mutable cell holding the value; read and write it with `r.Value`."
          "Array.create", "An array of `n` copies of `x`."
          "Array.length", "The number of elements."
          "String.length", "The length in bytes (UTF-8)."
          "String.sub", "The `len` bytes of `s` starting at byte `start`. Panics if out of range."
          "String.byte", "The byte at index `i`. Panics if out of range."
          "String.ofByte", "A one-byte string."
          "String.trim", "`s` without leading and trailing spaces, tabs and line breaks."
          "String.toUpper", "`s` with ASCII letters in upper case."
          "String.toLower", "`s` with ASCII letters in lower case."
          "String.replace", "`s` with every occurrence of `old` replaced by `by`."
          "String.ofCStr", "A Z# string copied from a C string (`const char*`)."
          "Array.set", "`a` with element `i` replaced by `x`. Arrays are values: `a` itself is unchanged (it is reused in place when nothing else refers to it)."
          "Buffer.create", "A Buffer of `n` copies of `x`. A Buffer is shared and mutable: a write is seen through every reference."
          "Buffer.length", "The number of elements."
          "Buffer.ofArray", "A new Buffer with the array's elements."
          "Buffer.toArray", "An array copy of the Buffer's current elements."
          "Int.wrappingAdd", "`a + b`, wrapping around on overflow instead of panicking."
          "Int.wrappingSub", "`a - b`, wrapping around on overflow instead of panicking."
          "Int.wrappingMul", "`a * b`, wrapping around on overflow instead of panicking."
          "Runtime.allocations", "The number of heap objects allocated so far."
          "Runtime.ticks", "A cycle counter for timing code: on a Cortex-M the SysTick count, elsewhere nanoseconds."
          "Mmio.read32", "Reads the 32-bit hardware register at an address (a volatile load)."
          "Mmio.write32", "Writes the 32-bit hardware register at an address (a volatile store)."
          "Mmio.read8", "Reads the 8-bit hardware register at an address (a volatile load)."
          "Mmio.write8", "Writes the 8-bit hardware register at an address (a volatile store)."
          "Process.exit", "Ends the program now with the exit code (output is flushed; nothing else is cleaned up)."
          "File.exists", "Whether `path` names an existing regular file."
          "Dir.exists", "Whether `path` names an existing directory." ]

/// A documented item of a source file, found by reading its declarations.
type DocItem =
    { kind: string // function, type, case, trait, method, derive, impl, member
      key: string // what hovers refer to: List.map, option, Some, Show.show, show, string#Length
      title: string // the declaration as written, without its body
      line: int
      doc: string option }

/// The declarations of a file with their doc comments: top-level `let`, `type`, `trait`,
/// `derive`, `impl`, plus union cases, trait methods and members under them.
let docItems (file: string) : DocItem list =
    let path = if file = "prelude.zs" then runtimeFile "prelude.zs" else file

    let lines =
        try
            (readSource path).Replace("\r\n", "\n").Split '\n'
        with _ ->
            [||]

    let header (l: string) =
        // the declaration without its body: up to a top-level `=` (not ==, <=, >=, <>)
        let t = l.Trim()
        let m = Text.RegularExpressions.Regex.Match(t, @"\s=(\s|$)")
        if m.Success then t.Substring(0, m.Index).Trim() else t

    let items = ResizeArray<DocItem>()
    let mutable container = "" // the type, extension or trait whose block we are in
    let mutable containerKind = ""

    let add kind key (i: int) =
        items.Add
            { kind = kind
              key = key
              title = header lines[i]
              line = i + 1
              doc = docAbove file (i + 1) }

    let rx (p: string) (l: string) = Text.RegularExpressions.Regex.Match(l, p)

    for i in 0 .. lines.Length - 1 do
        let l = lines[i]

        if l.Length > 0 && not (Char.IsWhiteSpace l[0]) && not (l.StartsWith "//") && not (l.StartsWith "[<") then
            container <- ""
            containerKind <- ""

            let m = rx @"^let\s+(rec\s+)?(private\s+)?([A-Za-z_][A-Za-z0-9_.]*|\(\|[^)]*\|\))" l

            if m.Success then
                if not m.Groups[2].Success then add "function" m.Groups[3].Value i // private: not API
            else
                let m = rx @"^type\s+(private\s+)?([A-Za-z_][A-Za-z0-9_]*)(<[^>]*>)?\s*(with)?" l

                if m.Success then
                    container <- m.Groups[2].Value

                    if m.Groups[1].Success then
                        containerKind <- "private"
                    elif m.Groups[4].Success then
                        containerKind <- "extension"
                    else
                        containerKind <- "type"
                        add "type" container i
                else
                    let m = rx @"^trait\s+([A-Za-z_][A-Za-z0-9_]*)" l

                    if m.Success then
                        container <- m.Groups[1].Value
                        containerKind <- "trait"
                        add "trait" container i
                    else
                        let m = rx @"^derive\s+([A-Za-z_][A-Za-z0-9_]*)" l

                        if m.Success then
                            add "derive" ("derive " + m.Groups[1].Value) i
                        else
                            let m = rx @"^impl\s+(.*?)\s*=\s*$" l
                            if m.Success then add "impl" ("impl " + m.Groups[1].Value) i
        elif container <> "" then
            let t = l.Trim()
            let m = rx @"^\|\s*([A-Z][A-Za-z0-9_]*)" t

            if m.Success && containerKind = "type" then
                add "case" m.Groups[1].Value i
            else
                let m = rx @"^abstract\s+([A-Za-z_][A-Za-z0-9_]*)" t

                if m.Success && containerKind = "trait" then
                    add "method" (container + "." + m.Groups[1].Value) i
                else
                    let m = rx @"^(static\s+)?member\s+(?:[A-Za-z_][A-Za-z0-9_]*\.)?([A-Za-z_][A-Za-z0-9_]*)" t
                    if m.Success then add "member" (container + "#" + m.Groups[2].Value) i

    List.ofSeq items
