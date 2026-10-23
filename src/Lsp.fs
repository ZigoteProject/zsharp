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

/// The last analysis of each open document, and the files its program is made of.
let private results = Dictionary<string, Program>()
let private problems = Dictionary<string, Diagnostic list>()
let private madeOf = Dictionary<string, HashSet<string>>()

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
            madeOf[path] <- HashSet<string>(prog.hovers |> Seq.map (fun h -> Path.GetFullPath h.hfile))
            prog.diagnostics
        with
        | CompileErrorAt(file, line, col, msg) -> [ errorAt file line col msg ]
        | ex -> [ errorAt path 1 0 ("internal compiler error: " + ex.Message) ]

    problems[path] <- diags

    let mine =
        diags
        |> List.filter (fun d -> Path.GetFullPath d.file = path)
        |> List.map (fun d ->
            let line = max 1 d.line
            let text = lineText path line
            let indent = text.Length - text.TrimStart().Length
            let start = if d.col > 0 then d.col - 1 else indent

            // a warning: severity 2, its kind as the code, its notes as related places (0021)
            let warning =
                if isError d then
                    []
                else
                    [ "code", str d.name
                      "relatedInformation",
                      arr (
                          d.notes
                          |> List.map (fun n ->
                              obj
                                  [ "location", obj [ "uri", str (toUri n.nfile); "range", range (n.nline - 1, max 0 (n.ncol - 1)) (n.nline - 1, max 1 n.ncol) ]
                                    "message", str n.ntext ])
                      ) ]

            obj (
                [ "range", range (line - 1, start) (line - 1, max (start + 1) text.Length)
                  "severity", num (if isError d then 1 else 2)
                  "source", str "zs"
                  "message", str d.msg ]
                @ warning
            ))

    // an error in an imported module shows on the first line of this file (a warning there
    // stays in its own file)
    let elsewhere =
        diags
        |> List.filter (fun d -> Path.GetFullPath d.file <> path && isError d)
        |> List.map (fun d ->
            obj
                [ "range", range (0, 0) (0, 1)
                  "severity", num 1
                  "source", str "zs"
                  "message", str (sprintf "%s:%d: %s" d.file d.line d.msg) ])

    notify "textDocument/publishDiagnostics" (obj [ "uri", str (toUri path); "diagnostics", arr (mine @ elsewhere) ])

