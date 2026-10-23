/// zs fmt (decision 33): one canonical layout, no options. Each line keeps the breaks it was
/// written with and is re-indented from the block structure (2 spaces a level; lines inside
/// brackets one level past their opener's line), spaced the same way everywhere, trimmed, with at
/// most one blank line between; comments stay where they are. A line over 100 columns is then
/// broken on the syntax tree (0019), outermost construct first: after a binding's `=` or a
/// lambda's `->`, at an `if`'s branches, before a pipeline's `|>`, between a match's clauses and
/// between the items of a tuple, list, array or record. String literals and comments never
/// break, so a line long because of one stays long. A break is kept only when the program parses
/// to the same tree, so formatting can't change what a program means.
open Token
open Diag.Diagnostic
open Diag.Report

/// The width a line is broken to fit.
let width = 100

// ------------------------------------------------------------ tokens as the layout sees them

// what the layout knows of a source's tokens: each one's text (its first line), line, last line
// (a string can span lines), column (in characters) and whether it's against the one before
type private Laid =
  { texts: array<string>
    lineNos: array<int>
    lastNos: array<int>
    cols: array<int>
    adjs: array<bool> }

// characters in a part of a string (UTF-8: the bytes that start one)
let private charsIn (s: string) (from: int) (stop: int) : int =
  let mutable n = 0
  for i in from .. stop - 1 do
    if (String.byte s i &&& u8 0xC0) <> u8 0x80 then
      n <- n + 1
  n

let private laidOf (src: Source.Source) (toks: array<Token>) : Laid =
  let s = src.text
  let n = Array.length toks
  let mutable texts = Array.create n ""
  let mutable lines = Array.create n 0
  let mutable lasts = Array.create n 0
  let mutable cols = Array.create n 0
  let mutable adjs = Array.create n false
  for i in 0 .. n - 1 do
    let t = toks.[i]
    let li = Source.lineOf src t.offset
    let start = src.lines.[li]
    let text = Token.text s t
    let firstLine =
      match String.indexOf "\n" text with
      | Some k -> String.sub text 0 k
      | None -> text
    texts.[i] <- firstLine
    lines.[i] <- li + 1
    lasts.[i] <- (if t.length > 0 then Source.lineOf src (t.offset + t.length - 1) + 1 else li + 1)
    cols.[i] <- charsIn s start t.offset + 1
    adjs.[i] <- t.offset > start && String.byte s (t.offset - 1) <> u8 32
  { texts = texts; lineNos = lines; lastNos = lasts; cols = cols; adjs = adjs }

// a symbol's or a keyword's text (an identifier's or a literal's is "")
let private symText (k: Kind) (text: string) : string =
  match k with
  | Int
  | Float
  | Str
  | Interp
  | Id
  | TyVar
  | Char
  | Bad
  | Newline
  | Indent
  | Dedent
  | Eof -> ""
  | Negate -> "~-"
  | _ -> text

let private isOpener (s: string) = s = "(" || s = "[" || s = "[|" || s = "{" || s = "[<"

let private isCloser (s: string) = s = ")" || s = "]" || s = "|]" || s = "}" || s = ">]"

// where spacing carries meaning (f(x) vs f (x), f -x, 9.58<s>, x?, list<int>, let!) or is a
// matter of taste the source already settled, it stays as written
let private asWritten (s: string) =
  match s with
  | "("
  | ")"
  | "<"
  | ">"
  | "."
  | "?"
  | "^"
  | "|"
  | "~-"
  | ">>"
  | ":"
  | "<-"
  | "!" -> true
  | _ -> false

let private isOperand (k: Kind) : bool =
  match k with
  | Id
  | Int
  | Float
  | Str
  | Interp
  | TyVar
  | True
  | False
  | RParen
  | RBrack
  | BarRBrack
  | RBrace
  | GtRBrack -> true
  | _ -> false

