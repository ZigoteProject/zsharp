/// The language server (LSP 3.17 over stdio): diagnostics as you type, hover types, inlay type
/// hints, document symbols, definition, references, completion, rename, signature help, code
/// actions and formatting, from the checker's results on the editor's buffers (the F# compiler's
/// Lsp). No build runs: a C name's type comes from libclang in this process.
// ponytail: each change checks the program again with the library; 0007's cache when that's slow
open Diag.Diagnostic

/// A hover where it is: its file's full path, its line and column (from 1), and its length in
/// characters.
type Spot = { path: string; line: int; col: int; len: int; h: Infer.Cx.Hover }

/// An open document's last analysis: the program checked, its hovers where they are, and what the
/// editor shows for the C names it imports.
type Analysis = { checked: Build.Check.Checked; spots: array<Spot>; cInfos: Map<string, Build.CImport.CInfo> }

/// The server: the open documents' texts by full path, each one's last analysis, the files its
/// program is made of, the documented items of files by their text, and where it writes.
type State =
  { texts: ref<Map<string, string>>
    results: ref<Map<string, Analysis>>
    madeOf: ref<Map<string, Set<string>>>
    docCache: ref<Map<string, string * list<Build.Doc.DocItem>>>
    out: IO.Writer }

let private num (n: int) = Rpc.num n

let private findSpot (p: Spot -> bool) (spots: array<Spot>) : option<Spot> = List.tryFind p (Array.toList spots)

let private pos (line: int) (ch: int) = JObject [ ("line", num line); ("character", num ch) ]

let private range (l1: int) (c1: int) (l2: int) (c2: int) = JObject [ ("start", pos l1 c1); ("end", pos l2 c2) ]

let private respond (st: State) (id: Json) (result: Json) = Rpc.send st.out (JObject [ ("jsonrpc", JString "2.0"); ("id", id); ("result", result) ])

let private failWith (st: State) (id: Json) (code: int) (msg: string) =
  Rpc.send st.out (JObject [ ("jsonrpc", JString "2.0"); ("id", id); ("error", JObject [ ("code", num code); ("message", JString msg) ]) ])

let private notify (st: State) (meth: string) (ps: Json) = Rpc.send st.out (JObject [ ("jsonrpc", JString "2.0"); ("method", JString meth); ("params", ps) ])

// a file's text, the editor's when it's open, its line breaks as \n
let private sourceOf (st: State) (path: string) : string =
  match Build.Modules.readSource st.texts.Value path with
  | Ok t -> String.replace t "\r\n" "\n"
  | Error _ -> ""

let private linesOf (st: State) (path: string) : array<string> = Array.ofList (String.split "\n" (sourceOf st path))

let private lineText (st: State) (path: string) (line: int) : string =
  let lines = linesOf st path
  if line >= 1 && line <= Array.length lines then lines.[line - 1] else ""

let private chars (s: string) = String.charCount s

// the byte index of a string's i-th character (from 0)
let private byteOf (s: string) (i: int) : int =
  let mutable b = 0
  let mutable c = 0
  while b < String.length s && c < i do
    let (_, next) = String.decodeAt s b
    b <- next
    c <- c + 1
  b

// the characters of s from the i-th on
let private fromChar (s: string) (i: int) : string =
  let b = byteOf s i
  String.sub s b (String.length s - b)

let private upToChar (s: string) (i: int) : string = String.sub s 0 (byteOf s i)

let private indentOf (l: string) = String.length l - String.length (String.trimStart l)

// ------------------------------------------------------------ analysis

// every hover of a checked program, where it is
let private spotsOf (c: Build.Check.Checked) : array<Spot> =
  let byIndex = Map.ofList (List.map (fun (m: Build.Modules.Loaded) -> (m.source.file, m)) c.modules)
  let full = Map.map (fun _ (m: Build.Modules.Loaded) -> Path.getFullPath m.source.path) byIndex
  let one (h: Infer.Cx.Hover) : option<Spot> =
    match Map.tryFind h.file byIndex with
    | Some m when h.token >= 0 && h.token < Array.length m.tree.tokens ->
      let t = m.tree.tokens.[h.token]
      let (line, col) = Syntax.Source.position m.source t.offset
      Some { path = Map.find h.file full; line = line; col = col; len = chars (String.sub m.source.text t.offset t.length); h = h }
    | _ -> None
  Array.ofList (List.choose one (Array.toList (Buffer.toArray c.cx.hovers)))

// a diagnostic's place: its file as shown, its full path, its line and column (from 1; 0 for none)
let private placeOf (sources: Map<int, Syntax.Source.Source>) (at: Span) : string * string * int * int =
  match Map.tryFind at.file sources with
  | Some src when at.offset >= 0 ->
    let (line, col) = Syntax.Source.position src at.offset
    (src.path, Path.getFullPath src.path, line, (if at.length < 0 then 0 else col))
  | Some src -> (src.path, Path.getFullPath src.path, 0, 0)
  | None -> ("", "", 0, 0)

