/// A project (the F# compiler's Driver manifest code): its zs.toml (the package, its
/// dependencies, its [c] section), a package as module lookup sees it, and zs fetch and zs update
/// for git dependencies, with zs.lock.
///   [package]  name = "wc"  version = "0.1.0"  main = "src/main.zs" (the default)
///              target = "cortex-m4" (what zs build builds for without --target)
///   [dependencies]  text = { path = "../text" }  json = { git = "https://…", rev = "v1" }
///   [c]  sources = ["c/xxhash.c"]  include = ["c"]  link = ["m"]  pkg-config = ["sqlite3"]
///   [c.cortex-m4]  link = ["rust/target/thumbv7em-none-eabihf/release/libkit.a"] (for one
///                  target, added to [c]: --target's name, or host for this machine)
///   [target.cortex-m4]  heap = "256K" (a chip's heap: bytes, or K and M)

/// A dependency: a directory (its full path), or a git repository at a rev (a tag, branch or
/// commit; "" for the default branch), or a git repository's releases (0018 item 2): its tags
/// v<major>.<minor>.<patch>, at least this version within its major.
type Dep =
  | PathDep of string
  | GitDep of string * string
  | GitVersion of string * Version

/// A release's version: a tag's (v1.2.3), or the least one a dependency asks for ("1.2" is 1.2.0).
and Version = { major: int; minor: int; patch: int }

/// "1.2" (1.2.0) or "1.2.3", a tag's after its v.
let parseVersion (s: string) : option<Version> =
  match List.map (fun (p: string) -> Int.parse p) (String.split "." s) with
  | [ Some a; Some b ] when a >= 0 && b >= 0 -> Some { major = a; minor = b; patch = 0 }
  | [ Some a; Some b; Some c ] when a >= 0 && b >= 0 && c >= 0 -> Some { major = a; minor = b; patch = c }
  | _ -> None

let showVersion (v: Version) : string = $"{v.major}.{v.minor}.{v.patch}"

// the major a release is in: 0 and 1 are one series (1.0.0 is a promise, not a break), as in Go
let private seriesOf (v: Version) : int = if v.major <= 1 then 1 else v.major

/// A package's [c] section (0018 item 4): C sources compiled and linked with it, directories for
/// its `import c`s and its sources' #includes, libraries to link (names, or files as [<Link>]
/// takes them), and pkg-config names, whose flags and libraries a host build adds. Paths are full.
type CConfig = { sources: list<string>; includes: list<string>; link: list<string>; pkgConfig: list<string> }

/// A zs.toml: the directory holding it, the package's name, version and main file (full path),
/// the target it's built for without --target ("" for this machine), its dependencies by name, its
/// [c] section, and the [c.<target>] sections by target name.
type Manifest = { root: string; name: string; version: string; main: string; target: string; deps: list<string * Dep>; c: CConfig; cFor: Map<string, CConfig>; targets: Map<string, TargetConfig>; provider: option<string>; members: list<string> }

/// A [target.<name>] section: a chip's heap in bytes (its default when None).
and TargetConfig = { heap: option<int> }

/// A package's C settings for a target (--target's name, "host" for this machine): its [c]
/// section with its [c.<target>] one added.
let cConfigFor (m: Manifest) (target: string) : CConfig =
  match Map.tryFind target m.cFor with
  | Some t -> { sources = List.append m.c.sources t.sources; includes = List.append m.c.includes t.includes; link = List.append m.c.link t.link; pkgConfig = List.append m.c.pkgConfig t.pkgConfig }
  | None -> m.c

/// What's wrong with a project: the file, its line (0 for the file's), and the message.
type Problem = { file: string; line: int; message: string }

let private unquote (v0: string) : option<string> =
  let v = String.trim v0
  if String.length v >= 2 && String.startsWith "\"" v && String.endsWith "\"" v then Some(String.sub v 1 (String.length v - 2)) else None

// { k = "v", … } as fields, or the problem with it
let private tableFields (value: string) : result<Map<string, string>, string> =
  if not (String.startsWith "{" value && String.endsWith "}" value) then
    Error "expected a table such as { path = \"../text\" }"
  else
    let field (acc: result<Map<string, string>, string>) (f: string) =
      match acc with
      | Error e -> Error e
      | Ok m ->
        if String.trim f = "" then
          Ok m
        else
          let bad = $"expected key = \"value\" inside {{ }}, found {String.trim f}"
          match String.indexOf "=" f with
          | Some eq ->
            match unquote (String.sub f (eq + 1) (String.length f - eq - 1)) with
            | Some v -> Ok(Map.add (String.trim (String.sub f 0 eq)) v m)
            | None -> Error bad
          | None -> Error bad
    List.fold field (Ok Map.empty) (String.split "," (String.sub value 1 (String.length value - 2)))

// [ "a", "b" ] as a list, or the problem with it
let private listOf (value: string) : result<list<string>, string> =
  if not (String.startsWith "[" value && String.endsWith "]" value) then
    Error "expected a list such as [\"a.c\", \"b.c\"]"
  else
    let items = List.filter (fun i -> i <> "") (List.map String.trim (String.split "," (String.sub value 1 (String.length value - 2))))
    if List.forall (fun (i: string) -> Option.isSome (unquote i)) items then Ok(List.map (fun (i: string) -> Option.get (unquote i)) items) else Error "expected quoted strings inside [ ]"

let private cKeys : list<string> = [ "sources"; "include"; "link"; "pkg-config" ]

/// Whether a name is one a directory may be named by: a dependency's, its directory under
/// .zs-cache/deps (fetch replaces what is there), and a package's name in a cache's (Modules):
/// letters, digits, - and _, so never `..`, a `/` or an absolute path.
let depName (key: string) =
  key <> "" && List.forall (fun (c: char) -> Char.isLetterOrDigit c || c = '-' || c = '_') (String.chars key)

// a file a manifest names (its main, its provider's): a relative path inside the package once `..`
// is taken out, so loading a dependency never reads another file of the machine (/dev/stdin, the
// language server's own input; a key)
let private inside (root: string) (p: string) : bool =
  let rel = Path.getRelativePath root (Path.combine root p)
  not (Path.isAbsolute p) && rel <> "." && rel <> ".." && not (String.startsWith "../" rel) && not (String.startsWith "..\\" rel)

/// The most bytes a zs.toml may have: a dependency's is read whole, and may be a link to any
/// file of the machine.
let manifestLimit = i64 1048576