/// A document changed: it's analyzed again, and so is every other open one whose program has it
/// (its modules that the change didn't reach come back from the cache, unchecked).
let private changed (path: string) =
    analyze path

    for other in List.ofSeq results.Keys do
        if other <> path && madeOf.ContainsKey other && madeOf[other].Contains path then
            analyze other

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

        // the effects in words, as the definition has them (0025)
        let words =
            let def =
                if h.isDef || h.key = "" then Some h
                else match results.TryGetValue path with
                     | true, prog -> prog.hovers |> List.tryFind (fun d -> d.isDef && d.key = h.key)
                     | _ -> None

            match def with
            | Some d when d.explain <> "" -> "\n  " + d.explain
            | _ -> ""

        obj
            [ "contents", obj [ "kind", str "markdown"; "value", str (sprintf "```zsharp\n%s : %s%s%s\n```%s" h.name (show h.hty) needs words doc) ]
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

// ------------------------------------------------------------ rename, signature help, code actions (0019)

/// A file the editor may change: the program's, not the library's or a dependency's.
let private editable (file: string) =
    let full = Path.GetFullPath file
    not (Driver.isLibrary full) && not (full.Contains "/.zs-cache/")

let private isIdentChar (c: char) = Char.IsLetterOrDigit c || c = '_'

/// Where the name `word` is in the text of a reference's span: the last place it stands alone.
let private wordAt (span: string) (word: string) =
    let rec go (from: int) =
        match span.LastIndexOf(word, from, StringComparison.Ordinal) with
        | -1 -> None
        | k when (k = 0 || not (isIdentChar span[k - 1])) && (k + word.Length = span.Length || not (isIdentChar span[k + word.Length])) -> Some k
        | k when k = 0 -> None
        | k -> go (k - 1)

    if span.Length = 0 || word.Length = 0 then None else go (span.Length - 1)

/// What a rename at a position changes: the name there and every reference to it, in the
/// programs of the open documents (a field's uses too: its key is field:Record.name), or why it
/// can't be renamed. A name's key depends on the program it's checked in (a module's names are
/// qualified, the main file's aren't), so another program's references are those of the
/// definition at the same place.
let private renameTarget (path: string) (line: int) (ch: int) : Result<Hover * Hover list, string> =
    match related path line ch with
    | Some h, all when h.key <> "" ->
        if Syntax.cInfo.ContainsKey h.name then
            Error(sprintf "%s is declared in a C header; rename it there" h.name)
        else
            match all |> List.tryFind (fun o -> o.isDef) with
            | Some d when not (editable d.hfile) -> Error(sprintf "%s is defined in %s, outside the program" (shortName h.name) (Path.GetFileName d.hfile))
            | def ->
                let place (o: Hover) = Path.GetFullPath o.hfile, o.hline, o.hcol

                let elsewhere =
                    match def with
                    | Some d ->
                        [ for prog in results.Values do
                              match prog.hovers |> List.tryFind (fun o -> o.isDef && place o = place d) with
                              | Some other -> yield! prog.hovers |> List.filter (fun o -> o.key = other.key)
                              | None -> () ]
                    | None -> []

                Ok(h, (all @ elsewhere) |> List.filter (fun o -> editable o.hfile) |> List.distinctBy place)
    | Some h, _ -> Error(sprintf "'%s' isn't a name the checker resolved, so it can't be renamed" h.name)
    | None, _ -> Error "there's no name here to rename"

// a reference's place: its file, line (0-based) and the columns of the name in it
let private placeOf (o: Hover) (word: string) =
    let file = Path.GetFullPath o.hfile
    let text = lineText file o.hline
    let from = o.hcol - 1

    if from < 0 || from > text.Length then None
    else
        let span = text.Substring(from, min o.hlen (text.Length - from))
        wordAt span word |> Option.map (fun k -> file, o.hline - 1, from + k)

/// The edits a rename makes: each reference's name replaced, in every file it's in.
let private renameEdits (h: Hover) (all: Hover list) (newName: string) : JsonNode =
    let word = h.name.Substring(h.name.LastIndexOf('.') + 1)

    let edits =
        all
        |> List.choose (fun o -> placeOf o word)
        |> List.distinct
        |> List.map (fun (file, l, c) -> file, obj [ "range", range (l, c) (l, c + word.Length); "newText", str newName ])

    obj [ "changes", obj [ for file, es in List.groupBy fst edits -> toUri file, arr (List.map snd es) ] ]

/// The range prepareRename answers with: the name under the cursor.
let private renameRange (path: string) (line: int) (ch: int) : JsonNode =
    match renameTarget path line ch with
    | Ok(h, _) ->
        let word = h.name.Substring(h.name.LastIndexOf('.') + 1)

        match placeOf h word with
        | Some(_, l, c) -> obj [ "range", range (l, c) (l, c + word.Length); "placeholder", str word ]
        | None -> null
    | Error _ -> null

/// A name a rename may give: an identifier, not a keyword.
let private validName (n: string) =
    n <> "" && (Char.IsLetter n[0] || n[0] = '_') && Seq.forall isIdentChar n && not (Syntax.keywords.Contains n)

/// The call the cursor is in, from its line up to the cursor: the function's name, its
/// parameters' types and names (from the definition's line) and the parameter the cursor is at.
let private signatureHelp (path: string) (line: int) (ch: int) : JsonNode =
    let text = lineText path (line + 1)
    let upto = text.Substring(0, min ch text.Length)
    let indent = upto.Length - upto.TrimStart().Length

    let toks =
        try
            Syntax.lex (upto.TrimStart()) |> Array.filter (fun t -> t.text <> "")
        with _ ->
            [||]

    // the application's atoms back to its start: what's after an operator, a keyword, an opening
    // bracket or a comma at the cursor's depth; brackets closed before the cursor are one atom
    let atoms = ResizeArray<Token>()
    let mutable depth = 0
    let mutable k = toks.Length - 1
    let mutable stop = false

    while k >= 0 && not stop do
        let t = toks[k]

        match t.tok with
        | KSym(")" | "]" | "|]" | "}") ->
            depth <- depth + 1
            k <- k - 1
        | KSym("(" | "[" | "[|" | "{") when depth > 0 ->
            depth <- depth - 1
            if depth = 0 then atoms.Insert(0, t)
            k <- k - 1
        | _ when depth > 0 -> k <- k - 1
        | KId _
        | KInt _
        | KFloat _
        | KStr _
        | KChar _
        | KInterp _
        | KKw("true" | "false") ->
            atoms.Insert(0, t)
            k <- k - 1
        | _ -> stop <- true

    match List.ofSeq atoms with
    | ({ tok = KId _ } as head) :: args ->
        let typing = upto.Length > 0 && upto[upto.Length - 1] <> ' '
        let active = if typing then max 0 (args.Length - 1) else args.Length

        let at =
            hoversAt path
            |> List.filter (fun h -> h.hline = line + 1 && h.hcol - 1 = indent + head.col - 1)
            |> List.sortBy (fun h -> h.hlen)
            |> List.tryHead

        match at with
        | Some h ->
            let rec spine (t: Ty) =
                match prune t with
                | TFun(a, b, _) ->
                    let ps, r = spine b
                    a :: ps, r
                | t -> [], t

            let ps, ret = spine h.hty

            // the parameters' names, from the definition's line: its words after the name, up to =
            let names =
                match results.TryGetValue path with
                | true, prog ->
                    match prog.hovers |> List.tryFind (fun d -> d.isDef && d.key = h.key && d.key <> "") with
                    | Some d ->
                        let def = lineText (Path.GetFullPath d.hfile) d.hline
                        let after = if d.hcol - 1 + d.hlen <= def.Length then def.Substring(d.hcol - 1 + d.hlen) else ""

                        try
                            let ts = Syntax.lex (after.TrimStart()) |> Array.filter (fun t -> t.text <> "")
                            let names = ResizeArray<string>()
                            let mutable d = 0
                            let mutable seen = false
                            let mutable i = 0

                            // up to the = (or the result's : ) outside parentheses
                            while i < ts.Length && (d > 0 || (ts[i].tok <> KSym "=" && ts[i].tok <> KSym ":")) do
                                match ts[i].tok with
                                | KSym "(" ->
                                    d <- d + 1
                                    seen <- false
                                | KSym ")" ->
                                    if d = 1 && not seen then names.Add "()"
                                    d <- d - 1
                                | KId x when d <= 1 && not seen ->
                                    names.Add x
                                    seen <- d = 1
                                | _ -> ()

                                i <- i + 1

                            List.ofSeq names
                        with _ ->
                            []
                    | None -> []
                | _ -> []

            let name = h.name.Substring(h.name.LastIndexOf('.') + 1)
            let parts = ps |> List.mapi (fun i p -> match List.tryItem i names with
                                                     | Some n when n <> "()" -> sprintf "(%s: %s)" n (show p)
                                                     | _ -> show p)

            let label = name + " " + String.concat " " parts + " : " + show ret
            let mutable at = name.Length + 1

            let offsets =
                parts
                |> List.map (fun p ->
                    let o = arr [ num at; num (at + p.Length) ]
                    at <- at + p.Length + 1
                    obj [ "label", o ])

            obj
                [ "signatures", arr [ obj [ "label", str label; "parameters", arr offsets ] ]
                  "activeSignature", num 0
                  "activeParameter", num (min active (max 0 (ps.Length - 1))) ]
        | None -> null
    | _ -> null

/// The code actions for a range: missing match cases added, a binder's type written, an `open`
/// for an unknown name (0019).
let private codeActions (path: string) (fromLine: int) (toLine: int) (diags: JsonNode) : JsonNode =
    let uri = toUri path
    let edit (l: int) (c: int) (text: string) = obj [ "changes", obj [ uri, arr [ obj [ "range", range (l, c) (l, c); "newText", str text ] ] ] ]
    let action (title: string) (kind: string) (e: JsonNode) = obj [ "title", str title; "kind", str kind; "edit", e ]
    let lines = (Driver.readSource path).Replace("\r\n", "\n").Split '\n'
    let indentOf (l: string) = l.Length - l.TrimStart().Length

    let fromDiagnostics =
        [ for d in (if isNull diags then [] else diags.AsArray() |> List.ofSeq) do
              let msg = getStr (d["message"])
              let line = getInt (d["range"]["start"]["line"])

              if msg.StartsWith "match is not exhaustive; missing case: " then
                  // after the match's last clause: the lines after the match's that are its
                  // clauses (from the first `|`, at that indentation or deeper)
                  let case = msg.Substring("match is not exhaustive; missing case: ".Length)
                  let first = [ line + 1 .. lines.Length - 1 ] |> List.tryFind (fun i -> lines[i].TrimStart().StartsWith "|")

                  match first with
                  | Some f ->
                      let ind = indentOf lines[f]
                      let mutable last = f

                      while last + 1 < lines.Length && (lines[last + 1].Trim() = "" || indentOf lines[last + 1] > ind || (indentOf lines[last + 1] = ind && lines[last + 1].TrimStart().StartsWith "|")) do
                          last <- last + 1

                      while last > f && lines[last].Trim() = "" do
                          last <- last - 1

                      let ctor = case.Split(' ')[0]
                      let clause = sprintf "\n%s| %s -> panic \"todo: %s\"" (String(' ', ind)) case ctor
                      yield action (sprintf "Add the missing case %s" case) "quickfix" (edit last lines[last].Length clause)
                  | None -> ()
              else
                  let m = Text.RegularExpressions.Regex.Match(msg, "^unknown (function|name) '([A-Za-z_][A-Za-z0-9_]*)'")

                  if m.Success then
                      let name = m.Groups[2].Value

                      let modules =
                          match results.TryGetValue path with
                          | true, prog ->
                              prog.funs
                              |> List.choose (fun f ->
                                  match f.name.LastIndexOf '.' with
                                  | -1 -> None
                                  | k when f.name.Substring(k + 1) = name && not (f.name.Contains "$") -> Some(f.name.Substring(0, k))
                                  | _ -> None)
                              |> List.distinct
                              |> List.map (fun m -> List.fold (fun (m: string) (ns: string) -> if m.StartsWith(ns + ".") then m.Substring(ns.Length + 1) else m) m Core.autoOpens)
                              |> List.distinct
                              |> List.truncate 5
                          | _ -> []

                      let lastOpen = lines |> Array.tryFindIndexBack (fun l -> l.StartsWith "open ")
                      let header = lines |> Array.tryFindIndex (fun l -> l.StartsWith "module " || l.StartsWith "namespace ")

                      for m in modules do
                          let at = match lastOpen, header with
                                   | Some i, _ -> i + 1
                                   | None, Some i -> i + 1
                                   | None, None -> 0

                          yield action (sprintf "open %s" m) "quickfix" (edit at 0 (sprintf "open %s\n" m))
                          let col = (lines[line]).IndexOf(name, StringComparison.Ordinal)

                          if col >= 0 then
                              yield action (sprintf "Write %s.%s" m name) "quickfix" (edit line col (m + ".")) ]

    // a binder whose type isn't written: the type, as hover shows it
    let annotations =
        hoversAt path
        |> List.filter (fun h -> h.inlay && h.hline - 1 >= fromLine && h.hline - 1 <= toLine && not (h.name.StartsWith "_"))
        |> List.distinctBy (fun h -> h.hline, h.hcol)
        |> List.map (fun h ->
            let l, c = h.hline - 1, h.hcol - 1
            let before = lines[l].Substring(0, c).TrimEnd()
            let ty = show h.hty

            // after let (or let mutable): x: T; a parameter: (x: T)
            let e =
                if before.EndsWith "let" || before.EndsWith "mutable" || before.EndsWith "for" then
                    edit l (c + h.name.Length) (": " + ty)
                else
                    obj [ "changes", obj [ uri, arr [ obj [ "range", range (l, c) (l, c + h.name.Length); "newText", str (sprintf "(%s: %s)" h.name ty) ] ] ] ]

            action (sprintf "Write the type of %s: %s" h.name ty) "refactor" e)

    arr (fromDiagnostics @ annotations)

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
    let hovers = hoversAt path |> List.filter (fun h -> h.hline - 1 >= fromLine && h.hline - 1 <= toLine)

    let types =
        hovers
        |> List.filter (fun h -> h.inlay && not (h.name.StartsWith "_"))
        |> List.distinctBy (fun h -> h.hline, h.hcol)
        |> List.map (fun h ->
            obj
                [ "position", pos (h.hline - 1) (h.hcol - 1 + h.name.Length)
                  "label", str (": " + show h.hty)
                  "kind", num 1 ])

    // a function's effects, when it has some its declaration doesn't write: before its `=`, so an
    // effect that leaked into it shows (/ Yield<int>)
    let effects =
        hovers
        |> List.filter (fun h -> h.decl)
        |> List.choose (fun h ->
            let rec own (t: Ty) =
                match prune t with
                | TFun(_, r, row) -> if isRowEmpty row then own r else Some row
                | _ -> None

            let line = lineText path h.hline
            let eq = if h.hcol - 1 < line.Length then line.IndexOf(" =", h.hcol - 1) else -1

            match own h.hty with
            | Some row when eq > 0 && not (line.Substring(0, eq).Contains " / ") ->
                let ls = fst (rowParts row) |> List.map show
                let text = match ls with
                           | [ l ] -> l
                           | ls -> "<" + String.concat ", " ls + ">"

                if ls.IsEmpty then None
                else Some(obj [ "position", pos (h.hline - 1) eq; "label", str (" / " + text); "kind", num 1 ])
            | _ -> None)

    arr (types @ effects)

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
        | TypeAlias(name, _, _) -> [ sym name 26 ln [] ] // 26: type parameter, the nearest to an alias
        | Trait(name, _, _) -> [ sym name 11 ln [] ]
        | Effect(name, _, ops) -> [ sym name 11 ln (ops |> List.map (fun (op, _) -> sym op 12 ln [])) ]
        | Impl(tr, STName(t, _), _, _) -> [ sym (sprintf "impl %s<%s>" tr t) 5 ln [] ]
        | Derive(name, _)
        | DeriveGroup(name, _) -> [ sym ("derive " + name) 12 ln [] ]
        | TypeGroup items -> items |> List.collect (fun (l, d) -> ofDecl l d)
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
                                    "documentRangeFormattingProvider", bool true
                                    "definitionProvider", bool true
                                    "referencesProvider", bool true
                                    "completionProvider", obj [ "triggerCharacters", arr [ str "." ] ]
                                    "renameProvider", obj [ "prepareProvider", bool true ]
                                    "signatureHelpProvider", obj [ "triggerCharacters", arr [ str " "; str "("; str "," ] ]
                                    "codeActionProvider", bool true ]
                              "serverInfo", obj [ "name", str "zs"; "version", str "0.4" ] ])
                | "textDocument/didOpen" ->
                    let path = docPath ()
                    Driver.overlay[path] <- getStr (ps["textDocument"]["text"])
                    analyze path
                | "textDocument/didChange" ->
                    let path = docPath ()
                    let changes = ps["contentChanges"].AsArray()
                    Driver.overlay[path] <- getStr (changes[changes.Count - 1]["text"])
                    changed path
                | "textDocument/didSave" -> changed (docPath ())
                | "textDocument/didClose" ->
                    let path = docPath ()
                    Driver.overlay.Remove path |> ignore
                    results.Remove path |> ignore
                    madeOf.Remove path |> ignore
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
                | "textDocument/prepareRename" ->
                    let p = ps["position"]
                    respond id (renameRange (docPath ()) (getInt (p["line"])) (getInt (p["character"])))
                | "textDocument/rename" ->
                    let p = ps["position"]
                    let newName = getStr (ps["newName"])

                    match renameTarget (docPath ()) (getInt (p["line"])) (getInt (p["character"])) with
                    | _ when not (validName newName) ->
                        send (obj [ "jsonrpc", str "2.0"; "id", id.DeepClone(); "error", obj [ "code", num -32602; "message", str (sprintf "'%s' isn't a name: a letter or _, then letters, digits and _, and not a keyword" newName) ] ])
                    | Ok(h, all) -> respond id (renameEdits h all newName)
                    | Error why -> send (obj [ "jsonrpc", str "2.0"; "id", id.DeepClone(); "error", obj [ "code", num -32602; "message", str why ] ])
                | "textDocument/signatureHelp" ->
                    let p = ps["position"]
                    respond id (signatureHelp (docPath ()) (getInt (p["line"])) (getInt (p["character"])))
                | "textDocument/codeAction" ->
                    let r = ps["range"]
                    let diags = match ps["context"] with
                                | null -> null
                                | c -> c["diagnostics"]

                    respond id (codeActions (docPath ()) (getInt (r["start"]["line"])) (getInt (r["end"]["line"])) diags)
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
                | "textDocument/rangeFormatting" ->
                    // the declarations and statements the range touches, formatted: one edit over
                    // their lines; none if they're formatted or the document doesn't parse
                    let r = ps["range"]
                    let src = Driver.readSource (docPath ())

                    match Format.formatRange src (getInt (r["start"]["line"]) + 1) (getInt (r["end"]["line"]) + 1) with
                    | Some(a, b, text) ->
                        let lines = src.Replace("\r\n", "\n").Split('\n')
                        respond id (arr [ obj [ "range", range (a - 1, 0) (b - 1, lines[b - 1].Length); "newText", str text ] ])
                    | None -> respond id (arr [])
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