/// The `//` comment on each line (from 1), "" where there's none: the text between tokens holds
/// only spaces and comments.
let private commentsOf (src: Source.Source) (toks: array<Token>) : array<string> =
  let s = src.text
  let mutable found = Array.create (Array.length src.lines + 2) ""
  let mutable from = 0
  for t in toks do
    let mutable i = from
    while i + 1 < t.offset do
      if String.byte s i = u8 47 && String.byte s (i + 1) = u8 47 then
        let mutable j = i
        while j < t.offset && String.byte s j <> u8 10 do
          j <- j + 1
        found.[Source.lineOf src i + 1] <- String.trimEnd (String.sub s i (j - i))
        i <- j
      else
        i <- i + 1
    from <- max from (t.offset + t.length)
  found

// ------------------------------------------------------------ the layout

/// Each line as written, laid out: its indentation from the blocks and brackets it is in, its
/// tokens spaced, its comment; at most one blank line between.
let private layout (text: string) (toks: array<Token>) : string =
  let src = Source.make 0 "" text
  let n = Array.length src.lines
  let laid = laidOf src toks
  let commentAt = commentsOf src toks
  // each code line: its level, and its tokens (from first to last; some in between are layout)
  let mutable levels = Array.create (n + 2) (-1)
  let mutable firsts = Array.create (n + 2) (-1)
  let mutable lasts = Array.create (n + 2) (-1)
  // the lines after the first of a string that spans lines are its text: they stay as written
  let mutable verbatim = Array.create (n + 2) false
  for i in 0 .. Array.length toks - 1 do
    for l in laid.lineNos.[i] + 1 .. laid.lastNos.[i] do
      verbatim.[l] <- true
  let mutable depth = 0
  let mutable current = -1
  let mutable lastLine = 0
  // each open bracket: the line it opened on, whether a block opened inside it yet, and whether
  // that block took the bracket's level, so `(fun x ->` with its body below is one level in,
  // not two
  let openLines = Buffer.empty
  let framed = Buffer.empty
  let took = Buffer.empty
  let mutable absorbed = 0
  for i in 0 .. Array.length toks - 1 do
    let t = toks.[i]
    match t.kind with
    | Indent ->
      depth <- depth + 1
      let top = Buffer.length openLines - 1
      if top >= 0 && not framed.[top] then
        framed.[top] <- true
        if openLines.[top] = lastLine then
          took.[top] <- true
          absorbed <- absorbed + 1
    | Dedent -> depth <- depth - 1
    | _ when verbatim.[laid.lineNos.[i]] || t.length = 0 -> ()
    | _ ->
      let line = laid.lineNos.[i]
      let s = symText t.kind laid.texts.[i]
      if line <> current then
        current <- line
        // a closer lines up with its opener's line, unless a block took its level
        let top = Buffer.length openLines - 1
        let closesOwnLevel = isCloser s && top >= 0 && not took.[top]
        levels.[line] <- depth + Buffer.length openLines - absorbed - (if closesOwnLevel then 1 else 0)
        firsts.[line] <- i
      lasts.[line] <- i
      lastLine <- line
      if isOpener s then
        Buffer.push line openLines
        Buffer.push false framed
        Buffer.push false took
      else if isCloser s && Buffer.length openLines > 0 then
        Buffer.removeLast openLines |> ignore
        Buffer.removeLast framed |> ignore
        if Buffer.removeLast took then
          absorbed <- absorbed - 1

  let levels = levels
  let firsts = firsts
  let lasts = lasts
  let verbatim = verbatim
  // tight: inside a.[i] or between < > of type arguments and measures, where spacing stays as written
  let space (prev: int) (cur: int) (unaryMinus: bool) (tight: bool) : string =
    let p = symText toks.[prev].kind laid.texts.[prev]
    let c = symText toks.[cur].kind laid.texts.[cur]
    if unaryMinus then ""
    else if tight || asWritten p || asWritten c || Lexer.isPrefixOp p then (if laid.adjs.[cur] then "" else " ")
    else if isOpener p && isCloser c then ""
    else if p = "[<" || c = ">]" then ""
    else if isOpener p || isCloser c then " "
    else if c = "," || c = ";" then ""
    else " "

  let render (line: int) : string =
    let parts = Buffer.empty
    Buffer.push (String.repeat (2 * levels.[line]) " ") parts
    let mutable prev = -1
    let mutable unaryNext = false
    // open a.[ … ] and f64< … > groups on this line
    let mutable tight = 0
    for i in firsts.[line] .. lasts.[line] do
      if toks.[i].length > 0 && laid.lineNos.[i] = line then
        let text = laid.texts.[i]
        if prev >= 0 then
          Buffer.push (space prev i unaryNext (tight > 0)) parts
        Buffer.push text parts
        if (text = "]" || text = ">") && tight > 0 then
          tight <- tight - 1
        if prev >= 0 && laid.texts.[prev] = "." && text = "[" then
          tight <- tight + 1
        else if prev >= 0 && text = "<" && laid.adjs.[i] then
          tight <- tight + 1
        // a '-' that doesn't follow an operand is a negation: nothing between it and its operand
        unaryNext <- text = "-" && (prev < 0 || not (isOperand toks.[prev].kind))
        prev <- i
    String.concat (Array.toList (Buffer.toArray parts))

  let lineText (l: int) : string =
    let from = src.lines.[l - 1]
    let stop = if l < n then src.lines.[l] - 1 else String.length text
    String.sub text from (stop - from)

  let nextLevel (from: int) : int =
    let mutable l = from
    while l <= n && levels.[l] < 0 do
      l <- l + 1
    if l <= n then levels.[l] else 0

  let out = Buffer.empty
  let mutable blank = 0
  for l in 1 .. n do
    let line =
      if verbatim.[l] then Some(lineText l)
      else if levels.[l] >= 0 && commentAt.[l] <> "" then Some(render l + " " + commentAt.[l])
      else if levels.[l] >= 0 then Some(render l)
      else if commentAt.[l] <> "" then Some(String.repeat (2 * nextLevel l) " " + commentAt.[l])
      else None
    match line with
    | Some t ->
      if blank > 0 && Buffer.length out > 0 then
        Buffer.push "" out
      blank <- 0
      Buffer.push t out
    | None -> blank <- blank + 1
  String.join "\n" (Array.toList (Buffer.toArray out)) + "\n"