/// Reads the subset of TOML a manifest uses: [sections], key = "string", key = { k = "v", … },
/// key = [ "a", "b" ].
let rec readManifest (root: string) : result<Manifest, Problem> =
  let file = Path.combine root "zs.toml"
  if Provide.Input.special file then
    Error { file = file; line = 0; message = "isn't a regular file but a pipe or a device" }
  else
    match File.size file with
    | Ok n when n > manifestLimit -> Error { file = file; line = 0; message = $"is {n} bytes; a manifest is at most 1 MB" }
    | _ ->
      match File.readAllLines file with
      | Error e -> Error { file = file; line = 0; message = e }
      | Ok lines -> parseManifest root file lines

/// A manifest's lines (zs.toml, or a release's, read at its tag): its paths under root, its
/// problems reported in file.
and parseManifest (root: string) (file: string) (lines: list<string>) : result<Manifest, Problem> =
    let section = ref ""
    let package = ref Map.empty
    let deps = Buffer.empty
    // the [c] section's keys under "", a [c.<target>] one's under its target
    let c : ref<Map<string, Map<string, list<string>>>> = ref Map.empty
    let targets : ref<Map<string, TargetConfig>> = ref Map.empty
    // [provider] main = "Provider.zs": the package is a type provider (0001), that program
    let provider = ref None
    // [workspace] members = ["app", "libs/*"]: the member projects' directories (0018 item 8)
    let members = Buffer.empty
    // 4096, 16K, 1M: bytes; a count whose bytes don't fit an int is none (overflow panics)
    let size (v: string) : option<int> =
      let n = String.length v
      let scaled (k: int) : option<int> =
        match Int.parse (String.sub v 0 (n - 1)) with
        | Some x when x >= 0 && x <= 9223372036854775807 / k -> Some(x * k)
        | _ -> None
      if n > 1 && String.endsWith "K" v then scaled 1024
      else if n > 1 && String.endsWith "M" v then scaled (1024 * 1024)
      else Int.parse v
    let problem = ref None
    let fail (n: int) (msg: string) =
      if Option.isNone problem.Value then
        problem.Value <- Some { file = file; line = n; message = msg }
    let one (i: int) (raw: string) =
      if Option.isNone problem.Value then
        let n = i + 1
        let uncommented =
          match String.indexOf "#" raw with
          | Some h -> String.sub raw 0 h
          | None -> raw
        let line = String.trim uncommented
        if line = "" then
          ()
        else if String.startsWith "[" line && String.endsWith "]" line then
          section.Value <- String.trim (String.sub line 1 (String.length line - 2))
        else
          match String.indexOf "=" line with
          | None -> fail n "expected key = value"
          | Some eq ->
            let key = String.trim (String.sub line 0 eq)
            let value = String.trim (String.sub line (eq + 1) (String.length line - eq - 1))
            match section.Value with
            | "package" ->
              match unquote value with
              | Some v when key = "main" && not (inside root v) -> fail n $"[package] main: \"{v}\" isn't a path inside the package"
              | Some v -> package.Value <- Map.add key v package.Value
              | None -> fail n $"expected a quoted string, found {value}"
            | "dependencies" ->
              match tableFields value with
              | Error msg -> fail n $"dependency '{key}': {msg}"
              | Ok _ when not (depName key) -> fail n $"dependency '{key}': a name is letters, digits, - and _"
              | Ok fields ->
                match (Map.tryFind "path" fields, Map.tryFind "git" fields) with
                | (Some p, _) -> Buffer.push (key, PathDep(Path.getFullPath (Path.combine root p))) deps
                | (None, Some url) ->
                  let rev = Option.defaultValue "" (List.tryPick (fun k -> Map.tryFind k fields) [ "rev"; "tag"; "branch" ])
                  match Map.tryFind "version" fields with
                  | Some _ when rev <> "" -> fail n $"dependency '{key}' has both rev and version; keep one"
                  | Some vs ->
                    match parseVersion vs with
                    | Some v -> Buffer.push (key, GitVersion(url, v)) deps
                    | None -> fail n $"dependency '{key}': version '{vs}' isn't one such as 1.2 or 1.2.3"
                  // git would take it as an option
                  | None when String.startsWith "-" rev -> fail n $"dependency '{key}': rev '{rev}' starts with -"
                  | None -> Buffer.push (key, GitDep(url, rev)) deps
                | _ -> fail n $"dependency '{key}' needs a path or a git URL"
            | s when s = "c" || String.startsWith "c." s ->
              let target = if s = "c" then "" else String.sub s 2 (String.length s - 2)
              if List.contains key cKeys then
                match listOf value with
                | Ok items ->
                  let keys = Option.defaultValue Map.empty (Map.tryFind target c.Value)
                  c.Value <- Map.add target (Map.add key items keys) c.Value
                | Error msg -> fail n $"[{s}] {key}: {msg}"
              else
                fail n $"unknown key '{key}' in [{s}]; it takes sources, include, link and pkg-config"
            | "workspace" ->
              match (key, listOf value) with
              | ("members", Ok patterns) ->
                // a pattern ending in /* takes the directories under it that have a zs.toml, in order
                for pat in patterns do
                  if String.endsWith "/*" pat || pat = "*" then
                    let dir = Path.getFullPath (Path.combine root (if pat = "*" then "." else String.sub pat 0 (String.length pat - 2)))
                    match Directory.list dir with
                    | Ok names ->
                      for d in List.sort names do
                        if File.exists (Path.combine (Path.combine dir d) "zs.toml") then
                          Buffer.push (Path.combine dir d) members
                    | Error _ -> fail n $"[workspace] members: no directory {dir}"
                  else
                    Buffer.push (Path.getFullPath (Path.combine root pat)) members
              | ("members", Error msg) -> fail n $"[workspace] members: {msg}"
              | _ -> fail n $"unknown key '{key}' in [workspace]; it takes members"
            | "provider" ->
              match (key, unquote value) with
              | ("main", Some v) when not (inside root v) -> fail n $"[provider] main: \"{v}\" isn't a path inside the package"
              | ("main", Some v) -> provider.Value <- Some v
              | ("main", None) -> fail n $"[provider] main: expected a quoted path such as \"Provider.zs\", found {value}"
              | _ -> fail n $"unknown key '{key}' in [provider]; it takes main"
            | s when String.startsWith "target." s ->
              let target = String.sub s 7 (String.length s - 7)
              let known = Option.defaultValue { heap = None } (Map.tryFind target targets.Value)
              match (key, unquote value) with
              | ("heap", Some v) ->
                match size v with
                | Some bytes when bytes > 0 -> targets.Value <- Map.add target { known with heap = Some bytes } targets.Value
                | _ -> fail n $"[{s}] heap: expected a size such as \"16K\", found {value}"
              | ("heap", None) -> fail n $"[{s}] heap: expected a quoted size such as \"16K\", found {value}"
              | _ -> fail n $"unknown key '{key}' in [{s}]; it takes heap"
            | s -> fail n $"unknown section [{s}]"
    List.iteri one lines
    match problem.Value with
    | Some p -> Error p
    | None ->
      let get (k: string) (d: string) = Option.defaultValue d (Map.tryFind k package.Value)
      let full (p: string) = Path.getFullPath (Path.combine root p)
      let linkItem (l: string) = if String.contains "/" l || List.contains (Path.getExtension l) [ ".a"; ".so"; ".o" ] then full l else l
      let config (keys: Map<string, list<string>>) : CConfig =
        let items (k: string) : list<string> = Option.defaultValue [] (Map.tryFind k keys)
        { sources = List.map full (items "sources"); includes = List.map full (items "include"); link = List.map linkItem (items "link"); pkgConfig = items "pkg-config" }
      let sections = Map.map (fun _ keys -> config keys) c.Value
      let m : Manifest =
        { root = root
          name = get "name" (Path.getFileName root)
          version = get "version" "0.1.0"
          main = full (get "main" "src/main.zs")
          target = get "target" ""
          deps = Array.toList (Buffer.toArray deps)
          c = Option.defaultValue (config Map.empty) (Map.tryFind "" sections)
          cFor = Map.remove "" sections
          targets = targets.Value
          provider = Option.map full provider.Value
          members = Array.toList (Buffer.toArray members) }
      Ok m

