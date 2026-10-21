/// Language server (LSP 3.17 over stdio): diagnostics as you type, hover types, inlay type
/// hints and document symbols. It runs the compiler's own front end on the editor's buffers.
module Lsp

open System
open System.Collections.Generic
open System.IO
open System.Text
open System.Text.Json.Nodes
open Syntax
open Core
open Rpc

let private input = Console.OpenStandardInput()
let private output = Console.OpenStandardOutput()

// ------------------------------------------------------------ JSON-RPC framing

/// One message: `Content-Length: n` headers, a blank line, n bytes of JSON. None at end of input.
let private readMessage () : JsonNode option =
    let mutable length = -1
    let mutable inHeaders = true
    let mutable eof = false
    let line = StringBuilder()

    while inHeaders && not eof do
        let b = input.ReadByte()

        if b < 0 then
            eof <- true
        elif b = int '\n' then
            let l = line.ToString().TrimEnd '\r'
            line.Clear() |> ignore

            if l = "" then
                inHeaders <- false
            elif l.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase) then
                length <- int (l.Substring(15).Trim())
        else
            line.Append(char b) |> ignore

    if eof || length < 0 then
        None
    else
        let buf = Array.zeroCreate<byte> length
        let mutable got = 0

        while got < length && not eof do
            let n = input.Read(buf, got, length - got)
            if n <= 0 then eof <- true else got <- got + n

        if eof then None else Some(JsonNode.Parse(Encoding.UTF8.GetString buf))

let private send (msg: JsonNode) =
    let body = Encoding.UTF8.GetBytes(msg.ToJsonString())
    let header = Encoding.ASCII.GetBytes(sprintf "Content-Length: %d\r\n\r\n" body.Length)
    output.Write(header, 0, header.Length)
    output.Write(body, 0, body.Length)
    output.Flush()

let private respond (id: JsonNode) (result: JsonNode) =
    send (obj [ "jsonrpc", str "2.0"; "id", id.DeepClone(); "result", result ])

let private notify (meth: string) (ps: JsonNode) =
    send (obj [ "jsonrpc", str "2.0"; "method", str meth; "params", ps ])

let private pos (line: int) (ch: int) = obj [ "line", num line; "character", num ch ]
let private range (l1, c1) (l2, c2) = obj [ "start", pos l1 c1; "end", pos l2 c2 ]

// ------------------------------------------------------------ documents and analysis

let private toPath (uri: string) = Uri(uri).LocalPath
let private toUri (path: string) = Uri(Path.GetFullPath path).AbsoluteUri

/// The last analysis of each open document.
let private results = Dictionary<string, Program>()
let private problems = Dictionary<string, Diagnostic list>()

let private lineText (path: string) (line: int) =
    let text = Driver.readSource path
    let lines = text.Replace("\r\n", "\n").Split '\n'
    if line >= 1 && line <= lines.Length then lines[line - 1] else ""

/// Re-checks a document (with its modules) and publishes its diagnostics.
// ponytail: re-checks on every change; debounce if large files make typing lag
let private analyze (path: string) =
    let diags =
        try
            let prog = Driver.check path false true
            results[path] <- prog
            prog.errors
        with
        | CompileErrorAt(file, line, col, msg) ->
            [ { file = file
                line = line
                col = col
                msg = msg } ]
        | ex ->
            [ { file = path
                line = 1
                col = 0
                msg = "internal compiler error: " + ex.Message } ]

    problems[path] <- diags

    let mine =
        diags
        |> List.filter (fun d -> d.file <> "prelude.zs" && Path.GetFullPath d.file = path)
        |> List.map (fun d ->
            let line = max 1 d.line
            let text = lineText path line
            let indent = text.Length - text.TrimStart().Length
            let start = if d.col > 0 then d.col - 1 else indent

            obj
                [ "range", range (line - 1, start) (line - 1, max (start + 1) text.Length)
                  "severity", num 1
                  "source", str "zs"
                  "message", str d.msg ])

    // an error in an imported module shows on the first line of this file
    let elsewhere =
        diags
        |> List.filter (fun d -> d.file <> "prelude.zs" && Path.GetFullPath d.file <> path)
        |> List.map (fun d ->
            obj
                [ "range", range (0, 0) (0, 1)
                  "severity", num 1
                  "source", str "zs"
                  "message", str (sprintf "%s:%d: %s" d.file d.line d.msg) ])

    notify "textDocument/publishDiagnostics" (obj [ "uri", str (toUri path); "diagnostics", arr (mine @ elsewhere) ])

let private hoversAt (path: string) =
    match results.TryGetValue path with
    | true, prog ->
        prog.hovers
        |> List.filter (fun h -> h.hfile <> "prelude.zs" && Path.GetFullPath h.hfile = path && not (h.name.StartsWith "$"))
    | _ -> []

let private hover (path: string) (line: int) (ch: int) : JsonNode =
    let hits =
        hoversAt path
        |> List.filter (fun h -> h.hline = line + 1 && ch >= h.hcol - 1 && ch < h.hcol - 1 + h.hlen)
        |> List.sortBy (fun h -> h.hlen)

    match hits with
    | h :: _ ->
        let needs = if h.constraints = "" then "" else " when " + h.constraints

        obj
            [ "contents", obj [ "kind", str "markdown"; "value", str (sprintf "```zsharp\n%s : %s%s\n```" h.name (show h.hty) needs) ]
              "range", range (h.hline - 1, h.hcol - 1) (h.hline - 1, h.hcol - 1 + h.hlen) ]
    | [] -> null

