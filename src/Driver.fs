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

/// A file's tokens and declarations, from its text.
let parseText (path: string) (text: string) =
    try
        let toks = lex text
        toks, parse toks
    with
    | CompileError(l, m) -> raise (CompileErrorAt(path, l, 0, m))
    | CompileErrorPos(l, c, m) -> raise (CompileErrorAt(path, l, c, m))

let parseFile (path: string) = parseText path (readSource path)

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
/// Where a file's C imports are saved (for editors without clang, and as what its checked
/// result depends on): the project's .zs-cache/cimport, or one next to the file.
let private cimportDir (path: string) =
    let dir = Path.GetDirectoryName(Path.GetFullPath path)

    let root =
        match findProject dir with
        | Some m -> m.root
        | None -> dir

    Path.Combine(root, ".zs-cache", "cimport")

let private expandImports (path: string) (decls: (int * Decl) list) =
    let dir = Path.GetDirectoryName(Path.GetFullPath path)

    decls
    |> List.collect (fun (ln, d) ->
        let imported header =
            try
                CImport.importHeader header dir (cimportDir path)
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

/// A release build (zs build --release): optimized (-O2) and, on the host, with ThinLTO. A debug
/// build, the default, compiles the program at -O0 for a fast edit loop (the runtime at -O2);
/// Z#'s own passes (fusion, inlining, reference counting) run in both, so a program allocates the
/// same in both. A microcontroller's build is optimized either way: -O0 code doesn't fit a chip.
let mutable release = false

/// The optimization level asked for (-O0 … -O3, or -Os for size), if one was.
let mutable optAsked: string option = None

/// The optimization level for clang: what was asked, else -O2 for a release build or a chip
/// and -O0 for a debug build.
let optLevel () =
    match optAsked with
    | Some o -> o
    | None -> if release || mcu.IsSome then "-O2" else "-O0"

/// The library that ships with zs: lib/ next to it.
let libraryDir = runtimeFile "lib"

/// The library's files after the prelude, in dependency order; a file's module is its path
/// (core/Collections/List.zs is Collections.List). Core needs no operating system, so every
/// target has it; Std is for targets that have one.
let private coreFiles =
    [ "Option"; "Result"; "Math"; "Int"; "Float"; "Runtime"; "Mmio"; "Ptr"; "Weak"; "Arena"; "Simd"; "Simd/X86"; "Simd/Arm"; "Collections/List"; "Collections/Span"; "Collections/Array"; "Collections/Buffer"; "Collections/Fixed"
      "Text/String"; "Text/Char"; "Collections/Map"; "Collections/Set"; "Collections/HashMap"; "Collections/HashSet"; "Throw"; "Collections/Seq"; "Text/Json"; "Time/DateTime" ]

let private stdFiles =
    [ "IO/Stream"; "Console"; "Environment"; "Threading/Atomic"; "Threading/Mutex"; "Threading/Channel"; "Threading/Task"; "Threading/Parallel"
      "Collections/Array/Parallel"; "IO/File"; "IO/Directory"; "IO/Path"; "Diagnostics/Process"; "Diagnostics/Stopwatch"; "Net/Tcp"; "Net/Unix"; "Time/Clock" ]

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

/// Where zs caches what it built: the user's cache directory (nothing in it depends on the
/// project), with checked modules in checked/ and compiled modules in objects/ and modules/.
let private cacheRoot () =
    match Environment.GetEnvironmentVariable "XDG_CACHE_HOME" with
    | null
    | "" -> Path.Combine(Environment.GetFolderPath Environment.SpecialFolder.UserProfile, ".cache", "zs")
    | dir -> Path.Combine(dir, "zs")

/// The compiler, as part of every key: a result holds only for the compiler that made it.
let private compilerId = lazy (Reflection.Assembly.GetExecutingAssembly().ManifestModule.ModuleVersionId.ToString())

let private hashOf (parts: string list) =
    let bytes = Text.Encoding.UTF8.GetBytes(String.concat "\u0000" parts)
    Convert.ToHexString(Security.Cryptography.SHA256.HashData bytes).Substring(0, 32).ToLowerInvariant()

let private hashBytes (b: byte[]) =
    Convert.ToHexString(Security.Cryptography.SHA256.HashData b).Substring(0, 32).ToLowerInvariant()

/// Where the build server for this compiler and this environment listens (zs build asks it,
/// Main.serve answers): a Unix socket in the cache, named after the compiler and what of the
/// environment it and the tools it runs read. Another environment has a server of its own.
let serverSocket () =
    let named =
        [ "PATH"; "HOME"; "XDG_CACHE_HOME"; "TMPDIR"; "CPATH"; "C_INCLUDE_PATH"; "LIBRARY_PATH"; "CC"; "CFLAGS"; "LDFLAGS"; "LANG"; "LC_ALL" ]
        |> List.map (fun v -> v + "=" + (Environment.GetEnvironmentVariable v |> Option.ofObj |> Option.defaultValue ""))

    let ours =
        [ for kv in Environment.GetEnvironmentVariables() |> Seq.cast<Collections.DictionaryEntry> do
              let k = string kv.Key
              if k.StartsWith "ZS_" || k.StartsWith "DOTNET_" then yield k + "=" + string kv.Value ]
        |> List.sort

    Path.GetFullPath(Path.Combine(cacheRoot (), "servers", (hashOf (compilerId.Value :: named @ ours)).Substring(0, 16) + ".sock"))

module private Array =
    /// The elements after the first n (all of them dropped when there are fewer).
    let skip' n (a: 'a[]) = if a.Length <= n then [||] else Array.skip n a

/// Keeps the n most recently used files of a cache directory with this extension.
let private evict (dir: string) (pattern: string) (n: int) =
    if Directory.Exists dir then
        for old in DirectoryInfo(dir).GetFiles pattern |> Array.sortByDescending (fun f -> f.LastWriteTimeUtc) |> Array.skip' n do
            try
                old.Delete()
            with _ ->
                ()

/// Whether builds use the cache (ZS_NO_CACHE=1 turns it off).
let private cacheOn () = isNull (Environment.GetEnvironmentVariable "ZS_NO_CACHE")

/// What a build needs of a source file before checking it, kept under a key of its text, so an
/// unchanged file isn't parsed: its `module` header, the modules it may use (`open M`, `M.x`),
/// its explicit impls (trait, type as written), and whether it imports C (such a file is always
/// parsed: its declarations come from clang, and its [<Link>]s are the build's).
type private Summary =
    { header: string option
      uses: string list
      impls: (string * string) list
      importsC: bool }

let private summaries = Dictionary<string, Summary>()

let private summaryOf (toks: Token[]) (decls: (int * Decl) list) : Summary =
    let rec qualified (toks: Token[]) =
        [ for t in toks do
              match t.tok with
              | KId s when s.Contains "." && Char.IsUpper s[0] -> yield s.Substring(0, s.IndexOf '.')
              | KInterp parts ->
                  for isExpr, text, _ in parts do
                      if isExpr then
                          yield! qualified (lex text)
              | _ -> () ]

    { header =
        match decls with
        | (_, ModuleHeader h) :: _ -> Some h
        | _ -> None
      uses = [ for _, d in decls do match d with Open m -> yield m | _ -> () ] @ qualified toks |> List.distinct
      impls = [ for _, d in decls do match d with Impl(tr, STName(n, _), _) -> yield tr, n | _ -> () ]
      importsC = decls |> List.exists (fun (_, d) -> match d with ImportC _ | Attrs(_, ImportC _) -> true | _ -> false) }