/// The nearest zs.toml at or above a directory.
let rec findProject (dir: string) : option<result<Manifest, Problem>> =
  if dir = "" then
    None
  else if File.exists (Path.combine dir "zs.toml") then
    Some(readManifest dir)
  else
    let parent = Path.getDirectoryName dir
    if parent = dir then None else findProject parent

/// The workspace a project is a member of (0018 item 8): the nearest zs.toml above it whose
/// [workspace] lists it; None for a project on its own.
let workspaceOf (m: Manifest) : option<Manifest> =
  let rec above (dir: string) : option<Manifest> =
    let parent = Path.getDirectoryName dir
    if parent = dir || parent = "" then
      None
    else
      match findProject parent with
      | Some(Ok w) -> if List.contains m.root w.members then Some w else above w.root
      | _ -> None
  above m.root

// zs.lock: the commit each git dependency resolved to, with the URL and the rev or the release
// (version, its tag's name after the v) it came from
//   [dependencies]
//   json = { git = "https://…", rev = "v1", commit = "<sha>" }
//   text = { git = "https://…", version = "1.3.0", commit = "<sha>" }
// A release's rev is its tag (v1.3.0) here; isVersion says which it was.
type private Locked = { url: string; rev: string; commit: string; isVersion: bool; hash: string }

let private readLock (root: string) : Map<string, Locked> =
  match File.readAllLines (Path.combine root "zs.lock") with
  | Error _ -> Map.empty
  | Ok lines ->
    let entry (acc: Map<string, Locked>) (line: string) =
      match String.indexOf "=" line with
      | Some eq ->
        if eq > 0 && not (String.startsWith "#" (String.trim line)) then
          match tableFields (String.trim (String.sub line (eq + 1) (String.length line - eq - 1))) with
          | Ok fields ->
            let name = String.trim (String.sub line 0 eq)
            match (Map.tryFind "git" fields, Map.tryFind "commit" fields, Map.tryFind "version" fields) with
            // a name is a directory under .zs-cache/deps and vendor/, which fetch and vendor delete
            // and replace: one a manifest couldn't have (../.., an absolute path) is no entry
            | _ when not (depName name) -> acc
            // a commit git would take as an option is no commit: the rev is resolved again
            | (Some url, Some commit, _) when String.startsWith "-" commit -> acc
            | (Some url, Some commit, Some v) -> Map.add name { url = url; rev = "v" + v; commit = commit; isVersion = true; hash = Option.defaultValue "" (Map.tryFind "hash" fields) } acc
            | (Some url, Some commit, None) -> Map.add name { url = url; rev = Option.defaultValue "" (Map.tryFind "rev" fields); commit = commit; isVersion = false; hash = Option.defaultValue "" (Map.tryFind "hash" fields) } acc
            | _ -> acc
          | Error _ -> acc
        else
          acc
      | None -> acc
    List.fold entry Map.empty lines

// a project's own lock root: its workspace's, else its own
let private rootOf (m: Manifest) : string =
  match workspaceOf m with
  | Some w -> w.root
  | None -> m.root

// the lock root of the project that has root as a dependency's checkout or copy
// (<project>/.zs-cache/deps/<name>, <project>/vendor/<name>) that its zs.lock lists
let rec private ownerRoot (root: string) : option<string> =
  let parent = Path.getDirectoryName root
  let up = Path.getDirectoryName parent
  let project =
    if Path.getFileName parent = "deps" && Path.getFileName up = ".zs-cache" then Some(Path.getDirectoryName up)
    else if Path.getFileName parent = "vendor" then Some up
    else None
  match project with
  | Some p when File.exists (Path.combine p "zs.toml") ->
    match readManifest p with
    | Ok o ->
      let r =
        match ownerRoot o.root with
        | Some r0 -> r0
        | None -> rootOf o
      if Map.containsKey (Path.getFileName root) (readLock r) then Some r else None
    | Error _ -> None
  | _ -> None

/// Where a project's lock, checkouts and vendor/ are: its workspace's root, else its own. A
/// dependency's checkout has the project's that fetched it, so a build in it (its provider's,
/// 0001; an editor's) reads the checkouts that project's zs.lock pinned and hashed.
let lockRoot (m: Manifest) : string =
  match ownerRoot m.root with
  | Some r -> r
  | None -> rootOf m

/// Where a git dependency is checked out: <project>/.zs-cache/deps/<name> (the workspace's root
/// for a member).
let gitDir (top: Manifest) (name: string) : string = Path.combine (Path.combine (Path.combine (lockRoot top) ".zs-cache") "deps") name

/// Where a vendored dependency is: <project>/vendor/<name> (zs vendor); a project with one reads
/// it and never fetches.
let vendorDir (top: Manifest) (name: string) : string = Path.combine (Path.combine (lockRoot top) "vendor") name

let private vendored (top: Manifest) (name: string) : bool = File.exists (Path.combine (vendorDir top name) "zs.toml")

