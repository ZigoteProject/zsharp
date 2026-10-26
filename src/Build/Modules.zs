/// The modules of a program (the F# compiler's Driver.libraryModules and loadModules): the
/// library's, the prelude first (its names are global), then Core, then Std on a target with an
/// operating system; then the program's, the main file and the modules it uses (`open M` or
/// `M.name`), dependencies first. A program's module is a file named by its path under the main
/// file's directory (`Ast.Expr` is Ast/Expr.zs or Ast/expr.zs).
// ponytail: no packages yet (0018's dependencies): a program's modules are its directory's
open Syntax
open Diag.Diagnostic

/// A parsed module.
type Loaded =
  { /// its path, as the user knows it
    path: string
    source: Source.Source
    tree: Tree.Tree
    /// None: its names are global (the prelude's and the main file's)
    modName: option<string>
    decls: list<Ast.Decl>
    /// the explicit impls it has: the trait and the type as written
    impls: list<string * string>
    /// the paths of the modules it uses
    uses: list<string>
    /// its syntax errors
    errors: array<Diagnostic>
    /// the C names its imports left out, with why
    skippedC: list<string * string>
    /// what the editor shows for the C names it imports
    cInfos: list<string * CImport.CInfo>
    /// what its imports gave (each header and its saved import): what its checked result
    /// depends on beside its text
    imported: string }

/// The library's files after the prelude, in dependency order; a file's module is its path
/// (core/Collections/List.zs is Collections.List). Core needs no operating system, so every
/// target has it; Std is for targets that have one.
let coreFiles : list<string> =
  [ "Option"; "Result"; "Math"; "Int"; "Float"; "Runtime"; "Mmio"; "Ptr"; "Weak"; "Arena"; "Simd"; "Simd/X86"; "Simd/Arm"; "Collections/List"; "Collections/Span"; "Collections/Array"; "Collections/Buffer"; "Collections/Fixed"; "Text/String"; "Text/Char"; "Text/Utf8"; "Collections/Map"; "Collections/Set"; "Collections/HashMap"; "Collections/HashSet"; "Collections/Queue"; "Collections/Stack"; "Collections/PriorityQueue"; "Iter"; "Testing"; "Binary"; "Throw"; "Collections/Seq"; "Text/Json"; "Time/DateTime"; "Numerics/Random"; "Threading/Atomic"; "Threading/Spsc"; "Irq"; "Cpu"; "Bits" ]

let stdFiles : list<string> =
  [ "IO/Stream"; "Console"; "Environment"; "Threading/Mutex"; "Threading/Channel"; "Threading/Task"; "Threading/Alt"; "Threading/Parallel"; "Collections/Array/Parallel"; "IO/File"; "IO/Directory"; "IO/Path"; "Diagnostics/Process"; "Diagnostics/Stopwatch"; "Net/Tcp"; "Net/Unix"; "Time/Clock"; "Numerics/Entropy"; "Testing/Runner" ]

/// The library: $ZS_LIB, else lib/ beside the compiler (an installed one), else the lib/ of the
/// checkout the compiler was built in (the first directory up from it with lib/prelude.zs).
let libraryDir () : string =
  match Environment.getVariable "ZS_LIB" with
  | Some d -> d
  | None ->
    let dir = Path.getDirectoryName (Tools.selfPath ())
    match Tools.findUp dir "lib/prelude.zs" with
    | Some root -> Path.combine root "lib"
    | None -> Path.combine dir "lib"

/// The library a file is part of: the lib directory above it that holds prelude.zs and core/. An
/// editor opening one of its files checks that library on its own, not as a program that would
/// define everything a second time.
let libraryRootOf (file: string) : option<string> =
  let rec up (dir: string) =
    if Path.getFileName dir = "lib" && File.exists (Path.combine dir "prelude.zs") && Directory.exists (Path.combine dir "core") then
      Some dir
    else
      let parent = Path.getDirectoryName dir
      if parent = "" || parent = dir then None else up parent
  up (Path.getDirectoryName (Path.getFullPath file))

// a file lexed and parsed: its source, tree, declarations and syntax errors
let private parse (index: int) (path: string) (text: string) : Source.Source * Tree.Tree * list<Ast.Decl> * array<Diagnostic> =
  let src = Source.make index path text
  let (toks, lexed) = Diag.Report.collect (fun () -> Lexer.lex src)
  let ((tree, decls), parsed) = Diag.Report.collect (fun () -> Parser.parse src toks)
  (src, tree, decls, Array.append lexed parsed)

