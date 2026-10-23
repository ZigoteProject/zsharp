/// A project (the F# compiler's Driver manifest code): its zs.toml (the package, its
/// dependencies, its [c] section), a package as module lookup sees it, and zs fetch and zs update
/// for git dependencies, with zs.lock.
///   [package]  name = "wc"  version = "0.1.0"  main = "src/main.zs" (the default)
///   [dependencies]  text = { path = "../text" }  json = { git = "https://…", rev = "v1" }
///   [c]  sources = ["c/xxhash.c"]  include = ["c"]  link = ["m"]  pkg-config = ["sqlite3"]

/// A dependency: a directory (its full path), or a git repository at a rev (a tag, branch or
/// commit; "" for the default branch).
type Dep =
  | PathDep of string
  | GitDep of string * string

/// A package's [c] section (0018 item 4): C sources compiled and linked with it, directories for
/// its `import c`s and its sources' #includes, libraries to link (names, or files as [<Link>]
/// takes them), and pkg-config names, whose flags and libraries a host build adds. Paths are full.
type CConfig = { sources: list<string>; includes: list<string>; link: list<string>; pkgConfig: list<string> }

/// A zs.toml: the directory holding it, the package's name, version and main file (full path),
/// its dependencies by name, and its [c] section.
type Manifest = { root: string; name: string; version: string; main: string; deps: list<string * Dep>; c: CConfig }

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

/// Reads the subset of TOML a manifest uses: [sections], key = "string", key = { k = "v", … },
/// key = [ "a", "b" ].
let readManifest (root: string) : result<Manifest, Problem> =
  let file = Path.combine root "zs.toml"
  match File.readAllLines file with
  | Error e -> Error { file = file; line = 0; message = e }
  | Ok lines ->
    let section = ref ""
    let package = ref Map.empty
    let deps = Buffer.empty
    let c = ref Map.empty
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
              | Ok fields ->
                match (Map.tryFind "path" fields, Map.tryFind "git" fields) with
                | (Some p, _) -> Buffer.push (key, PathDep(Path.getFullPath (Path.combine root p))) deps
                | (None, Some url) ->
                  let rev = List.tryPick (fun k -> Map.tryFind k fields) [ "rev"; "tag"; "branch" ]
                  Buffer.push (key, GitDep(url, Option.defaultValue "" rev)) deps
                | _ -> fail n $"dependency '{key}' needs a path or a git URL"
            | "c" ->
              if List.contains key cKeys then
                match listOf value with
                | Ok items -> c.Value <- Map.add key items c.Value
                | Error msg -> fail n $"[c] {key}: {msg}"
              else
                fail n $"unknown key '{key}' in [c]; it takes sources, include, link and pkg-config"
            | s -> fail n $"unknown section [{s}]"
    List.iteri one lines
    match problem.Value with
    | Some p -> Error p
    | None ->
      let get (k: string) (d: string) = Option.defaultValue d (Map.tryFind k package.Value)
      let items (k: string) : list<string> = Option.defaultValue [] (Map.tryFind k c.Value)
      let full (p: string) = Path.getFullPath (Path.combine root p)
      let linkItem (l: string) = if String.contains "/" l || List.contains (Path.getExtension l) [ ".a"; ".so"; ".o" ] then full l else l
      let config : CConfig = { sources = List.map full (items "sources"); includes = List.map full (items "include"); link = List.map linkItem (items "link"); pkgConfig = items "pkg-config" }
      let m : Manifest = { root = root; name = get "name" (Path.getFileName root); version = get "version" "0.1.0"; main = full (get "main" "src/main.zs"); deps = Array.toList (Buffer.toArray deps); c = config }
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
  | GitDep _ -> gitDir top name

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
/// dependencies, each read from its zs.toml once. Git dependencies must have been fetched (zs
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
          | GitDep _ ->
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
    | Ok p -> Ok { p with root = dir; main = full }
    | Error e -> Error e
  | Some(Error e) -> Error e
  | None -> Ok { prefix = None; root = dir; main = full; deps = []; manifest = None }

// runs git, failing instead of asking for a password: its output, or Error with its message
let private git (args: list<string>) : result<string, string> =
  match Tools.runSplit "env" ("GIT_TERMINAL_PROMPT=0" :: "git" :: args) with
  | Ok r -> if r.code = 0 then Ok(String.trim r.out) else Error(String.trim r.err)
  | Error _ -> Error "git isn't installed"