// whether root's parts lead through a symbolic link, which a repository may hold, pointing
// anywhere: what zs fetch or zs vendor would delete, clone or check out there is refused instead
let private throughLink (root: string) (parts: list<string>) : bool =
  let rec go (dir: string) (rest: list<string>) =
    match rest with
    | [] -> false
    | x :: more ->
      let here = Path.combine dir x
      // the runtime's hook: stage 0's library (0.6.1) has no public function for it
      let link = unsafe (Native.isSymlink here)
      link || go here more
  go root parts

// where a dependency is for a project whose checkouts and vendor/ are in root (its lock root)
let private depPathIn (root: string) (name: string) (d: Dep) : string =
  match d with
  | PathDep p -> p
  | GitDep _
  | GitVersion _ ->
    let v = Path.combine (Path.combine root "vendor") name
    if File.exists (Path.combine v "zs.toml") then v else Path.combine (Path.combine (Path.combine root ".zs-cache") "deps") name

/// The module a dependency's code is seen under (0018 K1): its key with the first letter
/// upper-cased, each `-` dropped and the letter after it upper-cased (`tree-sitter`: TreeSitter).
let modulePrefix (key: string) : string =
  let part (p: string) = String.toUpper (String.sub p 0 1) + String.sub p 1 (String.length p - 1)
  String.concat (List.map part (List.filter (fun p -> p <> "") (String.split "-" key)))

/// A package as module lookup sees it: the files under `root` (its main's directory) are named
/// by their path there (`Ast/Expr.zs` is `Ast.Expr`), behind `prefix` for a dependency (`Json`,
/// so `Json.Ast.Expr`; its main is `Json` itself); its dependencies, by prefix, are seen from its
/// own files only.
type Package = { prefix: option<string>; root: string; main: string; deps: list<PackageDep>; manifest: option<Manifest> }

/// A package's dependency: its prefix, and the package.
and PackageDep = PackageDep of string * Package

/// The program around a file: the file's directory, and (inside a project) the project's
/// dependencies, each read from its zs.toml once. A project's file other than its main (a test
/// in tests/ or beside the code) names modules from the main's directory, as the program does,
/// so `Domain.Stats` is the same module in both; Modules.fileIn looks in the file's own
/// directory after it. Git dependencies must have been fetched (zs
/// fetch, or any zs build, run, test or check). home: the lock root whose checkouts the git
/// dependencies are, the project's that fetched them (that a package's provider is built for,
/// or that a dependency's file opened as a program was fetched for); None: the file's project's.
let packageIn (file: string) (home: option<string>) : result<Package, Problem> =
  let full = Path.getFullPath file
  // a dependency's directory: its package; a prefix: the directory and key giving it; the
  // directories being read (a dependency of itself is a cycle)
  let made : ref<Map<string, Package>> = ref Map.empty
  let given : ref<Map<string, string * string>> = ref Map.empty
  let reading = ref Set.empty
  let rec package (top: Manifest) (prefix: option<string>) (m: Manifest) : result<Package, Problem> =
    let manifestFile = Path.combine m.root "zs.toml"
    let fail (msg: string) : result<list<PackageDep>, Problem> = Error { file = manifestFile; line = 0; message = msg }
    let rec deps (rest: list<string * Dep>) (acc: list<PackageDep>) : result<list<PackageDep>, Problem> =
      match rest with
      | [] -> Ok(List.rev acc)
      | (name, dep) :: more ->
        let path = depPathIn (Option.defaultValue (lockRoot top) home) name dep
        if not (File.exists (Path.combine path "zs.toml")) then
          match dep with
          | GitDep _
          | GitVersion _ ->
            if Directory.exists path then fail $"dependency '{name}': no zs.toml in {path}" else fail $"git dependency '{name}' isn't fetched yet: run zs fetch"
          | PathDep _ -> fail $"dependency '{name}': no zs.toml in {path}"
        else
          let key = modulePrefix name
          match Map.tryFind key given.Value with
          | Some(other, otherName) when other <> path -> fail $"dependency '{name}' is {path}, and '{otherName}' is {other}: one name is one package in a build"
          | _ ->
            given.Value <- Map.add key (path, name) given.Value
            match Map.tryFind path made.Value with
            | Some p ->
              if p.prefix <> Some key then fail $"the package in {path} is a dependency under two names, {Option.defaultValue "" p.prefix} and {key}; give it one" else deps more (PackageDep(key, p) :: acc)
            | None ->
              if Set.contains path reading.Value then
                fail $"dependency '{name}' depends on itself through {path}"
              else
                reading.Value <- Set.add path reading.Value
                match readManifest path with
                | Error e -> Error e
                | Ok dm ->
                  match package top (Some key) dm with
                  | Error e -> Error e
                  | Ok p ->
                    made.Value <- Map.add path p made.Value
                    deps more (PackageDep(key, p) :: acc)
    match deps m.deps [] with
    | Error e -> Error e
    | Ok ds -> Ok { prefix = prefix; root = Path.getDirectoryName m.main; main = m.main; deps = ds; manifest = Some m }
  let dir = Path.getDirectoryName full
  match findProject dir with
  | Some(Ok m) ->
    match package m None m with
    | Ok p -> Ok { p with main = full }
    | Error e -> Error e
  | Some(Error e) -> Error e
  | None -> Ok { prefix = None; root = dir; main = full; deps = []; manifest = None }

/// The program around a file, its git dependencies the project's own checkouts (packageIn).
let packageOf (file: string) : result<Package, Problem> = packageIn file None

// runs git, failing instead of asking for a password: its output, or Error with its message
let private git (args: list<string>) : result<string, string> =
  match Tools.runSplit "env" ("GIT_TERMINAL_PROMPT=0" :: "git" :: args) with
  | Ok r -> if r.code = 0 then Ok(String.trim r.out) else Error(String.trim r.err)
  | Error _ -> Error "git isn't installed"

// a package's symbolic link's text, a link made, a path with its links followed (src/host.c)
extern zs_host_link_text : cstr -> cstr
extern zs_host_make_link : cstr -> cstr -> cstr
extern zs_host_real_path : cstr -> cstr

/// A checkout's files hashed (0018 item 6): their paths under the directory, sorted, each with its
/// content, .git left out. A symbolic link is hashed as one, by its text, as git keeps it (its
/// path marked with a NUL, which no file's has): what it points at is never read, a file outside
/// the checkout or a device that never ends. Error for a pipe, a device or a socket, which a
/// package has no business holding, and for a directory that can't be read.
let dirHash (dir: string) : result<string, string> =
  match Directory.listRecursive dir with
  | Error e -> Error e
  | Ok rels ->
    let entry (acc: result<list<string>, string>) (r: string) : result<list<string>, string> =
      let p = Path.combine dir r
      match acc with
      | Error e -> Error e
      | Ok parts ->
        if r = ".git" || String.startsWith ".git/" r then Ok parts
        else if (unsafe (Native.isSymlink p)) then Ok(String.ofCStr (zs_host_link_text p) :: (r + String.ofByte (u8 0)) :: parts)
        else if Directory.exists p then Ok parts
        else if File.exists p then Ok(Result.defaultValue "" (File.readAllText p) :: r :: parts)
        else Error $"{r} isn't a file, a directory or a symbolic link (a pipe or a device?)"
    Result.map (fun (parts: list<string>) -> Tools.hashOf (List.rev parts)) (List.fold entry (Ok []) (List.sort rels))