/// Checks a document (with its modules) again and publishes its diagnostics. A program that
/// doesn't get to checking (a syntax error) keeps the last analysis's hovers.
let private analyze (st: State) (path: string) =
  let (diags, sources) =
    match Build.Check.programWith st.texts.Value path false true false true with
    | Ok c ->
      let spots = spotsOf c
      let infos = Map.ofList (List.collect (fun (m: Build.Modules.Loaded) -> m.cInfos) c.modules)
      st.results.Value <- Map.add path { checked = c; spots = spots; cInfos = infos } st.results.Value
      st.madeOf.Value <- Map.add path (Set.ofList (List.map (fun (s: Spot) -> s.path) (Array.toList spots))) st.madeOf.Value
      (Buffer.toArray c.cx.diagnostics, List.map (fun (m: Build.Modules.Loaded) -> m.source) c.modules)
    | Error(ds, srcs) -> (ds, srcs)
  let byIndex = Map.ofList (List.map (fun (s: Syntax.Source.Source) -> (s.file, s)) sources)
  let isError (d: Diagnostic) = d.severity = Err
  let mine (d: Diagnostic) =
    let (_, full, line0, col) = placeOf byIndex d.at
    if full <> path then
      None
    else
      let line = max 1 line0
      let text = lineText st path line
      let start = if col > 0 then col - 1 else indentOf text
      // a warning: severity 2, its kind as the code, its notes as related places (0021)
      let related (n: Note) =
        let (_, nfull, nline, ncol) = placeOf byIndex n.at
        JObject [ ("location", JObject [ ("uri", JString(Rpc.toUri nfull)); ("range", range (nline - 1) (max 0 (ncol - 1)) (nline - 1) (max 1 ncol)) ]); ("message", JString n.text) ]
      let warning = if isError d then [] else [ ("code", JString d.name); ("relatedInformation", JArray(List.map related d.notes)) ]
      let common =
        [ ("range", range (line - 1) start (line - 1) (max (start + 1) (chars text)))
          ("severity", num (if isError d then 1 else 2))
          ("source", JString "zs")
          ("message", JString d.message) ]
      Some(JObject(List.append common warning))
  // an error in an imported module shows on the first line of this file (a warning there stays in
  // its own file)
  let elsewhere (d: Diagnostic) =
    let (shown, full, line, _) = placeOf byIndex d.at
    if full <> path && isError d then
      Some(JObject [ ("range", range 0 0 0 1); ("severity", num 1); ("source", JString "zs"); ("message", JString $"{shown}:{line}: {d.message}") ])
    else
      None
  let all = Array.toList diags
  let shown = List.append (List.choose mine all) (List.choose elsewhere all)
  notify st "textDocument/publishDiagnostics" (JObject [ ("uri", JString(Rpc.toUri path)); ("diagnostics", JArray shown) ])

/// A document changed: it's analyzed again, and so is every other open one whose program has it.
let private changed (st: State) (path: string) =
  analyze st path
  for (other, _) in Map.toList st.results.Value do
    if other <> path then
      match Map.tryFind other st.madeOf.Value with
      | Some files when Set.contains path files -> analyze st other
      | _ -> ()

let private analysisOf (st: State) (path: string) : option<Analysis> = Map.tryFind path st.results.Value

let private hoversAt (st: State) (path: string) : list<Spot> =
  match analysisOf st path with
  | Some a -> List.filter (fun (s: Spot) -> s.path = path && not (String.startsWith "$" s.h.name)) (Array.toList a.spots)
  | None -> []

let private atPosition (line: int) (ch: int) (s: Spot) = s.line = line + 1 && ch >= s.col - 1 && ch < s.col - 1 + s.len

let private shortest (spots: list<Spot>) : option<Spot> = List.tryHead (List.sortBy (fun (s: Spot) -> s.len) spots)

let private show (a: Analysis) (t: Types.Ty.Ty) = Infer.Cx.show a.checked.cx t

// the documented items of a file, recomputed when its text changes
let private docIndex (st: State) (file: string) : list<Build.Doc.DocItem> =
  let text = sourceOf st file
  match Map.tryFind file st.docCache.Value with
  | Some(t, items) when t = text -> items
  | _ ->
    let items = Build.Doc.docItems text
    st.docCache.Value <- Map.add file (text, items) st.docCache.Value
    items

// the definition of what a hover refers to, in this document's program
let private definitionOf (a: Analysis) (s: Spot) : option<Spot> =
  if s.h.isDef || s.h.key = "" then Some s else findSpot (fun (d: Spot) -> d.h.isDef && d.h.key = s.h.key) a.spots

// the doc comment of what a hover refers to: at its definition, a built-in's, or by name in the
// files of this program (constructors, trait methods and members)
let private zsDocOf (st: State) (a: Analysis) (s: Spot) : option<string> =
  match Option.bind (fun (d: Spot) -> Build.Doc.docAbove (linesOf st d.path) d.line) (definitionOf a s) with
  | Some doc -> Some doc
  | None ->
    let builtin = Map.ofList Build.Doc.builtinDocs
    match List.tryPick (fun k -> Map.tryFind k builtin) [ s.h.key; s.h.name ] with
    | Some doc -> Some doc
    | None ->
      let files = List.distinct (List.map (fun (x: Spot) -> x.path) (Array.toList a.spots))
      // T.M (static) is T#M
      let statics =
        match String.lastIndexOf "." s.h.key with
        | Some i when i > 0 -> [ String.sub s.h.key 0 i + "#" + String.sub s.h.key (i + 1) (String.length s.h.key - i - 1) ]
        | _ -> []
      let keys = List.append [ s.h.key; s.h.name ] statics
      // `compare` is Ord.compare
      let fits (d: Build.Doc.DocItem) = Option.isSome d.doc && (List.contains d.key keys || (d.kind = "method" && String.endsWith ("." + s.h.name) d.key))
      List.tryPick (fun f -> Option.bind (fun (d: Build.Doc.DocItem) -> d.doc) (List.tryFind fits (docIndex st f))) files

// an imported C name's declaration and header comment, as Markdown
let private cDoc (a: Analysis) (name: string) : option<string> =
  match Map.tryFind name a.cInfos with
  | Some i -> Some("```c\n" + i.csig + "\n```" + (if i.cdoc = "" then "" else "\n\n" + i.cdoc))
  | None -> None

