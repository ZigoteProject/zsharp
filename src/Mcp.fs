/// MCP server (Model Context Protocol over stdio): compiler-backed tools for AI agents, so
/// they can check, query types, look up the library, build and run instead of guessing.
module Mcp

open System
open System.Diagnostics
open System.IO
open System.Text.Json.Nodes
open Syntax
open Core
open Rpc

let private send (msg: JsonNode) =
    Console.Out.WriteLine(msg.ToJsonString())
    Console.Out.Flush()

let private respond (id: JsonNode) (result: JsonNode) =
    send (obj [ "jsonrpc", str "2.0"; "id", id.DeepClone(); "result", result ])

let private failWith (id: JsonNode) (code: int) (msg: string) =
    send (obj [ "jsonrpc", str "2.0"; "id", id.DeepClone(); "error", obj [ "code", num code; "message", str msg ] ])

let private text (s: string) (isError: bool) : JsonNode =
    obj [ "content", arr [ obj [ "type", str "text"; "text", str s ] ]; "isError", bool isError ]

let private limit (n: int) (s: string) =
    if s.Length <= n then s else s.Substring(0, n) + sprintf "\n… (%d more characters)" (s.Length - n)

exception private ToolError of string

/// Tools only touch files inside the directory the server was started in.
let private projectFile (p: string) =
    let full = Path.GetFullPath p
    let root = Path.GetFullPath Environment.CurrentDirectory

    if not (full.StartsWith(root + string Path.DirectorySeparatorChar)) then
        raise (ToolError(sprintf "%s is outside the project (%s)" p root))

    if not (File.Exists full) then
        raise (ToolError(sprintf "%s does not exist" p))

    Path.GetRelativePath(root, full)

let private formatErrors (errors: Diagnostic list) =
    errors
    |> List.map (fun e ->
        if e.col > 0 then sprintf "%s:%d:%d: %s" e.file e.line e.col e.msg
        elif e.line > 0 then sprintf "%s:%d: %s" e.file e.line e.msg
        else sprintf "%s: %s" e.file e.msg)
    |> String.concat "\n"

let private check (file: string) =
    try
        Driver.check file false true
    with CompileErrorAt(f, l, c, m) ->
        raise (ToolError(formatErrors [ { file = f; line = l; col = c; msg = m } ]))

let private signature (h: Hover) =
    let needs = if h.constraints = "" then "" else " when " + h.constraints
    sprintf "%s : %s%s" (shortName h.name) (show h.hty) needs

let private schema (props: (string * string * string) list) (required: string list) : JsonNode =
    obj
        [ "type", str "object"
          "properties", obj [ for name, ty, desc in props -> name, obj [ "type", str ty; "description", str desc ] ]
          "required", arr (required |> List.map str) ]

let private fileArg = "file", "string", "Path of a .zs file, relative to the project directory"

let private tools: (string * string * JsonNode) list =
    [ "check", "Type-check a Z# file and the modules it uses. Returns every error as file:line:column: message.", schema [ fileArg ] [ "file" ]
      "type_at",
      "The inferred type of the name at a position in a Z# file (1-based line and column), with trait constraints for generic functions.",
      schema [ fileArg; "line", "integer", "1-based line"; "column", "integer", "1-based column" ] [ "file"; "line"; "column" ]
      "docs",
      "Search the Z# library (prelude, Core and Std): functions whose name contains the query, with their types and docs.",
      schema [ "query", "string", "Part of a name, such as List.map, sort or String" ] [ "query" ]
      "build", "Compile a Z# program to a native executable next to it.", schema [ fileArg ] [ "file" ]
      "run",
      "Compile and run a Z# program (10 second limit, empty stdin). Returns its output, exit code and the leak check.",
      schema [ fileArg ] [ "file" ]
      "emit_llvm", "The LLVM IR a Z# program compiles to.", schema [ fileArg ] [ "file" ]
      "format", "A Z# file in the canonical layout (zs fmt). Returns the formatted text; the file is not changed.", schema [ fileArg ] [ "file" ] ]