// ------------------------------------------------------------ the tree's shape and its breaks

/// The tree without what layout decides: layout tokens, `;` (a line break is one inside [ ] and
/// { }) and blocks (a body below its `=` rather than beside it), so two layouts of one program
/// have the same shape, and a break that changed the program doesn't.
let private shape (src: string) (t: Tree.Tree) : list<string> =
  let acc = Buffer.empty
  let rec go (n: int) =
    let block = t.kinds.[n] = Tree.Block
    if not block then
      Buffer.push ("(" + Tree.name t.kinds.[n]) acc
    for i in 0 .. t.counts.[n] - 1 do
      let c = Tree.child t n i
      if c >= 0 then
        go c
      else
        let tok = t.tokens.[-1 - c]
        if tok.length > 0 && tok.kind <> Semi then
          Buffer.push (Token.text src tok) acc
    if not block then
      Buffer.push ")" acc
  go (Tree.root t)
  Array.toList (Buffer.toArray acc)

// the first and the last token with text in a node (-1 for none)
let rec private firstWritten (t: Tree.Tree) (n: int) : int =
  let mutable found = -1
  let mutable i = 0
  while found < 0 && i < t.counts.[n] do
    let c = Tree.child t n i
    found <- (if c >= 0 then firstWritten t c else if t.tokens.[-1 - c].length > 0 then -1 - c else -1)
    i <- i + 1
  found

let rec private lastWritten (t: Tree.Tree) (n: int) : int =
  let mutable found = -1
  let mutable i = t.counts.[n] - 1
  while found < 0 && i >= 0 do
    let c = Tree.child t n i
    found <- (if c >= 0 then lastWritten t c else if t.tokens.[-1 - c].length > 0 then -1 - c else -1)
    i <- i - 1
  found