let private hover (st: State) (path: string) (line: int) (ch: int) : Json =
  match (analysisOf st path, shortest (List.filter (atPosition line ch) (hoversAt st path))) with
  | (Some a, Some s) ->
    let h = s.h
    let needs = if h.constraints = "" then "" else " when " + h.constraints
    let doc =
      match cDoc a h.name with
      | Some d -> "\n\n" + d
      | None ->
        match zsDocOf st a s with
        | Some d -> "\n\n" + d
        | None -> ""
    // the effects in words, as the definition has them (0025)
    let words =
      match definitionOf a s with
      | Some d when d.h.explain <> "" -> "\n  " + d.h.explain
      | _ -> ""
    let value = "```zsharp\n" + h.name + " : " + show a h.ty + needs + words + "\n```" + doc
    JObject [ ("contents", JObject [ ("kind", JString "markdown"); ("value", JString value) ]); ("range", range (s.line - 1) (s.col - 1) (s.line - 1) (s.col - 1 + s.len)) ]
  | _ -> JNull

let private location (s: Spot) : Json = JObject [ ("uri", JString(Rpc.toUri s.path)); ("range", range (s.line - 1) (s.col - 1) (s.line - 1) (s.col - 1 + s.len)) ]

// the name under the cursor, and everything in its program that refers to the same thing
let private related (st: State) (path: string) (line: int) (ch: int) : option<Spot> * list<Spot> =
  let here = shortest (List.filter (fun (s: Spot) -> s.h.key <> "" && atPosition line ch s) (hoversAt st path))
  match (here, analysisOf st path) with
  | (Some h, Some a) -> (Some h, List.filter (fun (o: Spot) -> o.h.key = h.h.key) (Array.toList a.spots))
  | _ -> (None, [])

let private definition (st: State) (path: string) (line: int) (ch: int) : Json =
  let cName =
    match analysisOf st path with
    | Some a ->
      let inHeader (s: Spot) =
        match Map.tryFind s.h.name a.cInfos with
        | Some i when i.cline > 0 && File.exists i.cfile -> Some i
        | _ -> None
      List.tryPick inHeader (List.filter (atPosition line ch) (hoversAt st path))
    | None -> None
  match cName with
  | Some i -> JObject [ ("uri", JString(Rpc.toUri i.cfile)); ("range", range (i.cline - 1) 0 (i.cline - 1) 0) ]
  | None ->
    match related st path line ch with
    | (Some _, all) ->
      match List.tryFind (fun (h: Spot) -> h.h.isDef) all with
      | Some d -> location d
      | None -> JNull
    | _ -> JNull

let private references (st: State) (path: string) (line: int) (ch: int) (withDecl: bool) : Json =
  let (_, all) = related st path line ch
  let chosen = List.filter (fun (h: Spot) -> withDecl || not h.h.isDef) all
  let distinct = List.fold (fun (acc: list<Spot>) (h: Spot) -> if List.exists (fun (o: Spot) -> o.path = h.path && o.line = h.line && o.col = h.col) acc then acc else List.append acc [ h ]) [] chosen
  JArray(List.map location distinct)

let private keywords =
  [ "let"; "rec"; "mutable"; "if"; "then"; "else"; "match"; "with"; "when"; "fun"; "for"; "in"; "do"; "while"; "type"; "of"; "member"; "static"; "trait"; "impl"; "derive"; "extern"; "open"; "module"; "private"; "not"; "true"; "false" ]

// ------------------------------------------------------------ rename, signature help, code actions (0019)

// a file the editor may change: the program's, not the library's or a dependency's
let private editable (file: string) =
  let full = Path.getFullPath file
  Option.isNone (Build.Modules.libraryRootOf full) && not (String.contains "/.zs-cache/" full)

let private isIdentByte (b: u8) = (b >= u8 97 && b <= u8 122) || (b >= u8 65 && b <= u8 90) || (b >= u8 48 && b <= u8 57) || b = u8 95

let private allIdent (s: string) =
  let mutable ok = true
  for i in 0 .. String.length s - 1 do
    if not (isIdentByte (String.byte s i)) then
      ok <- false
  ok

// where the name `word` stands alone in a reference's text, the last place
let private wordAt (span: string) (word: string) : option<int> =
  let n = String.length span
  let w = String.length word
  let rec go (from: int) =
    if from < 0 then
      None
    else
      let k = if from + w <= n && String.sub span from w = word then from else -1
      if k >= 0 && (k = 0 || not (isIdentByte (String.byte span (k - 1)))) && (k + w = n || not (isIdentByte (String.byte span (k + w)))) then Some k else go (from - 1)
  if n = 0 || w = 0 then None else go (n - w)

let private lastPart (name: string) =
  match String.lastIndexOf "." name with
  | Some i -> String.sub name (i + 1) (String.length name - i - 1)
  | None -> name

// what a rename at a position changes: the name there and every reference to it, in the programs
// of the open documents (a field's uses too: its key is field:Record.name), or why it can't be
// renamed. A name's key depends on the program it's checked in, so another program's references
// are those of the definition at the same place.
let private renameTarget (st: State) (path: string) (line: int) (ch: int) : result<Spot * list<Spot>, string> =
  match related st path line ch with
  | (Some h, all) when h.h.key <> "" ->
    let inC =
      match analysisOf st path with
      | Some a -> Map.containsKey h.h.name a.cInfos
      | None -> false
    if inC then
      Error $"{h.h.name} is declared in a C header; rename it there"
    else
      match List.tryFind (fun (o: Spot) -> o.h.isDef) all with
      | Some d when not (editable d.path) -> Error $"{Types.Ty.shortName h.h.name} is defined in {Path.getFileName d.path}, outside the program"
      | def ->
        let samePlace (a: Spot) (b: Spot) = a.path = b.path && a.line = b.line && a.col = b.col
        let elsewhere =
          match def with
          | Some d ->
            let inOther (a: Analysis) =
              match findSpot (fun (o: Spot) -> o.h.isDef && samePlace o d) a.spots with
              | Some other -> List.filter (fun (o: Spot) -> o.h.key = other.h.key) (Array.toList a.spots)
              | None -> []
            List.collect (fun (_, a) -> inOther a) (Map.toList st.results.Value)
          | None -> []
        let chosen = List.filter (fun (o: Spot) -> editable o.path) (List.append all elsewhere)
        let distinct = List.fold (fun (acc: list<Spot>) (o: Spot) -> if List.exists (samePlace o) acc then acc else List.append acc [ o ]) [] chosen
        Ok(h, distinct)
  | (Some h, _) -> Error $"'{h.h.name}' isn't a name the checker resolved, so it can't be renamed"
  | (None, _) -> Error "there's no name here to rename"