/// A source file: its text, its summary (from the cache when the text is unchanged), and its
/// tokens and declarations, parsed when needed.
let private source (path: string) =
    let text = readSource path
    let parsed = lazy (parseText path text)
    let key = hashOf [ compilerId.Value; "parsed"; Path.GetFullPath path; text ]
    let file = Path.Combine(cacheRoot (), "parsed", key)

    let summary =
        match summaries.TryGetValue key with
        | true, s -> s
        | _ ->
            let fromDisk =
                try
                    if cacheOn () && File.Exists file then
                        let lines = File.ReadAllLines file
                        let field (tag: string) = [ for l in lines do if l.StartsWith(tag + " ") then yield l.Substring(tag.Length + 1) ]

                        Some
                            { header = List.tryHead (field "header")
                              uses = field "use"
                              impls = field "impl" |> List.map (fun i -> let p = i.Split ' ' in p[0], p[1])
                              importsC = Array.contains "importsC" lines }
                    else
                        None
                with _ ->
                    None

            let s =
                match fromDisk with
                | Some s -> s
                | None ->
                    let s = summaryOf (fst parsed.Value) (snd parsed.Value)

                    if cacheOn () then
                        try
                            Directory.CreateDirectory(Path.GetDirectoryName file) |> ignore
                            let tmp = file + "." + Guid.NewGuid().ToString "N"

                            File.WriteAllLines(
                                tmp,
                                (s.header |> Option.map ((+) "header ") |> Option.toList)
                                @ (s.uses |> List.map ((+) "use "))
                                @ (s.impls |> List.map (fun (t, n) -> sprintf "impl %s %s" t n))
                                @ (if s.importsC then [ "importsC" ] else [])
                            )

                            File.Move(tmp, file, true)
                            evict (Path.GetDirectoryName file) "*" 4096
                        with _ ->
                            ()

                    s

            summaries[key] <- s
            s

    text, summary, parsed

/// A module of a check: its file (as the user knows it), module name (None: its names are
/// global, the prelude's and the main file's), text, explicit impls, declarations (parsed when
/// needed), the files of the modules it uses, and what its result depends on besides its text
/// (the C declarations it imports).
type Loaded =
    { path: string
      modName: string option
      text: string
      impls: (string * string) list
      decls: Lazy<(int * Decl) list>
      uses: string list
      imported: string }

/// The library rooted at `root` for one check, the prelude first (its names are global), then
/// Core, then (when hosted) Std.
let libraryModules (root: string) (hosted: bool) : Loaded list =
    let load (file: string) =
        let path = Path.Combine(root, file)
        let text, summary, parsed = source path

        { path = path
          modName = summary.header
          text = text
          impls = summary.impls
          decls = lazy (snd parsed.Value)
          uses = []
          imported = "" }

    load "prelude.zs"
    :: [ for f in coreFiles -> load ("core/" + f + ".zs") ]
    @ (if hosted then [ for f in stdFiles -> load ("std/" + f + ".zs") ] else [])

/// The main file and the modules it uses (`open M` or `M.name`, found as M.zs or m.zs next to
/// it or in a dependency), dependencies first. Each module is named after its file unless it
/// has a `module` header.
let loadModules (mainPath: string) : Loaded list =
    let dirs = moduleDirs mainPath
    let order = ResizeArray<Loaded>()
    let shown = Dictionary<string, string>() // a module's file: the path it was loaded as
    let finished = Dictionary<string, bool>() // module -> fully loaded?
    let display (p: string) = Path.GetRelativePath(Environment.CurrentDirectory, p)

    let fileOf (m: string) =
        [ for dir in dirs do
              for f in [ m + ".zs"; string (Char.ToLower m[0]) + m.Substring 1 + ".zs" ] -> Path.Combine(dir, f) ]
        |> List.tryFind (fun f -> File.Exists f || overlay.ContainsKey f)

    let rec visit (path: string) (modName: string option) (stack: string list) =
        let text, summary, parsed =
            try
                source path
            with CompileErrorAt(file, l, c, m) when file = path ->
                raise (CompileErrorAt(display path, l, c, m)) // the path as the user knows it, like other errors

        let decls =
            lazy
                (try
                    expandImports path (snd parsed.Value)
                 with CompileErrorAt(file, l, c, m) when file = path ->
                     raise (CompileErrorAt(display path, l, c, m)))

        // C imports now: their [<Link>]s are the build's, and what clang gave is what the
        // module's result depends on
        let imported =
            if summary.importsC then
                decls.Force() |> ignore

                [ for _, d in snd parsed.Value do
                      match d with
                      | ImportC h
                      | Attrs(_, ImportC h) ->
                          let saved = CImport.cacheFile h (cimportDir path)
                          yield h + "\n" + (if File.Exists saved then File.ReadAllText saved else "")
                      | _ -> () ]
                |> String.concat "\n"
            else
                ""

        let modName =
            match summary.header, modName with
            | Some h, Some _ -> Some h
            | _ -> modName

        let deps =
            summary.uses
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

        shown[path] <- display path

        order.Add
            { path = display path
              modName = modName
              text = text
              impls = summary.impls
              decls = decls
              uses = deps |> List.map (fun m -> shown[(fileOf m).Value])
              imported = imported }

    visit (Path.GetFullPath mainPath) None [ Path.GetFileNameWithoutExtension mainPath ]
    // the main file keeps the path the user gave
    let last = order.Count - 1
    order[last] <- { order[last] with path = mainPath }
    List.ofSeq order

/// Time spent in each compiler phase of the last build (zs build --time).
let timings = ResizeArray<string * float>()

