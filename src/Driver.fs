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

/// The library that ships with zs: lib/ next to it.
let libraryDir = runtimeFile "lib"

/// The library's files after the prelude, in dependency order; a file's module is its path
/// (core/Collections/List.zs is Collections.List). Core needs no operating system, so every
/// target has it; Std is for targets that have one.
let private coreFiles =
    [ "Option"; "Result"; "Math"; "Int"; "Runtime"; "Mmio"; "Ptr"; "Weak"; "Arena"; "Simd"; "Simd/X86"; "Simd/Arm"; "Collections/List"; "Collections/Array"; "Collections/Buffer"
      "Text/String"; "Text/Char"; "Collections/Map"; "Collections/Set"; "Collections/HashMap" ]

let private stdFiles =
    [ "Console"; "Environment"; "Threading/Atomic"; "Threading/Mutex"; "Threading/Channel"; "Threading/Task"; "Threading/Parallel"
      "Collections/Array/Parallel"; "IO/File"; "IO/Directory"; "IO/Path"; "Diagnostics/Process"; "Diagnostics/Stopwatch"; "Net/Tcp" ]

/// The library rooted at `root` for one check: (path, module name, declarations), the prelude
/// first (its names are global), then Core, then (when hosted) Std.
let libraryModules (root: string) (hosted: bool) : (string * string option * (int * Decl) list) list =
    let load (file: string) =
        let path = Path.Combine(root, file)
        let _, decls = parseFile path

        let modName =
            match decls with
            | (_, ModuleHeader h) :: _ -> Some h
            | _ -> None

        path, modName, decls

    load "prelude.zs"
    :: [ for f in coreFiles -> load ("core/" + f + ".zs") ]
    @ (if hosted then [ for f in stdFiles -> load ("std/" + f + ".zs") ] else [])

/// The library a file belongs to (the installed one, or lib/ in a checkout of zs): the lib/
/// directory above it that has prelude.zs and core/.
let libraryRootOf (file: string) : string option =
    let rec up (dir: string) =
        if isNull dir then None
        elif Path.GetFileName dir = "lib" && File.Exists(Path.Combine(dir, "prelude.zs")) && Directory.Exists(Path.Combine(dir, "core")) then Some dir
        else up (Path.GetDirectoryName dir)

    up (Path.GetDirectoryName(Path.GetFullPath file))

/// Whether a file is part of a library rather than a program.
let isLibrary (file: string) = (libraryRootOf file).IsSome

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

// ---- the checked library, cached between builds (libraries are source, DESIGN §9): the type
// checker's state after the library, and after the main file's other modules, saved under a
// hash of the compiler and of those modules' sources. A build whose library and other modules
// haven't changed starts there and checks only the main file.

/// Where zs caches what it built: the user's cache directory (nothing in it depends on the
/// project), with checked states in checked/ and compiled modules in objects/.
let private cacheRoot () =
    match Environment.GetEnvironmentVariable "XDG_CACHE_HOME" with
    | null
    | "" -> Path.Combine(Environment.GetFolderPath Environment.SpecialFolder.UserProfile, ".cache", "zs")
    | dir -> Path.Combine(dir, "zs")

let private cacheDir () = Path.Combine(cacheRoot (), "checked")

/// The compiler, as part of every key: a state holds only for the compiler that made it.
let private compilerId = lazy (Reflection.Assembly.GetExecutingAssembly().ManifestModule.ModuleVersionId.ToString())

let private hashOf (parts: string list) =
    let bytes = Text.Encoding.UTF8.GetBytes(String.concat "\u0000" parts)
    Convert.ToHexString(Security.Cryptography.SHA256.HashData bytes).Substring(0, 32).ToLowerInvariant()

module private Array =
    /// The elements after the first n (all of them dropped when there are fewer).
    let skip' n (a: 'a[]) = if a.Length <= n then [||] else Array.skip n a

/// Keeps the n most recently used files of a cache directory with this extension.
let private evict (dir: string) (pattern: string) (n: int) =
    for old in DirectoryInfo(dir).GetFiles pattern |> Array.sortByDescending (fun f -> f.LastWriteTimeUtc) |> Array.skip' n do
        try
            old.Delete()
        with _ ->
            ()

let private loadState (key: string) : Typer.State option =
    let file = Path.Combine(cacheDir (), key + ".bin")

    if not (File.Exists file) then
        None
    else
        try
            use s = new MemoryStream(File.ReadAllBytes file)
            use r = new BinaryReader(s, Text.Encoding.UTF8, true)
            // the key before and after: a file that isn't whole is never used
            if r.ReadString() <> key then failwith "another state"
            let st = Snapshot.read s (fun o p -> positions[o] <- p)
            if r.ReadString() <> key then failwith "a broken state"
            File.SetLastWriteTimeUtc(file, DateTime.UtcNow) // recently used: kept longest
            Some st
        with _ ->
            None // checked again, and saved anew

