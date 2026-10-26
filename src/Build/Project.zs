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
type Manifest = { root: string; name: string; version: string; main: string; target: string; deps: list<string * Dep>; c: CConfig; cFor: Map<string, CConfig>; targets: Map<string, TargetConfig> }

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

// a dependency's name, also its directory under .zs-cache/deps (fetch replaces what is there):
// letters, digits, - and _, so never `..`, a `/` or an absolute path
let private depName (key: string) =
  key <> "" && List.forall (fun (c: char) -> Char.isLetterOrDigit c || c = '-' || c = '_') (String.chars key)

/// Reads the subset of TOML a manifest uses: [sections], key = "string", key = { k = "v", … },
/// key = [ "a", "b" ].
let rec readManifest (root: string) : result<Manifest, Problem> =
  let file = Path.combine root "zs.toml"
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
    // 4096, 16K, 1M: bytes
    let size (v: string) : option<int> =
      let n = String.length v
      let scaled (k: int) : option<int> = Option.map (fun (x: int) -> x * k) (Int.parse (String.sub v 0 (n - 1)))
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
          targets = targets.Value }
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

/// Where a git dependency is checked out: <project>/.zs-cache/deps/<name>.
let gitDir (top: Manifest) (name: string) : string = Path.combine (Path.combine (Path.combine top.root ".zs-cache") "deps") name

let private depPath (top: Manifest) (name: string) (d: Dep) : string =
  match d with
  | PathDep p -> p
  | GitDep _
  | GitVersion _ -> gitDir top name

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
/// fetch, or any zs build, run, test or check).
let packageOf (file: string) : result<Package, Problem> =
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
        let path = depPath top name dep
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

// runs git, failing instead of asking for a password: its output, or Error with its message
let private git (args: list<string>) : result<string, string> =
  match Tools.runSplit "env" ("GIT_TERMINAL_PROMPT=0" :: "git" :: args) with
  | Ok r -> if r.code = 0 then Ok(String.trim r.out) else Error(String.trim r.err)
  | Error _ -> Error "git isn't installed"

// zs.lock: the commit each git dependency resolved to, with the URL and the rev or the release
// (version, its tag's name after the v) it came from
//   [dependencies]
//   json = { git = "https://…", rev = "v1", commit = "<sha>" }
//   text = { git = "https://…", version = "1.3.0", commit = "<sha>" }
// A release's rev is its tag (v1.3.0) here; isVersion says which it was.
type private Locked = { url: string; rev: string; commit: string; isVersion: bool }

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
            // a commit git would take as an option is no commit: the rev is resolved again
            | (Some url, Some commit, _) when String.startsWith "-" commit -> acc
            | (Some url, Some commit, Some v) -> Map.add name { url = url; rev = "v" + v; commit = commit; isVersion = true } acc
            | (Some url, Some commit, None) -> Map.add name { url = url; rev = Option.defaultValue "" (Map.tryFind "rev" fields); commit = commit; isVersion = false } acc
            | _ -> acc
          | Error _ -> acc
        else
          acc
      | None -> acc
    List.fold entry Map.empty lines

let private writeLock (root: string) (entries: list<string * Locked>) =
  let line (e: string * Locked) =
    let (name, l) = e
    let how = if l.isVersion then $"version = \"{String.sub l.rev 1 (String.length l.rev - 1)}\"" else $"rev = \"{l.rev}\""
    $"{name} = {{ git = \"{l.url}\", {how}, commit = \"{l.commit}\" }}"
  let lines = List.append [ "# zs.lock: the exact commits of git dependencies. zs update moves them to the newest"; "# commit of their rev, or release; commit this file so every build uses the same code."; "[dependencies]" ] (List.map line (List.sortBy fst entries))
  File.writeAllText (Path.combine root "zs.lock") (String.join "\n" lines + "\n") |> ignore

