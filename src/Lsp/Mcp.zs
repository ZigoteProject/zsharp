/// The MCP server (Model Context Protocol over stdio, a JSON message a line): the compiler's tools
/// for AI agents, so they can check, ask for types, look things up in the library, build and run
/// instead of guessing (the F# compiler's Mcp).
open Diag.Diagnostic

let private num (n: int) = Rpc.num n

let private send (out: IO.Writer) (msg: Json) =
  IO.Writer.writeText out (Rpc.write msg + "\n") |> ignore
  IO.Writer.flush out |> ignore

let private respond (out: IO.Writer) (id: Json) (result: Json) = send out (JObject [ ("jsonrpc", JString "2.0"); ("id", id); ("result", result) ])

let private failWith (out: IO.Writer) (id: Json) (code: int) (msg: string) =
  send out (JObject [ ("jsonrpc", JString "2.0"); ("id", id); ("error", JObject [ ("code", num code); ("message", JString msg) ]) ])

let private textResult (s: string) (isError: bool) : Json =
  JObject [ ("content", JArray [ JObject [ ("type", JString "text"); ("text", JString s) ] ]); ("isError", JBool isError) ]

// at most n characters of s, and how many more there were
let private limit (n: int) (s: string) =
  if String.charCount s <= n then
    s
  else
    let mutable b = 0
    for _ in 1 .. n do
      let (_, next) = String.decodeAt s b
      b <- next
    String.sub s 0 b + $"\n… ({String.charCount s - n} more characters)"

// a tool's file: inside the directory the server was started in, reached through no symbolic
// link (getFullPath works on the text, so a link could lead out of it), and there. Its parts are
// between Path's separators (`\` on Windows), as getFullPath writes them.
let private projectFile (p: string) : result<string, string> =
  let full = Path.getFullPath p
  let root = Path.getFullPath (Environment.currentDirectory ())
  let sep = string Path.separator
  let rec linked (dir: string) (parts: list<string>) =
    match parts with
    | [] -> false
    | x :: rest ->
      let here = Path.combine dir x
      // the runtime's hook: stage 0's library (0.6.1) has no public function for it
      let link = unsafe (Native.isSymlink here)
      link || linked here rest
  if not (String.startsWith (Path.combine root "") full) then
    Error $"{p} is outside the project ({Diag.Render.path root})"
  else if linked root (String.split sep (Path.getRelativePath root full)) then
    Error $"{p} is reached through a symbolic link"
  else if not (File.exists full) then Error $"{p} does not exist"
  else Ok(Path.getRelativePath root full)

// errors as `file:line:col: message`, warnings as `file:line:col: warning: message [kind]`
let private formatErrors (sources: list<Syntax.Source.Source>) (ds: list<Diagnostic>) : string =
  let byIndex = Map.ofList (List.map (fun (s: Syntax.Source.Source) -> (s.file, s)) sources)
  let one (d: Diagnostic) =
    let msg = if d.severity = Err then d.message else $"warning: {d.message} [{d.name}]"
    match Map.tryFind d.at.file byIndex with
    | Some src when d.at.offset >= 0 ->
      let (line, col) = Syntax.Source.position src d.at.offset
      let file = Diag.Render.path src.path
      if d.at.length >= 0 then $"{file}:{line}:{col}: {msg}" else $"{file}:{line}: {msg}"
    | Some src -> $"{Diag.Render.path src.path}: {msg}"
    | None -> msg
  String.join "\n" (List.map one ds)

// a file checked with every module it uses, or its errors as text; trusted: the project's own
// type providers built and run (--trust)
let private check (file: string) (trusted: bool) : result<Build.Check.Checked, string> =
  match Build.Check.programWith Map.empty file false true None "" trusted with
  | Ok c -> Ok c
  | Error(ds, sources) -> Error(formatErrors sources (Array.toList ds))

let private signature (c: Build.Check.Checked) (h: Infer.Cx.Hover) =
  let needs = if h.constraints = "" then "" else " when " + h.constraints
  let words = if h.explain = "" then "" else "\n  " + h.explain
  $"{Types.Ty.shortName h.name} : {Infer.Cx.show c.cx h.ty}{needs}{words}"

