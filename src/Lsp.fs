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
        |> List.filter (fun d -> Path.GetFullPath d.file = path)
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
        |> List.filter (fun d -> Path.GetFullPath d.file <> path)
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
        |> List.filter (fun h -> Path.GetFullPath h.hfile = path && not (h.name.StartsWith "$"))
    | _ -> []

/// Documented items per file, recomputed when the file's text changes.
let private docCache = Dictionary<string, string * Driver.DocItem list>()

let private docIndex (file: string) =
    let text =
        try
            Driver.readSource file
        with _ ->
            ""

    match docCache.TryGetValue file with
    | true, (t, items) when t = text -> items
    | _ ->
        let items = Driver.docItems file
        docCache[file] <- (text, items)
        items

/// The doc comment of what a hover refers to (found at its definition).
/// An imported C name's declaration and header comment, as Markdown.
let private cDoc (name: string) =
    match Syntax.cInfo.TryGetValue name with
    | true, i -> Some(sprintf "```c\n%s\n```%s" i.csig (if i.cdoc = "" then "" else "\n\n" + i.cdoc))
    | _ -> None

let private zsDocOf (path: string) (h: Hover) =
    let def =
        if h.isDef || h.key = "" then
            Some h
        else
            match results.TryGetValue path with
            | true, prog -> prog.hovers |> List.tryFind (fun d -> d.isDef && d.key = h.key)
            | _ -> None

    match def |> Option.bind (fun d -> Driver.docAbove d.hfile d.hline) with
    | Some doc -> Some doc
    | None ->
        match [ h.key; h.name ] |> List.tryPick (fun k -> match Driver.builtinDocs.TryGetValue k with
                                                          | true, doc -> Some doc
                                                          | _ -> None) with
        | Some doc -> Some doc
        | None ->
            // constructors, trait methods and members: by name in the files of this program
            let files =
                match results.TryGetValue path with
                | true, prog -> prog.hovers |> List.map (fun x -> x.hfile) |> List.distinct
                | _ -> []

            let keys =
                [ h.key; h.name ]
                @ (match h.key.LastIndexOf '.' with
                   | i when i > 0 -> [ h.key.Substring(0, i) + "#" + h.key.Substring(i + 1) ] // T.M (static) = T#M
                   | _ -> [])

            files
            |> List.tryPick (fun f ->
                docIndex f
                |> List.tryFind (fun d ->
                    d.doc.IsSome
                    && (List.contains d.key keys || (d.kind = "method" && d.key.EndsWith("." + h.name)))) // `compare` = Ord.compare
                |> Option.bind (fun d -> d.doc))

/// The documentation of what a hover refers to: a C declaration, or Z# doc comments.
let private docOf (path: string) (h: Hover) =
    match cDoc h.name with
    | Some d -> Some d
    | None -> zsDocOf path h

let private hover (path: string) (line: int) (ch: int) : JsonNode =
    let hits =
        hoversAt path
        |> List.filter (fun h -> h.hline = line + 1 && ch >= h.hcol - 1 && ch < h.hcol - 1 + h.hlen)
        |> List.sortBy (fun h -> h.hlen)

    match hits with
    | h :: _ ->
        let needs = if h.constraints = "" then "" else " when " + h.constraints
        let doc = docOf path h |> Option.map (fun d -> "\n\n" + d) |> Option.defaultValue ""

        obj
            [ "contents", obj [ "kind", str "markdown"; "value", str (sprintf "```zsharp\n%s : %s%s\n```%s" h.name (show h.hty) needs doc) ]
              "range", range (h.hline - 1, h.hcol - 1) (h.hline - 1, h.hcol - 1 + h.hlen) ]
    | [] -> null

/// The file a hover's position is in.
let private hoverPath (h: Hover) = Path.GetFullPath h.hfile

let private location (h: Hover) : JsonNode =
    obj [ "uri", str (toUri (hoverPath h)); "range", range (h.hline - 1, h.hcol - 1) (h.hline - 1, h.hcol - 1 + h.hlen) ]

/// The name under the cursor, and everything else that refers to the same thing.
let private related (path: string) (line: int) (ch: int) =
    let here =
        hoversAt path
        |> List.filter (fun h -> h.key <> "" && h.hline = line + 1 && ch >= h.hcol - 1 && ch < h.hcol - 1 + h.hlen)
        |> List.sortBy (fun h -> h.hlen)
        |> List.tryHead

    match here, results.TryGetValue path with
    | Some h, (true, prog) -> Some h, prog.hovers |> List.filter (fun o -> o.key = h.key)
    | _ -> None, []

let private definition (path: string) (line: int) (ch: int) : JsonNode =
    let cName =
        hoversAt path
        |> List.filter (fun h -> h.hline = line + 1 && ch >= h.hcol - 1 && ch < h.hcol - 1 + h.hlen)
        |> List.tryPick (fun h ->
            match Syntax.cInfo.TryGetValue h.name with
            | true, i when i.cline > 0 && File.Exists i.cfile -> Some i
            | _ -> None)

    match cName, related path line ch with
    | Some i, _ -> obj [ "uri", str (toUri i.cfile); "range", range (i.cline - 1, 0) (i.cline - 1, 0) ] // in the header
    | None, (Some _, all) ->
        match all |> List.tryFind (fun h -> h.isDef) with
        | Some d -> location d
        | None -> null
    | _ -> null