let private isUpper (b: u8) : bool = b >= u8 65 && b <= u8 90

// the modules a file names: those it opens, and the A.B of each qualified name A.B.c (a module, or
// A when B is a module nested in it)
let private usesOf (src: Source.Source) (tree: Tree.Tree) (decls: list<Ast.Decl>) : list<string> =
  let opens = List.choose (fun (d: Ast.Decl) -> match d.d with | Ast.Open m -> Some m | _ -> None) decls
  let qualified = Buffer.empty
  for t in tree.tokens do
    if t.kind = Token.Id && t.length > 0 then
      let s = Token.text src.text t
      if isUpper (String.byte s 0) then
        match String.lastIndexOf "." s with
        | Some i -> Buffer.push (String.sub s 0 i) qualified
        | None -> ()
  List.distinct (List.append opens (Array.toList (Buffer.toArray qualified)))

// the explicit impls of a file: the trait and the type as written
let private implsOf (decls: list<Ast.Decl>) : list<string * string> =
  let one (d: Ast.Decl) =
    match d.d with
    | Ast.Impl(tr, Ast.STName(n, _), _, _) -> Some(tr, n)
    | _ -> None
  List.choose one decls

// a file's `module` header
let private headerOf (decls: list<Ast.Decl>) : option<string> =
  match decls with
  | { d = Ast.ModuleHeader h } :: _ -> Some h
  | _ -> None

/// A file's text: the editor's when it has the file open (`texts`, by full path), else the disk's.
let readSource (texts: Map<string, string>) (path: string) : result<string, string> =
  match Map.tryFind (Path.getFullPath path) texts with
  | Some t -> Ok t
  | None -> File.readAllText path

/// A file read and parsed, as a module (its index in the build); Error when it can't be read.
let load (texts: Map<string, string>) (index: int) (path: string) (modName: option<string>) : result<Loaded, string> =
  match readSource texts path with
  | Error e -> Error e
  | Ok text ->
    let (src, tree, decls, errors) = parse index path text
    let m : Loaded =
      { path = path
        source = src
        tree = tree
        modName = modName
        decls = decls
        impls = implsOf decls
        uses = []
        errors = errors
        skippedC = []
        cInfos = []
        imported = "" }
    Ok m

/// The library rooted at `root`, the prelude first (its names are global), then Core, then (when
/// hosted) Std; each file's module named by its header.
let library (texts: Map<string, string>) (root: string) (hosted: bool) : result<list<Loaded>, string> =
  let files = List.concat [ [ "prelude.zs" ]; List.map (fun f -> "core/" + f + ".zs") coreFiles; (if hosted then List.map (fun f -> "std/" + f + ".zs") stdFiles else []) ]
  // each file read and parsed on the pool (decision 76), numbered by its place
  let paths = Array.ofList (List.map (fun (f: string) -> Path.combine root f) files)
  let all = Array.toList (Array.Parallel.init (Array.length paths) (fun i -> load texts i paths.[i] None))
  match List.tryPick (fun (r: result<Loaded, string>) -> match r with | Error e -> Some e | Ok _ -> None) all with
  | Some e -> Error e
  | None -> Ok(List.choose (fun (r: result<Loaded, string>) -> match r with | Ok m -> Some { m with modName = headerOf m.decls } | Error _ -> None) all)

/// What a program's packages give the link (their [c] sections): C flags for the C sources among
/// them, and the sources, libraries and files.
type Linked = { cflags: list<string>; links: list<string> }

let private lowerFirst (s: string) : string =
  if String.length s = 0 then
    s
  else
    let b = String.byte s 0
    (if isUpper b then String.ofByte (b + u8 32) else String.ofByte b) + String.sub s 1 (String.length s - 1)

/// A project's problem as a diagnostic, with the source it's in (the file's index in the build).
let problem (index: int) (p: Project.Problem) : Diagnostic * option<Source.Source> =
  match File.readAllText p.file with
  | Ok text ->
    let display = Path.getRelativePath (Environment.currentDirectory ()) p.file
    let src = Source.make index display text
    let offset = if p.line > 0 && p.line <= Array.length src.lines then src.lines.[p.line - 1] else -1
    (error { file = index; offset = offset; length = -1 } p.message, Some src)
  | Error _ -> (error { file = -1; offset = -1; length = -1 } (p.file + ": " + p.message), None)