// zs.lock: the commit each git dependency resolved to, with the URL and rev it came from
//   [dependencies]
//   json = { git = "https://…", rev = "v1", commit = "<sha>" }
let private readLock (root: string) : Map<string, string * string * string> =
  match File.readAllLines (Path.combine root "zs.lock") with
  | Error _ -> Map.empty
  | Ok lines ->
    let entry (acc: Map<string, string * string * string>) (line: string) =
      match String.indexOf "=" line with
      | Some eq ->
        if eq > 0 && not (String.startsWith "#" (String.trim line)) then
          match tableFields (String.trim (String.sub line (eq + 1) (String.length line - eq - 1))) with
          | Ok fields ->
            match (Map.tryFind "git" fields, Map.tryFind "commit" fields) with
            | (Some url, Some commit) -> Map.add (String.trim (String.sub line 0 eq)) (url, Option.defaultValue "" (Map.tryFind "rev" fields), commit) acc
            | _ -> acc
          | Error _ -> acc
        else
          acc
      | None -> acc
    List.fold entry Map.empty lines

let private writeLock (root: string) (entries: list<string * (string * string * string)>) =
  let line (e: string * (string * string * string)) =
    let (name, (url, rev, commit)) = e
    $"{name} = {{ git = \"{url}\", rev = \"{rev}\", commit = \"{commit}\" }}"
  let lines = List.append [ "# zs.lock: the exact commits of git dependencies. zs update moves them to the newest"; "# commit of their rev; commit this file so every build uses the same code."; "[dependencies]" ] (List.map line (List.sortBy fst entries))
  File.writeAllText (Path.combine root "zs.lock") (String.join "\n" lines + "\n") |> ignore

/// Checks out every git dependency of the project (and of its dependencies) at the commit in
/// zs.lock. A new dependency, a changed URL or rev, or update resolves the rev again (fetching
/// when needed) and records the new commit. Returns error messages.
let fetchDeps (top: Manifest) (update: bool) : list<string> =
  let lock = readLock top.root
  let resolved = ref Map.empty
  let errors = Buffer.empty
  let visited = ref Set.empty
  let checkout (name: string) (url: string) (rev: string) : bool =
    let dir = gitDir top name
    let locked =
      match Map.tryFind name lock with
      | Some(u, r, c) -> if u = url && r = rev && not update then Some c else None
      | None -> None
    let head () = git [ "-C"; dir; "rev-parse"; "HEAD" ]
    let cloned =
      if Directory.exists (Path.combine dir ".git") then
        Ok ""
      else
        if Directory.exists dir then
          Directory.deleteRecursive dir |> ignore
        Directory.create (Path.combine top.root ".zs-cache") |> ignore
        Directory.create (Path.getDirectoryName dir) |> ignore
        eprintln $"fetching {name} from {url}"
        git [ "clone"; "--quiet"; "--"; url; dir ]
    let checkedOut =
      match cloned with
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
      resolved.Value <- Map.add name (url, rev, commit) resolved.Value
      true
    | Error e ->
      Buffer.push $"git dependency '{name}' ({url}{(if rev = "" then "" else " " + rev)}): {e}" errors
      false
  let rec visit (m: Manifest) =
    for (name, dep) in m.deps do
      match dep with
      | GitDep(url, rev) ->
        match Map.tryFind name resolved.Value with
        | Some(u, _, _) ->
          if u <> url then
            Buffer.push $"two git dependencies are named '{name}': {u} and {url}" errors
        | None ->
          let dir = gitDir top name
          if checkout name url rev && File.exists (Path.combine dir "zs.toml") && not (Set.contains dir visited.Value) then
            visited.Value <- Set.add dir visited.Value
            match readManifest dir with
            | Ok dm -> visit dm
            | Error p -> Buffer.push $"{p.file}: {p.message}" errors
      | PathDep p ->
        if File.exists (Path.combine p "zs.toml") && not (Set.contains p visited.Value) then
          visited.Value <- Set.add p visited.Value
          match readManifest p with
          | Ok dm -> visit dm
          | Error pr -> Buffer.push $"{pr.file}: {pr.message}" errors
  visit top
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