// a break: the token whose end it starts from, the token the next line starts with, and
// whether that line is a level deeper (a block) or at its line's own level
type private Break = { from: int; next: int; deeper: bool }

/// Where a node may break: before which written tokens, and whether the breaks are of the
/// program's structure, taken whenever they parse, or between a bracket's items, taken only when
/// every line they make fits. Z#'s offside rule allows no other: a call's arguments can't
/// continue on the next line outside brackets.
let rec private breaks (src: string) (t: Tree.Tree) (n: int) : list<Break> * bool =
  let count = t.counts.[n]
  let child (k: int) = Tree.child t n k
  // the first written token of child k, and the last written token before child k
  let written (k: int) =
    let c = child k
    if c >= 0 then firstWritten t c else if t.tokens.[-1 - c].length > 0 then -1 - c else -1
  let before (k: int) =
    let mutable found = -1
    let mutable j = k - 1
    while found < 0 && j >= 0 do
      let c = child j
      found <- (if c >= 0 then lastWritten t c else if t.tokens.[-1 - c].length > 0 then -1 - c else -1)
      j <- j - 1
    found
  let isTok (s: string) (k: int) =
    let c = child k
    c < 0 && Token.text src t.tokens.[-1 - c] = s
  let isLayout (k: int) =
    let c = child k
    c < 0 && t.tokens.[-1 - c].length = 0
  let atLevel (deeper: bool) (k: int) : list<Break> =
    let p = before k
    let w = written k
    if p >= 0 && w >= 0 then [ { from = p; next = w; deeper = deeper } ] else []
  let after (s: string) : list<Break> =
    List.concat [ for k in 1 .. count - 1 do if isTok s (k - 1) && not (isLayout k) then yield atLevel true k ]
  let isNode (kind: Tree.Kind) (k: int) =
    let c = child k
    c >= 0 && t.kinds.[c] = kind
  match t.kinds.[n] with
  | Tree.Let
  | Tree.Member
  | Tree.Use
  | Tree.LetBang -> (after "=", true)
  | Tree.Lambda
  | Tree.Clause -> (after "->", true)
  | Tree.If ->
    // the branches, and `else` on its own line; an `else if` stays on one line, and its `if`
    // breaks with this one
    let found =
      [ for k in 1 .. count - 1 do
          if isTok "then" (k - 1) then
            yield atLevel true k
          else if isTok "else" k then
            yield atLevel false k
          else if isTok "else" (k - 1) then
            if isNode Tree.If k then yield fst (breaks src t (child k)) else yield atLevel true k ]
    (List.concat found, true)
  | Tree.Infix ->
    // before a pipeline's |> or a custom operator: a line starting with one continues the line
    // before
    let found =
      [ for k in 1 .. count - 1 do
          let c = child k
          if c < 0 && (t.tokens.[-1 - c].kind = PipeRight || (t.tokens.[-1 - c].kind = Op && Lexer.isInfixOp (Token.text src t.tokens.[-1 - c]))) then
            yield atLevel false k ]
    (List.concat found, true)
  | Tree.Match
  | Tree.Function
  | Tree.Handle -> (List.concat [ for k in 1 .. count - 1 do if isNode Tree.Clause k then yield atLevel false k ], true)
  | Tree.Tuple -> (after ",", false)
  // a line break inside [ ] and { } is a `;`; inside [| |] it's only space, so the `;` stays
  | Tree.List
  | Tree.Record ->
    let found =
      [ for k in 2 .. count - 1 do
          if isTok ";" (k - 1) && not (isLayout k) then
            let p = before (k - 1)
            let w = written k
            if p >= 0 && w >= 0 then
              yield { from = p; next = w; deeper = true } ]
    (found, false)
  | Tree.Array -> (after ";", false)
  | _ -> ([], true)

// ------------------------------------------------------------ reflow