let private timed (phase: string) (f: unit -> 'a) : 'a =
    let sw = Stopwatch.StartNew()
    let r = f ()
    timings.Add(phase, sw.Elapsed.TotalMilliseconds)
    r

// ---- checked modules, cached between builds (libraries are source, DESIGN §9): each module's
// result (what it adds to the type checker's state), kept under a key of its source and of what
// it sees of the modules before it: the interfaces of those it uses (all of the library's), and
// of the others what's seen without naming them (impls, members of others' types). A build
// checks only the modules whose key it hasn't seen, and writes the others' results back into
// the checker's state. The CLI, zs lsp, zs mcp and zs doc share it: in memory in a running
// server, and in the user's cache directory between runs.

/// A module's checked result: its key; the hashes of what the modules after it see of it, all
/// of its interface (iface) or what's seen without naming it (global'); and its parts.
type CheckedModule =
    { key: string
      iface: string
      global': string
      parts: Snapshot.Parts }

/// The results this process has had, by key, newest last (a server's: what typing changes is
/// one module's, the others stay); kept at most 512.
let private inMemory = Dictionary<string, CheckedModule>()
let private inMemoryOrder = Queue<string>()

let private remember (m: CheckedModule) =
    if not (inMemory.ContainsKey m.key) then
        inMemory[m.key] <- m
        inMemoryOrder.Enqueue m.key

        while inMemoryOrder.Count > 512 do
            inMemory.Remove(inMemoryOrder.Dequeue()) |> ignore

let private checkedDir () = Path.Combine(cacheRoot (), "checked")

/// A module's result under its key: in memory, or from the cache directory.
let private loadChecked (key: string) : CheckedModule option =
    match inMemory.TryGetValue key with
    | true, m -> Some m
    | _ ->
        let file = Path.Combine(checkedDir (), key + ".bin")

        if not (File.Exists file) then
            None
        else
            try
                use s = new MemoryStream(File.ReadAllBytes file)
                use r = new BinaryReader(s, Text.Encoding.UTF8, true)
                // the key before and after: a file that isn't whole is never used
                if r.ReadString() <> key then failwith "another module"
                let iface = r.ReadString()
                let global' = r.ReadString()
                let part () = r.ReadBytes(r.ReadInt32())
                let ifaceBytes = part ()
                let funs = part ()
                let hovers = part ()
                let warnings = part ()
                if r.ReadString() <> key then failwith "a broken file"
                File.SetLastWriteTimeUtc(file, DateTime.UtcNow) // recently used: kept longest

                let m =
                    { key = key
                      iface = iface
                      global' = global'
                      parts =
                        { iface = ifaceBytes
                          global' = [||]
                          funs = funs
                          hovers = hovers
                          warnings = warnings } }

                remember m
                Some m
            with _ ->
                None // checked again, and saved anew

/// Keeps a module's result: in memory, and in the cache directory (whole or not at all).
let private saveChecked (m: CheckedModule) =
    remember m

    try
        let dir = checkedDir ()
        Directory.CreateDirectory dir |> ignore
        let tmp = Path.Combine(dir, sprintf "%s.%s.tmp" m.key (Guid.NewGuid().ToString "N"))

        do
            use s = new FileStream(tmp, FileMode.CreateNew)
            use w = new BinaryWriter(s, Text.Encoding.UTF8, true)
            w.Write m.key
            w.Write m.iface
            w.Write m.global'

            for part in [ m.parts.iface; m.parts.funs; m.parts.hovers; m.parts.warnings ] do
                w.Write part.Length
                w.Write part

            w.Write m.key

        // for builds running at the same time
        File.Move(tmp, Path.Combine(dir, m.key + ".bin"), true)
        // the most recently used are kept (each compiler and version of a module has its own)
        evict dir "*.bin" 4096
    with _ ->
        () // not cached: the next build checks it again

/// A module of a check, with what it sees of each module before it (by index): all its
/// interface, or only what's seen without naming it.
type private ToCheck =
    { m: Loaded
      sees: int -> bool
      library: bool }

/// A module as a check left it: its file and key, the functions it defines (their names with
/// how many type variables each is generic over, and their checked Core, read when needed), and
/// the modules it sees all of (by index).
type private CheckedUnit =
    { file: string
      key: string
      library: bool
      names: (string * int) list
      funs: Lazy<Core.FunDef list>
      sees: int -> bool }

/// Checks the modules in order (the library's, then the program's), each from the cache when
/// its key is there; the program has the hovers when asked for (editors, zs doc), and the
/// functions of the modules checked now (the others' are each unit's).
let private checkModules (requireMain: bool) (collect: bool) (withHovers: bool) (modules: ToCheck list) : Core.Program * CheckedUnit[] =
    let modules = Array.ofList modules
    let library, program = modules |> Array.partition (fun m -> m.library)
    let names (ms: ToCheck[]) = ms |> Seq.choose (fun m -> m.m.modName) |> List.ofSeq
    let impls (ms: ToCheck[]) = ms |> Seq.collect (fun m -> m.m.impls) |> List.ofSeq
    let s = Typer.session requireMain collect (names library) (impls library)
    // what every program module's key has: the program's modules and explicit impls
    let programKey = hashOf ("program" :: names program @ (impls program |> List.map (fun (t, n) -> t + " " + n)))
    let use' = cacheOn ()
    let results = ResizeArray<CheckedModule>()
    let units = ResizeArray<CheckedUnit>()
    let hovers = ResizeArray<Lazy<Core.Hover list>>()
    let mutable ok = true // no errors so far: results are kept
    let fresh = ResizeArray<ToCheck>()
    let restoring = Stopwatch()
    let checking = Stopwatch()
    let place (o: obj) (p: int * int * int) = positions[o] <- p

    let position (o: obj) =
        match positions.TryGetValue o with
        | true, p -> Some p
        | _ -> None

    for i, t in Array.indexed modules do
        let m = t.m

        if i > 0 && not t.library && modules[i - 1].library then
            s.addProgram (names program) (impls program)

        let key =
            hashOf (
                [ compilerId.Value
                  "check"
                  m.path
                  defaultArg m.modName ""
                  m.text
                  m.imported
                  (if t.library then "library" else programKey) ]
                @ [ for j in 0 .. i - 1 -> if t.sees j then "I" + results[j].iface else "G" + results[j].global' ]
            )

        match (if use' && ok then loadChecked key else None) with
        | Some c ->
            restoring.Start()
            let names = Snapshot.readModule c.parts.iface s.state place
            restoring.Stop()
            results.Add c

            units.Add
                { file = m.path
                  key = key
                  library = t.library
                  names = names
                  funs = lazy (Snapshot.readFuns c.parts.funs)
                  sees = t.sees }

            hovers.Add(lazy (Snapshot.readHovers c.parts.hovers))
            s.diagnostics.AddRange(Snapshot.readWarnings c.parts.warnings)
        | None ->
            fresh.Add t
            checking.Start()
            let before = s.diagnostics.Count
            let clean = s.check m.path m.modName m.decls.Value
            ok <- ok && clean
            let marks = s.marks ()
            let warnings = [ for k in before .. s.diagnostics.Count - 1 do if not (Core.isError s.diagnostics[k]) then s.diagnostics[k] ]

            let c =
                try
                    let parts =
                        { Snapshot.writeModule s.state marks (Seq.skip marks.hovers s.hovers) position with
                            warnings = Snapshot.writeWarnings warnings }

                    { key = key
                      iface = hashBytes parts.iface
                      global' = hashBytes parts.global'
                      parts = parts }
                with Snapshot.Unwritable _ ->
                    // not kept, nor anything after it (hashes no key can match)
                    ok <- false
                    let never = Guid.NewGuid().ToString "N"

                    { key = key
                      iface = never
                      global' = never
                      parts = { iface = [||]; global' = [||]; funs = [||]; hovers = [||]; warnings = [||] } }

            if use' && ok then
                saveChecked c

            checking.Stop()
            results.Add c
            let mine = [ for k in marks.funs .. s.state.funs.Count - 1 -> s.state.funs[k] ]
            let theirHovers = [ for k in marks.hovers .. s.hovers.Count - 1 -> s.hovers[k] ]

            units.Add
                { file = m.path
                  key = key
                  library = t.library
                  names = mine |> List.map (fun f -> f.name, f.ngen - f.rows) // generic in its types
                  funs = lazy mine
                  sees = t.sees }

            hovers.Add(lazy theirHovers)

    // which of the program's modules were checked (by file name), so a test can tell
    let names = fresh |> Seq.filter (fun t -> not t.library) |> Seq.map (fun t -> Path.GetFileName t.m.path) |> List.ofSeq
    timings.Add("restore", restoring.Elapsed.TotalMilliseconds)
    timings.Add(sprintf "check (%d of %d; program: %s)" fresh.Count modules.Length (if names.IsEmpty then "none" else String.concat " " names), checking.Elapsed.TotalMilliseconds)
    // an error about the whole program (what main performs) the checker had no place for, as when
    // the main module came from the cache: at main, in the main file
    let atMain () =
        match units |> Seq.tryLast with
        | Some u -> u.file, (u.funs.Value |> List.tryFind (fun f -> f.name = "main") |> Option.map (fun f -> f.line) |> Option.defaultValue 0)
        | None -> "", 0

    let prog =
        try
            s.finish ()
        with CompileErrorAt("", l, c, msg) ->
            let file, line = atMain ()
            raise (CompileErrorAt(file, (if l = 0 then line else l), c, msg))

    let prog =
        if prog.diagnostics |> List.exists (fun e -> e.file = "") then
            let file, line = atMain ()
            { prog with diagnostics = prog.diagnostics |> List.map (fun e -> if e.file = "" then { e with file = file; line = (if e.line = 0 then line else e.line) } else e) }
        else
            prog

    { prog with hovers = if withHovers then hovers |> Seq.collect (fun h -> h.Value) |> List.ofSeq else [] }, units.ToArray()

/// Parses and type-checks the main file's program, the library first; with collect, every
/// declaration's error is in the result; with withHovers, every module's hovers (editors).
let private checkUnits (withHovers: bool) (mainPath: string) (requireMain: bool) (collect: bool) : Core.Program * CheckedUnit[] =
    positions.Clear()
    links.Clear()
    Typer.unavailable.Clear()

    // each library module sees every one before it
    let library (root: string) (hosted: bool) =
        timed "parse library" (fun () -> libraryModules root hosted)
        |> List.map (fun m ->
            { m = m
              sees = fun _ -> true
              library = true })

    match libraryRootOf mainPath with
    | Some root ->
        // a file of the library itself (an editor opening it): that library, checked on its
        // own rather than as a program that would define everything a second time
        checkModules false collect withHovers (library root true)
    | None ->
        // a microcontroller has no operating system, so no Std
        let hosted = mcu.IsNone

        if not hosted then
            for f in stdFiles do
                Typer.unavailable.Add(f.Replace('/', '.')) |> ignore

        let lib = library libraryDir hosted
        let program = timed "parse program" (fun () -> loadModules mainPath)
        let index = program |> List.mapi (fun i m -> m.path, lib.Length + i) |> dict
        // each program module sees the library and the modules it uses, directly or not
        let seen = Array.create program.Length Set.empty<int>

        for i, m in List.indexed program do
            seen[i] <- m.uses |> List.fold (fun acc u -> let j = index[u] in Set.add j (Set.union acc seen[j - lib.Length])) Set.empty

        let mine =
            program
            |> List.mapi (fun i m ->
                { m = m
                  sees = fun j -> j < lib.Length || seen[i].Contains j
                  library = false })

        checkModules requireMain collect withHovers (lib @ mine)

/// Parses and type-checks the main file's program, the library first; with collect, every
/// declaration's error is in the result; with withHovers, every module's hovers (editors).
let checkProgram (withHovers: bool) (mainPath: string) (requireMain: bool) (collect: bool) : Core.Program =
    let prog, units = checkUnits withHovers mainPath requireMain collect
    { prog with funs = units |> Seq.collect (fun u -> u.funs.Value) |> List.ofSeq }

/// Parses and type-checks everything, with every hover (editors and tools).
let check (mainPath: string) (requireMain: bool) (collect: bool) : Core.Program = checkProgram true mainPath requireMain collect


/// zs test: build the [<Test>] functions with a test dispatcher in place of `main`.
let mutable testBuild = false

/// --cpu: the processor to compile for (native, x86-64-v3, neoverse-n1, …); None for the
/// target's baseline.
let mutable cpu: string option = None

/// --sanitize=thread: a sanitized build checks for data races (ThreadSanitizer) instead of
/// memory errors (AddressSanitizer and UndefinedBehaviorSanitizer).
let mutable threadSanitizer = false

/// Source files -> checked functions, monomorphic and closure-converted: what reference
/// counting takes, with its entries (functions called from outside, which own their parameters).
let private lift (mainPath: string) (isLib: bool) =
    timings.Clear()
    let prog = timed "parse + check (all)" (fun () -> checkProgram false mainPath (not isLib) true)

    let prog =
        if testBuild then { prog with funs = prog.funs |> List.filter (fun f -> f.name <> "main") } else prog

    // a library has no startup to compute values in
    match prog.values with
    | (v, _) :: _ when isLib ->
        raise (CompileErrorAt(mainPath, 0, 0, sprintf "top-level value '%s' is computed at startup, which a library doesn't have; make it a constant or a function" v))
    | _ -> ()

    match prog.diagnostics |> List.filter Core.isError with
    | _ :: _ as errors -> Error errors
    | [] ->
        let prog = Mono.lowered prog

        let funs =
            try
                // a -g build keeps every function whole, so breakpoints on them hit
                let fixedNames = set ("main" :: prog.tests @ (prog.exports |> List.map (fun e -> e.fname)))
                // [<Target>] and [<Multiversion>] functions stay whole: their code is for features
                // their callers may not have
                Codegen.targets <- prog.targets
                Codegen.optimized <- optLevel () <> "-O0"
                Codegen.cpu <- cpu
                Inline.kept <- fun n -> prog.targets.ContainsKey(Core.baseFunName n)
                let inline' = if Codegen.debugInfo then id else Inline.uncurry fixedNames >> Inline.run
                // ZS_NO_DECIDE=1: matches as written, to compare with decision trees
                let decide = if isNull (Environment.GetEnvironmentVariable "ZS_NO_DECIDE") then Decide.run prog.types else id
                let mono = timed "monomorphize" (fun () -> Mono.run prog |> Mono.checkShared prog |> Mono.fuse)
                let mono = timed "inline" (fun () -> inline' mono)
                let mono = timed "simplify" (fun () -> if Codegen.debugInfo then mono else Simplify.run prog.types mono)
                let mono = timed "effects" (fun () -> Evidence.run prog.types prog.effects mono)
                let mono = timed "decision trees" (fun () -> decide mono)
                let lifted = timed "lift closures" (fun () -> Lift.run mono)
                // a task's state machine owns its parameters: they live in its coroutine frame
                // past the call that starts it
                let rec waits (e: Core.CExpr) =
                    match e.k with
                    | Core.CPrim(("task.suspend" | "task.abandon"), _) -> true
                    | k -> Core.children k |> List.exists waits

                let machines = lifted |> List.filter (fun f -> waits f.body) |> List.map (fun f -> f.name) |> Set.ofList
                lifted, fixedNames + machines
            with CompileError(l, m) ->
                raise (CompileErrorAt(mainPath, l, 0, m))

        Ok(prog, fst funs, snd funs)

/// ZS_DUMP_CORE=name: the Core of matching functions after reference counting.
let private dumpCore (counted: Mono.MFun list) =
    match Environment.GetEnvironmentVariable "ZS_DUMP_CORE" with
    | null -> ()
    | name ->
        for f in counted do
            if f.name.Contains name then
                eprintfn "%s(%s) =\n%s\n" f.name (f.pars |> List.map fst |> String.concat ", ") (Core.showCore 1 f.body)

/// Source files -> checked and lowered (monomorphic, closure-converted, RC-annotated) functions.
let private lower (mainPath: string) (isLib: bool) =
    lift mainPath isLib
    |> Result.map (fun (prog, lifted, entries) ->
        let counted = timed "reference counting" (fun () -> Rc.run prog.types entries lifted)
        dumpCore counted
        prog, counted)

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
/// spawned or on Task.blocking's helper thread, values threads share, or a callback C may call
/// on any thread (callback<share<F>>).
let private threaded (externs: Dictionary<string, Core.ExternSig>) (funs: Mono.MFun list) =
    let prims = set [ "par.fork"; "Loop.blocking"; "Loop.spawn"; "atomic.make"; "mutex.make"; "chan.make" ]

    let anyThread (s: Core.ExternSig) =
        s.pars
        |> List.exists (fun t ->
            match Core.prune t with
            | Core.TCon("callback", [ f ]) ->
                match Core.prune f with
                | Core.TCon("share", _) -> true
                | _ -> false
            | _ -> false)

    let rec uses (e: Core.CExpr) =
        match e.k with
        | Core.CPrim(p, _) when prims.Contains p -> true
        | Core.CExtern(n, _) when externs.ContainsKey n && anyThread externs[n] -> true
        | k -> Core.children k |> List.exists uses

    funs |> List.exists (fun f -> uses f.body)

/// Whether a library gives C handles (Z# objects it holds: not strings, records or tuples,
/// which cross as their bytes and fields), which a C host may use on any thread.
let private exportsHandles (prog: Core.Program) =
    let handle (t: Core.Ty) =
        Core.needsRc prog.types t
        && (match Core.prune t with
            | Core.TCon("string", _)
            | Core.TTuple _ -> false
            | Core.TCon(n, _) -> not (match prog.types.TryGetValue n with | true, { def = Core.RecordDef _ } -> true | _ -> false)
            | _ -> true)

    prog.exports |> List.exists (fun e -> handle e.ret || List.exists handle e.pars)

/// The runtime's defines: ZS_THREADS when the program runs code on other threads, so the
/// runtime counts objects atomically and locks its tables.
let mutable private rtDefines: string list = []

/// Whether the program has SIMD vectors (Codegen.wideVectors): objects 64-byte aligned, where
/// the runtime's pool gives 8.
let private wideVectors (funs: Mono.MFun list) =
    let rec wide (t: Core.Ty) =
        match Core.prune t with
        | Core.TCon(n, args) ->
            (match Core.vectorInfo.TryGetValue n with
             | true, _ -> true
             | _ -> false)
            || List.exists wide args
        | Core.TTuple ts -> List.exists wide ts
        | Core.TFun(a, b, _) -> wide a || wide b
        | _ -> false

    let rec inExpr (e: Core.CExpr) = wide e.ty || Core.children e.k |> List.exists inExpr
    funs |> List.exists (fun f -> wide f.ret || f.pars |> List.exists (snd >> wide) || inExpr f.body)

let private setRuntime (prog: Core.Program) (isLib: bool) (funs: Mono.MFun list) =
    Codegen.checkedHeap <- checkedHeap funs
    Codegen.wideVectors <- wideVectors funs
    // a library's handles may be used on any thread of its C host
    Codegen.threaded <- threaded prog.externs funs || (isLib && exportsHandles prog)

    // ZS_NO_POOL: objects from malloc, one by one, for valgrind (a sanitized build has that too)
    rtDefines <-
        (if Codegen.threaded then [ "-DZS_THREADS" ] else [])
        @ (if isNull (Environment.GetEnvironmentVariable "ZS_NO_POOL") then [] else [ "-DZS_NO_POOL" ])

let private warningsOf (prog: Core.Program) = prog.diagnostics |> List.filter (Core.isError >> not)

/// The program as one LLVM module (and the C header of its exports), and its warnings.
let compileProgram (mainPath: string) (isLib: bool) =
    lower mainPath isLib
    |> Result.map (fun (prog, funs) ->
        setRuntime prog isLib funs
        timed "LLVM IR" (fun () -> Codegen.compile prog.types prog.externs prog.exports prog.tests prog.values prog.clayouts None funs), warningsOf prog)

// ---- a module's code, cached between builds: each source file of the program is an LLVM
// module of its own functions (its non-generic ones, which the others call), with a copy of
// each library function and instance of a generic one they use, so LLVM inlines within a
// module as it would in one big one. Nothing of another module's code is in it but what that
// module's ABI says of its functions (their types after uncurrying, the parameters they borrow,
// what they reach that threads can't share): a closure of one goes through a function of its
// own, and no other module's function is inlined into it. So a module's code is made from its
// checked result, the library's, the generic functions it copies and the ABIs of what it calls;
// a key of those (its world) finds its object, and a build makes again only the modules for
// which one of them changed, monomorphization through code generation.

/// A module's code as the module cache keeps it, under a key of its checked result and the
/// library's (the rest of what it's made from is in it, checked when it's found).
let private worldFile (pre: string) = Path.Combine(cacheRoot (), "worlds", pre + ".bin")

let private loadWorld (pre: string) : Snapshot.World option =
    let file = worldFile pre

    if not (cacheOn ()) || not (File.Exists file) then
        None
    else
        try
            let w = Snapshot.readWorld (File.ReadAllBytes file)
            (try File.SetLastWriteTimeUtc(file, DateTime.UtcNow) with _ -> ()) // recently used: kept longest
            Some w
        with _ ->
            None

let private saveWorld (pre: string) (w: Snapshot.World) =
    if cacheOn () then
        try
            let file = worldFile pre
            Directory.CreateDirectory(Path.GetDirectoryName file) |> ignore
            let tmp = file + "." + Guid.NewGuid().ToString "N"
            File.WriteAllBytes(tmp, Snapshot.writeWorld w)
            File.Move(tmp, file, true) // whole or not at all, for builds running at the same time
            evict (Path.GetDirectoryName file) "*.bin" 4096
        with _ ->
            ()

/// A module of the program: its object from the module cache, or its LLVM IR and key.
type private Module =
    | Cached of string
    | Fresh of ir: string * key: string

/// A module made this build: its functions after reference counting, and the other modules'
/// it calls (their ABI).
type private Made =
    { funs: Mono.MFun list
      calls: Snapshot.AbiFun list }

/// The program's modules, a module per source file: each one's object from the module cache
/// (cachedObject, by key), or its LLVM IR, made for the modules a change reached. A program of
/// one file is one module, as it always was.
let private compileUnits (mainPath: string) (cachedObject: string -> string option) =
    timings.Clear()
    let prog, units = timed "parse + check (all)" (fun () -> checkUnits false mainPath true true)

    match prog.diagnostics |> List.filter Core.isError with
    | _ :: _ as errors -> Error errors
    | [] ->
        let prog = Mono.lowered prog
        Codegen.targets <- prog.targets
        Codegen.optimized <- optLevel () <> "-O0"
        Codegen.cpu <- cpu
        // [<Target>] and [<Multiversion>] functions stay whole: their code is for features their
        // callers may not have
        Inline.kept <- fun n -> prog.targets.ContainsKey(Core.baseFunName n)
        let lib, mods = units |> Array.partition (fun u -> u.library)
        let mainUnit = mods[mods.Length - 1]
        let keyOf = units |> Seq.map (fun u -> u.file, u.key) |> dict
        let libKey = hashOf ("library" :: [ for u in lib -> u.key ])
        let decide = isNull (Environment.GetEnvironmentVariable "ZS_NO_DECIDE")
        // the settings a module's code is made with (its object's are in its key)
        let settings = sprintf "%b %b %b" Codegen.debugInfo testBuild decide

        // which module defines each function, and a module's own functions: its non-generic ones
        // (in a test build, not main)
        let declaredIn = Dictionary<string, CheckedUnit>()
        let owner = Dictionary<string, string>()

        for u in units do
            for n, ngen in u.names do
                declaredIn[n] <- u

                if not u.library && ngen = 0 && not (testBuild && n = "main") then
                    owner[n] <- u.file

        // a lifted lambda or local function goes with the function it's in
        let root (name: string) =
            match name.IndexOf('$', 1) with
            | -1 -> name
            | i -> name.Substring(0, i)

        let unitOf (name: string) =
            match owner.TryGetValue(root name) with
            | true, u -> Some u
            | _ -> None

        let ownOf (u: CheckedUnit) = [ for n, ngen in u.names do if owner.ContainsKey n && ngen = 0 then yield n ]

        // the main module also starts the library's values
        let libraryInits = prog.values |> List.map snd |> List.filter (fun i -> declaredIn.ContainsKey i && declaredIn[i].library)
        let seeds (u: CheckedUnit) = ownOf u @ (if u.file = mainUnit.file then libraryInits else [])

        let defs = Dictionary<string, Core.FunDef>()
        let read = HashSet<string>()

        let defOf (name: string) =
            match defs.TryGetValue name with
            | true, f -> f
            | _ ->
                let u = declaredIn[name]

                if read.Add u.file then
                    for f in u.funs.Value do
                        defs[f.name] <- f

                defs[name]

        let pre (u: CheckedUnit) = hashOf [ "world"; compilerId.Value; settings; u.file; u.key; libKey ]
        let worlds = Dictionary<string, Snapshot.World>()
        let abiHash = Dictionary<string, string>()
        let abiFun = Dictionary<string, Snapshot.AbiFun>()
        let made = Dictionary<string, Made>()

        let accept (u: CheckedUnit) (w: Snapshot.World) =
            worlds[u.file] <- w
            abiHash[u.file] <- hashBytes (Snapshot.abiBytes w.abi)

            for f in w.abi do
                abiFun[f.name] <- f

        let fixedNames = set ("main" :: prog.tests @ (prog.exports |> List.map (fun e -> e.fname)))

        /// Makes the code of these modules: one run of the passes over their own functions and
        /// the copies they need, the other modules' functions known by their ABI.
        let make (these: CheckedUnit list) =
            let mine = HashSet<string>(these |> List.map (fun u -> u.file))
            let external (g: string) = owner.ContainsKey g && not (mine.Contains owner[g])
            let roots = these |> List.collect seeds
            let reachOf (g: string) = match abiFun.TryGetValue g with | true, a -> a.reach | _ -> None

            let monomorphic = timed "monomorphize" (fun () -> Mono.runFrom prog defOf roots external)
            let reach, _ = Mono.reaching prog monomorphic reachOf
            let mono = timed "monomorphize" (fun () -> monomorphic |> Mono.checkSharedWith prog reachOf |> Mono.fuse)

            let mayInline (caller: string) (g: string) =
                match unitOf g with
                | None -> true
                | u -> unitOf caller = u

            let mono =
                if Codegen.debugInfo then mono
                else timed "inline" (fun () -> mono |> Inline.uncurry fixedNames |> Inline.runWith mayInline)

            let mono = timed "simplify" (fun () -> if Codegen.debugInfo then mono else Simplify.run prog.types mono)
            let mono = timed "effects" (fun () -> Evidence.run prog.types prog.effects mono)
            let mono = timed "decision trees" (fun () -> if decide then Decide.run prog.types mono else mono)

            let arityOf (g: string) = match abiFun.TryGetValue g with | true, a -> Some a.pars.Length | _ -> None
            let lifted = timed "lift closures" (fun () -> Lift.runWith arityOf true mono)

            // a task's state machine owns its parameters: they live in its coroutine frame past
            // the call that starts it
            let rec waits (e: Core.CExpr) =
                match e.k with
                | Core.CPrim(("task.suspend" | "task.abandon"), _) -> true
                | k -> Core.children k |> List.exists waits

            let machines = lifted |> List.filter (fun f -> waits f.body) |> List.map (fun f -> f.name) |> Set.ofList
            let borrowedOf (g: string) = match abiFun.TryGetValue g with | true, a -> Some(Set.ofList a.borrowed) | _ -> None
            let borrowed = timed "borrowed parameters" (fun () -> Rc.borrowingWith prog.types (fixedNames + machines) borrowedOf lifted)
            let byName = lifted |> List.map (fun f -> f.name, f) |> dict
            // what the module's code was made from is what monomorphization copied, before
            // inlining hid some of it
            let monoByName = monomorphic |> List.map (fun f -> f.name, f) |> dict

            let refs (e: Core.CExpr) =
                let acc = ResizeArray<string>()

                let rec walk (e: Core.CExpr) =
                    match e.k with
                    | Core.CGlobal(g, _)
                    | Core.CCallDirect(g, _)
                    | Core.CMkClosure(g, _) -> acc.Add g
                    | Core.CPrim(op, _) when op.StartsWith "fn:" -> acc.Add(op.Substring 3) // in a vtable
                    | _ -> ()

                    Core.children e.k |> List.iter walk

                walk e
                acc

            // what a module's functions reach in a list of functions: those of its own and the
            // copies (shared ones), and the other modules' it calls
            let reached (unit: string) (start: string list) (funs: IDictionary<string, Mono.MFun>) =
                let inModule = HashSet<string>()
                let others = HashSet<string>()
                let queue = Queue<string>()

                for n in start do
                    if funs.ContainsKey n && inModule.Add n then
                        queue.Enqueue n

                while queue.Count > 0 do
                    let f = funs[queue.Dequeue()]

                    for g in refs f.body do
                        if funs.ContainsKey g then
                            match unitOf g with
                            | None -> if inModule.Add g then queue.Enqueue g
                            | Some u when u = unit -> if inModule.Add g then queue.Enqueue g
                            | Some _ -> others.Add g |> ignore
                        elif external g || abiFun.ContainsKey g then
                            others.Add g |> ignore

                inModule, others

            for u in these do
                let ownNames = ownOf u
                let start = lifted |> List.filter (fun f -> unitOf f.name = Some u.file) |> List.map (fun f -> f.name)
                let funsHere, others = reached u.file (start @ seeds u) byName

                // its ABI: its own functions as the others call them
                let abi =
                    ownNames
                    |> List.map (fun n ->
                        let f = byName[n]

                        ({ name = n
                           pars = f.pars |> List.map snd
                           ret = f.ret
                           borrowed = (match borrowed.TryGetValue n with | true, s -> Set.toList s | _ -> [])
                           reach = reach n }
                        : Snapshot.AbiFun))

                // what it was made from: the generic functions it copied (before inlining, so
                // those inlined count), and the other modules it calls
                let copied, _ = reached u.file (seeds u) monoByName

                let checks =
                    [ for n in copied do
                          match unitOf n with
                          | None ->
                              match declaredIn.TryGetValue(Core.baseFunName n) with
                              | true, d when not d.library && d.file <> u.file -> yield d.file
                              | _ -> ()
                          | _ -> () ]
                    |> List.distinct

                let calls = others |> Seq.choose (fun g -> unitOf g) |> Seq.filter ((<>) u.file) |> Seq.distinct |> List.ofSeq
                // by name: the order the run made them in depends on what else it made
                let funs = lifted |> List.filter (fun f -> funsHere.Contains f.name) |> List.sortBy (fun f -> f.name)
                let facts = [ (if checkedHeap funs then "weak" else ""); (if wideVectors funs then "wide" else ""); (if threaded prog.externs funs then "threads" else "") ] |> List.filter ((<>) "")

                let w: Snapshot.World =
                    { deps = (checks |> List.sort |> List.map (fun d -> d, "check", keyOf[d])) @ (calls |> List.sort |> List.map (fun d -> d, "abi", "")) // filled below
                      abi = abi
                      facts = facts }

                made[u.file] <-
                    { funs = funs
                      calls = [] }

                worlds[u.file] <- w

            // the ABIs, now that all of these modules have one; then each one's dependencies on
            // the others' ABIs, and its code with reference counting
            for u in these do
                accept u worlds[u.file]

            for u in these do
                let w = worlds[u.file]
                let deps = w.deps |> List.map (fun (d, kind, h) -> if kind = "abi" then d, kind, abiHash[d] else d, kind, h)
                let w = { w with deps = deps }
                worlds[u.file] <- w
                saveWorld (pre u) w
                let m = made[u.file]
                let externals = HashSet<string>()

                for f in m.funs do
                    for g in refs f.body do
                        if not (m.funs |> List.exists (fun h -> h.name = g)) && abiFun.ContainsKey g then
                            externals.Add g |> ignore

                // reference counting with the parameters each callee borrows, this module's own and
                // the others'
                let all = Dictionary<string, Set<int>>(borrowed)

                for g in externals do
                    all[g] <- Set.ofList abiFun[g].borrowed

                let counted = timed "reference counting" (fun () -> Rc.lower prog.types all m.funs)
                dumpCore counted

                made[u.file] <-
                    { funs = counted
                      calls = externals |> Seq.map (fun g -> abiFun[g]) |> List.ofSeq }

        // a module's code is current when what it was made from is: its checked result's key and
        // the library's (in its key), the generic functions it copied, and the ABIs of the
        // modules it calls; those come before it, so they're known in order. One made now may
        // change an ABI a later one was made with: it's made then too.
        try
            let mutable pending = List.ofArray mods

            while not pending.IsEmpty do
                let todo = ResizeArray<CheckedUnit>()
                let later = ResizeArray<CheckedUnit>()

                for u in pending do
                    match loadWorld (pre u) with
                    | Some w ->
                        let state (d: string, kind: string, h: string) =
                            match kind with
                            | "check" -> if keyOf.ContainsKey d && keyOf[d] = h then 1 else 0
                            | _ ->
                                match abiHash.TryGetValue d with
                                | true, current -> if current = h then 1 else 0
                                | _ -> if todo |> Seq.exists (fun t -> t.file = d) || later |> Seq.exists (fun t -> t.file = d) then 2 else 0

                        let states = w.deps |> List.map state

                        if states |> List.contains 0 then todo.Add u
                        elif states |> List.contains 2 then later.Add u // waits for an ABI made now
                        else accept u w
                    | None -> todo.Add u

                if todo.Count > 0 then
                    make (List.ofSeq todo)

                pending <- List.ofSeq later

            // the runtime's settings, from every module's code
            Codegen.checkedHeap <- worlds.Values |> Seq.exists (fun w -> List.contains "weak" w.facts)
            Codegen.wideVectors <- worlds.Values |> Seq.exists (fun w -> List.contains "wide" w.facts)
            Codegen.threaded <- worlds.Values |> Seq.exists (fun w -> List.contains "threads" w.facts)

            // ZS_NO_POOL: objects from malloc, one by one, for valgrind (a sanitized build has that too)
            rtDefines <-
                (if Codegen.threaded then [ "-DZS_THREADS" ] else [])
                @ (if isNull (Environment.GetEnvironmentVariable "ZS_NO_POOL") then [] else [ "-DZS_NO_POOL" ])

            // a module's object: under a key of its world, and of what code generation adds
            let objectKey (u: CheckedUnit) =
                let w = worlds[u.file]

                hashOf (
                    [ "module"
                      pre u
                      sprintf "%b %b %b %b %s %A %d" Codegen.optimizeSize Codegen.checkedHeap Codegen.wideVectors Codegen.threaded Codegen.target Codegen.cpu mods.Length ]
                    @ [ for d, kind, h in w.deps -> d + " " + kind + " " + h ]
                )

            // a module of a program of several files is two LLVM modules: its own functions, and
            // its copies of library functions and generic instances, which change only when the
            // copies it needs do (so a change to its code compiles only its own again); a program
            // of one file is one module, as it always was
            let kinds = if mods.Length = 1 then [ "whole" ] else [ "own"; "copies" ]
            let parts = [| for u in mods do for kind in kinds -> u, kind |]
            let keys = parts |> Array.map (fun (u, kind) -> hashOf [ objectKey u; kind ])
            let cached = keys |> Array.map cachedObject
            let missing =
                [ for i in 0 .. parts.Length - 1 do
                      let u = fst parts[i]

                      if cached[i].IsNone && not (made.ContainsKey u.file) then
                          yield u ]
                |> List.distinctBy (fun u -> u.file)

            // current, but its object is gone (or made with other settings): made again
            if not missing.IsEmpty then
                make missing

            timings.Add(sprintf "module cache (%d of %d)" (cached |> Array.filter Option.isSome |> Array.length) parts.Length, 0.0)
            let names = mods |> Array.filter (fun u -> made.ContainsKey u.file) |> Array.map (fun u -> Path.GetFileName u.file)
            timings.Add(sprintf "made (%s)" (if names.Length = 0 then "none" else String.concat " " names), 0.0)

            // a module is named after its source file (relative to the main one): what a profile
            // calls its internal functions, which must be the same in every build
            let nameOf (file: string) =
                let main = Path.GetFullPath mainPath
                Path.GetRelativePath(Path.GetDirectoryName main, Path.GetFullPath file).Replace('\\', '/')

            timed "LLVM IR" (fun () ->
                let compile (u: CheckedUnit, kind: string) =
                    let m = made[u.file]
                    let own = HashSet<string>(ownOf u)

                    let defined =
                        match kind with
                        | "own" -> m.funs |> List.filter (fun f -> unitOf f.name = Some u.file)
                        | "copies" -> m.funs |> List.filter (fun f -> unitOf f.name <> Some u.file)
                        | _ -> m.funs

                    let part: Codegen.Part option =
                        match kind with
                        | "whole" -> None
                        | _ ->
                            Some
                                { defines = HashSet<string>(defined |> List.map (fun f -> f.name))
                                  called = own
                                  entry = (kind = "own" && u.file = mainUnit.file)
                                  copies = (kind = "copies")
                                  file = Path.GetFullPath u.file }

                    let stub (a: Snapshot.AbiFun) : Mono.MFun =
                        { name = a.name
                          pars = a.pars |> List.mapi (fun i t -> sprintf "a%d" i, t)
                          ret = a.ret
                          row = Core.rowEmpty
                          body = { k = Core.CUnit; ty = Core.tUnit }
                          file = ""
                          line = 0 }

                    // the other modules' functions it calls, by their ABI; and the entry's: main,
                    // the tests, exports and the values' initializers
                    let stubs = m.calls |> List.map stub
                    let have = HashSet<string>((m.funs @ stubs) |> List.map (fun f -> f.name))

                    let entries =
                        if u.file <> mainUnit.file then
                            []
                        else
                            [ for n in Set.toList fixedNames @ (prog.values |> List.map snd) do
                                  match abiFun.TryGetValue n with
                                  | true, a when have.Add n -> yield stub a
                                  | _ -> () ]

                    let name = if kind = "copies" then nameOf u.file + "#copies" else nameOf u.file

                    // the functions it calls in the module's other part are declared, from m.funs
                    let ir =
                        sprintf "source_filename = \"%s\"\n" name
                        + fst (Codegen.compile prog.types prog.externs prog.exports prog.tests prog.values prog.clayouts part (m.funs @ stubs @ entries))

                    match Environment.GetEnvironmentVariable "ZS_DUMP_IR" with
                    | null -> ()
                    | dir -> File.WriteAllText(Path.Combine(dir, name.Replace('/', '_') + ".ll"), ir)

                    ir

                try
                    Array.zip3 parts keys cached
                    |> Array.Parallel.map (fun (p, key, c) ->
                        match c with
                        | Some obj -> Cached obj
                        | None -> Fresh(compile p, key))
                    |> List.ofArray
                with :? AggregateException as e ->
                    // the error itself, with its own stack (a compiler bug's names where it happened)
                    System.Runtime.ExceptionServices.ExceptionDispatchInfo.Throw e.InnerExceptions[0]
                    failwith "unreachable")
            |> fun modules -> Ok(modules, warningsOf prog)
        with CompileError(l, m) ->
            raise (CompileErrorAt(mainPath, l, 0, m))

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

/// The optimization level, and the processor when --cpu names one: -march on x86-64, -mcpu
/// elsewhere (as clang takes them).
let private cpuFlags () =
    let x86 =
        if Codegen.target = "" then
            Runtime.InteropServices.RuntimeInformation.OSArchitecture = Runtime.InteropServices.Architecture.X64
        else
            Codegen.target.StartsWith "x86_64"

    cpu |> Option.map (fun c -> (if x86 then "-march=" else "-mcpu=") + c) |> Option.toList

let private optFlags () = optLevel () :: cpuFlags ()

/// Runs a tool; None, or the failure with its output.
let private run (exe: string) (args: string list) =
    let code, output = exec exe args true
    if code = 0 then None else Some(sprintf "%s failed: %s" exe (output.Trim()))

/// Profile-guided optimization: --profile-generate builds a program that writes a profile
/// (default.profraw, or LLVM_PROFILE_FILE) when it ends; llvm-profdata merges it; and
/// --profile-use <file> builds with it.
let mutable profileGenerate = false
let mutable profileUse: string option = None

/// The flags for a profile, and what the object cache keys on (the profile's contents).
let private profileFlags () =
    if profileGenerate then [ "-fprofile-generate" ], "generate"
    else
        match profileUse with
        | Some p -> [ "-fprofile-use=" + Path.GetFullPath p ], hashOf [ "profile"; File.ReadAllText p ]
        | None -> [], ""

/// ThinLTO for a host executable: modules and the runtime compiled to bitcode, then optimized
/// together at the link (lld, with its cache), so the runtime's allocation functions inline
/// into the program. Only when lld is there.
let private lld =
    lazy
        (let path = Environment.GetEnvironmentVariable "PATH"
         not (isNull path) && path.Split ':' |> Array.exists (fun d -> d <> "" && File.Exists(Path.Combine(d, "ld.lld"))))

let private thinLto = lazy (lld.Value && isNull (Environment.GetEnvironmentVariable "ZS_NO_LTO"))

/// ThinLTO in this build: a release one, with lld.
let private useLto () = release && thinLto.Value

/// The object compiled from source (LLVM IR, or C with c) with these clang flags: from the
/// cache when it has one for exactly this source and these flags, else compiled and kept
/// there. Returns the object file and whether it was compiled now.
let private objectOf (source: string) (cFile: string option) (flags: string list) : Result<string * bool, string> =
    let c = cFile.IsSome
    let key = hashOf ("object" :: string c :: snd (profileFlags ()) :: flags @ [ source ])
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
        // C from its own file (a profile names its static functions after it, the same in
        // every build); IR from a file of its own
        let tmp = Path.Combine(dir, sprintf "%s.%s" key (Guid.NewGuid().ToString "N"))
        let input = defaultArg cFile (tmp + ".ll")
        if cFile.IsNone then File.WriteAllText(input, source)

        let failure = run "clang" (flags @ [ "-c"; "-Wno-override-module"; input; "-o"; tmp + ".o" ])
        if cFile.IsNone then File.Delete input

        match failure with
        | Some msg -> Error msg
        | None ->
            File.Move(tmp + ".o", obj, true) // whole or not at all, for builds running at the same time
            Ok(obj, true)

/// The clang flags of a host build's objects.
let private objectFlags () =
    let lto = if useLto () then [ "-flto=thin" ] else []
    optFlags () @ fst (profileFlags ()) @ lto

/// Where the module cache keeps the object of a module's key, built with this build's flags.
let private moduleObject (key: string) =
    Path.Combine(cacheRoot (), "modules", hashOf (key :: snd (profileFlags ()) :: objectFlags ()) + ".o")

/// The module cache's object for a module's key, when it has one.
let private cachedModule (key: string) =
    let obj = moduleObject key

    if cacheOn () && File.Exists obj then
        (try File.SetLastWriteTimeUtc(obj, DateTime.UtcNow) with _ -> ()) // recently used: kept longest
        Some obj
    else
        None

/// Keeps a module's object under its key for the next build (whole or not at all).
let private keepModule (key: string) (obj: string) =
    if cacheOn () then
        try
            let path = moduleObject key
            Directory.CreateDirectory(Path.GetDirectoryName path) |> ignore
            let tmp = path + "." + Guid.NewGuid().ToString "N"
            File.Copy(obj, tmp)
            File.Move(tmp, path, true)
        with _ ->
            () // not writable: compiled every time

/// Compiles a program's LLVM modules to objects in parallel (each one the caches haven't seen),
/// the runtime too, and links them into an executable.
let private linkParts (modules: Module list) (out: string) : string option =
    let lto = if useLto () then [ "-flto=thin" ] else []
    let flags = objectFlags ()
    let sw = Stopwatch.StartNew()

    let objects =
        Array.ofList (None :: List.map Some modules)
        |> Array.Parallel.map (fun m ->
            match m with
            | None ->
                // the runtime optimized in a debug build too (a program debugs its own code)
                let rtFlags = if useLto () then flags else "-O2" :: cpuFlags () @ fst (profileFlags ())
                objectOf (File.ReadAllText(runtimeFile "rt.c")) (Some(runtimeFile "rt.c")) (rtFlags @ rtDefines)
            | Some(Cached obj) -> Ok(obj, false)
            | Some(Fresh(ir, key)) ->
                objectOf ir None flags
                |> Result.map (fun (obj, compiled) ->
                    keepModule key obj
                    obj, compiled))

    let compiled = objects |> Array.sumBy (fun o -> match o with Ok(_, true) -> 1 | _ -> 0)
    timings.Add(sprintf "clang (%d of %d new)" compiled objects.Length, sw.Elapsed.TotalMilliseconds)

    match objects |> Array.tryPick (fun o -> match o with Error msg -> Some msg | Ok _ -> None) with
    | Some msg -> Some msg
    | None ->
        evict (Path.Combine(cacheRoot (), "objects")) "*.o" 256
        evict (Path.Combine(cacheRoot (), "modules")) "*.o" 256
        let files = objects |> Array.map (fun o -> match o with Ok(f, _) -> f | Error _ -> "") |> List.ofArray
        let linked = links |> Seq.map (fun l -> if l.Contains "/" then l else "-l" + l) |> List.ofSeq
        let ltoLink =
            if not lto.IsEmpty then [ "-fuse-ld=lld"; "-Wl,--thinlto-cache-dir=" + Path.Combine(cacheRoot (), "lto") ]
            elif lld.Value then [ "-fuse-ld=lld" ] // faster than the system's linker
            else []
        timed "link" (fun () -> run "clang" (flags @ ltoLink @ [ "-rdynamic" ] @ files @ linked @ [ "-o"; out; "-lm" ]))

/// .zs -> LLVM IR -> clang (with the runtime) -> native executable, or with isLib a static
/// library (.a) plus its header (.h).
/// The build's warnings, or its errors.
let build (src: string) (out: string) (emitLlvm: bool) (sanitize: bool) (isLib: bool) : Result<Core.Diagnostic list, Core.Diagnostic list> =
    let toolError (msg: string) : Core.Diagnostic list = [ Core.errorAt src 0 0 msg ]

    let catching (f: unit -> Result<'a, Core.Diagnostic list>) =
        try
            if not (File.Exists src || overlay.ContainsKey(Path.GetFullPath src)) then
                raise (CompileErrorAt(src, 0, 0, "file not found"))

            f ()
        with
        | CompileErrorAt(file, line, col, msg) -> Error [ Core.errorAt file line col msg ]
        | CompileError(line, msg) -> Error [ Core.errorAt src line 0 msg ]

    // a native executable for the host: a module per source file, compiled in parallel and
    // from the cache when unchanged (the other builds are one module, as they always were)
    let split = mcu.IsNone && Codegen.target = "" && not isLib && not emitLlvm && not Codegen.debugInfo && not sanitize

    if split then
        catching (fun () -> compileUnits src cachedModule)
        |> Result.bind (fun (parts, warnings) ->
            match linkParts parts out with
            | None -> Ok warnings
            | Some msg -> Error(toolError msg))
    else

    match catching (fun () -> compileProgram src isLib) with
    | Error e -> Error e
    | Ok((ir, header), warnings) ->
        let ll =
            if emitLlvm then
                Path.ChangeExtension(out, ".ll")
            else
                Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N") + ".ll")

        File.WriteAllText(ll, ir)
        let san =
            if not sanitize then []
            elif threadSanitizer then [ "-fsanitize=thread"; "-g" ]
            else [ "-fsanitize=address,undefined"; "-g"; "-DZS_NO_POOL" ] // AddressSanitizer sees each object
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

                // the runtime as a separate object: as bitcode (measured in phase 9,
                // docs/reports/microcontrollers.md) it changes nothing at -Os, and at -O2 costs
                // 1.4-3.1 KB of flash for gains that aren't the runtime's
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
        | None -> Ok warnings
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
          "Collections.Array.length", "The number of elements (of an array, a Buffer or a span)."
          "Collections.Array.ofSpan", "An array with a copy of the span's elements."
          "Collections.Span.length", "The number of elements."
          "Collections.Fixed.length", "The number of elements: the N of fixed<'a, N>."
          "Collections.Fixed.get", "The element at index `i`. Panics if out of range."
          "Collections.Fixed.set", "The fixed-size array with element `i` replaced by `x` (a value: the original is unchanged)."
          "Collections.Fixed.create", "N copies of `x`, N from the type expected of it."
          "Collections.Fixed.ofArray", "A fixed-size array with the elements of `a`, which must have exactly N (a panic otherwise)."
          "Collections.Span.ofPtr", "A span over `n` elements of C memory at `p`, in `unsafe`: its lifetime isn't checked, so the span mustn't outlive the memory."
          "Collections.Buffer.ofSpan", "A new Buffer with a copy of the span's elements."
          "Text.String.bytes", "The string's bytes (its UTF-8), as a span: no copy."
          "Text.String.ofBytes", "A string with a copy of the bytes, each malformed UTF-8 byte replaced by U+FFFD."
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
          "Collections.Buffer.toArray", "An array copy of the elements (of a Buffer, or of any span)."
          "Int.wrappingAdd", "`a + b`, wrapping around on overflow instead of panicking."
          "Int.wrappingSub", "`a - b`, wrapping around on overflow instead of panicking."
          "Int.wrappingMul", "`a * b`, wrapping around on overflow instead of panicking."
          "Runtime.allocations", "The number of heap objects allocated so far."
          "Runtime.mallocs", "The number of times memory was taken from the system allocator: for a chunk of the runtime's object pool, a large object, or an arena's block."
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
          "Threading.Channel.make", "A channel holding up to `capacity` values; with 0, a send waits for a receiver to take its value."
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
    { kind: string // module or namespace (a file's header), function, type, case, trait, method, effect, operation, derive, impl, member
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
                    let m = rx @"^(trait|effect)\s+([A-Za-z_][A-Za-z0-9_]*)" l

                    if m.Success then
                        container <- prefix + m.Groups[2].Value
                        containerKind <- m.Groups[1].Value
                        add m.Groups[1].Value container i
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
                elif m.Success && containerKind = "effect" then
                    add "operation" (container + "." + m.Groups[1].Value) i
                else
                    let m = rx @"^(static\s+)?member\s+(?:[A-Za-z_][A-Za-z0-9_]*\.)?([A-Za-z_][A-Za-z0-9_]*)" t
                    if m.Success then add "member" (container + "#" + m.Groups[2].Value) i

    List.ofSeq items