let private writeLock (root: string) (entries: list<string * Locked>) =
  let line (e: string * Locked) =
    let (name, l) = e
    let how = if l.isVersion then $"version = \"{String.sub l.rev 1 (String.length l.rev - 1)}\"" else $"rev = \"{l.rev}\""
    let hash = if l.hash = "" then "" else $", hash = \"{l.hash}\""
    $"{name} = {{ git = \"{l.url}\", {how}, commit = \"{l.commit}\"{hash} }}"
  let lines = List.append [ "# zs.lock: the exact commits of git dependencies, and a hash of each one's files. zs update"; "# moves them to the newest commit of their rev, or release; commit this file so every build"; "# uses the same code."; "[dependencies]" ] (List.map line (List.sortBy fst entries))
  File.writeAllText (Path.combine root "zs.lock") (String.join "\n" lines + "\n") |> ignore

// a dependency's line with its version field's value replaced (zs update): the field whose key is
// version between the line's braces, not the first "version" in the line, which may be in its URL
// (…/conversion); the rest of the line, its comment too, as it was
let private withVersion (line: string) (v: string) : string =
  let code =
    match String.indexOf "#" line with
    | Some h -> String.sub line 0 h
    | None -> line
  let comment = String.sub line (String.length code) (String.length line - String.length code)
  match (String.indexOf "{" code, String.lastIndexOf "}" code) with
  | (Some o, Some c) when o < c ->
    let field (f: string) : string =
      match String.indexOf "=" f with
      | Some eq when String.trim (String.sub f 0 eq) = "version" ->
        let value = String.sub f (eq + 1) (String.length f - eq - 1)
        match String.indexOf "\"" value with
        | Some q1 ->
          let after = String.sub value (q1 + 1) (String.length value - q1 - 1)
          match String.indexOf "\"" after with
          | Some q2 -> String.sub f 0 (eq + 1) + String.sub value 0 (q1 + 1) + v + String.sub after q2 (String.length after - q2)
          | None -> f
        | None -> f
      | _ -> f
    let fields = List.map field (String.split "," (String.sub code (o + 1) (c - o - 1)))
    String.sub code 0 (o + 1) + String.join "," fields + String.sub code c (String.length code - c) + comment
  | _ -> line

/// The commit zs.lock has for a git dependency, by its name in zs.toml (`zs tree`).
let lockedCommit (top: Manifest) (name: string) : option<string> =
  Option.map (fun (l: Locked) -> l.commit) (Map.tryFind name (readLock (lockRoot top)))

/// The project a package's directory is a checkout or a vendored copy for, its lock root:
/// <project>/.zs-cache/deps/<name>, or <project>/vendor/<name> that the project's zs.lock has. A
/// dependency's file opened as a program (an editor's go-to-definition, zs check on it) is that
/// project's: it fetched the dependencies, and what the build writes goes to it.
let fetchedFor (root: string) : option<string> =
  let parent = Path.getDirectoryName root
  let up = Path.getDirectoryName parent
  if Path.getFileName parent = "deps" && Path.getFileName up = ".zs-cache" then
    Some(Path.getDirectoryName up)
  else if Path.getFileName parent = "vendor" then
    match readManifest up with
    | Ok outer -> if Option.isSome (lockedCommit outer (Path.getFileName root)) then Some up else None
    | Error _ -> None
  else
    None