let private saveState (key: string) (st: Typer.State) =
    try
        let dir = cacheDir ()
        Directory.CreateDirectory dir |> ignore
        let tmp = Path.Combine(dir, sprintf "%s.%s.tmp" key (Guid.NewGuid().ToString "N"))

        do
            use s = new MemoryStream()
            use w = new BinaryWriter(s, Text.Encoding.UTF8, true)
            w.Write key

            Snapshot.write s st (fun o ->
                match positions.TryGetValue o with
                | true, p -> Some p
                | _ -> None)

            w.Write key
            w.Flush()
            File.WriteAllBytes(tmp, s.ToArray())

        // whole or not at all, for builds running at the same time
        File.Move(tmp, Path.Combine(dir, key + ".bin"), true)

        // the most recently used states are kept (each compiler and set of sources has its own)
        evict dir "*.bin" 64
    with _ ->
        () // not cached: the next build checks everything again

/// Whether builds use the cache (ZS_NO_CACHE=1 turns it off).
let private cacheOn () = isNull (Environment.GetEnvironmentVariable "ZS_NO_CACHE")

/// Parses and type-checks; with collect, every declaration's error is in the result. With
/// cached, the checked library and the main file's other modules come from the cache when
/// their sources haven't changed; their hovers aren't kept, so it's for builds, not editors.
let checkWith (cached: bool) (mainPath: string) (requireMain: bool) (collect: bool) : Core.Program =
    positions.Clear()
    links.Clear()
    Typer.unavailable.Clear()

    match libraryRootOf mainPath with
    | Some root ->
        // a file of the library itself (an editor opening it): that library, checked on its
        // own rather than as a program that would define everything a second time
        Typer.check false collect (libraryModules root true)
    | None ->
        // a microcontroller has no operating system, so no Std
        let hosted = mcu.IsNone

        if not hosted then
            for f in stdFiles do
                Typer.unavailable.Add(f.Replace('/', '.')) |> ignore

        let program = loadModules mainPath

        if not (cached && cacheOn ()) then
            Typer.check requireMain collect (libraryModules libraryDir hosted @ program)
        else
            let libFiles =
                "prelude.zs"
                :: [ for f in coreFiles -> "core/" + f + ".zs" ]
                @ (if hosted then [ for f in stdFiles -> "std/" + f + ".zs" ] else [])
                |> List.map (fun f -> Path.Combine(libraryDir, f))

            let deps = List.take (program.Length - 1) program
            let libKey = hashOf (compilerId.Value :: [ for f in libFiles -> f + "\n" + readSource f ])
            let depKey = hashOf (libKey :: [ for path, m, _ in deps -> path + "\n" + defaultArg m "" + "\n" + readSource path ])

            let full () =
                let lib = libraryModules libraryDir hosted

                Typer.checkFrom requireMain collect None (fun i st ->
                    if i = lib.Length - 1 then saveState libKey st
                    elif i = lib.Length + deps.Length - 1 then saveState depKey st) (lib @ program)

            try
                match (if deps.IsEmpty then None else loadState depKey) with
                | Some st -> Typer.checkFrom requireMain collect (Some st) (fun _ _ -> ()) [ List.last program ]
                | None ->
                    match loadState libKey with
                    | Some st -> Typer.checkFrom requireMain collect (Some st) (fun i st -> if i = deps.Length - 1 then saveState depKey st) program
                    | None -> full ()
            with Typer.StaleSnapshot _ ->
                full () // the program's own positions stay; the snapshot's are never reached again

/// Parses and type-checks everything (with every hover, for editors and tools).
let check (mainPath: string) (requireMain: bool) (collect: bool) : Core.Program = checkWith false mainPath requireMain collect

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

/// --cpu: the processor to compile for (native, x86-64-v3, neoverse-n1, …); None for the
/// target's baseline.
let mutable cpu: string option = None

/// --sanitize=thread: a sanitized build checks for data races (ThreadSanitizer) instead of
/// memory errors (AddressSanitizer and UndefinedBehaviorSanitizer).
let mutable threadSanitizer = false