// a reference's place: its file, line (from 0) and the column of the name in it
let private nameIn (st: State) (o: Spot) (word: string) : option<string * int * int> =
  let text = lineText st o.path o.line
  let from = o.col - 1
  if from < 0 || from > chars text then
    None
  else
    let rest = fromChar text from
    let span = upToChar rest (min o.len (chars rest))
    Option.map (fun k -> (o.path, o.line - 1, from + chars (String.sub span 0 k))) (wordAt span word)

// the edits a rename makes: each reference's name replaced, in every file it's in
let private renameEdits (st: State) (h: Spot) (all: list<Spot>) (newName: string) : Json =
  let word = lastPart h.h.name
  let places = List.distinct (List.choose (fun (o: Spot) -> nameIn st o word) all)
  let files = List.distinct (List.map (fun (f, _, _) -> f) places)
  let editsIn (file: string) =
    let one (p: string * int * int) =
      let (_, l, c) = p
      JObject [ ("range", range l c l (c + chars word)); ("newText", JString newName) ]
    (Rpc.toUri file, JArray(List.map one (List.filter (fun (f, _, _) -> f = file) places)))
  JObject [ ("changes", JObject(List.map editsIn files)) ]

// the range prepareRename answers with: the name under the cursor
let private renameRange (st: State) (path: string) (line: int) (ch: int) : Json =
  match renameTarget st path line ch with
  | Ok(h, _) ->
    let word = lastPart h.h.name
    match nameIn st h word with
    | Some(_, l, c) -> JObject [ ("range", range l c l (c + chars word)); ("placeholder", JString word) ]
    | None -> JNull
  | Error _ -> JNull

// a name a rename may give: an identifier, not a keyword
let private validName (n: string) =
  let first = if n = "" then u8 0 else String.byte n 0
  n <> "" && ((first >= u8 97 && first <= u8 122) || (first >= u8 65 && first <= u8 90) || first = u8 95) && allIdent n && Syntax.Token.keyword n = Syntax.Token.Id

// a text's written tokens (not layout's)
let private tokensOf (text: string) : list<Syntax.Token.Token> =
  let src = Syntax.Source.make 0 "" text
  let (toks, _) = Diag.Report.collect (fun () -> Syntax.Lexer.lex src)
  List.filter (fun (t: Syntax.Token.Token) -> t.length > 0) (Array.toList toks)

// the call the cursor is in, from its line up to the cursor: the function's name, its parameters'
// types and names (from the definition's line) and the parameter the cursor is at
let private signatureHelp (st: State) (path: string) (line: int) (ch: int) : Json =
  let text = lineText st path (line + 1)
  let upto = upToChar text (min ch (chars text))
  let indent = indentOf upto
  let trimmed = String.trimStart upto
  let toks = Array.ofList (tokensOf trimmed)
  // the application's atoms back to its start: what's after an operator, a keyword, an opening
  // bracket or a comma at the cursor's depth; brackets closed before the cursor are one atom
  let atoms = ref []
  let mutable depth = 0
  let mutable k = Array.length toks - 1
  let mutable stop = false
  while k >= 0 && not stop do
    let t = toks.[k]
    match t.kind with
    | Syntax.Token.RParen
    | Syntax.Token.RBrack
    | Syntax.Token.BarRBrack
    | Syntax.Token.RBrace ->
      depth <- depth + 1
      k <- k - 1
    | Syntax.Token.LParen
    | Syntax.Token.LBrack
    | Syntax.Token.LBrackBar
    | Syntax.Token.LBrace when depth > 0 ->
      depth <- depth - 1
      if depth = 0 then
        atoms.Value <- t :: atoms.Value
      k <- k - 1
    | _ when depth > 0 -> k <- k - 1
    | Syntax.Token.Id
    | Syntax.Token.Int
    | Syntax.Token.Float
    | Syntax.Token.Str
    | Syntax.Token.Char
    | Syntax.Token.Interp
    | Syntax.Token.True
    | Syntax.Token.False ->
      atoms.Value <- t :: atoms.Value
      k <- k - 1
    | _ -> stop <- true
  match (atoms.Value, analysisOf st path) with
  | (head :: args, Some a) when head.kind = Syntax.Token.Id ->
    let typing = String.length upto > 0 && String.byte upto (String.length upto - 1) <> u8 32
    let active = if typing then max 0 (List.length args - 1) else List.length args
    let headCol = chars (String.sub trimmed 0 head.offset) + 1
    let at = shortest (List.filter (fun (h: Spot) -> h.line = line + 1 && h.col - 1 = indent + headCol - 1) (hoversAt st path))
    match at with
    | Some h ->
      let v = a.checked.cx.v
      let rec spine (t: Types.Ty.Ty) : list<Types.Ty.Ty> * Types.Ty.Ty =
        match Types.Vars.prune v t with
        | Types.Ty.TFun(x, b, _) ->
          let (ps, r) = spine b
          (x :: ps, r)
        | r -> ([], r)
      let (ps, ret) = spine h.h.ty
      // the parameters' names, from the definition's line: its words after the name, up to =
      let names =
        match findSpot (fun (d: Spot) -> d.h.isDef && d.h.key = h.h.key && d.h.key <> "") a.spots with
        | Some d ->
          let def = lineText st d.path d.line
          let after = if d.col - 1 + d.len <= chars def then fromChar def (d.col - 1 + d.len) else ""
          let ts = Array.ofList (tokensOf (String.trimStart after))
          let found = ref []
          let mutable dd = 0
          let mutable seen = false
          let mutable i = 0
          // up to the = (or the result's :) outside parentheses
          while i < Array.length ts && (dd > 0 || (ts.[i].kind <> Syntax.Token.Equals && ts.[i].kind <> Syntax.Token.Colon)) do
            let t = ts.[i]
            if t.kind = Syntax.Token.LParen then
              dd <- dd + 1
              seen <- false
            else if t.kind = Syntax.Token.RParen then
              if dd = 1 && not seen then
                found.Value <- "()" :: found.Value
              dd <- dd - 1
            else if t.kind = Syntax.Token.Id && dd <= 1 && not seen then
              found.Value <- Syntax.Token.text (String.trimStart after) t :: found.Value
              seen <- dd = 1
            i <- i + 1
          List.rev found.Value
        | None -> []
      let name = lastPart h.h.name
      let part (i: int) (p: Types.Ty.Ty) =
        match List.tryItem i names with
        | Some n when n <> "()" -> $"({n}: {show a p})"
        | _ -> show a p
      let parts = List.mapi part ps
      let label = name + " " + String.join " " parts + " : " + show a ret
      let offsets = ref []
      let mutable from = chars name + 1
      for p in parts do
        offsets.Value <- JObject [ ("label", JArray [ num from; num (from + chars p) ]) ] :: offsets.Value
        from <- from + chars p + 1
      let signature = JObject [ ("label", JString label); ("parameters", JArray(List.rev offsets.Value)) ]
      JObject [ ("signatures", JArray [ signature ]); ("activeSignature", num 0); ("activeParameter", num (min active (max 0 (List.length ps - 1)))) ]
    | None -> JNull
  | _ -> JNull