/// Checks out every git dependency of the project (and of its dependencies) at the commit in
/// zs.lock. A new dependency, a changed URL or rev, or update resolves the rev again (fetching
/// when needed) and records the new commit. A dependency on releases (version) gets one by
/// minimal version selection (0018 item 2, Go's): asking for at least 1.2 of a package is its
/// lowest release at or above 1.2.0 within the major; that release's zs.toml (read at its tag)
/// asks for its own; each package gets the highest release asked for, so the result follows
/// from the manifests alone. The lock stands while it gives every release asked for at least
/// what's asked (by the projects and the releases they get), and keeps only what's asked: an
/// entry no manifest asks for is dropped; update first raises the project's own minimums in
/// zs.toml to the newest releases. A dependency's checkout fetches nothing: the project that has
/// it does. Each checkout's files are hashed into the lock and checked against it (item 6): a
/// locked checkout that differs is restored from its commit, and one that still differs is an
/// error; a vendored dependency (vendor/<name>) is read as it is, its hash checked, and never
/// fetched. offline (--offline, or ZS_OFFLINE=1): an error instead of the network. Returns error
/// messages.
let fetchDeps (top: Manifest) (update: bool) (offline0: bool) : list<string> =
  let offline = offline0 || Environment.getVariable "ZS_OFFLINE" = Some "1"
  let root = lockRoot top
  let lock = readLock root
  let resolved = ref Map.empty
  let errors = Buffer.empty
  // a dependency's checkout (its provider's own zs build, an editor in it): what it depends on
  // was fetched, hashed and locked by the project that has it, whose checkouts it's built
  // against; nothing is fetched or locked here
  let owned = Option.isSome (ownerRoot top.root)
  if owned then
    for (name, d) in top.deps do
      match d with
      | PathDep _ -> ()
      | _ ->
        if not (Map.containsKey name lock) then
          Buffer.push $"{top.name} is a dependency of the project at {Path.getRelativePath (Environment.currentDirectory ()) root}, whose zs.lock has no '{name}'; run zs fetch there" errors
  // a member's lock: the workspace has the one (0018 item 8)
  match workspaceOf top with
  | Some w when File.exists (Path.combine top.root "zs.lock") ->
    Buffer.push $"{Path.getRelativePath (Environment.currentDirectory ()) (Path.combine top.root "zs.lock")} belongs to the workspace at {Path.getRelativePath (Environment.currentDirectory ()) (Path.combine w.root "zs.toml")}, which has the one lock; delete it and run zs fetch at the root" errors
  | _ -> ()
  // a workspace's members resolve together, into the one lock (0018 item 8)
  let projects =
    match workspaceOf top with
    | Some w -> List.choose (fun (d: string) -> match readManifest d with | Ok m -> Some m | Error _ -> None) w.members
    | None -> [ top ]
  let forProject (top: Manifest) =
    let visited = ref Set.empty
    let noNetwork (what: string) = Error $"{what} needs the network, and --offline was given"
    // a clone of the dependency's repository, made once
    let cloneOf (name: string) (url: string) : result<string, string> =
      let dir = gitDir top name
      if throughLink root [ ".zs-cache"; "deps"; name ] then
        Error $"{Path.getRelativePath top.root dir} is reached through a symbolic link, which zs fetch doesn't follow"
      else if Directory.exists (Path.combine dir ".git") then
        Ok dir
      else if offline then
        Error "isn't fetched here, and --offline was given (zs vendor keeps a copy in the project)"
      else
        if Directory.exists dir then
          Directory.deleteRecursive dir |> ignore
        Directory.create (Path.combine root ".zs-cache") |> ignore
        Directory.create (Path.getDirectoryName dir) |> ignore
        eprintln $"fetching {name} from {url}"
        Result.map (fun _ -> dir) (git [ "clone"; "--quiet"; "--"; url; dir ])
    let fetchOrigin (dir: string) (what: string) : result<string, string> =
      if offline then noNetwork what else git [ "-C"; dir; "fetch"; "--quiet"; "--tags"; "--force"; "origin" ]
    let mismatch (name: string) (where: string) = $"{name} doesn't match zs.lock's hash: the tag moved, or {where} was edited; zs fetch restores the locked files, zs update accepts the new ones"
    let checkout (name: string) (url: string) (rev: string) (isVersion: bool) : bool =
      let dir = gitDir top name
      let entry = Map.tryFind name lock
      let locked =
        match entry with
        | Some l -> if l.url = url && l.rev = rev && not update then Some l else None
        | None -> None
      let head () = git [ "-C"; dir; "rev-parse"; "HEAD" ]
      if vendored top name then
        // vendored: as it is, against the lock's hash
        let vdir = vendorDir top name
        match (dirHash vdir, locked) with
        | (Error e, _) ->
          Buffer.push $"vendored {name}: {e}" errors
          false
        | (Ok h, Some l) when l.hash <> "" && l.hash <> h ->
          Buffer.push (mismatch name (Path.getRelativePath top.root vdir)) errors
          false
        | (Ok h, _) ->
          let l0 = Option.defaultValue { url = url; rev = rev; commit = ""; isVersion = isVersion; hash = "" } locked
          resolved.Value <- Map.add name { l0 with hash = h; isVersion = isVersion } resolved.Value
          true
      else
        let checkedOut =
          match cloneOf name url with
          | Error e -> Error e
          | Ok _ ->
            match locked with
            | Some l ->
              let c = l.commit
              let at =
                match head () with
                // already checked out: no network
                | Ok h when h = c -> Ok h
                | _ ->
                  // the locked commit: fetched only if this clone doesn't have it
                  let have = git [ "-C"; dir; "cat-file"; "-e"; c + "^{commit}" ]
                  let fetched =
                    match have with
                    | Ok _ -> Ok ""
                    | Error _ -> fetchOrigin dir $"the locked commit of {name}"
                  match fetched with
                  | Error e -> Error e
                  | Ok _ ->
                    match git [ "-C"; dir; "checkout"; "--quiet"; "--detach"; c ] with
                    | Error e -> Error e
                    | Ok _ -> head ()
              // the files against the lock's hash: an edited checkout is restored from its commit
              match at with
              | Error e -> Error e
              | Ok h ->
                if l.hash = "" || Result.defaultValue "" (dirHash dir) = l.hash then
                  Ok h
                else
                  match git [ "-C"; dir; "checkout"; "--quiet"; "--force"; "--detach"; c ] with
                  | Error e -> Error e
                  | Ok _ ->
                    // ignored files too (-x): a checkout's .zs-cache an older zs wrote is in the hash
                    git [ "-C"; dir; "clean"; "-ffdxq" ] |> ignore
                    if Result.defaultValue "" (dirHash dir) = l.hash then Ok h else Error(mismatch name (Path.getRelativePath top.root dir))
            | None ->
              // the rev resolved on the remote's current state: a branch means origin's branch
              eprintln $"resolving {name} {(if rev = "" then "(default branch)" else rev)}"
              match fetchOrigin dir $"resolving {name}" with
              | Error e -> Error e
              | Ok _ ->
                let target =
                  if rev = "" then
                    "origin/HEAD"
                  else
                    match git [ "-C"; dir; "rev-parse"; "--verify"; "--quiet"; "refs/remotes/origin/" + rev ] with
                    | Ok _ -> "origin/" + rev
                    | Error _ -> rev
                match git [ "-C"; dir; "checkout"; "--quiet"; "--detach"; target ] with
                | Error e -> Error e
                | Ok _ -> head ()
        match Result.bind (fun (commit: string) -> Result.map (fun (h: string) -> (commit, h)) (dirHash dir)) checkedOut with
        | Ok(commit, h) ->
          resolved.Value <- Map.add name { url = url; rev = rev; commit = commit; isVersion = isVersion; hash = h } resolved.Value
          true
        | Error e ->
          Buffer.push $"git dependency '{name}' ({url}{(if rev = "" then "" else " " + rev)}): {e}" errors
          false
    // a package's releases, its tags (v1.2.3) by version, fetched once a run
    let tagLists = ref Map.empty
    let releases (name: string) (url: string) : result<list<Version * string>, string> =
      match Map.tryFind name tagLists.Value with
      | Some r -> r
      | None ->
        let listed =
          match cloneOf name url with
          | Error e -> Error e
          | Ok dir ->
            match fetchOrigin dir $"the releases of {name}" with
            | Error e -> Error e
            | Ok _ -> Result.map (fun (out: string) -> String.split "\n" out) (git [ "-C"; dir; "tag"; "--list"; "v*" ])
        let tagged (t: string) = Option.map (fun (v: Version) -> (v, t)) (parseVersion (String.sub t 1 (String.length t - 1)))
        let r = Result.map (fun (ts: list<string>) -> List.choose tagged (List.filter (fun (t: string) -> String.length t > 1) ts)) listed
        tagLists.Value <- Map.add name r tagLists.Value
        r
    // the project's own minimums, raised to the newest releases by update (zs.toml rewritten)
    let raise (name: string) (url: string) (least: Version) : Version =
      match releases name url with
      | Ok tags when update ->
        let mine = List.filter (fun (vt: Version * string) -> seriesOf (fst vt) = seriesOf least) tags
        if List.isEmpty mine then
          least
        else
          let newest = fst (List.last (List.sortBy fst mine))
          if newest > least then
            match File.readAllLines (Path.combine top.root "zs.toml") with
            | Ok lines ->
              // the dependency's own line, by its key in [dependencies], as parseManifest reads it
              let out = Buffer.empty
              let section = ref ""
              for l in lines do
                let code =
                  match String.indexOf "#" l with
                  | Some h -> String.sub l 0 h
                  | None -> l
                let t = String.trim code
                if String.startsWith "[" t && String.endsWith "]" t then
                  section.Value <- String.trim (String.sub t 1 (String.length t - 2))
                  Buffer.push l out
                else
                  match String.indexOf "=" t with
                  | Some eq when section.Value = "dependencies" && String.trim (String.sub t 0 eq) = name -> Buffer.push (withVersion l (showVersion newest)) out
                  | _ -> Buffer.push l out
              File.writeAllText (Path.combine top.root "zs.toml") (String.join "\n" (Array.toList (Buffer.toArray out)) + "\n") |> ignore
              eprintln $"{name}: version {showVersion least} -> {showVersion newest}"
            | Error _ -> ()
            newest
          else
            least
      | _ -> least
    // what the project and its path and rev dependencies ask for of releases
    let wanted = Buffer.empty
    let rec visit (m: Manifest) =
      for (name, dep) in m.deps do
        match dep with
        | GitDep(url, rev) ->
          match Map.tryFind name resolved.Value with
          | Some l ->
            if l.url <> url then
              Buffer.push $"two git dependencies are named '{name}': {l.url} and {url}" errors
            else if l.isVersion then
              Buffer.push $"'{name}' is both a git dependency at a rev and one on releases (version); a name is one package in a build" errors
          | None ->
            let dir = if vendored top name then vendorDir top name else gitDir top name
            if checkout name url rev false && File.exists (Path.combine dir "zs.toml") && not (Set.contains dir visited.Value) then
              visited.Value <- Set.add dir visited.Value
              match readManifest dir with
              | Ok dm -> visit dm
              | Error p -> Buffer.push $"{p.file}: {p.message}" errors
        | GitVersion(url, least) -> Buffer.push (name, url, (if m.root = top.root then raise name url least else least)) wanted
        | PathDep p ->
          if File.exists (Path.combine p "zs.toml") && not (Set.contains p visited.Value) then
            visited.Value <- Set.add p visited.Value
            match readManifest p with
            | Ok dm -> visit dm
            | Error pr -> Buffer.push $"{pr.file}: {pr.message}" errors
    visit top
    // the releases: the lock's while it gives each at least what's asked, else selected
    let asked = Array.toList (Buffer.toArray wanted)
    // the lock's release of a package when it gives at least what's asked (a rev's entry gives
    // none: its rev is no tag)
    let lockGives (w: string * string * Version) : option<Version> =
      let (name, url, least) = w
      match Map.tryFind name lock with
      | Some l when l.isVersion && l.url = url ->
        match parseVersion (String.sub l.rev 1 (String.length l.rev - 1)) with
        | Some v when seriesOf v = seriesOf least && v >= least -> Some v
        | _ -> None
      | _ -> None
    let chosen : ref<Map<string, string * Version * string>> = ref Map.empty
    // a chosen release checked out once a run (the lock's, then perhaps the selection's), and its
    // zs.toml; a name a rev dependency has is refused, as the two would share one checkout
    let taken : ref<Map<string, string * option<Manifest>>> = ref Map.empty
    let take (name: string) (url: string) (tag: string) : option<Manifest> =
      match (Map.tryFind name taken.Value, Map.tryFind name resolved.Value) with
      | (Some(t, dm), _) when t = tag -> dm
      | (_, Some l) when not l.isVersion ->
        Buffer.push $"'{name}' is both a git dependency at a rev and one on releases (version); a name is one package in a build" errors
        taken.Value <- Map.add name (tag, None) taken.Value
        None
      | _ ->
        let dir = if vendored top name then vendorDir top name else gitDir top name
        let dm =
          if checkout name url tag true && File.exists (Path.combine dir "zs.toml") then
            match readManifest dir with
            | Ok m -> Some m
            | Error p ->
              Buffer.push $"{p.file}: {p.message}" errors
              None
          else
            None
        taken.Value <- Map.add name (tag, dm) taken.Value
        dm
    // what a release's zs.toml asks for of releases
    let asksOf (dm: option<Manifest>) : list<string * string * Version> =
      match dm with
      | Some m -> List.choose (fun (kd: string * Dep) -> match snd kd with | GitVersion(u, l) -> Some(fst kd, u, l) | _ -> None) m.deps
      | None -> []
    // from the lock: what's asked, then what those releases ask in turn, each the lock's; an entry
    // nothing asks for any more (zs remove, a version made a rev) isn't taken, and leaves the lock.
    // A release asking for what the lock doesn't give (a lock merged by hand) is selected again
    let before = resolved.Value
    let errorsBefore = Buffer.length errors
    let stale = ref (update || not (List.forall (fun (w: string * string * Version) -> Option.isSome (lockGives w)) asked))
    let rec fromLock (pending: list<string * string * Version>) =
      match pending with
      | [] -> ()
      | w :: rest ->
        let (name, url, _) = w
        match (lockGives w, Map.tryFind name lock) with
        | (Some _, _) when Map.containsKey name chosen.Value -> fromLock rest
        | (Some v, Some l) ->
          chosen.Value <- Map.add name (url, v, l.rev) chosen.Value
          fromLock (List.append (asksOf (take name url l.rev)) rest)
        | _ -> stale.Value <- true
    if not stale.Value then
      fromLock asked
      // a checkout that failed is its error already, which a selection would only repeat
      if Buffer.length errors > errorsBefore then
        stale.Value <- false
    if stale.Value then
      chosen.Value <- Map.empty
      let met = ref Set.empty
      let rec require (name: string) (url: string) (least: Version) =
        match releases name url with
        | Error e -> Buffer.push $"git dependency '{name}' ({url}): {e}" errors
        | Ok tags ->
          let series = List.filter (fun (vt: Version * string) -> seriesOf (fst vt) = seriesOf least) tags
          match List.sortBy fst (List.filter (fun (vt: Version * string) -> fst vt >= least) series) with
          | [] ->
            let newest = if List.isEmpty series then "it has none" else $"the newest is {snd (List.last (List.sortBy fst series))}"
            Buffer.push $"{name}: no tag v{showVersion least} or later below v{seriesOf least + 1}.0.0 ({newest}); ask for an older version, or for a release" errors
          | (v, tag) :: _ ->
            match Map.tryFind name chosen.Value with
            | Some(u, _, _) when u <> url -> Buffer.push $"two dependencies are named '{name}': {u} and {url}; a name is one package in a build" errors
            | _ ->
              if not (Set.contains (name, tag) met.Value) then
                met.Value <- Set.add (name, tag) met.Value
                match Map.tryFind name chosen.Value with
                | Some(_, w, _) when w >= v -> ()
                | _ -> chosen.Value <- Map.add name (url, v, tag) chosen.Value
                // what that release asks for, from its zs.toml at its tag
                match git [ "-C"; gitDir top name; "show"; tag + ":zs.toml" ] with
                | Ok text when i64 (String.length text) > manifestLimit -> Buffer.push $"{name} {tag}: zs.toml is larger than a manifest may be (1 MB)" errors
                | Ok text ->
                  match parseManifest (gitDir top name) $"{name} {tag}: zs.toml" (String.split "\n" text) with
                  | Ok dm ->
                    for (k, d) in dm.deps do
                      match d with
                      | GitVersion(u2, l2) -> require k u2 l2
                      | _ -> ()
                  | Error p -> Buffer.push $"{p.file}: {p.message}" errors
                | Error _ -> ()
      for (name, url, least) in asked do
        require name url least
    // a release the lock gave that the selection didn't take: not locked
    for (name, _) in Map.toList taken.Value do
      if not (Map.containsKey name chosen.Value) && not (Map.containsKey name before) then
        resolved.Value <- Map.remove name resolved.Value
    // each chosen release checked out, and what it depends on by path or rev visited
    for (name, (url, _, tag)) in Map.toList chosen.Value do
      match take name url tag with
      | Some dm when not (Set.contains dm.root visited.Value) ->
        visited.Value <- Set.add dm.root visited.Value
        visit dm
      | _ -> ()
  if Buffer.length errors = 0 && not owned then
    for p in projects do
      forProject p
  if Buffer.length errors = 0 && not owned && (not (Map.isEmpty resolved.Value) || File.exists (Path.combine root "zs.lock")) then
    writeLock root (Map.toList resolved.Value)
  Array.toList (Buffer.toArray errors)