/// Source files -> checked and lowered (monomorphic, closure-converted, RC-annotated) functions.
let private lower (mainPath: string) (isLib: bool) =
    timings.Clear()
    let prog = timed "parse + check" (fun () -> checkWith true mainPath (not isLib) true)

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
                // a -g build keeps every function whole, so breakpoints on them hit
                let fixedNames = set ("main" :: prog.tests @ (prog.exports |> List.map (fun e -> e.fname)))
                // [<Target>] and [<Multiversion>] functions stay whole: their code is for features
                // their callers may not have
                Codegen.targets <- prog.targets
                Codegen.cpu <- cpu
                Inline.kept <- fun n -> prog.targets.ContainsKey(Core.baseFunName n)
                let inline' = if Codegen.debugInfo then id else Inline.uncurry fixedNames >> Inline.run
                // ZS_NO_DECIDE=1: matches as written, to compare with decision trees
                let decide = if isNull (Environment.GetEnvironmentVariable "ZS_NO_DECIDE") then Decide.run prog.types else id
                let mono = timed "monomorphize" (fun () -> Mono.run prog |> Mono.checkShared prog |> Mono.fuse)
                let mono = timed "inline" (fun () -> inline' mono)
                let mono = timed "simplify" (fun () -> if Codegen.debugInfo then mono else Simplify.run prog.types mono)
                let mono = timed "decision trees" (fun () -> decide mono)
                let lifted = timed "lift closures" (fun () -> Lift.run mono)
                let counted = timed "reference counting" (fun () -> Rc.run prog.types fixedNames lifted)

                // ZS_DUMP_CORE=name: the Core of matching functions after reference counting
                match Environment.GetEnvironmentVariable "ZS_DUMP_CORE" with
                | null -> ()
                | name ->
                    for f in counted do
                        if f.name.Contains name then
                            eprintfn "%s(%s) =\n%s\n" f.name (f.pars |> List.map fst |> String.concat ", ") (Core.showCore 1 f.body)

                counted
            with CompileError(l, m) ->
                raise (CompileErrorAt(mainPath, l, 0, m))

        Ok(prog, funs)

/// Whether the program uses one of these primitives.
let private usesPrim (prims: Set<string>) (funs: Mono.MFun list) =
    let rec uses (e: Core.CExpr) =
        match e.k with
        | Core.CPrim(p, _) when prims.Contains p -> true
        | k -> Core.children k |> List.exists uses

    funs |> List.exists (fun f -> uses f.body)

/// Whether the program has weak references or arenas (Codegen.checkedHeap).
let private checkedHeap = usesPrim (set [ "weak.new"; "arena.with" ])

/// Whether the program runs code on other threads (Codegen.threaded): the thread pool, a task
/// spawned or on Task.blocking's helper thread, or values threads share.
let private threaded =
    usesPrim (
        set
            [ "par.fork"
              "Loop.blocking"
              "Loop.spawn"
              "atomic.make"
              "mutex.make"
              "chan.make" ]
    )

/// The runtime's defines: ZS_THREADS when the program runs code on other threads, so the
/// runtime counts objects atomically and locks its tables.
let mutable private rtDefines: string list = []

/// Whether the program has SIMD vectors of 32 or 64 bytes (Codegen.wideVectors).
let private wideVectors (funs: Mono.MFun list) =
    let rec wide (t: Core.Ty) =
        match Core.prune t with
        | Core.TCon(n, args) ->
            (match Core.vectorInfo.TryGetValue n with
             | true, (e, k) -> k * (if e = "f32" then 32 elif e = "f64" then 64 else int (e.Substring 1)) > 128
             | _ -> false)
            || List.exists wide args
        | Core.TTuple ts -> List.exists wide ts
        | Core.TFun(a, b) -> wide a || wide b
        | _ -> false

    let rec inExpr (e: Core.CExpr) = wide e.ty || Core.children e.k |> List.exists inExpr
    funs |> List.exists (fun f -> wide f.ret || f.pars |> List.exists (snd >> wide) || inExpr f.body)

let private setRuntime (funs: Mono.MFun list) =
    Codegen.checkedHeap <- checkedHeap funs
    Codegen.wideVectors <- wideVectors funs
    Codegen.threaded <- threaded funs
    rtDefines <- if Codegen.threaded then [ "-DZS_THREADS" ] else []

/// The program as one LLVM module (and the C header of its exports).
let compileProgram (mainPath: string) (isLib: bool) =
    lower mainPath isLib
    |> Result.map (fun (prog, funs) ->
        setRuntime funs
        timed "LLVM IR" (fun () -> Codegen.compile prog.types prog.externs prog.exports prog.tests prog.values prog.clayouts None funs))

/// How a program is split into LLVM modules: one per source file of the program, holding that
/// file's functions and a copy of each library function (or instance of a generic one) they
/// use, so LLVM inlines within a module as it would in one big module. A file whose functions
/// don't change compiles to the same IR, which the object cache then reuses.
let private partition (mainPath: string) (prog: Core.Program) (funs: Mono.MFun list) : Codegen.Part list =
    // a lifted lambda or local function goes with the function it's in
    let root (name: string) =
        match name.IndexOf('$', 1) with
        | -1 -> name
        | i -> name.Substring(0, i)

    let library = Dictionary<string, bool>()

    let shared (f: Mono.MFun) =
        let lib =
            match library.TryGetValue f.file with
            | true, b -> b
            | _ ->
                let b = f.file = "" || isLibrary f.file
                library[f.file] <- b
                b

        lib || (root f.name).Contains '<'

    let byName = funs |> List.map (fun f -> f.name, f) |> dict

    let calls (f: Mono.MFun) =
        let acc = HashSet<string>()

        let rec walk (e: Core.CExpr) =
            match e.k with
            | Core.CCallDirect(g, _)
            | Core.CMkClosure(g, _) -> acc.Add g |> ignore
            | Core.CPrim(op, _) when op.StartsWith "fn:" -> acc.Add(op.Substring 3) |> ignore // in a vtable
            | _ -> ()

            Core.children e.k |> List.iter walk

        walk f.body
        acc

    let main = Path.GetFullPath mainPath
    let owners = funs |> List.filter (shared >> not) |> List.groupBy (fun f -> Path.GetFullPath f.file)
    let ownerOf = Dictionary<string, string>()

    for file, fs in owners do
        for f in fs do
            ownerOf[f.name] <- file

    // what the entry points call: main, the tests, exports and the values' initializers
    let entryCalls = "main" :: prog.tests @ (prog.exports |> List.map (fun e -> e.fname)) @ (prog.values |> List.map snd)
    let called = HashSet<string>()

    let parts =
        owners
        |> List.map (fun (file, fs) ->
            let defines = HashSet<string>(fs |> List.map (fun f -> f.name))
            let queue = Queue<Mono.MFun>(fs)

            while queue.Count > 0 do
                let f = queue.Dequeue()

                for g in calls f do
                    match byName.TryGetValue g with
                    | true, gf when shared gf -> if defines.Add g then queue.Enqueue gf
                    | true, _ when ownerOf[g] <> file -> called.Add g |> ignore
                    | _ -> ()

            file, defines)

    for g in entryCalls do
        match ownerOf.TryGetValue g with
        | true, file when file <> main -> called.Add g |> ignore
        | _ -> ()

    parts
    |> List.map (fun (file, defines) ->
        { defines = defines
          called = HashSet<string>(defines |> Seq.filter called.Contains)
          entry = (file = main) })

/// The program as LLVM modules, one per source file (partition).
let private compileParts (mainPath: string) =
    lower mainPath false
    |> Result.map (fun (prog, funs) ->
        setRuntime funs

        timed "LLVM IR" (fun () ->
            let compile part = fst (Codegen.compile prog.types prog.externs prog.exports prog.tests prog.values prog.clayouts part funs)

            let parts =
                match partition mainPath prog funs with
                | [ _ ] -> [ compile None ] // one file: one module, as it always was
                | parts ->
                    // each part on its own, on every core
                    try
                        parts |> Array.ofList |> Array.Parallel.map (Some >> compile) |> List.ofArray
                    with :? AggregateException as e ->
                        raise e.InnerExceptions[0]

            parts))

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

/// The optimization level for clang: -O2, or -Os (zs build -Os) for size.
let mutable optLevel = "-O2"

/// The optimization level, and the processor when --cpu names one: -march on x86-64, -mcpu
/// elsewhere (as clang takes them).
let private optFlags () =
    let x86 =
        if Codegen.target = "" then
            Runtime.InteropServices.RuntimeInformation.OSArchitecture = Runtime.InteropServices.Architecture.X64
        else
            Codegen.target.StartsWith "x86_64"

    optLevel :: (cpu |> Option.map (fun c -> (if x86 then "-march=" else "-mcpu=") + c) |> Option.toList)

/// Runs a tool; None, or the failure with its output.
let private run (exe: string) (args: string list) =
    let code, output = exec exe args true
    if code = 0 then None else Some(sprintf "%s failed: %s" exe (output.Trim()))

/// The object compiled from source (LLVM IR, or C with c) with these clang flags: from the
/// cache when it has one for exactly this source and these flags, else compiled and kept
/// there. Returns the object file and whether it was compiled now.
let private objectOf (source: string) (c: bool) (flags: string list) : Result<string * bool, string> =
    let key = hashOf ("object" :: string c :: flags @ [ source ])
    let cached = Path.Combine(cacheRoot (), "objects")

    let dir =
        try
            Directory.CreateDirectory cached |> ignore
            cached
        with _ ->
            Path.GetTempPath() // not writable: compiled every time

    let obj = Path.Combine(dir, key + ".o")

    if File.Exists obj then
        (try File.SetLastWriteTimeUtc(obj, DateTime.UtcNow) with _ -> ()) // recently used: kept longest
        Ok(obj, false)
    else
        let tmp = Path.Combine(dir, sprintf "%s.%s" key (Guid.NewGuid().ToString "N"))
        let input = tmp + (if c then ".c" else ".ll")
        File.WriteAllText(input, source)

        let failure = run "clang" (flags @ [ "-c"; "-Wno-override-module"; input; "-o"; tmp + ".o" ])
        File.Delete input

        match failure with
        | Some msg -> Error msg
        | None ->
            File.Move(tmp + ".o", obj, true) // whole or not at all, for builds running at the same time
            Ok(obj, true)

/// Compiles a program's LLVM modules to objects in parallel (each one the cache hasn't seen),
/// the runtime too, and links them into an executable.
let private linkParts (parts: string list) (out: string) : string option =
    let flags = optFlags ()
    let all = Array.ofList ((File.ReadAllText(runtimeFile "rt.c"), true) :: (parts |> List.map (fun ir -> ir, false)))
    let sw = Stopwatch.StartNew()
    let objects = all |> Array.Parallel.map (fun (source, c) -> objectOf source c (if c then flags @ rtDefines else flags))
    let compiled = objects |> Array.sumBy (fun o -> match o with Ok(_, true) -> 1 | _ -> 0)
    timings.Add(sprintf "clang (%d of %d new)" compiled objects.Length, sw.Elapsed.TotalMilliseconds)

    match objects |> Array.tryPick (fun o -> match o with Error msg -> Some msg | Ok _ -> None) with
    | Some msg -> Some msg
    | None ->
        evict (Path.Combine(cacheRoot (), "objects")) "*.o" 256
        let files = objects |> Array.map (fun o -> match o with Ok(f, _) -> f | Error _ -> "") |> List.ofArray
        let linked = links |> Seq.map (fun l -> if l.Contains "/" then l else "-l" + l) |> List.ofSeq
        timed "link" (fun () -> run "clang" (flags @ [ "-rdynamic" ] @ files @ linked @ [ "-o"; out; "-lm" ]))

/// .zs -> LLVM IR -> clang (with the runtime) -> native executable, or with isLib a static
/// library (.a) plus its header (.h).
let build (src: string) (out: string) (emitLlvm: bool) (sanitize: bool) (isLib: bool) : Result<unit, Core.Diagnostic list> =
    let toolError (msg: string) : Core.Diagnostic list =
        [ { file = src
            line = 0
            col = 0
            msg = msg } ]

    let catching (f: unit -> Result<'a, Core.Diagnostic list>) =
        try
            if not (File.Exists src || overlay.ContainsKey(Path.GetFullPath src)) then
                raise (CompileErrorAt(src, 0, 0, "file not found"))

            f ()
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

    // a native executable for the host: a module per source file, compiled in parallel and
    // from the cache when unchanged (the other builds are one module, as they always were)
    let split = mcu.IsNone && Codegen.target = "" && not isLib && not emitLlvm && not Codegen.debugInfo && not sanitize

    if split then
        catching (fun () -> compileParts src)
        |> Result.bind (fun parts ->
            match linkParts parts out with
            | None -> Ok()
            | Some msg -> Error(toolError msg))
    else

    match catching (fun () -> compileProgram src isLib) with
    | Error e -> Error e
    | Ok(ir, header) ->
        let ll =
            if emitLlvm then
                Path.ChangeExtension(out, ".ll")
            else
                Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N") + ".ll")

        File.WriteAllText(ll, ir)
        let san =
            if not sanitize then []
            elif threadSanitizer then [ "-fsanitize=thread"; "-g" ]
            else [ "-fsanitize=address,undefined"; "-g" ]
        // -g: unoptimized, so stepping follows the source
        let opt = if Codegen.debugInfo then [ "-O0"; "-g" ] else optFlags ()

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
                        timed "zig cc" (fun () -> cc (opt @ rtDefines @ [ obj; runtimeFile "rt.c" ] @ linked @ [ "-o"; out; "-lm" ])))

                if File.Exists obj then
                    File.Delete obj

                failure
            elif isLib then
                // objects for the program and the runtime, position-independent so they link
                // into a shared library too, archived (or, for a .so, linked as one), plus the header
                let obj = Path.ChangeExtension(ll, ".o")
                let rt = Path.ChangeExtension(ll, ".rt.o")
                let pic = [ "-fPIC" ]

                let failure =
                    run "clang" (opt @ pic @ tclang @ [ "-c"; "-Wno-override-module" ] @ san @ [ ll; "-o"; obj ])
                    |> Option.orElseWith (fun () -> cc (opt @ pic @ rtDefines @ [ "-c" ] @ san @ [ runtimeFile "rt.c"; "-o"; rt ]))
                    |> Option.orElseWith (fun () ->
                        if File.Exists out then
                            File.Delete out

                        if out.EndsWith ".so" then
                            let linked = links |> Seq.map (fun l -> if l.Contains "/" then l else "-l" + l) |> List.ofSeq
                            cc (opt @ [ "-shared" ] @ san @ [ obj; rt ] @ linked @ [ "-o"; out; "-lm" ])
                        else
                            run "llvm-ar" [ "rcs"; out; obj; rt ])

                File.WriteAllText(Path.ChangeExtension(out, ".h"), header)

                for f in [ obj; rt ] do
                    if File.Exists f then
                        File.Delete f

                failure
            else
                let linked = links |> Seq.map (fun l -> if l.Contains "/" then l else "-l" + l) |> List.ofSeq
                timed "clang" (fun () -> run "clang" (opt @ rtDefines @ [ "-rdynamic"; "-Wno-override-module" ] @ san @ [ ll; runtimeFile "rt.c" ] @ linked @ [ "-o"; out; "-lm" ]))

        if not emitLlvm then
            File.Delete ll

        match failure with
        | None -> Ok()
        | Some msg -> Error(toolError msg)

/// The `///` comment lines right above a definition (attribute lines in between are skipped),
/// without the slashes; None if there are none.
let docAbove (file: string) (line: int) : string option =
    let lines =
        try
            (readSource file).Replace("\r\n", "\n").Split '\n'
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
/// The SIMD functions' docs: every vector type's module has the same functions.
let private simdDocs =
    [ for n, e, k in Core.vectorTypes do
          let m = Core.simdModule n
          let isF = Core.floats.Contains e
          m + ".splat", sprintf "A %s with `x` in every lane." n
          m + ".load", sprintf "The %d elements of the array from index `i` (all of them in it, or a panic)." k
          m + ".store", "The array with the lanes written into it from index `i`: in place when nothing else refers to it (arrays are values)."
          m + ".get", sprintf "Lane `i` (0 to %d)." (k - 1)
          m + ".set", "The vector with lane `i` replaced by `x`."
          m + ".init", sprintf "The vector of `f 0`, …, `f %d`." (k - 1)
          m + ".sum", "The lanes added together, in no particular order (a tree, as SIMD code adds them)."
          m + ".min", "Lane by lane, the smaller."
          m + ".max", "Lane by lane, the larger."
          m + ".reduceMin", "The smallest lane."
          m + ".reduceMax", "The largest lane."
          m + ".abs", "Lane by lane, the absolute value."
          m + ".equal", sprintf "Lane by lane, whether `a`'s equals `b`'s: a mask%d." k
          m + ".notEqual", sprintf "Lane by lane, whether `a`'s differs from `b`'s: a mask%d." k
          m + ".lessThan", sprintf "Lane by lane, whether `a`'s is less than `b`'s: a mask%d." k
          m + ".lessOrEqual", sprintf "Lane by lane, whether `a`'s is at most `b`'s: a mask%d." k
          m + ".greaterThan", sprintf "Lane by lane, whether `a`'s is greater than `b`'s: a mask%d." k
          m + ".greaterOrEqual", sprintf "Lane by lane, whether `a`'s is at least `b`'s: a mask%d." k
          m + ".select", "Lane by lane, `a`'s where the mask is true, else `b`'s."
          m + ".shuffle", sprintf "The lanes the indices pick (an array literal of %d constants): 0 to %d from `a`, %d to %d from `b`." k (k - 1) k (2 * k - 1)

          if isF then
              m + ".sqrt", "Lane by lane, the square root."
              m + ".floor", "Lane by lane, the largest integer not above it."
              m + ".ceil", "Lane by lane, the smallest integer not below it."
              m + ".round", "Lane by lane, the nearest integer (halves to the even one)."
              m + ".mulAdd", "Lane by lane, `a * b + c`, rounded once (a fused multiply-add)."

          for n2, _, k2 in Core.vectorTypes do
              if k2 = k && n2 <> n then
                  m + ".of" + Core.simdModule n2, sprintf "A %s converted lane by lane (a float into an integer saturates)." n2
      for mn, k in Core.maskTypes do
          let mm = Core.simdModule mn
          mm + ".any", "Whether any lane is true."
          mm + ".all", "Whether every lane is true."
          mm + ".count", "How many lanes are true."
          mm + ".not", "Each lane negated."
          mm + ".get", sprintf "Lane `i` (0 to %d)." (k - 1)
      "Simd.X86.rsqrt4", "An estimate of 1 / sqrt x per lane, to within 1.5 × 2^-12 (SSE's rsqrtps)."
      "Simd.X86.rsqrt8", "An estimate of 1 / sqrt x per lane, to within 1.5 × 2^-12 (AVX's vrsqrtps)."
      "Simd.X86.rcp4", "An estimate of 1 / x per lane, to within 1.5 × 2^-12 (SSE's rcpps)."
      "Simd.X86.rcp8", "An estimate of 1 / x per lane, to within 1.5 × 2^-12 (AVX's vrcpps)."
      "Simd.X86.hadd4", "Pairs added: a0+a1, a2+a3, b0+b1, b2+b3 (SSE3's haddps)."
      "Simd.X86.hadd8", "Pairs added within each 128-bit half (AVX's vhaddps)."
      "Simd.X86.movemask4", "The lanes' sign bits as the low bits of an i32 (SSE's movmskps)."
      "Simd.X86.movemask8", "The lanes' sign bits as the low bits of an i32 (AVX's vmovmskps)."
      "Simd.X86.movemaskBytes16", "The bytes' top bits as the low bits of an i32 (SSE2's pmovmskb)."
      "Simd.X86.movemaskBytes32", "The bytes' top bits as an i32 (AVX2's vpmovmskb)."
      "Simd.X86.shuffleBytes16", "The bytes of `a` the indices in `b` pick; an index with its top bit set gives 0 (SSSE3's pshufb)."
      "Simd.X86.shuffleBytes32", "pshufb within each 128-bit half (AVX2's vpshufb)."
      "Simd.X86.maddPairs8", "The products of the i16 lanes, adjacent pairs added into i32s (SSE2's pmaddwd)."
      "Simd.X86.maddPairs16", "pmaddwd over 256 bits (AVX2's vpmaddwd)."
      "Simd.X86.sadBytes16", "The sums of absolute differences of each 8 bytes, as u64s (SSE2's psadbw)."
      "Simd.X86.sadBytes32", "psadbw over 256 bits (AVX2's vpsadbw)."
      "Simd.Arm.rsqrtEstimate4", "An estimate of 1 / sqrt x per lane, to 8 bits (NEON's frsqrte)."
      "Simd.Arm.recipEstimate4", "An estimate of 1 / x per lane, to 8 bits (NEON's frecpe)."
      "Simd.Arm.pairwiseAdd4", "Pairs added: a0+a1, a2+a3, b0+b1, b2+b3 (NEON's faddp)."
      "Simd.Arm.tableLookup16", "The bytes of `a` the indices in `b` pick; an index past 15 gives 0 (NEON's tbl)."
      "Simd.Arm.dotBytes16", "`acc` plus, per i32 lane, the dot product of 4 i8s of `a` and of `b` (the dotprod extension's sdot)." ]

let builtinDocs =
    dict (
        [ "print", "Writes the string to standard output, without a newline."
          "println", "Writes the string and a newline to standard output."
          "eprintln", "Writes the string and a newline to standard error."
          "string", "The text form of a value (`Show.show`): numbers, bools, strings, and any type with `Show`."
          "panic", "Stops the program with the message (and a backtrace). For bugs, not for errors a caller should handle."
          "failwith", "Same as `panic`."
          "assert", "Panics with \"assertion failed\" when the condition is false."
          "ignore", "Discards a value."
          "ref", "A mutable cell holding the value; read and write it with `r.Value`."
          "Collections.Array.create", "An array of `n` copies of `x`."
          "Collections.Array.length", "The number of elements."
          "Text.String.length", "The length in bytes (UTF-8)."
          "Text.String.sub", "The `len` bytes of `s` starting at byte `start`. Panics if out of range."
          "Text.String.byte", "The byte at index `i`. Panics if out of range."
          "Text.String.ofByte", "A one-byte string."
          "Text.String.trim", "`s` without leading and trailing spaces, tabs and line breaks."
          "Text.String.toUpper", "`s` with ASCII letters in upper case."
          "Text.String.toLower", "`s` with ASCII letters in lower case."
          "Text.String.replace", "`s` with every occurrence of `old` replaced by `by`."
          "Text.String.ofCStr", "A Z# string copied from a C string (`const char*`)."
          "Text.String.indexOfFrom", "The byte index of the first `sub` in `s` at or after byte `from`, or -1."
          "Collections.Array.set", "`a` with element `i` replaced by `x`. Arrays are values: `a` itself is unchanged (it is reused in place when nothing else refers to it)."
          "Collections.Array.copy", "A new array with the same elements (copied at once, as by `memcpy`)."
          "Collections.Buffer.create", "A Buffer of `n` copies of `x`. A Buffer is shared and mutable: a write is seen through every reference."
          "Collections.Buffer.length", "The number of elements."
          "Collections.Buffer.ofArray", "A new Buffer with the array's elements."
          "Collections.Buffer.toArray", "An array copy of the Buffer's current elements."
          "Int.wrappingAdd", "`a + b`, wrapping around on overflow instead of panicking."
          "Int.wrappingSub", "`a - b`, wrapping around on overflow instead of panicking."
          "Int.wrappingMul", "`a * b`, wrapping around on overflow instead of panicking."
          "Runtime.allocations", "The number of heap objects allocated so far."
          "Runtime.mallocs", "The number of times memory was taken from the system allocator: for an object, or for an arena's block."
          "Ptr.read", "The value the pointer points to. Unsafe: only inside `unsafe`."
          "Ptr.write", "Writes the value where the pointer points. Unsafe."
          "Ptr.add", "The pointer moved by a number of elements (pointer arithmetic). Unsafe."
          "Ptr.null", "The null pointer."
          "Ptr.isNull", "Whether the pointer is null."
          "Ptr.alloc", "C memory for a number of elements, zeroed (C's `calloc`); give it back with `Ptr.free`. Unsafe."
          "Ptr.free", "Frees memory from `Ptr.alloc` (C's `free`). Unsafe."
          "Ptr.ofCPtr", "A C pointer (`cptr`, as `import c` gives one) as a typed pointer. Unsafe."
          "Ptr.toCPtr", "The pointer as a `cptr`, to pass to a C function that takes one."
          "Ptr.cast", "The same address as a pointer to another type. Unsafe."
          "Threading.Atomic.make", "An atomic value holding `x`."
          "Threading.Atomic.get", "The value now."
          "Threading.Atomic.set", "Sets the value."
          "Threading.Atomic.exchange", "Sets the value, giving the one it replaced."
          "Threading.Atomic.compareExchange", "Sets the value to `desired` only if it is `expected`, giving the value it held (so it succeeded when that is `expected`), as .NET's `Interlocked.CompareExchange`."
          "Threading.Atomic.add", "Adds `n` to the value, giving the new value (an integer wraps around on overflow)."
          "Threading.Mutex.make", "A mutex holding `x` (which is then shared between threads)."
          "Threading.Mutex.get", "The value now (with a reference of its own, taken under the lock)."
          "Threading.Mutex.set", "Replaces the value."
          "Threading.Mutex.update", "Replaces the value with `f` of it, holding the lock meanwhile (so updates from several threads don't lose one another), and gives the new value. `f` mustn't use the same mutex."
          "Threading.Channel.make", "A channel holding up to `capacity` values (at least 1)."
          "Threading.Channel.send", "Sends `x`, waiting while the channel is full. Panics once it's closed."
          "Threading.Channel.receive", "The next value, waiting for one: `None` once the channel is closed and empty."
          "Threading.Channel.close", "Closes the channel: receivers get what's left, then `None`; a send panics."
          "Weak.create", "A weak reference to the object: it doesn't keep the object alive."
          "Weak.get", "`Some` object while it lives (with a reference of its own), `None` once it has gone."
          "Arena.with", "Runs the function with an arena: what it allocates comes from the arena's blocks, freed at once when the last of those objects goes (when the function returns, unless something it made lives on)."
          "Math.sqrt", "The square root of an `f64` or `f32` (NaN for a negative number): one instruction where the hardware has it."
          "Runtime.ticks", "A cycle counter for timing code: on a Cortex-M the SysTick count, elsewhere nanoseconds."
          "Mmio.read32", "Reads the 32-bit hardware register at an address (a volatile load)."
          "Mmio.write32", "Writes the 32-bit hardware register at an address (a volatile store)."
          "Mmio.read8", "Reads the 8-bit hardware register at an address (a volatile load)."
          "Mmio.write8", "Writes the 8-bit hardware register at an address (a volatile store)."
          "Environment.exit", "Ends the program now with the exit code (output is flushed; nothing else is cleaned up)."
          "IO.File.exists", "Whether `path` names an existing regular file."
          "IO.Directory.exists", "Whether `path` names an existing directory." ]
        @ simdDocs
    )

/// A documented item of a source file, found by reading its declarations.
type DocItem =
    { kind: string // module or namespace (a file's header), function, type, case, trait, method, derive, impl, member
      key: string // what hovers refer to: List.map, option, Some, Show.show, show, string#Length
      title: string // the declaration as written, without its body
      line: int
      doc: string option }

/// The declarations of a file with their doc comments: top-level `let`, `type`, `trait`,
/// `derive`, `impl`, plus union cases, trait methods and members under them.
let docItems (file: string) : DocItem list =
    let lines =
        try
            (readSource file).Replace("\r\n", "\n").Split '\n'
        with _ ->
            [||]

    let header (l: string) =
        // the declaration without its body: up to a top-level `=` (not ==, <=, >=, <>)
        let t = l.Trim()
        let m = Text.RegularExpressions.Regex.Match(t, @"\s=(\s|$)")
        if m.Success then t.Substring(0, m.Index).Trim() else t

    let items = ResizeArray<DocItem>()
    let mutable prefix = "" // the file's module or namespace, as names inside start: "Collections.List."
    let mutable container = "" // the type, extension, trait or module whose block we are in
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

            let m = rx @"^let\s+(rec\s+)?(private\s+)?([A-Za-z_][A-Za-z0-9_.]*|``[^`]+``|\(\|[^)]*\|\)|\([!%&*+\-./<=>?@^|~$]+\))" l
            let header = rx @"^(module|namespace)\s+([A-Za-z_][A-Za-z0-9_.]*)\s*$" l

            if header.Success then
                // module Collections.List / namespace Collections: what the file's names start with
                prefix <- header.Groups[2].Value + "."
                add header.Groups[1].Value header.Groups[2].Value i
            elif m.Success then
                // an operator's name is the operator: (>>=) is >>=
                let name = m.Groups[3].Value
                let name = if name.StartsWith "(" && not (name.StartsWith "(|") then name.Trim('(', ')') else name.Trim '`'
                if not m.Groups[2].Success then add "function" (prefix + name) i // private: not API
            else
                let m = rx @"^type\s+(private\s+)?([A-Za-z_][A-Za-z0-9_]*)(<[^>]*>)?\s*(with)?" l

                if m.Success then
                    let name = m.Groups[2].Value
                    // an extension of a built-in type (string, list) keeps the type's own name
                    container <- if m.Groups[4].Success && Char.IsLower name[0] then name else prefix + name

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
                        container <- prefix + m.Groups[1].Value
                        containerKind <- "trait"
                        add "trait" container i
                    else
                        let m = rx @"^derive\s+([A-Za-z_][A-Za-z0-9_]*)" l

                        if m.Success then
                            add "derive" ("derive " + m.Groups[1].Value) i
                        else
                            let m = rx @"^impl\s+(.*?)\s*=\s*$" l

                            if m.Success then
                                add "impl" ("impl " + m.Groups[1].Value) i
                            else
                                // module Inner = …: its functions are Inner.name
                                let m = rx @"^module\s+([A-Za-z_][A-Za-z0-9_]*)\s*=" l

                                if m.Success then
                                    container <- prefix + m.Groups[1].Value
                                    containerKind <- "module"
        elif container <> "" then
            let t = l.Trim()
            let m = rx @"^\|\s*([A-Z][A-Za-z0-9_]*)" t
            let fm = rx @"^let\s+(rec\s+)?(private\s+)?([A-Za-z_][A-Za-z0-9_]*|``[^`]+``)" t

            if containerKind = "module" then
                // the module's own definitions, at the block's indentation (not local lets)
                if fm.Success && not fm.Groups[2].Success && l.StartsWith "  " && not (Char.IsWhiteSpace l[2]) then
                    add "function" (container + "." + fm.Groups[3].Value.Trim '`') i
            elif m.Success && containerKind = "type" then
                add "case" (prefix + m.Groups[1].Value) i
            else
                let m = rx @"^abstract\s+([A-Za-z_][A-Za-z0-9_]*)" t

                if m.Success && containerKind = "trait" then
                    add "method" (container + "." + m.Groups[1].Value) i
                else
                    let m = rx @"^(static\s+)?member\s+(?:[A-Za-z_][A-Za-z0-9_]*\.)?([A-Za-z_][A-Za-z0-9_]*)" t
                    if m.Success then add "member" (container + "#" + m.Groups[2].Value) i

    List.ofSeq items