/// Checks out every git dependency of the project (and of its dependencies) at the commit in
/// zs.lock. A new dependency, a changed URL or rev, or update resolves the rev again (fetching
/// when needed) and records the new commit. A dependency on releases (version) gets one by
/// minimal version selection (0018 item 2, Go's): asking for at least 1.2 of a package is its
/// lowest release at or above 1.2.0 within the major; that release's zs.toml (read at its tag)
/// asks for its own; each package gets the highest release asked for, so the result follows
/// from the manifests alone. The lock stands while it gives every release asked for at least
/// what's asked; update first raises the project's own minimums in zs.toml to the newest
/// releases. Returns error messages.
let fetchDeps (top: Manifest) (update: bool) : list<string> =
  let lock = readLock top.root
  let resolved = ref Map.empty
  let errors = Buffer.empty
  let visited = ref Set.empty
  // a clone of the dependency's repository, made once
  let cloneOf (name: string) (url: string) : result<string, string> =
    let dir = gitDir top name
    if Directory.exists (Path.combine dir ".git") then
      Ok dir
    else
      if Directory.exists dir then
        Directory.deleteRecursive dir |> ignore
      Directory.create (Path.combine top.root ".zs-cache") |> ignore
      Directory.create (Path.getDirectoryName dir) |> ignore
      eprintln $"fetching {name} from {url}"
      Result.map (fun _ -> dir) (git [ "clone"; "--quiet"; "--"; url; dir ])
  let checkout (name: string) (url: string) (rev: string) (isVersion: bool) : bool =
    let dir = gitDir top name
    let locked =
      match Map.tryFind name lock with
      | Some l -> if l.url = url && l.rev = rev && not update then Some l.commit else None
      | None -> None
    let head () = git [ "-C"; dir; "rev-parse"; "HEAD" ]
    let checkedOut =
      match cloneOf name url with
      | Error e -> Error e
      | Ok _ ->
        match locked with
        | Some c ->
          match head () with
          // already checked out: no network
          | Ok h when h = c -> Ok h
          | _ ->
            // the locked commit: fetched only if this clone doesn't have it
            let have = git [ "-C"; dir; "cat-file"; "-e"; c + "^{commit}" ]
            let fetched =
              match have with
              | Ok _ -> Ok ""
              | Error _ -> git [ "-C"; dir; "fetch"; "--quiet"; "--tags"; "origin" ]
            match fetched with
            | Error e -> Error e
            | Ok _ ->
              match git [ "-C"; dir; "checkout"; "--quiet"; "--detach"; c ] with
              | Error e -> Error e
              | Ok _ -> head ()
        | None ->
          // the rev resolved on the remote's current state: a branch means origin's branch
          eprintln $"resolving {name} {(if rev = "" then "(default branch)" else rev)}"
          match git [ "-C"; dir; "fetch"; "--quiet"; "--tags"; "--force"; "origin" ] with
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
    match checkedOut with
    | Ok commit ->
      resolved.Value <- Map.add name { url = url; rev = rev; commit = commit; isVersion = isVersion } resolved.Value
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
          match git [ "-C"; dir; "fetch"; "--quiet"; "--tags"; "--force"; "origin" ] with
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
            let bump (l: string) =
              let t = String.trim l
              if (String.startsWith (name + " ") t || String.startsWith (name + "=") t) && String.contains "version" t then
                match String.indexOf "version" l with
                | Some at ->
                  let rest = String.sub l at (String.length l - at)
                  match (String.indexOf "\"" rest) with
                  | Some q1 ->
                    let after = String.sub rest (q1 + 1) (String.length rest - q1 - 1)
                    match String.indexOf "\"" after with
                    | Some q2 -> String.sub l 0 (at + q1 + 1) + showVersion newest + String.sub after q2 (String.length after - q2)
                    | None -> l
                  | None -> l
                | None -> l
              else
                l
            File.writeAllText (Path.combine top.root "zs.toml") (String.join "\n" (List.map bump lines) + "\n") |> ignore
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
        | None ->
          let dir = gitDir top name
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
  let fromLock (w: string * string * Version) =
    let (name, url, least) = w
    match Map.tryFind name lock with
    | Some l when l.isVersion && l.url = url ->
      match parseVersion (String.sub l.rev 1 (String.length l.rev - 1)) with
      | Some v -> seriesOf v = seriesOf least && v >= least
      | None -> false
    | _ -> false
  let chosen : ref<Map<string, string * Version * string>> = ref Map.empty
  if not update && List.forall fromLock asked then
    for (name, l) in Map.toList lock do
      match (l.isVersion, parseVersion (String.sub l.rev 1 (String.length l.rev - 1))) with
      | (true, Some v) -> chosen.Value <- Map.add name (l.url, v, l.rev) chosen.Value
      | _ -> ()
  else
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
  // each chosen release checked out, and what it depends on by path or rev visited
  for (name, (url, _, tag)) in Map.toList chosen.Value do
    let dir = gitDir top name
    if checkout name url tag true && File.exists (Path.combine dir "zs.toml") && not (Set.contains dir visited.Value) then
      visited.Value <- Set.add dir visited.Value
      match readManifest dir with
      | Ok dm -> visit dm
      | Error p -> Buffer.push $"{p.file}: {p.message}" errors
  if Buffer.length errors = 0 && (not (Map.isEmpty resolved.Value) || File.exists (Path.combine top.root "zs.lock")) then
    writeLock top.root (Map.toList resolved.Value)
  Array.toList (Buffer.toArray errors)

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
    File.writeAllText (Path.combine name ".gitignore") "build/\n" |> ignore
    println $"created {name}: zs.toml, src/main.zs (cd {name} && zs run)"
    true