let private schema (props: list<string * string * string>) (required: list<string>) : Json =
  let prop (p: string * string * string) =
    let (name, ty, desc) = p
    (name, JObject [ ("type", JString ty); ("description", JString desc) ])
  JObject [ ("type", JString "object"); ("properties", JObject(List.map prop props)); ("required", JArray(List.map JString required)) ]

let private fileArg = ("file", "string", "Path of a .zs file, relative to the project directory")

let private tools : list<string * string * Json> =
  [ ("check", "Type-check a Z# file and the modules it uses. Returns every error as file:line:column: message.", schema [ fileArg ] [ "file" ])
    ("type_at", "The inferred type of the name at a position in a Z# file (1-based line and column), with trait constraints for generic functions.", schema [ fileArg; ("line", "integer", "1-based line"); ("column", "integer", "1-based column") ] [ "file"; "line"; "column" ])
    ("docs", "Search the Z# library (prelude, Core and Std): functions whose name contains the query, with their types and docs.", schema [ ("query", "string", "Part of a name, such as List.map, sort or String") ] [ "query" ])
    ("build", "Compile a Z# program to a native executable next to it.", schema [ fileArg ] [ "file" ])
    ("run", "Compile and run a Z# program (10 second limit, empty stdin). Returns its output, exit code and the leak check.", schema [ fileArg ] [ "file" ])
    ("emit_llvm", "The LLVM IR a Z# program compiles to.", schema [ fileArg ] [ "file" ])
    ("format", "A Z# file in the canonical layout (zs fmt). Returns the formatted text; the file is not changed.", schema [ fileArg ] [ "file" ])
    ("definition", "Where the name at a position in a Z# file is defined (1-based line and column): file:line:column and the defining line, in the program's files or the library's.", schema [ fileArg; ("line", "integer", "1-based line"); ("column", "integer", "1-based column") ] [ "file"; "line"; "column" ])
    ("explain", "The name at a position in a Z# file explained: its type with constraints, its effects in words, where it is defined, and its doc comment.", schema [ fileArg; ("line", "integer", "1-based line"); ("column", "integer", "1-based column") ] [ "file"; "line"; "column" ]) ]

// where a hover's token is: its module, and its 1-based line and column
let private placeOf (c: Build.Check.Checked) (h: Infer.Cx.Hover) : option<Build.Modules.Loaded * int * int> =
  match List.tryFind (fun (m: Build.Modules.Loaded) -> m.source.file = h.file) c.modules with
  | Some m when h.token >= 0 && h.token < Array.length m.tree.tokens ->
    let t = m.tree.tokens.[h.token]
    let (l, k) = Syntax.Source.position m.source t.offset
    Some(m, l, k)
  | _ -> None

// the hover at a position of a file (1-based): the shortest name there
let private hoverAt (c: Build.Check.Checked) (file: string) (line: int) (col: int) : option<Infer.Cx.Hover> =
  let full = Path.getFullPath file
  let at (h: Infer.Cx.Hover) : option<int * Infer.Cx.Hover> =
    match placeOf c h with
    | Some(m, hl, hc) when Path.getFullPath m.source.path = full ->
      let t = m.tree.tokens.[h.token]
      let len = String.charCount (String.sub m.source.text t.offset t.length)
      if hl = line && col >= hc && col < hc + len then Some(len, h) else None
    | _ -> None
  match List.sortBy fst (List.choose at (Array.toList (Buffer.toArray c.cx.hovers))) with
  | (_, h) :: _ -> Some h
  | [] -> None

// the definition of what a hover names: itself when it is one, else the hover defining its key
let private definitionOf (c: Build.Check.Checked) (h: Infer.Cx.Hover) : option<Infer.Cx.Hover> =
  if h.isDef || h.key = "" then Some h else List.tryFind (fun (d: Infer.Cx.Hover) -> d.isDef && d.key = h.key) (Array.toList (Buffer.toArray c.cx.hovers))