// a text's tokens and tree, what's wrong with them dropped (a trial's)
let private parsed (text: string) : Source.Source * array<Token> * Tree.Tree * int =
  let src = Source.make 0 "" text
  let (toks, ld) = collect (fun () -> Lexer.lex src)
  let (tree, pd) = collect (fun () -> Parser.parse src toks)
  (src, toks, tree, Array.length ld + Array.length pd)

// the lines of a text, as String.split gives them
let private linesOf (text: string) : array<string> = Array.ofList (String.split "\n" text)

/// Breaks the lines of a laid-out text that are over the width, outermost construct first (and
/// only one that runs past the width, as a Wadler group breaks), keeping each break only when the
/// text still parses to the same shape.
let private reflow (start: string) (expected: list<string>) : string =
  let mutable text = start
  let mutable rejected: list<list<int>> = []
  let mutable go = true
  while go do
    let (src, _, tree, _) = parsed text
    let s = src.text
    let nLines = Array.length src.lines
    let count = Array.length tree.tokens
    // each token's line and the column it ends at
    let mutable lineOf = Array.create count 0
    let mutable lastOf = Array.create count 0
    let mutable endOf = Array.create count 0
    let mutable colOf = Array.create count 0
    let mutable adjOf = Array.create count false
    for i in 0 .. count - 1 do
      let tk = tree.tokens.[i]
      let li = Source.lineOf src tk.offset
      let start = src.lines.[li]
      lineOf.[i] <- li + 1
      lastOf.[i] <- (if tk.length > 0 then Source.lineOf src (tk.offset + tk.length - 1) + 1 else li + 1)
      colOf.[i] <- charsIn s start tk.offset + 1
      endOf.[i] <- colOf.[i] - 1 + charsIn s tk.offset (tk.offset + tk.length)
      adjOf.[i] <- tk.offset > start && String.byte s (tk.offset - 1) <> u8 32
    // each line's code width (a line holding a string that spans lines is left alone), and its
    // first written token
    let mutable widthOf = Array.create (nLines + 2) 0
    let mutable multi = Array.create (nLines + 2) false
    let mutable firstOn = Array.create (nLines + 2) (-1)
    for i in 0 .. tree.lexed - 1 do
      if tree.tokens.[i].length > 0 then
        let l = lineOf.[i]
        if lastOf.[i] > l then
          multi.[l] <- true
        widthOf.[l] <- max widthOf.[l] endOf.[i]
        if firstOn.[l] < 0 then
          firstOn.[l] <- i
    let lineOf = lineOf
    let lastOf = lastOf
    let endOf = endOf
    let colOf = colOf
    let adjOf = adjOf
    let widthOf = widthOf
    let multi = multi
    let firstOn = firstOn
    // the candidates on a line: each node's breaks there, outermost first, of the nodes that
    // run past the width on it
    let candidates (line: int) : list<list<Break> * bool> =
      let found = Buffer.empty
      let rec walk (n: int) (depth: int) =
        // how far the node reaches on the line, and whether it goes on past it
        let reach = ref 0
        let continues = ref false
        let rec scan (m: int) =
          for i in 0 .. tree.counts.[m] - 1 do
            let c = Tree.child tree m i
            if c >= 0 then
              scan c
            else
              let k = -1 - c
              if tree.tokens.[k].length > 0 then
                if lineOf.[k] = line then
                  reach.Value <- max reach.Value endOf.[k]
                else if lineOf.[k] > line then
                  continues.Value <- true
        scan n
        if reach.Value > width || (continues.Value && widthOf.[line] > width && reach.Value > 0) then
          let (points, structural) = breaks s tree n
          // never before a token written against the one before it: f(x), x?, a.[i]
          let here =
            points
            |> List.filter (fun b ->
              lineOf.[b.next] = line && lineOf.[b.from] = line && firstOn.[line] >= 0 && tree.tokens.[firstOn.[line]].offset <> tree.tokens.[b.next].offset && not adjOf.[b.next])
          if not (List.isEmpty here) then
            Buffer.push (depth, (here, structural)) found
          for i in 0 .. tree.counts.[n] - 1 do
            let c = Tree.child tree n i
            if c >= 0 then
              walk c (depth + 1)
      walk (Tree.root tree) 0
      Array.toList (Buffer.toArray found) |> List.sortBy fst |> List.map snd
    let attempt (line: int) (cut: list<Break>) (structural: bool) : option<string> =
      let parts = Buffer.empty
      let mutable from = 0
      for b in List.sortBy (fun b -> tree.tokens.[b.next].offset) cut do
        // the new line's indentation: the lexer reads a block from it
        let indent = colOf.[firstOn.[lineOf.[b.from]]] - 1 + (if b.deeper then 2 else 0)
        let p = tree.tokens.[b.from]
        Buffer.push (String.sub s from (p.offset + p.length - from)) parts
        Buffer.push ("\n" + String.repeat indent " ") parts
        from <- tree.tokens.[b.next].offset
      Buffer.push (String.sub s from (String.length s - from)) parts
      let broken = String.concat (Array.toList (Buffer.toArray parts))
      let (bsrc, btoks, _, berrors) = parsed broken
      if berrors > 0 then
        None
      else
        let laid = layout bsrc.text btoks
        let (_, _, after, errors) = parsed laid
        // a bracket's items break only into lines that fit
        let laidLines = linesOf laid
        let made = Array.length laidLines - Array.length (linesOf s)
        let mutable fits = true
        for k in line - 1 .. line - 1 + made do
          if k < Array.length laidLines then
            let l = laidLines.[k]
            if String.charCount l > width && not (String.startsWith "//" (String.trimStart l)) then
              fits <- false
        if errors = 0 && shape laid after = expected && (structural || fits) then Some laid else None
    let mutable next = None
    let mutable l = 1
    while Option.isNone next && l <= nLines do
      if widthOf.[l] > width && not multi.[l] then
        for (cut, structural) in candidates l do
          if Option.isNone next then
            let key = List.map (fun b -> tree.tokens.[b.next].offset) cut
            if not (List.contains key rejected) then
              next <- Some(l, cut, structural, key)
      l <- l + 1
    match next with
    | None -> go <- false
    | Some(line, cut, structural, key) ->
      match attempt line cut structural with
      | Some laid ->
        text <- laid
        rejected <- []
      | None -> rejected <- key :: rejected
  text