let private inlayHints (path: string) (fromLine: int) (toLine: int) : JsonNode =
    hoversAt path
    |> List.filter (fun h -> h.inlay && h.hline - 1 >= fromLine && h.hline - 1 <= toLine && not (h.name.StartsWith "_"))
    |> List.distinctBy (fun h -> h.hline, h.hcol)
    |> List.map (fun h ->
        obj
            [ "position", pos (h.hline - 1) (h.hcol - 1 + h.name.Length)
              "label", str (": " + show h.hty)
              "kind", num 1 ])
    |> arr

/// Top-level declarations, with union cases and members as children.
let private symbols (path: string) : JsonNode =
    let decls =
        try
            snd (Driver.parseFile path)
        with _ ->
            []

    let sym (name: string) (kind: int) (line: int) (children: JsonNode list) =
        let text = lineText path line
        let r = range (line - 1, 0) (line - 1, max 1 text.Length)

        obj
            [ "name", str name
              "kind", num kind
              "range", r
              "selectionRange", r.DeepClone()
              "children", arr children ]

    // LSP SymbolKind: 5 class, 10 enum, 11 interface, 12 function, 22 enum member, 23 struct, 6 method
    let rec ofDecl ln d : JsonNode list =
        match d with
        | Fun(name, _, _, _, _) -> [ sym name 12 ln [] ]
        | Extern(name, _, _, _) -> [ sym name 12 ln [] ]
        | TypeDecl(name, _, body, ms) ->
            let memberSyms = ms |> List.map (fun m -> sym m.name 6 m.mline [])

            match body with
            | UnionTy cases when not cases.IsEmpty -> [ sym name 10 ln ((cases |> List.map (fun (c, _) -> sym c 22 ln [])) @ memberSyms) ]
            | _ -> [ sym name 23 ln memberSyms ]
        | TypeExt(name, _, ms) -> [ sym (name + " (extension)") 5 ln (ms |> List.map (fun m -> sym m.name 6 m.mline [])) ]
        | Trait(name, _, _) -> [ sym name 11 ln [] ]
        | Impl(tr, STName(t, _), _) -> [ sym (sprintf "impl %s<%s>" tr t) 5 ln [] ]
        | Derive(name, _) -> [ sym ("derive " + name) 12 ln [] ]
        | Attrs(_, d)
        | Private d -> ofDecl ln d
        | _ -> []

    decls |> List.collect (fun (ln, d) -> ofDecl ln d) |> arr

// ------------------------------------------------------------ the loop

let serve () : int =
    let mutable running = true
    let mutable exitCode = 0

    while running do
        match readMessage () with
        | None -> running <- false
        | Some msg ->
            let meth = msg["method"]
            let id = msg["id"]
            let ps = msg["params"]

            let docPath () = toPath (getStr (ps["textDocument"]["uri"]))

            try
                match (if isNull meth then "" else getStr meth) with
                | "initialize" ->
                    respond
                        id
                        (obj
                            [ "capabilities",
                              obj
                                  [ "textDocumentSync", num 1 // full text on every change
                                    "hoverProvider", bool true
                                    "documentSymbolProvider", bool true
                                    "inlayHintProvider", bool true ]
                              "serverInfo", obj [ "name", str "zs"; "version", str "0.4" ] ])
                | "textDocument/didOpen" ->
                    let path = docPath ()
                    Driver.overlay[path] <- getStr (ps["textDocument"]["text"])
                    analyze path
                | "textDocument/didChange" ->
                    let path = docPath ()
                    let changes = ps["contentChanges"].AsArray()
                    Driver.overlay[path] <- getStr (changes[changes.Count - 1]["text"])
                    analyze path
                | "textDocument/didSave" -> analyze (docPath ())
                | "textDocument/didClose" ->
                    let path = docPath ()
                    Driver.overlay.Remove path |> ignore
                    results.Remove path |> ignore
                    notify "textDocument/publishDiagnostics" (obj [ "uri", str (toUri path); "diagnostics", arr [] ])
                | "textDocument/hover" ->
                    let p = ps["position"]
                    respond id (hover (docPath ()) (getInt (p["line"])) (getInt (p["character"])))
                | "textDocument/inlayHint" ->
                    let r = ps["range"]
                    respond id (inlayHints (docPath ()) (getInt (r["start"]["line"])) (getInt (r["end"]["line"])))
                | "textDocument/documentSymbol" -> respond id (symbols (docPath ()))
                | "shutdown" -> respond id null
                | "exit" ->
                    running <- false
                    exitCode <- 0
                | _ when not (isNull id) ->
                    send (obj [ "jsonrpc", str "2.0"; "id", id.DeepClone(); "error", obj [ "code", num -32601; "message", str "method not found" ] ])
                | _ -> () // notifications we don't use
            with ex ->
                if not (isNull id) then
                    send (obj [ "jsonrpc", str "2.0"; "id", id.DeepClone(); "error", obj [ "code", num -32603; "message", str ex.Message ] ])

    exitCode