// the code actions for a range: missing match cases added, a binder's type written, an `open` for
// an unknown name (0019)
let private codeActions (st: State) (path: string) (fromLine: int) (toLine: int) (diags: Json) : Json =
  let uri = Rpc.toUri path
  let edit (l: int) (c: int) (text: string) = JObject [ ("changes", JObject [ (uri, JArray [ JObject [ ("range", range l c l c); ("newText", JString text) ] ]) ]) ]
  let action (title: string) (kind: string) (e: Json) = JObject [ ("title", JString title); ("kind", JString kind); ("edit", e) ]
  let lines = linesOf st path
  let n = Array.length lines
  let missing = "match is not exhaustive; missing case: "
  let fromDiagnostic (d: Json) : list<Json> =
    let msg = Rpc.text (Rpc.field "message" d)
    let line = Rpc.intOf (Rpc.at [ "range"; "start"; "line" ] d)
    if String.startsWith missing msg then
      // after the match's last clause: the lines after the match's that are its clauses (from the
      // first `|`, at that indentation or deeper)
      let case = String.sub msg (String.length missing) (String.length msg - String.length missing)
      match List.tryFind (fun i -> String.startsWith "|" (String.trimStart lines.[i])) (List.init (max 0 (n - line - 1)) (fun i -> line + 1 + i)) with
      | Some f ->
        let ind = indentOf lines.[f]
        let mutable last = f
        let clauseLine (l: string) = String.trim l = "" || indentOf l > ind || (indentOf l = ind && String.startsWith "|" (String.trimStart l))
        while last + 1 < n && clauseLine lines.[last + 1] do
          last <- last + 1
        while last > f && String.trim lines.[last] = "" do
          last <- last - 1
        let ctor = List.head (String.split " " case)
        let clause = "\n" + String.repeat ind " " + $"| {case} -> panic \"todo: {ctor}\""
        [ action $"Add the missing case {case}" "quickfix" (edit last (chars lines.[last]) clause) ]
      | None -> []
    else
      // unknown function 'x' / unknown name 'x'
      let unknown = if String.startsWith "unknown function '" msg then 18 else if String.startsWith "unknown name '" msg then 14 else -1
      let close = if unknown > 0 then String.indexOfFrom msg "'" unknown else -1
      let name = if close > unknown then String.sub msg unknown (close - unknown) else ""
      if name <> "" && allIdent name then
        let modules =
          match analysisOf st path with
          | Some a ->
            let definers (f: Core.Ir.FunDef) =
              match String.lastIndexOf "." f.name with
              | Some k when String.sub f.name (k + 1) (String.length f.name - k - 1) = name && not (String.contains "$" f.name) -> Some(String.sub f.name 0 k)
              | _ -> None
            let found = List.distinct (List.choose definers (Array.toList (Buffer.toArray a.checked.cx.funs)))
            let short (m: string) = List.fold (fun (m: string) (ns: string) -> if String.startsWith (ns + ".") m then String.sub m (String.length ns + 1) (String.length m - String.length ns - 1) else m) m Types.Ty.autoOpens
            List.take 5 (List.distinct (List.map short found))
          | None -> []
        let lastOpen = List.tryLast (List.filter (fun i -> String.startsWith "open " lines.[i]) (List.init n (fun i -> i)))
        let header = List.tryFind (fun i -> String.startsWith "module " lines.[i] || String.startsWith "namespace " lines.[i]) (List.init n (fun i -> i))
        let at =
          match (lastOpen, header) with
          | (Some i, _) -> i + 1
          | (None, Some i) -> i + 1
          | (None, None) -> 0
        let forModule (m: string) =
          let opening = action $"open {m}" "quickfix" (edit at 0 $"open {m}\n")
          let col = if line < n then String.indexOf name lines.[line] else None
          match col with
          | Some c -> [ opening; action $"Write {m}.{name}" "quickfix" (edit line (chars (String.sub lines.[line] 0 c)) (m + ".")) ]
          | None -> [ opening ]
        List.collect forModule modules
      else
        []
  let fromDiagnostics =
    match diags with
    | JArray ds -> List.collect fromDiagnostic ds
    | _ -> []
  // a binder whose type isn't written: the type, as hover shows it
  let annotations =
    match analysisOf st path with
    | Some a ->
      let wanted (h: Spot) = h.h.inlay && h.line - 1 >= fromLine && h.line - 1 <= toLine && not (String.startsWith "_" h.h.name)
      let distinct = List.fold (fun (acc: list<Spot>) (h: Spot) -> if List.exists (fun (o: Spot) -> o.line = h.line && o.col = h.col) acc then acc else List.append acc [ h ]) [] (List.filter wanted (hoversAt st path))
      let annotate (h: Spot) =
        let l = h.line - 1
        let c = h.col - 1
        let before = String.trimEnd (upToChar lines.[l] c)
        let ty = show a h.h.ty
        // after let (or let mutable): x: T; a parameter: (x: T)
        let e =
          if String.endsWith "let" before || String.endsWith "mutable" before || String.endsWith "for" before then
            edit l (c + chars h.h.name) (": " + ty)
          else
            JObject [ ("changes", JObject [ (uri, JArray [ JObject [ ("range", range l c l (c + chars h.h.name)); ("newText", JString $"({h.h.name}: {ty})") ] ]) ]) ]
        action $"Write the type of {h.h.name}: {ty}" "refactor" e
      List.map annotate distinct
    | None -> []
  JArray(List.append fromDiagnostics annotations)