// the tokens' kinds and texts, the end of the file left out
let private written (src: string) (toks: array<Token>) : list<Kind * string> =
  [ for t in toks do if t.kind <> Eof then yield (t.kind, Token.text src t) ]

// a text that parses, formatted
let private formatParsed (text: string) (toks: array<Token>) (tree: Tree.Tree) : result<string, string> / <> =
  let expected = shape text tree
  let laid = layout text toks
  let (lsrc, ltoks, _, lerrors) = parsed laid
  if lerrors > 0 || written text toks <> written lsrc.text ltoks then
    Error "formatting would change the program's tokens (a zs fmt bug; the file was left alone)"
  else
    let result = reflow laid expected
    let (_, _, after, errors) = parsed result
    if errors = 0 && shape result after = expected then
      Ok result
    else
      Error "formatting would change the program (a zs fmt bug; the file was left alone)"

/// A file's text formatted. A text that doesn't parse is left alone: its errors are reported and
/// the result is an Error with no reason of its own; a formatting that would change the program
/// (a formatter's bug) is an Error saying so.
let format (file: int) (path: string) (text: string) : result<string, string> / Report =
  let src = Source.make file path text
  let (toks, ld) = collect (fun () -> Lexer.lex src)
  let (tree, pd) = collect (fun () -> Parser.parse src toks)
  if Array.length ld + Array.length pd > 0 then
    for d in Array.append ld pd do
      Report.diagnostic d
    Error ""
  else
    formatParsed src.text toks tree