/// import c's flags for a target: for one with an OS, clang's triple and zig's C library headers
/// for it as the system's (what the build links against), from `zig cc -v`'s search list; for a
/// chip or WebAssembly, its triple and flags, freestanding, with the compiler's own headers only
/// (stdint.h, stddef.h: there's no C library), so a vendor's header sees the chip it's for; none
/// for this machine.
let private targetFlags (target: string) (chip: option<Options.Mcu>) : list<string> =
  if target = "" then []
  else if String.contains "-none" target || String.startsWith "wasm32" target then
    let flags =
      match chip with
      | Some m -> m.cflags
      | None -> []
    List.append [ "--target=" + target; "-ffreestanding"; "-nostdlibinc" ] flags
  else
    let empty = Result.defaultValue "" (File.createTemp "zs-target-")
    let listed =
      match Tools.runMerged "zig" [ "cc"; "-target"; target; "-E"; "-v"; "-x"; "c"; empty; "-o"; empty + ".i" ] with
      | Ok r ->
        // the lines between "#include <...> search starts here:" and "End of search list."
        let rec dirs (inside: bool) (lines: list<string>) : list<string> =
          match lines with
          | [] -> []
          | l :: rest ->
            if String.startsWith "#include <...>" l then dirs true rest
            else if String.startsWith "End of search list" l then []
            else if inside then l :: dirs true rest
            else dirs false rest
        dirs false (List.map String.trim (String.split "\n" r.out))
      | Error _ -> []
    File.delete empty |> ignore
    File.delete (empty + ".i") |> ignore
    ("--target=" + Options.clangTriple { Options.defaults with target = target }) :: "-nostdlibinc" :: List.collect (fun d -> [ "-isystem"; d ]) listed