// after `x.`: the fields and members of x's type; otherwise names in scope (approximately: library
// and project functions, types, constructors, this file's own names) and keywords
let private completion (st: State) (path: string) (line: int) (ch: int) : Json =
  let text = lineText st path (line + 1)
  let upto = upToChar text (min ch (chars text))
  let mutable i = String.length upto - 1
  while i >= 0 && isIdentByte (String.byte upto i) do
    i <- i - 1
  let item (label: string) (kind: int) (detail: string) = JObject [ ("label", JString label); ("kind", num kind); ("detail", JString detail) ]
  let keywordItems = List.map (fun k -> item k 14 "keyword") keywords
  match analysisOf st path with
  | Some a when i >= 0 && String.byte upto i = u8 46 ->
    // the receiver ends right before the dot
    let dotCol = chars (String.sub upto 0 i)
    let receiver = shortest (List.filter (fun (h: Spot) -> h.line = line + 1 && h.col - 1 + h.len = dotCol) (hoversAt st path))
    let cx = a.checked.cx
    match Option.map (fun (h: Spot) -> Types.Vars.prune cx.v h.h.ty) receiver with
    | Some(Types.Ty.TCon(n, args)) ->
      let fields =
        match Map.tryFind n cx.types.Value with
        | Some { def = Types.Ty.RecordDef fs } -> List.map (fun (f, t) -> item f 5 (show a (Types.Norm.substGen cx.v args t))) fs
        | _ -> []
      let members =
        match Map.tryFind n cx.members.Value with
        | Some ms -> List.map (fun (m, _) -> item m 2 n) ms
        | None -> []
      JArray(List.append fields members)
    | _ -> JArray []
  | Some a ->
    let cx = a.checked.cx
    let firstByName (xs: list<Spot>) = List.fold (fun (acc: list<Spot>) (h: Spot) -> if List.exists (fun (o: Spot) -> o.h.name = h.h.name) acc then acc else List.append acc [ h ]) [] xs
    let global (h: Spot) =
      // as programs write it: List.map, not Collections.List.map
      let label = Types.Ty.shortName h.h.name
      match Build.Doc.docAbove (linesOf st h.path) h.line with
      | Some d -> JObject [ ("label", JString label); ("kind", num 3); ("detail", JString(show a h.h.ty)); ("documentation", JObject [ ("kind", JString "markdown"); ("value", JString d) ]) ]
      | None -> item label 3 (show a h.h.ty)
    let globals = List.map global (firstByName (List.filter (fun (h: Spot) -> h.h.decl && not (String.contains "$" h.h.name)) (Array.toList a.spots)))
    let cName (p: string * Build.CImport.CInfo) =
      let (n, ci) = p
      let kind = if String.startsWith "typedef struct" ci.csig then 22 else if String.contains "(" ci.csig then 3 else 21
      JObject [ ("label", JString n); ("kind", num kind); ("detail", JString ci.csig); ("documentation", JObject [ ("kind", JString "markdown"); ("value", JString ci.cdoc) ]) ]
    let cNames = List.map cName (Map.toList a.cInfos)
    let locals = List.map (fun (h: Spot) -> item h.h.name 6 (show a h.h.ty)) (firstByName (List.filter (fun (h: Spot) -> h.h.isDef && not h.h.decl) (hoversAt st path)))
    let typeItems (p: string * Types.Ty.TypeInfo) : list<Json> =
      let (n, info) = p
      if String.contains "$" n then
        []
      else
        match info.def with
        | Types.Ty.RecordDef _ -> [ item (Types.Ty.shortName n) 22 "" ]
        | Types.Ty.UnionDef cs -> item (Types.Ty.shortName n) 13 "" :: List.map (fun (c, _) -> item (Types.Ty.shortName c) 20 (Types.Ty.shortName n)) cs
    let typesAndCases = List.collect typeItems (Map.toList cx.types.Value)
    JArray(List.concat [ locals; globals; cNames; typesAndCases; keywordItems ])
  | None -> JArray keywordItems

