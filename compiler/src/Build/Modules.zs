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
    errors: array<Diagnostic> }

/// The library's files after the prelude, in dependency order; a file's module is its path
/// (core/Collections/List.zs is Collections.List). Core needs no operating system, so every
/// target has it; Std is for targets that have one.
let coreFiles : list<string> =
  [ "Option"; "Result"; "Math"; "Int"; "Float"; "Runtime"; "Mmio"; "Ptr"; "Weak"; "Arena"; "Simd"; "Simd/X86"; "Simd/Arm"; "Collections/List"; "Collections/Span"; "Collections/Array"; "Collections/Buffer"; "Collections/Fixed"; "Text/String"; "Text/Char"; "Collections/Map"; "Collections/Set"; "Collections/HashMap"; "Collections/HashSet"; "Iter"; "Testing"; "Binary"; "Throw"; "Collections/Seq"; "Text/Json"; "Time/DateTime" ]

let stdFiles : list<string> =
  [ "IO/Stream"; "Console"; "Environment"; "Threading/Atomic"; "Threading/Mutex"; "Threading/Channel"; "Threading/Task"; "Threading/Parallel"; "Collections/Array/Parallel"; "IO/File"; "IO/Directory"; "IO/Path"; "Diagnostics/Process"; "Diagnostics/Stopwatch"; "Net/Tcp"; "Net/Unix"; "Time/Clock"; "Testing/Runner" ]

/// The library: $ZS_LIB, else lib/ beside the compiler, else lib/ two directories up (the
/// compiler built in compiler/build of a checkout of zs).
let libraryDir () : string =
  match Environment.getVariable "ZS_LIB" with
  | Some d -> d
  | None ->
    let dir = Path.getDirectoryName (Environment.programName ())
    let beside = Path.combine dir "lib"
    if File.exists (Path.combine beside "prelude.zs") then beside else Path.combine (Path.combine (Path.combine dir "..") "..") "lib"

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

/// A file read and parsed, as a module (its index in the build); Error when it can't be read.
let load (index: int) (path: string) (modName: option<string>) : result<Loaded, string> =
  match File.readAllText path with
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
        errors = errors }
    Ok m

/// The library rooted at `root`, the prelude first (its names are global), then Core, then (when
/// hosted) Std; each file's module named by its header.
let library (root: string) (hosted: bool) : result<list<Loaded>, string> =
  let files = List.concat [ [ "prelude.zs" ]; List.map (fun f -> "core/" + f + ".zs") coreFiles; (if hosted then List.map (fun f -> "std/" + f + ".zs") stdFiles else []) ]
  let loaded = Buffer.empty
  let failure = ref None
  for f in files do
    if Option.isNone failure.Value then
      match load (Buffer.length loaded) (Path.combine root f) None with
      | Ok m -> Buffer.push { m with modName = headerOf m.decls } loaded
      | Error e -> failure.Value <- Some e
  match failure.Value with
  | Some e -> Error e
  | None -> Ok(Array.toList (Buffer.toArray loaded))

/// The main file and the modules it uses, dependencies first (files from index `first` on); an
/// import cycle is an error at the file that closes it (no place: the file's), with its source.
let program (first: int) (mainPath: string) : result<list<Loaded>, Diagnostic * option<Source.Source>> =
  let order = Buffer.empty
  let count = ref first
  // a module: whether it's fully loaded
  let finished = ref Map.empty
  let failure = ref None
  let mainFull = Path.getFullPath mainPath
  let root = Path.getDirectoryName mainFull
  let display (p: string) = Path.getRelativePath (Environment.currentDirectory ()) p
  // the file of the module A.B under the root, not the main file
  let fileOf (m: string) : option<string> =
    let parts = String.split "." m
    let dir = List.fold Path.combine root (List.take (List.length parts - 1) parts)
    let last = List.last parts
    let b = String.byte last 0
    let lowered = (if isUpper b then String.ofByte (b + u8 32) else String.ofByte b) + String.sub last 1 (String.length last - 1)
    List.tryFind (fun (f: string) -> f <> mainFull && File.exists f) [ Path.combine dir (last + ".zs"); Path.combine dir (lowered + ".zs") ]
  // the modules a file's uses name: for A.B, the module A.B wherever it resolves (or A, when
  // nothing does): in the modules enclosing the file's, the modules it opens, then globally
  let usedBy (modName: option<string>) (opens: list<string>) (uses: list<string>) : list<string * string> =
    let enclosing =
      match modName with
      | Some n -> List.rev (Infer.Cx.withEnclosing n)
      | None -> []
    let near (p: string) = List.append (List.map (fun e -> e + "." + p) enclosing) [ p ]
    let opened = List.collect near opens
    let rec named (m: string) : list<string * string> =
      let candidates = List.append (near m) (List.map (fun o -> o + "." + m) opened)
      match List.choose (fun c -> Option.map (fun f -> (c, f)) (fileOf c)) candidates with
      | [] when String.contains "." m -> named (Option.get (Infer.Cx.beforeLastDot m))
      | found -> found
    List.collect named uses
  let rec visit (path: string) (modName0: option<string>) (stack: list<string>) =
    if Option.isNone failure.Value then
      count.Value <- count.Value + 1
      match load (count.Value - 1) (display path) modName0 with
      | Error e -> failure.Value <- Some(error { file = -1; offset = -1; length = -1 } e, None)
      | Ok m ->
        // a file's header names it when it's the main file's or no other name is given
        let modName =
          match (headerOf m.decls, modName0) with
          | (Some h, Some _) -> Some h
          | _ -> modName0
        let opens = List.choose (fun (d: Ast.Decl) -> match d.d with | Ast.Open o -> Some o | _ -> None) m.decls
        let all = usedBy modName opens (usesOf m.source m.tree m.decls)
        let fresh = List.filter (fun (n, f) -> Some n <> modName && f <> path && f <> mainFull) all
        let deps = List.fold (fun (acc: list<string * string>) (n, f) -> if List.exists (fun (k, _) -> k = n) acc then acc else List.append acc [ (n, f) ]) [] fresh
        for (n, f) in deps do
          if Option.isNone failure.Value then
            match Map.tryFind n finished.Value with
            | Some true -> ()
            | Some false ->
              let cycle = String.join " -> " (List.rev (n :: stack))
              failure.Value <- Some(error { file = m.source.file; offset = -1; length = -1 } $"import cycle: {cycle}", Some m.source)
            | None ->
              finished.Value <- Map.add n false finished.Value
              visit f (Some n) (n :: stack)
              finished.Value <- Map.add n true finished.Value
        let used = List.map (fun (_, f) -> display f) deps
        Buffer.push { m with modName = modName; uses = used } order
  visit mainFull None [ Path.getFileNameWithoutExtension mainPath ]
  match failure.Value with
  | Some f -> Error f
  | None ->
    let loaded = Array.toList (Buffer.toArray order)
    // the main file keeps the path the user gave
    let last = List.last loaded
    Ok(List.append (List.take (List.length loaded - 1) loaded) [ { last with path = mainPath; source = { last.source with path = mainPath } } ])