/// The main file and the modules it uses, dependencies first (files from index `first` on), and
/// what its packages give the link. A module is a file of its package named by its path under
/// the package's root (`Ast.Expr` is Ast/Expr.zs or Ast/expr.zs), and a dependency's modules are
/// behind its name (0018 K1): `Json` is the json package's main file, `Json.Parser` its
/// Parser.zs. A file names the package's modules as the checker resolves names, in the modules
/// enclosing its own, in the modules it opens, then globally; only its package's files see its
/// dependencies. An import cycle is an error at the file that closes it. target: --target's
/// triple, "" for this machine (where pkg-config runs).
let program (texts: Map<string, string>) (first: int) (mainPath: string) (target: string) (chip: option<Options.Mcu>) : result<list<Loaded> * Linked, Diagnostic * option<Source.Source>> =
  let hosted = target = ""
  let forTarget = targetFlags target chip
  let targetName = Options.targetName chip target
  let order = Buffer.empty
  let count = ref first
  // a module: whether it's fully loaded
  let finished = ref Map.empty
  let failure = ref None
  let mainFull = Path.getFullPath mainPath
  let display (p: string) = Path.getRelativePath (Environment.currentDirectory ()) p
  let cflags = Buffer.empty
  let links = Buffer.empty
  let used = ref Set.empty
  let fail (d: Diagnostic * option<Source.Source>) =
    if Option.isNone failure.Value then
      failure.Value <- Some d
  let failProblem (p: Project.Problem) =
    count.Value <- count.Value + 1
    fail (problem (count.Value - 1) p)
  // the file of the module at `path` (A.B) under a package's root, not its main (a dependency's
  // main is its name alone; the program's isn't a module); then under the main's own directory,
  // when that isn't the root (a test in tests/ finds its helpers beside it)
  let fileIn (pkg: Project.Package) (path: string) : option<string> =
    let parts = String.split "." path
    let last = List.last parts
    let dirs = List.take (List.length parts - 1) parts
    // each name below root as the directory lists it: macOS's and Windows's file systems ignore
    // case, so File.exists finds simd/x86.zs for Simd/X86.zs, which would make a file the module
    // of another name (a library's, or the file itself)
    let rec listed (dir: string) (names: list<string>) =
      match names with
      | [] -> true
      | n :: rest ->
        match Directory.list dir with
        | Ok here -> List.contains n here && listed (Path.combine dir n) rest
        | Error _ -> true
    let under (root: string) =
      let dir = List.fold Path.combine root dirs
      let named (file: string) = Path.combine dir file <> pkg.main && File.exists (Path.combine dir file) && listed root (List.append dirs [ file ])
      Option.map (Path.combine dir) (List.tryFind named [ last + ".zs"; lowerFirst last + ".zs" ])
    let own = Path.getDirectoryName pkg.main
    match under pkg.root with
    | None when own <> pkg.root -> under own
    | found -> found
  // the module with the full name m, as a file of pkg or of one of its dependencies
  let find (pkg: Project.Package) (m: string) : option<string * string * Project.Package> =
    let within (p: Project.Package) (prefix: option<string>) : option<string * string * Project.Package> =
      match prefix with
      | Some k ->
        if m = k then
          Some(m, p.main, p)
        else if String.startsWith (k + ".") m then
          Option.map (fun f -> (m, f, p)) (fileIn p (String.sub m (String.length k + 1) (String.length m - String.length k - 1)))
        else
          None
      | None -> Option.map (fun f -> (m, f, p)) (fileIn p m)
    match within pkg pkg.prefix with
    | Some r -> Some r
    | None -> List.tryPick (fun (pd: Project.PackageDep) -> match pd with | Project.PackageDep(k, d) -> within d (Some k)) pkg.deps
  // the modules a file's uses name: for A.B, the module A.B wherever it resolves (or A, when
  // nothing does): in the modules enclosing the file's, the modules it opens, then globally
  let usedBy (pkg: Project.Package) (modName: option<string>) (opens: list<string>) (uses: list<string>) : list<string * string * Project.Package> =
    let enclosing =
      match modName with
      | Some n -> List.rev (Infer.Cx.withEnclosing n)
      | None -> []
    let near (p: string) = List.append (List.map (fun e -> e + "." + p) enclosing) [ p ]
    let opened = List.collect near opens
    let rec named (m: string) : list<string * string * Project.Package> =
      let candidates = List.append (near m) (List.map (fun o -> o + "." + m) opened)
      match List.choose (find pkg) candidates with
      | [] when String.contains "." m -> named (Option.get (Infer.Cx.beforeLastDot m))
      | found -> found
    List.collect named uses
  // pkg-config's --cflags or --libs for a name in a package's [c], as arguments
  let pkgConfig (m: Project.Manifest) (what: string) (name: string) : list<string> =
    match Tools.runSplit "pkg-config" [ what; name ] with
    | Ok r ->
      if r.code = 0 then
        List.filter (fun a -> a <> "") (String.split " " (String.replace (String.replace r.out "\t" " ") "\n" " "))
      else
        failProblem { file = Path.combine m.root "zs.toml"; line = 0; message = $"package {m.name}: pkg-config knows no '{name}'; install the library's development files, or give include and link in [c]" }
        []
    | Error _ ->
      failProblem { file = Path.combine m.root "zs.toml"; line = 0; message = $"package {m.name}: pkg-config isn't installed; install it, or give include and link in [c]" }
      []
  // a package's [c] once a file of it is loaded: its sources, libraries and C flags are the
  // build's; its include directories and pkg-config's flags are its `import c`s'
  let cOf (pkg: Project.Package) : list<string> =
    match pkg.manifest with
    | None -> []
    | Some m ->
      let c = Project.cConfigFor m targetName
      let pc (what: string) = if hosted then List.collect (pkgConfig m what) c.pkgConfig else []
      let flags = List.append (List.map (fun i -> "-I" + i) c.includes) (pc "--cflags")
      if not (Set.contains m.root used.Value) then
        used.Value <- Set.add m.root used.Value
        for f in flags do
          if not (List.contains f (Array.toList (Buffer.toArray cflags))) then
            Buffer.push f cflags
        for l in List.concat [ c.sources; c.link; pc "--libs" ] do
          if not (List.contains l (Array.toList (Buffer.toArray links))) then
            Buffer.push l links
      flags
  // import c: each replaced by the header's declarations, saved in the project's
  // .zs-cache/cimport (or one next to the file); a [<Link>] on one is the build's
  let imports (m: Loaded) (path: string) (flags: list<string>) : result<Loaded, Diagnostic> =
    let dir = Path.getDirectoryName (Path.getFullPath path)
    let root =
      match Project.findProject dir with
      | Some(Ok pm) -> pm.root
      | _ -> dir
    let cacheDir = Path.combine (Path.combine root ".zs-cache") "cimport"
    let lineOf (d: Ast.Decl) : Span =
      let offset = if d.dat >= 0 && d.dat < Array.length m.tree.tokens then m.tree.tokens.[d.dat].offset else 0
      { file = m.source.file; offset = offset; length = -1 }
    let problem = ref None
    let report (d: Ast.Decl) (msg: string) =
      if Option.isNone problem.Value then
        problem.Value <- Some(error (lineOf d) msg)
    let skipped = Buffer.empty
    let infos = Buffer.empty
    let gave = Buffer.empty
    let imported (header: string) (d: Ast.Decl) : list<Ast.Decl> =
      match CImport.importHeader header dir flags cacheDir d.dat with
      | Ok r ->
        Buffer.push (header + "\n" + Result.defaultValue "" (File.readAllText (CImport.savedFile header flags cacheDir))) gave
        for x in r.skipped do
          Buffer.push x skipped
        for x in r.infos do
          Buffer.push x infos
        List.map (fun (shape: Ast.DeclShape) -> Ast.decl shape d.dat) r.decls
      | Error msg ->
        report d msg
        []
    let expand (d: Ast.Decl) : list<Ast.Decl> =
      match d.d with
      | Ast.ImportC header -> imported header d
      | Ast.Attrs(attrs, inner) ->
        match inner.d with
        | Ast.ImportC header ->
          for (a, args) in attrs do
            if a <> "Link" || List.isEmpty args then
              report inner $"unknown attribute '{a}' on import c (use [<Link \"lib\">])"
            for l in args do
              let item = if List.contains (Path.getExtension l) [ ".c"; ".o"; ".a"; ".so" ] then Path.combine dir l else l
              if not (List.contains item (Array.toList (Buffer.toArray links))) then
                Buffer.push item links
          imported header inner
        | _ -> [ d ]
      | _ -> [ d ]
    let decls = List.collect expand m.decls
    match problem.Value with
    | Some p -> Error p
    | None -> Ok { m with decls = decls; skippedC = Array.toList (Buffer.toArray skipped); cInfos = Array.toList (Buffer.toArray infos); imported = String.join "\n" (Array.toList (Buffer.toArray gave)) }
  let rec visit (path: string) (pkg: Project.Package) (modName0: option<string>) (stack: list<string>) =
    if Option.isNone failure.Value then
      count.Value <- count.Value + 1
      match load texts (count.Value - 1) (display path) modName0 with
      | Error e -> fail (error { file = -1; offset = -1; length = -1 } e, None)
      | Ok loaded ->
        // the package's [c] is the build's; its include directories and pkg-config's flags are
        // its import c's
        match imports loaded path (List.append (cOf pkg) forTarget) with
        | Error d -> fail (d, Some loaded.source)
        | Ok m ->
          // a dependency's file is named by its place in the package; a header may only agree
          let header = headerOf m.decls
          let named =
            match (header, modName0, pkg.prefix) with
            | (Some h, Some mn, Some k) ->
              if h <> mn && mn <> k + "." + h then Error $"this file is the module {mn}, named by its place in its package; its header says {h}: remove it" else Ok modName0
            | (Some h, Some _, None) -> Ok(Some h)
            | _ -> Ok modName0
          match named with
          | Error msg -> fail (error { file = m.source.file; offset = 0; length = -1 } msg, Some m.source)
          | Ok modName ->
            let opens = List.choose (fun (d: Ast.Decl) -> match d.d with | Ast.Open o -> Some o | _ -> None) m.decls
            let all = usedBy pkg modName opens (usesOf m.source m.tree m.decls)
            let fresh = List.filter (fun (n, f, _) -> Some n <> modName && f <> path && f <> mainFull) all
            let deps = List.fold (fun (acc: list<string * string * Project.Package>) (n, f, p) -> if List.exists (fun (k, _, _) -> k = n) acc then acc else List.append acc [ (n, f, p) ]) [] fresh
            for (n, f, p) in deps do
              if Option.isNone failure.Value then
                match Map.tryFind n finished.Value with
                | Some true -> ()
                | Some false ->
                  let cycle = String.join " -> " (List.rev (n :: stack))
                  fail (error { file = m.source.file; offset = -1; length = -1 } $"import cycle: {cycle}", Some m.source)
                | None ->
                  finished.Value <- Map.add n false finished.Value
                  visit f p (Some n) (n :: stack)
                  finished.Value <- Map.add n true finished.Value
            let usedFiles = List.map (fun (_, f, _) -> display f) deps
            Buffer.push { m with modName = modName; uses = usedFiles } order
  match Project.packageOf mainPath with
  | Error p ->
    failProblem p
    Error(Option.get failure.Value)
  | Ok pkg ->
    visit mainFull pkg None [ Path.getFileNameWithoutExtension mainPath ]
    match failure.Value with
    | Some f -> Error f
    | None ->
      let loaded = Array.toList (Buffer.toArray order)
      // the main file keeps the path the user gave
      let last = List.last loaded
      let mods = List.append (List.take (List.length loaded - 1) loaded) [ { last with path = mainPath; source = { last.source with path = mainPath } } ]
      Ok(mods, { cflags = Array.toList (Buffer.toArray cflags); links = Array.toList (Buffer.toArray links) })