// a module's path as shown: the library's under lib/, the program's as given
let private shownPath (m: Build.Modules.Loaded) : string =
  let lib = Build.Modules.libraryDir ()
  let full = Path.getFullPath m.source.path
  let shown =
    if String.startsWith lib full then "lib/" + Path.getRelativePath lib full else m.source.path
  Diag.Render.path shown

// a definition's place and line: "file:line:column\n  the line"
let private definitionText (c: Build.Check.Checked) (h: Infer.Cx.Hover) : option<string> =
  match Option.bind (placeOf c) (definitionOf c h) with
  | Some(m, l, k) ->
    let lines = String.splitLines m.source.text
    let text = if l >= 1 && l <= List.length lines then String.trim (List.item (l - 1) lines) else ""
    Some $"{shownPath m}:{l}:{k}\n  {text}"
  | None -> None

// a build's warnings before what it made
let private withWarnings (b: Build.Make.Built) (text: string) =
  if Array.length b.diagnostics = 0 then text else formatErrors b.sources (Array.toList b.diagnostics) + "\n" + text

// a tool's answer: its text, or Error with the text of what went wrong; trusted: started with
// --trust, so a package's type provider is built and run (by check as by build)
let private call (name: string) (args: Json) (trusted: bool) : result<string, string> =
  let arg (k: string) : result<Json, string> =
    match Rpc.field k args with
    | JNull -> Error $"missing argument '{k}'"
    | v -> Ok v
  let fileOf () : result<string, string> =
    match arg "file" with
    | Ok v -> projectFile (Rpc.text v)
    | Error e -> Error e
  // built for this machine as zs build builds: on Windows for mingw-w64 (clang alone targets MSVC)
  let options (file: string) (out: string) : Build.Options.Options =
    { Build.Options.defaults with main = file; out = out; target = Build.Options.nativeTarget (); trusted = trusted }
  if name = "check" then
    match fileOf () with
    | Error e -> Error e
    | Ok file ->
      match check file trusted with
      | Error e -> Error e
      | Ok c ->
        let ds = Array.toList (Buffer.toArray c.cx.diagnostics)
        Ok(if List.isEmpty ds then "no errors" else formatErrors (List.map (fun (m: Build.Modules.Loaded) -> m.source) c.modules) ds)
  else if name = "type_at" || name = "definition" || name = "explain" then
    match (fileOf (), arg "line", arg "column") with
    | (Ok file, Ok l, Ok k) ->
      let line = Rpc.intOf l
      let col = Rpc.intOf k
      match check file trusted with
      | Error e -> Error e
      | Ok c ->
        match hoverAt c file line col with
        | None -> Ok $"no name at {Diag.Render.path file}:{line}:{col}"
        | Some h when name = "type_at" -> Ok(signature c h)
        | Some h when name = "definition" -> Ok(Option.defaultValue $"{h.name} has no definition in this program's files (a built-in)" (definitionText c h))
        | Some h ->
          // explain: the signature, where it's defined, and its doc comment (at the definition,
          // or a built-in's)
          let defined =
            match definitionText c h with
            | Some d -> "\ndefined at " + d
            | None -> "\nbuilt into the compiler"
          let doc =
            let above =
              match Option.bind (placeOf c) (definitionOf c h) with
              | Some(m, dl, _) -> Build.Doc.docAbove (Array.ofList (String.splitLines m.source.text)) dl
              | None -> None
            match above with
            | Some d -> Some d
            | None -> List.tryPick (fun (key: string) -> Option.map snd (List.tryFind (fun (kd: string * string) -> fst kd = key) Build.Doc.builtinDocs)) [ h.key; h.name ]
          Ok(signature c h + defined + (match doc with | Some d -> "\n\n" + d | None -> ""))
    | (Error e, _, _) -> Error e
    | (_, Error e, _) -> Error e
    | (_, _, Error e) -> Error e
  else if name = "docs" then
    match arg "query" with
    | Error e -> Error e
    | Ok q ->
      let query = String.toLower (Rpc.text q)
      // this user's cache: in a shared /tmp another user could make zs-docs/probe.zs a link to
      // one of this user's files, which the write would overwrite
      let dir = Path.combine (Build.Tools.cacheRoot ()) "docs"
      Build.Tools.makeDirectory dir
      let probe = Path.combine dir "probe.zs"
      File.writeAllText probe "let main () = 0\n" |> ignore
      match Build.Check.program probe true true None "" with
      | Error(ds, sources) -> Error(formatErrors sources (Array.toList ds))
      | Ok c ->
        let library = Map.ofList (List.choose (fun (m: Build.Modules.Loaded) -> if Option.isSome (Build.Modules.libraryRootOf m.source.path) then Some(m.source.file, m) else None) c.modules)
        let wanted (h: Infer.Cx.Hover) = h.decl && Map.containsKey h.file library && String.contains query (String.toLower (Types.Ty.shortName h.name))
        let hovers = List.filter wanted (Array.toList (Buffer.toArray c.cx.hovers))
        let distinct = List.fold (fun (acc: list<Infer.Cx.Hover>) (h: Infer.Cx.Hover) -> if List.exists (fun (o: Infer.Cx.Hover) -> o.name = h.name) acc then acc else List.append acc [ h ]) [] hovers
        let shown (h: Infer.Cx.Hover) =
          let m = Map.find h.file library
          let line = Syntax.Source.lineOf m.source m.tree.tokens.[h.token].offset + 1
          let lines = Array.ofList (String.split "\n" (String.replace m.source.text "\r\n" "\n"))
          match Build.Doc.docAbove lines line with
          | Some d -> signature c h + "\n  " + String.replace d "\n" "\n  "
          | None -> signature c h
        Ok(if List.isEmpty distinct then $"nothing in the library matches '{Rpc.text q}'" else String.join "\n" (List.map shown distinct))
  else if name = "build" then
    match fileOf () with
    | Error e -> Error e
    | Ok file ->
      let out = Path.changeExtension file ""
      let b = Build.Make.make (options file out) false
      if b.made then Ok(withWarnings b $"built {Diag.Render.path out}") else Error(formatErrors b.sources (Array.toList b.diagnostics))
  else if name = "run" then
    match fileOf () with
    | Error e -> Error e
    | Ok file ->
      // a fresh temporary file, never a fixed name: in a shared /tmp another user could swap it
      // between the build and the run
      match File.createTemp "zs-" with
      | Error e -> Error $"no temporary file for the program: {e}"
      | Ok exe ->
        let b = Build.Make.make (options file exe) false
        if not b.made then
          File.delete exe |> ignore
          Error(formatErrors b.sources (Array.toList b.diagnostics))
        else
          let ran = Build.Tools.runBounded [ ("ZS_LEAKCHECK", "1") ] 10000 exe []
          File.delete exe |> ignore
          match ran with
          | Error e -> Error e
          | Ok r ->
            let status = if r.code = 124 then "killed after 10 seconds" else $"exit code {r.code}"
            Ok(withWarnings b $"{status}\n--- stdout\n{limit 20000 r.out}\n--- stderr\n{limit 20000 r.err}")
  else if name = "emit_llvm" then
    match fileOf () with
    | Error e -> Error e
    | Ok file ->
      match Build.Check.programWith Map.empty file true true None "" trusted with
      | Error(ds, sources) -> Error(formatErrors sources (Array.toList ds))
      | Ok c ->
        let sources = List.map (fun (m: Build.Modules.Loaded) -> m.source) c.modules
        let errors = List.filter (fun (d: Diagnostic) -> d.severity = Err) (Array.toList (Buffer.toArray c.cx.diagnostics))
        if not (List.isEmpty errors) then
          Error(formatErrors sources errors)
        else
          match Build.Compile.generate (options file "") (Build.Check.programOf c) false with
          | Ok(_, ir, _, _) -> Ok(limit 100000 ir)
          | Error(Build.Compile.InPass e) -> Error $"{Diag.Render.path file}:{e.line}: {e.message}"
          | Error(Build.Compile.InTool m) -> Error m
  else if name = "format" then
    match fileOf () with
    | Error e -> Error e
    | Ok file ->
      match File.readAllText file with
      | Error e -> Error e
      | Ok text ->
        let (r, diags) = Diag.Report.collect (fun () -> Syntax.Format.format 0 file text)
        match r with
        | Ok formatted -> Ok formatted
        | Error why ->
          let src = Syntax.Source.make 0 file text
          if Array.length diags > 0 then Error(formatErrors [ src ] (Array.toList diags)) else Error why
  else
    Error $"unknown tool '{name}'"