let private inlayHints (st: State) (path: string) (fromLine: int) (toLine: int) : Json =
  match analysisOf st path with
  | None -> JArray []
  | Some a ->
    let v = a.checked.cx.v
    let spots = List.filter (fun (h: Spot) -> h.line - 1 >= fromLine && h.line - 1 <= toLine) (hoversAt st path)
    let distinct = List.fold (fun (acc: list<Spot>) (h: Spot) -> if List.exists (fun (o: Spot) -> o.line = h.line && o.col = h.col) acc then acc else List.append acc [ h ]) [] (List.filter (fun (h: Spot) -> h.h.inlay && not (String.startsWith "_" h.h.name)) spots)
    let types = List.map (fun (h: Spot) -> JObject [ ("position", pos (h.line - 1) (h.col - 1 + chars h.h.name)); ("label", JString(": " + show a h.h.ty)); ("kind", num 1) ]) distinct
    // a function's effects, when it has some its declaration doesn't write: before its `=`, so an
    // effect that leaked into it shows (/ Yield<int>)
    let effectHint (h: Spot) : option<Json> =
      let rec own (t: Types.Ty.Ty) : option<Types.Ty.Ty> =
        match Types.Vars.prune v t with
        | Types.Ty.TFun(_, r, row) -> if Types.Norm.isRowEmpty v row then own r else Some row
        | _ -> None
      let line = lineText st path h.line
      let eq =
        if h.col - 1 < chars line then
          let from = byteOf line (h.col - 1)
          let k = String.indexOfFrom line " =" from
          if k >= 0 then chars (String.sub line 0 k) else -1
        else
          -1
      match own h.h.ty with
      | Some row when eq > 0 && not (String.contains " / " (upToChar line eq)) ->
        let ls = List.map (show a) (fst (Types.Norm.rowParts v row))
        let text =
          match ls with
          | [ l ] -> l
          | _ -> "<" + String.join ", " ls + ">"
        if List.isEmpty ls then None else Some(JObject [ ("position", pos (h.line - 1) eq); ("label", JString(" / " + text)); ("kind", num 1) ])
      | _ -> None
    let effects = List.choose effectHint (List.filter (fun (h: Spot) -> h.h.decl) spots)
    JArray(List.append types effects)

// top-level declarations, with union cases and members as children
let private symbols (st: State) (path: string) : Json =
  let text = sourceOf st path
  let src = Syntax.Source.make 0 path text
  let (toks, _) = Diag.Report.collect (fun () -> Syntax.Lexer.lex src)
  let ((tree, decls), _) = Diag.Report.collect (fun () -> Syntax.Parser.parse src toks)
  let lineOfToken (t: int) = if t >= 0 && t < Array.length tree.tokens then Syntax.Source.lineOf src tree.tokens.[t].offset + 1 else 1
  let sym (name: string) (kind: int) (line: int) (children: list<Json>) =
    let r = range (line - 1) 0 (line - 1) (max 1 (chars (lineText st path line)))
    JObject [ ("name", JString name); ("kind", num kind); ("range", r); ("selectionRange", r); ("children", JArray children) ]
  // LSP SymbolKind: 5 class, 10 enum, 11 interface, 12 function, 22 enum member, 23 struct, 6
  // method, 26 type parameter (the nearest to an alias)
  let memberSyms (ms: list<Syntax.Ast.Member>) = List.map (fun (m: Syntax.Ast.Member) -> sym m.memberName 6 (lineOfToken m.mat) []) ms
  let rec ofDecl (ln: int) (d: Syntax.Ast.Decl) : list<Json> =
    match d.d with
    | Syntax.Ast.Fun(name, _, _, _, _) -> [ sym name 12 ln [] ]
    | Syntax.Ast.Extern(name, _, _, _) -> [ sym name 12 ln [] ]
    | Syntax.Ast.TypeDecl(name, _, body, ms) ->
      match body with
      | Syntax.Ast.UnionTy cases when not (List.isEmpty cases) -> [ sym name 10 ln (List.append (List.map (fun (c: Syntax.Ast.Case) -> sym c.case 22 ln []) cases) (memberSyms ms)) ]
      | _ -> [ sym name 23 ln (memberSyms ms) ]
    | Syntax.Ast.TypeExt(name, _, ms) -> [ sym (name + " (extension)") 5 ln (memberSyms ms) ]
    | Syntax.Ast.TypeAlias(name, _, _) -> [ sym name 26 ln [] ]
    | Syntax.Ast.Trait(name, _, _) -> [ sym name 11 ln [] ]
    | Syntax.Ast.Effect(name, _, ops) -> [ sym name 11 ln (List.map (fun (op, _, _) -> sym op 12 ln []) ops) ]
    | Syntax.Ast.Impl(tr, Syntax.Ast.STName(t, _), _, _) -> [ sym $"impl {tr}<{t}>" 5 ln [] ]
    | Syntax.Ast.Derive(name, _) -> [ sym ("derive " + name) 12 ln [] ]
    | Syntax.Ast.DeriveGroup(name, _) -> [ sym ("derive " + name) 12 ln [] ]
    | Syntax.Ast.TypeGroup items -> List.collect (fun (i: Syntax.Ast.Decl) -> ofDecl (lineOfToken i.dat) i) items
    | Syntax.Ast.Attrs(_, inner) -> ofDecl ln inner
    | Syntax.Ast.Private inner -> ofDecl ln inner
    | _ -> []
  JArray(List.collect (fun (d: Syntax.Ast.Decl) -> ofDecl (lineOfToken d.dat) d) decls)

// ------------------------------------------------------------ the loop

let private capabilities : Json =
  let caps =
    [ ("textDocumentSync", num 1)
      ("hoverProvider", JBool true)
      ("documentSymbolProvider", JBool true)
      ("inlayHintProvider", JBool true)
      ("documentFormattingProvider", JBool true)
      ("documentRangeFormattingProvider", JBool true)
      ("definitionProvider", JBool true)
      ("referencesProvider", JBool true)
      ("completionProvider", JObject [ ("triggerCharacters", JArray [ JString "." ]) ])
      ("renameProvider", JObject [ ("prepareProvider", JBool true) ])
      ("signatureHelpProvider", JObject [ ("triggerCharacters", JArray [ JString " "; JString "("; JString "," ]) ])
      ("codeActionProvider", JBool true) ]
  JObject [ ("capabilities", JObject caps); ("serverInfo", JObject [ ("name", JString "zs"); ("version", JString "0.4") ]) ]