/// zs vendor (0018 item 6): each git dependency's checkout copied into vendor/<name> (.git left
/// out), the lock's hash with it, so the project builds from its own files and never fetches. A
/// symbolic link is copied as a link when it leads inside the package; one leading out of it, a
/// pipe or a device is an error, and the package isn't vendored. Returns error messages.
let vendor (top: Manifest) : list<string> =
  match fetchDeps top false false with
  | [] ->
    let errors = Buffer.empty
    for (name, l) in Map.toList (readLock (lockRoot top)) do
      let from = if vendored top name then vendorDir top name else gitDir top name
      let into = vendorDir top name
      if from <> into && throughLink (lockRoot top) [ "vendor"; name ] then
        Buffer.push $"vendor {name}: {Path.getRelativePath top.root into} is reached through a symbolic link, which zs vendor doesn't follow" errors
      else if from <> into then
        if Directory.exists into then
          Directory.deleteRecursive into |> ignore
        match Directory.listRecursive from with
        | Error e -> Buffer.push $"vendor {name}: {e}" errors
        | Ok rels ->
          Directory.create (Path.combine (lockRoot top) "vendor") |> ignore
          Directory.create into |> ignore
          let failed = Buffer.length errors
          // the checkout with its links followed: a link is copied as the link it is, and only
          // when it leads inside the checkout, never what it points at (vendor/ is committed, and
          // a link may point at any file of the machine)
          let realRoot = String.ofCStr (zs_host_real_path from)
          for r in List.sort rels do
            if r <> ".git" && not (String.startsWith ".git/" r) then
              let src = Path.combine from r
              let dst = Path.combine into r
              if (unsafe (Native.isSymlink src)) then
                let text = String.ofCStr (zs_host_link_text src)
                let target = String.ofCStr (zs_host_real_path src)
                if text = "" || Path.isAbsolute text || realRoot = "" || not (target = realRoot || String.startsWith (realRoot + "/") target) then
                  Buffer.push $"vendor {name}: {r} is a symbolic link to {text}, which leads out of the package (or nowhere); zs vendor copies a link only when it leads inside" errors
                else
                  match String.ofCStr (zs_host_make_link text dst) with
                  | "" -> ()
                  | why -> Buffer.push $"vendor {name}: {r}: {why}" errors
              else if Directory.exists src then
                Directory.create dst |> ignore
              else if File.exists src then
                match File.copy src dst with
                | Ok _ -> ()
                | Error e -> Buffer.push $"vendor {name}: {r}: {e}" errors
              else
                Buffer.push $"vendor {name}: {r} isn't a file, a directory or a symbolic link (a pipe or a device?)" errors
          if Buffer.length errors = failed then
            match dirHash into with
            | Ok h when h = l.hash -> println $"vendored {name} {l.rev} into {Path.getRelativePath top.root into}"
            | Ok _ -> Buffer.push $"vendor {name}: the copy's hash differs from the lock's" errors
            | Error e -> Buffer.push $"vendor {name}: {e}" errors
          // a copy cut short isn't left to be read as the package
          if Buffer.length errors > failed then
            Directory.deleteRecursive into |> ignore
    Array.toList (Buffer.toArray errors)
  | errors -> errors