// the design documents, when the server runs in the Z# repository
let private documents () : list<string * string> =
  List.filter (fun (p, _) -> File.exists p) (List.map (fun (f, title) -> (Path.getFullPath f, title)) [ ("DESIGN.md", "Z# design"); ("ROADMAP.md", "Z# roadmap") ])

// one message's answer
let private answer (out: IO.Writer) (trusted: bool) (msg: Json) =
  let id = Rpc.field "id" msg
  let ps = Rpc.field "params" msg
  let meth = Rpc.text (Rpc.field "method" msg)
  if meth = "initialize" then
    let version =
      match Rpc.field "protocolVersion" ps with
      | JString v -> v
      | _ -> "2025-06-18"
    let caps = JObject [ ("tools", JObject [ ("listChanged", JBool false) ]); ("resources", JObject []) ]
    let instructions = "Z# compiler tools. Use check before build or run; use type_at and docs instead of guessing types and library names."
    respond out id (JObject [ ("protocolVersion", JString version); ("capabilities", caps); ("serverInfo", JObject [ ("name", JString "zs"); ("version", JString Build.Tools.version) ]); ("instructions", JString instructions) ])
  else if meth = "ping" then
    respond out id (JObject [])
  else if meth = "tools/list" then
    let tool (t: string * string * Json) =
      let (name, desc, input) = t
      JObject [ ("name", JString name); ("description", JString desc); ("inputSchema", input) ]
    respond out id (JObject [ ("tools", JArray(List.map tool tools)) ])
  else if meth = "tools/call" then
    let args =
      match Rpc.field "arguments" ps with
      | JNull -> JObject []
      | a -> a
    match call (Rpc.text (Rpc.field "name" ps)) args trusted with
    | Ok text -> respond out id (textResult text false)
    | Error text -> respond out id (textResult text true)
  else if meth = "resources/list" then
    let resource (d: string * string) =
      let (path, title) = d
      JObject [ ("uri", JString(Rpc.toUri path)); ("name", JString(Path.getFileName path)); ("title", JString title); ("mimeType", JString "text/markdown") ]
    respond out id (JObject [ ("resources", JArray(List.map resource (documents ()))) ])
  else if meth = "resources/read" then
    let uri = Rpc.text (Rpc.field "uri" ps)
    match List.tryFind (fun (p, _) -> Rpc.toUri p = uri) (documents ()) with
    | Some(path, _) ->
      let text = Result.defaultValue "" (File.readAllText path)
      respond out id (JObject [ ("contents", JArray [ JObject [ ("uri", JString uri); ("mimeType", JString "text/markdown"); ("text", JString text) ] ]) ])
    | None -> failWith out id -32002 $"unknown resource {uri}"
  else if id <> JNull then
    failWith out id -32601 "method not found"

/// Serves on standard input (`input`) and output, a message a line, until the input ends. `first`:
/// a line protocol detection already read; `trusted`: --trust, the project's own type providers
/// built and run.
let serve (input: IO.Reader) (first: option<string>) (trusted: bool) : int =
  let out = Console.openStandardOutput ()
  let one (line: string) =
    if String.trim line <> "" then
      match Json.parse line with
      | Ok msg -> answer out trusted msg
      | Error _ -> failWith out JNull -32700 "parse error"
  match first with
  | Some l -> one l
  | None -> ()
  let mutable running = true
  while running do
    match IO.Reader.readLine input with
    | Ok(Some line) -> one line
    | _ -> running <- false
  0