// one message's answer (and its notifications)
let private answer (st: State) (msg: Json) : bool =
  let meth = Rpc.text (Rpc.field "method" msg)
  let id = Rpc.field "id" msg
  let ps = Rpc.field "params" msg
  let docPath () = Rpc.toPath (Rpc.text (Rpc.at [ "textDocument"; "uri" ] ps))
  let line () = Rpc.intOf (Rpc.at [ "position"; "line" ] ps)
  let character () = Rpc.intOf (Rpc.at [ "position"; "character" ] ps)
  let mutable running = true
  if meth = "initialize" then
    respond st id capabilities
  else if meth = "textDocument/didOpen" then
    let path = docPath ()
    st.texts.Value <- Map.add path (Rpc.text (Rpc.at [ "textDocument"; "text" ] ps)) st.texts.Value
    analyze st path
  else if meth = "textDocument/didChange" then
    let path = docPath ()
    match Rpc.field "contentChanges" ps with
    | JArray changes when not (List.isEmpty changes) ->
      st.texts.Value <- Map.add path (Rpc.text (Rpc.field "text" (List.last changes))) st.texts.Value
      changed st path
    | _ -> ()
  else if meth = "textDocument/didSave" then
    changed st (docPath ())
  else if meth = "textDocument/didClose" then
    let path = docPath ()
    st.texts.Value <- Map.remove path st.texts.Value
    st.results.Value <- Map.remove path st.results.Value
    st.madeOf.Value <- Map.remove path st.madeOf.Value
    notify st "textDocument/publishDiagnostics" (JObject [ ("uri", JString(Rpc.toUri path)); ("diagnostics", JArray []) ])
  else if meth = "textDocument/hover" then
    respond st id (hover st (docPath ()) (line ()) (character ()))
  else if meth = "textDocument/inlayHint" then
    respond st id (inlayHints st (docPath ()) (Rpc.intOf (Rpc.at [ "range"; "start"; "line" ] ps)) (Rpc.intOf (Rpc.at [ "range"; "end"; "line" ] ps)))
  else if meth = "textDocument/documentSymbol" then
    respond st id (symbols st (docPath ()))
  else if meth = "textDocument/definition" then
    respond st id (definition st (docPath ()) (line ()) (character ()))
  else if meth = "textDocument/references" then
    let withDecl =
      match Rpc.at [ "context"; "includeDeclaration" ] ps with
      | JBool b -> b
      | _ -> true
    respond st id (references st (docPath ()) (line ()) (character ()) withDecl)
  else if meth = "textDocument/prepareRename" then
    respond st id (renameRange st (docPath ()) (line ()) (character ()))
  else if meth = "textDocument/rename" then
    let newName = Rpc.text (Rpc.field "newName" ps)
    if not (validName newName) then
      failWith st id -32602 $"'{newName}' isn't a name: a letter or _, then letters, digits and _, and not a keyword"
    else
      match renameTarget st (docPath ()) (line ()) (character ()) with
      | Ok(h, all) -> respond st id (renameEdits st h all newName)
      | Error why -> failWith st id -32602 why
  else if meth = "textDocument/signatureHelp" then
    respond st id (signatureHelp st (docPath ()) (line ()) (character ()))
  else if meth = "textDocument/codeAction" then
    let diags = Rpc.at [ "context"; "diagnostics" ] ps
    respond st id (codeActions st (docPath ()) (Rpc.intOf (Rpc.at [ "range"; "start"; "line" ] ps)) (Rpc.intOf (Rpc.at [ "range"; "end"; "line" ] ps)) diags)
  else if meth = "textDocument/completion" then
    respond st id (completion st (docPath ()) (line ()) (character ()))
  else if meth = "textDocument/formatting" then
    // one edit replacing the whole document; none if it doesn't parse
    let src = sourceOf st (docPath ())
    let (formatted, _) = Diag.Report.collect (fun () -> Syntax.Format.format 0 "" src)
    match formatted with
    | Ok f when f <> src -> respond st id (JArray [ JObject [ ("range", range 0 0 (List.length (String.split "\n" src)) 0); ("newText", JString f) ] ])
    | _ -> respond st id (JArray [])
  else if meth = "textDocument/rangeFormatting" then
    // the declarations and statements the range touches, formatted: one edit over their lines;
    // none if they're formatted or the document doesn't parse
    let src = sourceOf st (docPath ())
    let first = Rpc.intOf (Rpc.at [ "range"; "start"; "line" ] ps) + 1
    let last = Rpc.intOf (Rpc.at [ "range"; "end"; "line" ] ps) + 1
    let (r, _) = Diag.Report.collect (fun () -> Syntax.Format.formatRange src first last)
    match r with
    | Some(a, b, text) ->
      let lines = Array.ofList (String.split "\n" src)
      respond st id (JArray [ JObject [ ("range", range (a - 1) 0 (b - 1) (chars lines.[b - 1])); ("newText", JString text) ] ])
    | None -> respond st id (JArray [])
  else if meth = "shutdown" then
    respond st id JNull
  else if meth = "exit" then
    running <- false
  else if id <> JNull then
    failWith st id -32601 "method not found"
  running

/// Serves the editor on standard input (`input`) and output until it says exit (or the input
/// ends). `first`: a header line protocol detection already read.
let serve (input: IO.Reader) (first: option<string>) : int =
  let st : State = { texts = ref Map.empty; results = ref Map.empty; madeOf = ref Map.empty; docCache = ref Map.empty; out = Console.openStandardOutput () }
  let mutable pending = first
  let mutable running = true
  while running do
    match Rpc.readMessage input pending with
    | None -> running <- false
    | Some msg ->
      pending <- None
      running <- answer st msg
  0