/// A new project: zs.toml, src/main.zs with a test, and .gitignore; false (with a message) when
/// the directory exists.
let newProject (name: string) : bool =
  if Directory.exists name then
    eprintln $"{name} already exists"
    false
  else
    Directory.create name |> ignore
    Directory.create (Path.combine name "src") |> ignore
    let pkg = Path.getFileName (Path.getFullPath name)
    File.writeAllText (Path.combine name "zs.toml") $"[package]\nname = \"{pkg}\"\nversion = \"0.1.0\"\nmain = \"src/main.zs\"\n\n[dependencies]\n# text = {{ path = \"../text\" }}\n" |> ignore
    File.writeAllText (Path.combine (Path.combine name "src") "main.zs") "open Testing\n\nlet greeting (who: string) = $\"Hello, {who}!\"\n\nlet main () =\n  match Environment.args () with\n  | [] -> println (greeting \"world\")\n  | who :: _ -> println (greeting who)\n  0\n\n[<Tests>]\nlet tests = testList \"greeting\" [ test \"greets\" (fun () -> assert (greeting \"Z#\" = \"Hello, Z#!\")) ]\n" |> ignore
    File.writeAllText (Path.combine name ".gitignore") "build/\n.zs-cache/\n" |> ignore
    println $"created {name}: zs.toml, src/main.zs (cd {name} && zs run)"
    true
