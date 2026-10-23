/// The lexer: a source's tokens, with the offside rule's layout tokens, as the F# compiler makes
/// them (one tree for both). A line deeper than its block opens one (Indent), a shallower one
/// closes blocks (Dedent), and one at the block's indentation is a Newline. Inside brackets, a
/// line ending in `->` (or `then`, `else`, `do`, a builder's `{`) and a deeper line after it open
/// a block too, which the closing bracket ends, and a new line inside `{ }` or `[ ]` is a `;`.
/// A line starting with `|>` or an infix custom operator goes on with the line before.
/// `Upper.name` is one identifier. A mistake is reported and lexing goes on.
open Token
open Diag.Diagnostic
open Diag.Report

let private isDigit (c: int) = c >= 48 && c <= 57

let private isUpper (c: int) = c >= 65 && c <= 90

// a letter: ASCII's, and any byte of a character beyond it
let private isLetter (c: int) = (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c >= 128

let private isIdent (c: int) = isLetter c || isDigit c || c = 95

/// One of the characters operators are made of: ! % & * + - . / < = > ? @ ^ | ~ $
let isOpChar (c: int) =
  match c with
  | 33
  | 36
  | 37
  | 38
  | 42
  | 43
  | 45
  | 46
  | 47
  | 60
  | 61
  | 62
  | 63
  | 64
  | 94
  | 124
  | 126 -> true
  | _ -> false

// the byte at i as a number, or -1 past the end
let private at (s: string) (i: int) = if i < String.length s then int (String.byte s i) else -1

/// Where the run of operator characters from i ends, stopping at a `//` comment or a `$"…"`.
let opRunEnd (s: string) (i: int) (stop: int) =
  let mutable j = i
  while j < stop && isOpChar (at s j) && not (at s j = 47 && at s (j + 1) = 47) && not (at s j = 36 && at s (j + 1) = 34) do
    j <- j + 1
  j

/// A custom operator: operator characters that aren't one of the language's symbols, such as
/// `>>=`, `<|>` or `.>>`.
let isCustomOp (op: string) =
  op <> "" && Option.isNone (symbol op) && String.trimStart (String.replace op "." "") <> ""

/// A prefix operator: a custom one starting with `!` (but not `!=`) or `~`: `!r`, `~~x`.
let isPrefixOp (op: string) =
  isCustomOp op && ((String.startsWith "!" op && not (String.startsWith "!=" op)) || String.startsWith "~" op)

/// A custom operator written between its operands.
let isInfixOp (op: string) = isCustomOp op && not (isPrefixOp op)

// a line starting with |> or an infix custom operator goes on with the one before
let private continuesLine (s: string) (i: int) (stop: int) =
  let op = String.sub s i (opRunEnd s i stop - i)
  String.startsWith "|>" op || isInfixOp op

// the digits a literal in this radix may have
let private isDigitIn (radix: int) (c: int) =
  if radix = 16 then isDigit c || (c >= 97 && c <= 102) || (c >= 65 && c <= 70)
  else c >= 48 && c < 48 + radix

/// The tokens of a source, ending in Eof.
let lex (src: Source.Source) : array<Token> =
  let s = src.text
  let n = String.length s
  let toks = Buffer.empty
  let indents = Buffer.ofArray [| 0 |]
  let brackets = Buffer.empty
  // per bracket: the indentation of the blocks open inside it
  let frames: Buffer<Buffer<int>> = Buffer.empty
  let mutable lastIndent = 0
  // a string that spans lines ends on resumeLine, and lexing goes on at resumeAt there
  let mutable resumeLine = -1
  let mutable resumeAt = 0
  let mutable first = true
  let lines = Array.length src.lines

  let report (at: int) (length: int) (message: string) = Report.diagnostic (error { file = src.file; offset = at; length = length } message)

  for li in 0 .. lines - 1 do
    let ls = src.lines.[li]
    let le = if li + 1 < lines then src.lines.[li + 1] - 1 else n
    let mutable i = ls
    let inString = resumeLine >= 0 && li < resumeLine
    let resuming = resumeLine >= 0 && li = resumeLine

    if resuming then
      resumeLine <- -1

    while i < le && at s i = 32 do
      i <- i + 1

    let blank = i >= le || (at s i = 47 && at s (i + 1) = 47) || inString || resuming
    let col = i - ls
    let last () = toks.[Buffer.length toks - 1].kind

    if not blank && Buffer.length brackets = 0 && not (continuesLine s i le) then
      if at s i = 9 then
        report i 1 "tabs are not allowed for indentation"

      if first then
        if col <> 0 then
          report i 1 "top-level declarations must start at column 1"
        first <- false
      else if col > indents.[Buffer.length indents - 1] then
        Buffer.push col indents
        Buffer.push { kind = Indent; offset = i; length = 0 } toks
      else
        while col < indents.[Buffer.length indents - 1] do
          Buffer.pop indents |> ignore
          Buffer.push { kind = Dedent; offset = i; length = 0 } toks
        if col <> indents.[Buffer.length indents - 1] then
          report i 1 "inconsistent indentation"
        Buffer.push { kind = Newline; offset = i; length = 0 } toks
    else if not blank && Buffer.length brackets > 0 && not (continuesLine s i le) then
      let frame = frames.[Buffer.length frames - 1]
      let c = at s i
      let closer = c = 41 || c = 125 || c = 93 || (c = 124 && at s (i + 1) = 93)

      if not closer then
        let opensBlock =
          match last () with
          | Arrow
          | Then
          | Else
          | Do -> true
          // `task {` ending a line: a computation expression's body, a block
          | LBrace -> Buffer.length toks > 1 && toks.[Buffer.length toks - 2].kind = Id
          | _ -> false

        // a block inside the bracket, as at the top level: (fun x -> and a deeper line
        if Buffer.length frame = 0 && opensBlock && col > lastIndent then
          Buffer.push col frame
          Buffer.push { kind = Indent; offset = i; length = 0 } toks
        else if Buffer.length frame > 0 then
          if col > frame.[Buffer.length frame - 1] then
            Buffer.push col frame
            Buffer.push { kind = Indent; offset = i; length = 0 } toks
          else
            while Buffer.length frame > 0 && col < frame.[Buffer.length frame - 1] do
              Buffer.pop frame |> ignore
              Buffer.push { kind = Dedent; offset = i; length = 0 } toks
            if Buffer.length frame > 0 then
              if col <> frame.[Buffer.length frame - 1] then
                report i 1 "inconsistent indentation"
              Buffer.push { kind = Newline; offset = i; length = 0 } toks

        // outside such blocks, a new line inside { } or [ ] separates items
        let b = brackets.[Buffer.length brackets - 1]
        if Buffer.length frame = 0 && (b = 123 || b = 91) then
          match last () with
          | Semi
          | LBrace
          | LBrack
          | LBrackBar
          | With -> ()
          | _ -> Buffer.push { kind = Semi; offset = i; length = 0 } toks

    if not blank then
      lastIndent <- col

    if inString then
      i <- le
    else if resuming then
      i <- resumeAt

    while i < le do
      let c = at s i
      let start = i

      if c = 32 then
        i <- i + 1
      else if c = 47 && at s (i + 1) = 47 then
        i <- le
      else if c = 48 && i + 2 < le && (at s (i + 1) = 120 || at s (i + 1) = 88 || at s (i + 1) = 98 || at s (i + 1) = 66 || at s (i + 1) = 111 || at s (i + 1) = 79) then
        // 0xFF, 0b1010, 0o17, with _ separators
        let r = at s (i + 1)
        let radix = if r = 120 || r = 88 then 16 else if r = 98 || r = 66 then 2 else 8
        i <- i + 2
        let digits = i
        while i < le && (isDigitIn radix (at s i) || at s i = 95) do
          i <- i + 1
        if i = digits then
          report start (i - start) $"expected digits after 0{String.sub s (start + 1) 1}"
        else if i < le && isIdent (at s i) then
          report i 1 $"'{String.sub s i 1}' isn't a digit in base {radix}"
        Buffer.push { kind = Int; offset = start; length = i - start } toks
      else if isDigit c then
        while i < le && (isDigit (at s i) || at s i = 95) do
          i <- i + 1
        if i + 1 < le && at s i = 46 && isDigit (at s (i + 1)) then
          i <- i + 1
          while i < le && (isDigit (at s i) || at s i = 95) do
            i <- i + 1
          if i < le && (at s i = 101 || at s i = 69) then
            i <- i + 1
            if i < le && (at s i = 45 || at s i = 43) then
              i <- i + 1
            while i < le && isDigit (at s i) do
              i <- i + 1
          Buffer.push { kind = Float; offset = start; length = i - start } toks
        else
          Buffer.push { kind = Int; offset = start; length = i - start } toks
      else if c = 39 && i + 2 < le && (at s (i + 1) = 92 || at s (i + 2) = 39 || (at s (i + 1) >= 192 && i + 3 < le && at s (i + 1 + (if at s (i + 1) >= 240 then 4 else if at s (i + 1) >= 224 then 3 else 2)) = 39)) then
        // a character literal: 'a', '\n', '\u{e9}', 'é' (a type variable 'a has no closing quote)
        i <- i + 1
        if at s i = 92 then
          i <- i + 2
          while i < le && at s i <> 39 do
            i <- i + 1
        else
          i <- i + 1
          while i < le && (at s i &&& 0xC0) = 0x80 do
            i <- i + 1
        if at s i <> 39 then
          report start (i - start) "a character literal holds one character: 'a'"
        else
          i <- i + 1
        Buffer.push { kind = Char; offset = start; length = i - start } toks
      else if c = 39 && i + 1 < le && isLetter (at s (i + 1)) then
        i <- i + 1
        while i < le && isIdent (at s i) do
          i <- i + 1
        Buffer.push { kind = TyVar; offset = start; length = i - start } toks
      else if c = 96 && at s (i + 1) = 96 then
        // ``name``: a name that may be a keyword (Parallel.``for``)
        i <- i + 2
        while i + 1 < le && not (at s i = 96 && at s (i + 1) = 96) do
          i <- i + 1
        if i + 1 >= le then
          report start (le - start) "unterminated ``name``"
          i <- le
        else
          i <- i + 2
        Buffer.push { kind = Id; offset = start; length = i - start } toks
      else if isLetter c || c = 95 then
        while i < le && isIdent (at s i) do
          i <- i + 1
        while isUpper (at s start) && i + 1 < le && at s i = 46 && isLetter (at s (i + 1)) do
          i <- i + 1
          while i < le && isIdent (at s i) do
            i <- i + 1
        Buffer.push { kind = keyword (String.sub s start (i - start)); offset = start; length = i - start } toks
      else if c = 34 || (c = 36 && at s (i + 1) = 34) then
        let interp = c = 36
        let triple = not interp && at s (i + 1) = 34 && at s (i + 2) = 34
        i <- i + (if interp then 2 else if triple then 3 else 1)
        // the string goes on over line breaks until its closing quote
        let mutable closed = false
        while not closed && i < n do
          let d = at s i
          if triple then
            if d = 34 && at s (i + 1) = 34 && at s (i + 2) = 34 then
              closed <- true
              i <- i + 3
            else
              i <- i + 1
          else if d = 34 then
            closed <- true
            i <- i + 1
          else if d = 92 && i + 1 < n then
            i <- i + 2
          else if interp && d = 123 && at s (i + 1) = 123 then
            i <- i + 2
          else if interp && d = 125 && at s (i + 1) = 125 then
            i <- i + 2
          else if interp && d = 123 then
            // a hole, which may hold braces itself: {f { x = 1 }}; it ends on its line
            let hole = i
            let mutable depth = 0
            i <- i + 1
            while i < n && at s i <> 10 && (at s i <> 125 || depth > 0) do
              if at s i = 123 then depth <- depth + 1 else if at s i = 125 then depth <- depth - 1
              i <- i + 1
            if i >= n || at s i = 10 then
              report hole 1 "unterminated '{' in interpolated string"
            else
              i <- i + 1
          else
            i <- i + 1
        if not closed then
          report start 1 "unterminated string literal"
        Buffer.push { kind = (if interp then Interp else Str); offset = start; length = i - start } toks
        if i > le then
          // it ended on a later line: lexing goes on after the closing quote there
          resumeLine <- Source.lineOf src i
          resumeAt <- i
          if resumeLine = li then
            resumeLine <- -1
          i <- le
      else
        let two = if i + 1 < le then String.sub s i 2 else ""
        let kind, length =
          if two = "|]" then
            (BarRBrack, 2)
          else if two = ">]" then
            (GtRBrack, 2)
          else if isOpChar c then
            // the longest run of operator characters: a symbol, or a custom operator
            let stop = opRunEnd s i le
            let run = String.sub s i (stop - i)
            // a symbol and then the sign of its operand: x=-1, a*-b (but not (<+) or (++))
            let signed = String.endsWith "-" run || String.endsWith "+" run
            let len =
              if (String.length run > 1 && signed && Option.isSome (symbol (String.sub run 0 (String.length run - 1)))
                  && stop < le && (isIdent (at s stop) || at s stop = 40)) then
                String.length run - 1
              else
                String.length run
            let op = String.sub s i len
            match symbol op with
            | Some k -> (k, len)
            | None -> (Op, len)
          else
            match c with
            | 40 -> (LParen, 1)
            | 41 -> (RParen, 1)
            | 123 -> (LBrace, 1)
            | 125 -> (RBrace, 1)
            | 91 when at s (i + 1) = 124 -> (LBrackBar, 2)
            | 91 when at s (i + 1) = 60 -> (LBrackLt, 2)
            | 91 -> (LBrack, 1)
            | 93 -> (RBrack, 1)
            | 44 -> (Comma, 1)
            | 59 -> (Semi, 1)
            | 58 when at s (i + 1) = 58 -> (Cons, 2)
            | 58 -> (Colon, 1)
            | _ -> (Bad, 1)

        // F#: `f -x` (a space before, none after, following an operand) negates an argument
        let afterOperand =
          if Buffer.length toks = 0 then
            false
          else
            match last () with
            | Id
            | Int
            | Float
            | Str
            | RParen
            | RBrack
            | BarRBrack -> true
            | _ -> false
        let negates = kind = Minus && i > ls && at s (i - 1) = 32 && i + 1 < le && at s (i + 1) <> 32 && afterOperand

        match kind with
        | LParen
        | LBrace
        | LBrack ->
          Buffer.push c brackets
          Buffer.push Buffer.empty frames
        | LBrackBar
        | LBrackLt ->
          Buffer.push 40 brackets
          Buffer.push Buffer.empty frames
        | RParen
        | RBrace
        | RBrack
        | BarRBrack
        | GtRBrack when Buffer.length brackets > 0 ->
          // the blocks opened inside the bracket end with it
          let frame = frames.[Buffer.length frames - 1]
          for _ in 1 .. Buffer.length frame do
            Buffer.push { kind = Dedent; offset = i; length = 0 } toks
          Buffer.pop frames |> ignore
          Buffer.pop brackets |> ignore
        | Bad -> report i 1 $"unexpected character '{String.sub s i 1}'"
        | _ -> ()

        i <- i + length
        Buffer.push { kind = (if negates then Negate else kind); offset = start; length = length } toks

  for _ in 2 .. Buffer.length indents do
    Buffer.push { kind = Dedent; offset = n; length = 0 } toks

  Buffer.push { kind = Eof; offset = n; length = 0 } toks
  Buffer.toArray toks
