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

// a tool's file: inside the directory the server was started in, and there
let private projectFile (p: string) : result<string, string> =
  let full = Path.getFullPath p
  let root = Path.getFullPath (Environment.currentDirectory ())
  if not (String.startsWith (root + "/") full) then Error $"{p} is outside the project ({root})"
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
      if d.at.length >= 0 then $"{src.path}:{line}:{col}: {msg}" else $"{src.path}:{line}: {msg}"
    | Some src -> $"{src.path}: {msg}"
    | None -> msg
  String.join "\n" (List.map one ds)

// a file checked with every module it uses, or its errors as text
let private check (file: string) : result<Build.Check.Checked, string> =
  match Build.Check.program file false true false "" with
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
    ("format", "A Z# file in the canonical layout (zs fmt). Returns the formatted text; the file is not changed.", schema [ fileArg ] [ "file" ]) ]

// a build's warnings before what it made
let private withWarnings (b: Build.Make.Built) (text: string) =
  if Array.length b.diagnostics = 0 then text else formatErrors b.sources (Array.toList b.diagnostics) + "\n" + text

// a tool's answer: its text, or Error with the text of what went wrong
let private call (name: string) (args: Json) : result<string, string> =
  let arg (k: string) : result<Json, string> =
    match Rpc.field k args with
    | JNull -> Error $"missing argument '{k}'"
    | v -> Ok v
  let fileOf () : result<string, string> =
    match arg "file" with
    | Ok v -> projectFile (Rpc.text v)
    | Error e -> Error e
  let options (file: string) (out: string) : Build.Options.Options = { Build.Options.defaults with main = file; out = out }
  if name = "check" then
    match fileOf () with
    | Error e -> Error e
    | Ok file ->
      match check file with
      | Error e -> Error e
      | Ok c ->
        let ds = Array.toList (Buffer.toArray c.cx.diagnostics)
        Ok(if List.isEmpty ds then "no errors" else formatErrors (List.map (fun (m: Build.Modules.Loaded) -> m.source) c.modules) ds)
  else if name = "type_at" then
    match (fileOf (), arg "line", arg "column") with
    | (Ok file, Ok l, Ok k) ->
      let line = Rpc.intOf l
      let col = Rpc.intOf k
      match check file with
      | Error e -> Error e
      | Ok c ->
        let full = Path.getFullPath file
        let at (h: Infer.Cx.Hover) : option<int * Infer.Cx.Hover> =
          match List.tryFind (fun (m: Build.Modules.Loaded) -> m.source.file = h.file) c.modules with
          | Some m when Path.getFullPath m.source.path = full && h.token >= 0 && h.token < Array.length m.tree.tokens ->
            let t = m.tree.tokens.[h.token]
            let (hl, hc) = Syntax.Source.position m.source t.offset
            let len = String.charCount (String.sub m.source.text t.offset t.length)
            if hl = line && col >= hc && col < hc + len then Some(len, h) else None
          | _ -> None
        match List.sortBy fst (List.choose at (Array.toList (Buffer.toArray c.cx.hovers))) with
        | (_, h) :: _ -> Ok(signature c h)
        | [] -> Ok $"no name at {file}:{line}:{col}"
    | (Error e, _, _) -> Error e
    | (_, Error e, _) -> Error e
    | (_, _, Error e) -> Error e
  else if name = "docs" then
    match arg "query" with
    | Error e -> Error e
    | Ok q ->
      let query = String.toLower (Rpc.text q)
      let dir = Path.combine (Directory.temp ()) "zs-docs"
      Build.Tools.makeDirectory dir
      let probe = Path.combine dir "probe.zs"
      File.writeAllText probe "let main () = 0\n" |> ignore
      match Build.Check.program probe true true false "" with
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
      if b.made then Ok(withWarnings b $"built {out}") else Error(formatErrors b.sources (Array.toList b.diagnostics))
  else if name = "run" then
    match fileOf () with
    | Error e -> Error e
    | Ok file ->
      let exe =
        match File.createTemp "zs-" with
        | Ok p -> p
        | Error _ -> Path.combine (Directory.temp ()) "zs-mcp-run"
      let b = Build.Make.make (options file exe) false
      if not b.made then
        File.delete exe |> ignore
        Error(formatErrors b.sources (Array.toList b.diagnostics))
      else
        // ponytail: standard output read to its end before standard error; a program filling the
        // second pipe waits there until the time limit
        let ran = Build.Tools.runSplit "env" [ "ZS_LEAKCHECK=1"; "timeout"; "--kill-after=1"; "10"; exe ]
        File.delete exe |> ignore
        match ran with
        | Error e -> Error e
        | Ok r ->
          let status = if r.code = 124 || r.code = 137 then "killed after 10 seconds" else $"exit code {r.code}"
          Ok(withWarnings b $"{status}\n--- stdout\n{limit 20000 r.out}\n--- stderr\n{limit 20000 r.err}")
  else if name = "emit_llvm" then
    match fileOf () with
    | Error e -> Error e
    | Ok file ->
      match Build.Check.program file true true false "" with
      | Error(ds, sources) -> Error(formatErrors sources (Array.toList ds))
      | Ok c ->
        let sources = List.map (fun (m: Build.Modules.Loaded) -> m.source) c.modules
        let errors = List.filter (fun (d: Diagnostic) -> d.severity = Err) (Array.toList (Buffer.toArray c.cx.diagnostics))
        if not (List.isEmpty errors) then
          Error(formatErrors sources errors)
        else
          match Build.Compile.generate (options file "") (Build.Check.programOf c) false with
          | Ok(_, ir, _, _) -> Ok(limit 100000 ir)
          | Error(Build.Compile.InPass e) -> Error $"{file}:{e.line}: {e.message}"
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
let private answer (out: IO.Writer) (msg: Json) =
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
    respond out id (JObject [ ("protocolVersion", JString version); ("capabilities", caps); ("serverInfo", JObject [ ("name", JString "zs"); ("version", JString "0.4") ]); ("instructions", JString instructions) ])
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
    match call (Rpc.text (Rpc.field "name" ps)) args with
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
/// a line protocol detection already read.
let serve (input: IO.Reader) (first: option<string>) : int =
  let out = Console.openStandardOutput ()
  let one (line: string) =
    if String.trim line <> "" then
      match Json.parse line with
      | Ok msg -> answer out msg
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