let private call (name: string) (args: JsonNode) : string =
    let arg (k: string) =
        match args[k] with
        | null -> raise (ToolError(sprintf "missing argument '%s'" k))
        | v -> v

    match name with
    | "check" ->
        let prog = check (projectFile (getStr (arg "file")))
        if prog.errors.IsEmpty then "no errors" else formatErrors prog.errors
    | "type_at" ->
        let file = projectFile (getStr (arg "file"))
        let line, col = getInt (arg "line"), getInt (arg "column")
        let prog = check file

        prog.hovers
        |> List.filter (fun h ->
            Path.GetFullPath h.hfile = Path.GetFullPath file
            && h.hline = line
            && col >= h.hcol
            && col < h.hcol + h.hlen)
        |> List.sortBy (fun h -> h.hlen)
        |> List.tryHead
        |> Option.map signature
        |> Option.defaultValue (sprintf "no name at %s:%d:%d" file line col)
    | "docs" ->
        let query = getStr (arg "query")
        let dir = Path.Combine(Path.GetTempPath(), "zs-docs")
        Directory.CreateDirectory dir |> ignore
        let probe = Path.Combine(dir, "probe.zs")
        File.WriteAllText(probe, "let main () = 0\n")
        let prog = Driver.check probe true true

        let found =
            prog.hovers
            |> List.filter (fun h -> h.decl && Driver.isLibrary h.hfile && (shortName h.name).Contains(query, StringComparison.OrdinalIgnoreCase))
            |> List.distinctBy (fun h -> h.name)
            |> List.map (fun h ->
                match Driver.docAbove h.hfile h.hline with
                | Some d -> signature h + "\n  " + d.Replace("\n", "\n  ")
                | None -> signature h)

        if found.IsEmpty then sprintf "nothing in the library matches '%s'" query else String.concat "\n" found
    | "build" ->
        let file = projectFile (getStr (arg "file"))
        let out = Path.ChangeExtension(file, null)

        match Driver.build file out false false false with
        | Ok() -> sprintf "built %s" out
        | Error errors -> raise (ToolError(formatErrors errors))
    | "run" ->
        let file = projectFile (getStr (arg "file"))
        let exe = Path.Combine(Path.GetTempPath(), "zs-" + Guid.NewGuid().ToString("N"))

        match Driver.build file exe false false false with
        | Error errors -> raise (ToolError(formatErrors errors))
        | Ok() ->
            let psi = ProcessStartInfo exe
            psi.RedirectStandardOutput <- true
            psi.RedirectStandardError <- true
            psi.RedirectStandardInput <- true
            psi.Environment["ZS_LEAKCHECK"] <- "1"
            use p = Process.Start psi
            p.StandardInput.Close()
            let out = p.StandardOutput.ReadToEndAsync()
            let err = p.StandardError.ReadToEndAsync()
            let finished = p.WaitForExit 10000

            if not finished then
                p.Kill true

            File.Delete exe
            let status = if finished then sprintf "exit code %d" p.ExitCode else "killed after 10 seconds"
            sprintf "%s\n--- stdout\n%s\n--- stderr\n%s" status (limit 20000 out.Result) (limit 20000 err.Result)
    | "emit_llvm" ->
        let file = projectFile (getStr (arg "file"))

        match Driver.compileProgram file false with
        | Ok(ir, _) -> limit 100000 ir
        | Error errors -> raise (ToolError(formatErrors errors))
    | "format" ->
        let file = projectFile (getStr (arg "file"))

        try
            match Format.format (File.ReadAllText file) with
            | Ok formatted -> formatted
            | Error msg -> raise (ToolError msg)
        with
        | CompileError(l, m)
        | CompileErrorPos(l, _, m) -> raise (ToolError(sprintf "%s:%d: %s" file l m))
    | _ -> raise (ToolError(sprintf "unknown tool '%s'" name))

/// The design documents, when the server runs in the Z# repository.
let private documents () =
    [ "DESIGN.md", "Z# design"; "ROADMAP.md", "Z# roadmap" ]
    |> List.map (fun (f, title) -> Path.GetFullPath f, title)
    |> List.filter (fst >> File.Exists)

let serve () : int =
    let mutable running = true
    let reader = new StreamReader(Rpc.input)

    while running do
        match reader.ReadLine() with
        | null -> running <- false
        | line when line.Trim() = "" -> ()
        | line ->
            let msg = JsonNode.Parse line
            let id = msg["id"]
            let ps = msg["params"]

            try
                match (if isNull msg["method"] then "" else getStr msg["method"]) with
                | "initialize" ->
                    let version =
                        match ps with
                        | null -> "2025-06-18"
                        | p when isNull p["protocolVersion"] -> "2025-06-18"
                        | p -> getStr p["protocolVersion"]

                    respond
                        id
                        (obj
                            [ "protocolVersion", str version
                              "capabilities", obj [ "tools", obj [ "listChanged", bool false ]; "resources", obj [] ]
                              "serverInfo", obj [ "name", str "zs"; "version", str "0.4" ]
                              "instructions",
                              str "Z# compiler tools. Use check before build or run; use type_at and docs instead of guessing types and library names." ])
                | "ping" -> respond id (obj [])
                | "tools/list" ->
                    respond
                        id
                        (obj
                            [ "tools",
                              arr [ for name, desc, input in tools -> obj [ "name", str name; "description", str desc; "inputSchema", input ] ] ])
                | "tools/call" ->
                    let name = getStr ps["name"]
                    let args = if isNull ps["arguments"] then (obj []) else ps["arguments"]

                    let result =
                        try
                            text (call name args) false
                        with
                        | ToolError m -> text m true
                        | ex -> text ("internal error: " + ex.Message) true

                    respond id result
                | "resources/list" ->
                    respond
                        id
                        (obj
                            [ "resources",
                              arr
                                  [ for path, title in documents () ->
                                        obj
                                            [ "uri", str (Uri(path).AbsoluteUri)
                                              "name", str (Path.GetFileName path)
                                              "title", str title
                                              "mimeType", str "text/markdown" ] ] ])
                | "resources/read" ->
                    let uri = getStr ps["uri"]

                    match documents () |> List.tryFind (fun (p, _) -> Uri(p).AbsoluteUri = uri) with
                    | Some(path, _) ->
                        respond
                            id
                            (obj [ "contents", arr [ obj [ "uri", str uri; "mimeType", str "text/markdown"; "text", str (File.ReadAllText path) ] ] ])
                    | None -> failWith id -32002 (sprintf "unknown resource %s" uri)
                | _ when not (isNull id) -> failWith id -32601 "method not found"
                | _ -> () // notifications
            with ex ->
                if not (isNull id) then
                    failWith id -32603 ex.Message

    0