let private references (path: string) (line: int) (ch: int) (withDecl: bool) : JsonNode =
    let _, all = related path line ch

    all
    |> List.filter (fun h -> withDecl || not h.isDef)
    |> List.distinctBy (fun h -> h.hfile, h.hline, h.hcol)
    |> List.map location
    |> arr

let private keywords =
    [ "let"; "rec"; "mutable"; "if"; "then"; "else"; "match"; "with"; "when"; "fun"; "for"; "in"; "do"; "while"
      "type"; "of"; "member"; "static"; "trait"; "impl"; "derive"; "extern"; "open"; "module"; "private"; "not"; "true"; "false" ]

/// After `x.`: the fields and members of x's type; otherwise names in scope (approximately:
/// library and project functions, types, constructors, this file's own names) and keywords.
let private completion (path: string) (line: int) (ch: int) : JsonNode =
    let text = lineText path (line + 1)
    let upto = text.Substring(0, min ch text.Length)
    let mutable i = upto.Length - 1

    while i >= 0 && (Char.IsLetterOrDigit upto[i] || upto[i] = '_') do
        i <- i - 1

    let item (label: string) (kind: int) (detail: string) =
        obj [ "label", str label; "kind", num kind; "detail", str detail ]

    match results.TryGetValue path with
    | true, prog when i >= 0 && upto[i] = '.' ->
        // the receiver ends right before the dot
        let receiver =
            hoversAt path
            |> List.filter (fun h -> h.hline = line + 1 && h.hcol - 1 + h.hlen = i)
            |> List.sortBy (fun h -> h.hlen)
            |> List.tryHead

        match receiver |> Option.map (fun h -> prune h.hty) with
        | Some(TCon(n, args)) ->
            let fields =
                match prog.types.TryGetValue n with
                | true, { def = RecordDef fs } -> fs |> List.map (fun (f, t) -> item f 5 (show (substGen args t)))
                | _ -> []

            let members =
                match prog.memberNames.TryGetValue n with
                | true, ms -> ms |> List.map (fun m -> item m 2 n)
                | _ -> []

            arr (fields @ members)
        | _ -> arr []
    | true, prog ->
        let globals =
            prog.hovers
            |> List.filter (fun h -> h.decl && not (h.name.Contains "$"))
            |> List.distinctBy (fun h -> h.name)
            |> List.map (fun h ->
                // as programs write it: List.map, not Collections.List.map
                let label = shortName h.name

                match Driver.docAbove h.hfile h.hline with
                | Some d -> obj [ "label", str label; "kind", num 3; "detail", str (show h.hty); "documentation", obj [ "kind", str "markdown"; "value", str d ] ]
                | None -> item label 3 (show h.hty))

        let cNames =
            [ for KeyValue(n, i) in Syntax.cInfo ->
                  let kind = if i.csig.StartsWith "typedef struct" then 22 elif i.csig.Contains "(" then 3 else 21
                  obj [ "label", str n; "kind", num kind; "detail", str i.csig; "documentation", obj [ "kind", str "markdown"; "value", str i.cdoc ] ] ]

        let locals =
            hoversAt path
            |> List.filter (fun h -> h.isDef && not h.decl)
            |> List.distinctBy (fun h -> h.name)
            |> List.map (fun h -> item h.name 6 (show h.hty))

        let typesAndCases =
            [ for KeyValue(n, info) in prog.types do
                  if not (n.Contains "$") then
                      yield item (shortName n) (match info.def with
                                                | RecordDef _ -> 22
                                                | UnionDef _ -> 13) ""

                      match info.def with
                      | UnionDef cs ->
                          for c, _ in cs do
                              yield item (shortName c) 20 (shortName n)
                      | RecordDef _ -> () ]

        arr (locals @ globals @ cNames @ typesAndCases @ (keywords |> List.map (fun k -> item k 14 "keyword")))
    | _ -> arr (keywords |> List.map (fun k -> item k 14 "keyword"))

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
                                    "inlayHintProvider", bool true
                                    "documentFormattingProvider", bool true
                                    "definitionProvider", bool true
                                    "referencesProvider", bool true
                                    "completionProvider", obj [ "triggerCharacters", arr [ str "." ] ] ]
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
                | "textDocument/definition" ->
                    let p = ps["position"]
                    respond id (definition (docPath ()) (getInt (p["line"])) (getInt (p["character"])))
                | "textDocument/references" ->
                    let p = ps["position"]

                    let withDecl =
                        match ps["context"] with
                        | null -> true
                        | c when isNull c["includeDeclaration"] -> true
                        | c -> c["includeDeclaration"].GetValue<bool>()

                    respond id (references (docPath ()) (getInt (p["line"])) (getInt (p["character"])) withDecl)
                | "textDocument/completion" ->
                    let p = ps["position"]
                    respond id (completion (docPath ()) (getInt (p["line"])) (getInt (p["character"])))
                | "textDocument/formatting" ->
                    // one edit replacing the whole document; none if it doesn't parse
                    let path = docPath ()
                    let src = Driver.readSource path

                    match (try Format.format src with _ -> Error "") with
                    | Ok formatted when formatted <> src ->
                        let lines = src.Split '\n'
                        respond id (arr [ obj [ "range", range (0, 0) (lines.Length, 0); "newText", str formatted ] ])
                    | _ -> respond id (arr [])
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
