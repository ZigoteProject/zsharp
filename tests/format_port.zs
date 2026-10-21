// zs fmt in Z#: src/Format.fs and the lexer it reads (from src/Syntax.fs), ported as a first
// large piece of the compiler in its own language. It formats a messy sample and its own source,
// which must come out as the F# zs fmt formats them.
// ponytail: columns and letters are bytes and ASCII, where the F# lexer counts UTF-16 units and
// knows Unicode letters; the same on ASCII code, which is all the compiler meets outside strings

// ---------------------------------------------------------------- lexer

type Tok =
  | KInt of int
  | KFloat of f64
  | KStr of string
  | KInterp of list<bool * string * int>
  | KId of string
  | KTyVar of string
  | KChar of int
  | KKw of string
  | KSym of string
  | KNewline
  | KIndent
  | KDedent
  | KEof

// col is 1-based (0 for layout tokens); adj: no space before it; last: the line it ends on
type Token = { tok: Tok; line: int; col: int; len: int; adj: bool; last: int }

let fail ln msg = panic $"line {ln}: {msg}"

let ch (s: string) (i: int) = char (String.byte s i)

let keywords =
  Set.ofList [ "let"; "rec"; "if"; "then"; "else"; "extern"; "true"; "false"; "not"; "match"; "with"; "when"; "type"; "of"; "as"; "fun"; "for"; "in"; "do"; "while"; "mutable"; "member"; "static"; "trait"; "impl"; "abstract"; "derive"; "open"; "module"; "namespace"; "private"; "and" ]

// longest first
let symbols =
  [ "&&&"; "|||"; "^^^"; "<<<"; ">>>"; "~~~"; "..."; ".."; "->"; "<-"; "|>"; "|]"; "[|"; "[<"; ">]"; "::"; ">>"; "<>"; "<="; ">="; "&&"; "||"; "?"; "("; ")"; "{"; "}"; "["; "]"; ","; ";"; "|"; "."; ":"; "="; "<"; ">"; "+"; "-"; "*"; "/"; "%"; "@"; "^" ]

let symbolSet = Set.ofList symbols

let isOpChar (c: char) = String.contains (String.ofChar c) "!%&*+-./<=>?@^|~$"

// the run of operator characters at line.[at], stopping at a // comment or a $"…" string
let opRun (line: string) (at: int) =
  let n = String.length line
  let mutable j = at
  while j < n && isOpChar (ch line j) && not (ch line j = '/' && j + 1 < n && ch line (j + 1) = '/') && not (ch line j = '$' && j + 1 < n && ch line (j + 1) = '"') do
    j <- j + 1
  String.sub line at (j - at)

let isCustomOp (s: string) =
  s <> "" && not (Set.contains s symbolSet) && List.forall isOpChar (String.chars s) && not (List.forall (fun c -> c = '.') (String.chars s))

let isPrefixOp (s: string) =
  isCustomOp s && ((String.startsWith "!" s && not (String.startsWith "!=" s)) || String.startsWith "~" s)

let isInfixOp (s: string) = isCustomOp s && not (isPrefixOp s)

// a line starting with |> or an infix custom operator continues the previous one
let continuesLine (rest: string) =
  let run = opRun rest 0
  String.startsWith "|>" run || isInfixOp run

let hexDigit (c: char) =
  if Char.isDigit c then int c - int '0'
  else if c >= 'a' && c <= 'f' then int c - int 'a' + 10
  else if c >= 'A' && c <= 'F' then int c - int 'A' + 10
  else 99

// an escape after a backslash at line.[i]: its code point and the index after it
let unescapeAt ln (line: string) (i: int) : int * int =
  match ch line i with
  | 'n' -> (10, i + 1)
  | 'r' -> (13, i + 1)
  | 't' -> (9, i + 1)
  | '0' -> (0, i + 1)
  | '\\' -> (int '\\', i + 1)
  | '"' -> (int '"', i + 1)
  | '\'' -> (int '\'', i + 1)
  | 'u' when i + 1 < String.length line && ch line (i + 1) = '{' ->
    let close = String.indexOfFrom line "}" (i + 2)
    if close < 0 then fail ln "unterminated \\u{…} escape"
    let hex = String.sub line (i + 2) (close - i - 2)
    let mutable v = 0
    let mutable ok = hex <> "" && String.length hex <= 6
    for c in hex do
      if hexDigit c < 16 then v <- v * 16 + hexDigit c else ok <- false
    if ok && v <= 0x10FFFF && not (v >= 0xD800 && v <= 0xDFFF) then (v, close + 1)
    else fail ln $"\\u{{{hex}}} is not a Unicode scalar value"
  | c -> fail ln $"unknown escape '\\{c}'"

// the code point of the character at line.[j], and the index after it
let codeAt (line: string) (j: int) =
  let (c, after) = String.decodeAt line j
  (int c, after)

// a character literal's closing quote follows the character at line.[j]
let closesCharLit (line: string) (j: int) =
  let (_, after) = codeAt line j
  after < String.length line && ch line after = '\''

let token t ln start i (line: string) =
  { tok = t; line = ln; col = start + 1; len = max 1 (i - start); adj = start > 0 && ch line (start - 1) <> ' '; last = ln }

let lastTok (toks: list<Token>) =
  match toks with
  | t :: _ -> t.tok
  | [] -> KEof

let opensBlock tok =
  match tok with
  | KSym "->" -> true
  | KKw ("then" | "else" | "do") -> true
  | _ -> false

let endsItem tok =
  match tok with
  | KSym (";" | "{" | "[" | "[|") -> false
  | KKw "with" -> false
  | _ -> true

let followsOperandForMinus tok =
  match tok with
  | KId _ | KInt _ | KFloat _ | KStr _ -> true
  | KSym (")" | "]" | "|]") -> true
  | _ -> false

// Offside rule: KIndent / KDedent / KNewline at line starts outside brackets, and blocks inside
// them after ->, then, else and do; a new line inside { } or [ ] acts as ';'. Also returns
// every // comment: (line, column, text).
let lexComments (src: string) : array<Token> * list<int * int * string> =
  let lines = Array.ofList (String.split "\n" (String.replace src "\r\n" "\n"))
  let mutable toks = []
  let mutable comments = []
  let mutable indents = [ 0 ]
  let mutable brackets = []
  // per bracket: the indentation of the blocks open inside it (empty while there are none)
  let mutable frames = []
  let mutable lastIndent = 0
  // a string that spans lines ends here: lexing goes on at (line index, column)
  let mutable resume = None
  let mutable first = true
  for li in 0 .. Array.length lines - 1 do
    let line = lines.[li]
    let n = String.length line
    let ln = li + 1
    let mutable i = 0
    let mutable start = 0
    let mutable inString = false
    let mutable resumeCol = -1
    match resume with
    | Some (rl, _) when li < rl -> inString <- true
    | Some (rl, col) when li = rl ->
      resume <- None
      resumeCol <- col
    | _ -> ()
    while i < n && ch line i = ' ' do
      i <- i + 1
    let rest = String.sub line i (n - i)
    let blank = rest = "" || String.startsWith "//" rest || inString || resumeCol >= 0
    if not blank && List.isEmpty brackets && not (continuesLine rest) then
      if ch rest 0 = '\t' then fail ln "tabs are not allowed for indentation"
      if first then
        if i <> 0 then fail ln "top-level declarations must start at column 1"
        first <- false
      else if i > List.head indents then
        indents <- i :: indents
        toks <- token KIndent ln start i line :: toks
      else
        while i < List.head indents do
          indents <- List.tail indents
          toks <- token KDedent ln start i line :: toks
        if i <> List.head indents then fail ln "inconsistent indentation"
        toks <- token KNewline ln start i line :: toks
    else if not blank && not (List.isEmpty brackets) && not (continuesLine rest) then
      let mutable frame = List.head frames
      let closer = String.startsWith ")" rest || String.startsWith "}" rest || String.startsWith "]" rest || String.startsWith "|]" rest
      if not closer then
        // a block inside the bracket, as at the top level: (fun x -> and a deeper line
        if List.isEmpty frame && opensBlock (lastTok toks) && i > lastIndent then
          frame <- i :: frame
          toks <- token KIndent ln start i line :: toks
        else if not (List.isEmpty frame) then
          if i > List.head frame then
            frame <- i :: frame
            toks <- token KIndent ln start i line :: toks
          else
            while not (List.isEmpty frame) && i < List.head frame do
              frame <- List.tail frame
              toks <- token KDedent ln start i line :: toks
            if not (List.isEmpty frame) then
              if i <> List.head frame then fail ln "inconsistent indentation"
              toks <- token KNewline ln start i line :: toks
        // outside such blocks, a new line inside { } or [ ] separates items
        let b = List.head brackets
        if List.isEmpty frame && (b = '{' || b = '[') && endsItem (lastTok toks) then
          toks <- token (KSym ";") ln start i line :: toks
      frames <- frame :: List.tail frames
    if not blank then lastIndent <- i
    if inString then i <- n
    else if resumeCol >= 0 then i <- resumeCol
    while i < n do
      let c = ch line i
      start <- i
      if c = ' ' then i <- i + 1
      else if c = '/' && i + 1 < n && ch line (i + 1) = '/' then
        comments <- (ln, i + 1, String.sub line i (n - i)) :: comments
        i <- n
      else if c = '0' && i + 2 < n && String.contains (String.ofChar (ch line (i + 1))) "xXbBoO" then
        // 0xFF, 0b1010, 0o17 (with _ separators), wrapping to 64 bits
        let radix =
          match Char.toLower (ch line (i + 1)) with
          | 'x' -> 16
          | 'b' -> 2
          | _ -> 8
        i <- i + 2
        let s = i
        let mutable value = 0
        while i < n && (hexDigit (ch line i) < radix || ch line i = '_') do
          if ch line i <> '_' then value <- Int.wrappingAdd (Int.wrappingMul value radix) (hexDigit (ch line i))
          i <- i + 1
        if String.replace (String.sub line s (i - s)) "_" "" = "" then fail ln $"expected digits after 0{ch line (s - 1)}"
        if i < n && Char.isLetterOrDigit (ch line i) then fail ln $"'{ch line i}' isn't a digit in base {radix}"
        toks <- token (KInt value) ln start i line :: toks
      else if Char.isDigit c then
        let s = i
        while i < n && (Char.isDigit (ch line i) || ch line i = '_') do
          i <- i + 1
        if i + 1 < n && ch line i = '.' && Char.isDigit (ch line (i + 1)) then
          i <- i + 1
          while i < n && (Char.isDigit (ch line i) || ch line i = '_') do
            i <- i + 1
          if i < n && (ch line i = 'e' || ch line i = 'E') then
            i <- i + 1
            if i < n && (ch line i = '-' || ch line i = '+') then i <- i + 1
            while i < n && Char.isDigit (ch line i) do
              i <- i + 1
          toks <- token (KFloat (String.toFloat (String.replace (String.sub line s (i - s)) "_" ""))) ln start i line :: toks
        else
          match String.parseInt (String.replace (String.sub line s (i - s)) "_" "") with
          | Some v -> toks <- token (KInt v) ln start i line :: toks
          | None -> fail ln "integer literal too large"
      else if c = '\'' && i + 2 < n && (ch line (i + 1) = '\\' || closesCharLit line (i + 1)) then
        // a character literal: 'a', '\n', '\u{e9}' (a type variable 'a has no closing quote)
        let (cp, next) = if ch line (i + 1) = '\\' then unescapeAt ln line (i + 2) else codeAt line (i + 1)
        if next >= n || ch line next <> '\'' then fail ln "a character literal holds one character: 'a'"
        i <- next + 1
        toks <- token (KChar cp) ln start i line :: toks
      else if c = '\'' && i + 1 < n && Char.isLetter (ch line (i + 1)) then
        let s = i + 1
        i <- i + 1
        while i < n && (Char.isLetterOrDigit (ch line i) || ch line i = '_') do
          i <- i + 1
        toks <- token (KTyVar (String.sub line s (i - s))) ln start i line :: toks
      else if Char.isLetter c || c = '_' then
        let s = i
        while i < n && (Char.isLetterOrDigit (ch line i) || ch line i = '_') do
          i <- i + 1
        // Upper.name is one qualified identifier (List.map, Array.length)
        while Char.isUpper (ch line s) && i + 1 < n && ch line i = '.' && Char.isLetter (ch line (i + 1)) do
          i <- i + 1
          while i < n && (Char.isLetterOrDigit (ch line i) || ch line i = '_') do
            i <- i + 1
        let w = String.sub line s (i - s)
        toks <- token (if Set.contains w keywords then KKw w else KId w) ln start i line :: toks
      else if c = '"' || (c = '$' && i + 1 < n && ch line (i + 1) = '"') then
        let interp = c = '$'
        // """…""": raw text, with quotes and backslashes as written
        let triple = not interp && i + 3 <= n && String.sub line i 3 = "\"\"\""
        let mutable parts = []
        let mutable text = ""
        // a string can go on over the next lines: cur is the line being read
        let mutable cur = line
        let mutable curLine = li
        let mutable closed = false
        i <- i + (if interp then 2 else if triple then 3 else 1)
        while not closed do
          let m = String.length cur
          if i >= m then
            // the line ends inside the string: a newline in its text
            if curLine + 1 >= Array.length lines then fail ln "unterminated string literal"
            text <- text + "\n"
            curLine <- curLine + 1
            cur <- lines.[curLine]
            i <- 0
          else if triple then
            if i + 3 <= m && String.sub cur i 3 = "\"\"\"" then
              closed <- true
              i <- i + 3
            else
              text <- text + String.sub cur i 1
              i <- i + 1
          else if ch cur i = '"' then
            closed <- true
            i <- i + 1
          else if ch cur i = '\\' && i + 1 < m then
            let (cp, next) = unescapeAt (curLine + 1) cur (i + 1)
            text <- text + String.ofChar (char cp)
            i <- next
          else if interp && ch cur i = '{' && i + 1 < m && ch cur (i + 1) = '{' then
            text <- text + "{"
            i <- i + 2
          else if interp && ch cur i = '}' && i + 1 < m && ch cur (i + 1) = '}' then
            text <- text + "}"
            i <- i + 2
          else if interp && ch cur i = '{' then
            parts <- (false, text, 0) :: parts
            text <- ""
            let s = i + 1
            let mutable depth = 0
            i <- i + 1
            // the hole may itself contain braces: {f { x = 1 }}
            while i < m && (ch cur i <> '}' || depth > 0) do
              if ch cur i = '{' then depth <- depth + 1
              else if ch cur i = '}' then depth <- depth - 1
              i <- i + 1
            if i >= m then fail (curLine + 1) "unterminated '{' in interpolated string"
            parts <- (true, String.sub cur s (i - s), s + 1) :: parts
            i <- i + 1
          else
            text <- text + String.sub cur i 1
            i <- i + 1
        let tok = if interp then KInterp (List.rev ((false, text, 0) :: parts)) else KStr text
        if curLine = li then toks <- token tok ln start i line :: toks
        else
          // it ended on a later line: the token takes the rest of this line, and lexing goes on
          // after the closing quote there
          resume <- Some (curLine, i)
          toks <- { tok = tok; line = ln; col = start + 1; len = n - start; adj = start > 0 && ch line (start - 1) <> ' '; last = curLine + 1 } :: toks
          i <- n
      else
        let at = i
        let two = if at + 1 < n then String.sub line at 2 else ""
        let s =
          if two = "|]" || two = ">]" then two
          else if isOpChar c then
            // the longest run of operator characters: a symbol, or a custom operator
            let run = opRun line at
            let next = at + String.length run
            // a symbol and then the sign of its operand: x=-1, a*-b (but not (<+) or (++))
            let k = String.length run
            if k > 1 && (String.endsWith "-" run || String.endsWith "+" run) && Set.contains (String.sub run 0 (k - 1)) symbolSet && next < n && (Char.isLetterOrDigit (ch line next) || ch line next = '_' || ch line next = '(') then String.sub run 0 (k - 1)
            else run
          else
            match List.tryFind (fun s -> at + String.length s <= n && String.sub line at (String.length s) = s) symbols with
            | Some s -> s
            | None -> fail ln $"unexpected character '{c}'"
        // F#: `f -x` (space before, none after, following an operand) negates an argument
        let prefixMinus = s = "-" && at > 0 && ch line (at - 1) = ' ' && at + 1 < n && ch line (at + 1) <> ' ' && followsOperandForMinus (lastTok toks)
        match s with
        | "(" | "{" | "[" ->
          brackets <- ch s 0 :: brackets
          frames <- [] :: frames
        | "[|" | "[<" ->
          brackets <- '(' :: brackets
          frames <- [] :: frames
        | ")" | "}" | "]" | "|]" | ">]" when not (List.isEmpty brackets) ->
          // the blocks opened inside the bracket end with it
          for _ in 1 .. List.length (List.head frames) do
            toks <- token KDedent ln start i line :: toks
          frames <- List.tail frames
          brackets <- List.tail brackets
        | _ -> ()
        i <- i + String.length s
        toks <- token (KSym (if prefixMinus then "~-" else s)) ln start i line :: toks
  let count = Array.length lines
  for _ in 2 .. List.length indents do
    toks <- { tok = KDedent; line = count; col = 0; len = 0; adj = false; last = count } :: toks
  toks <- { tok = KEof; line = count; col = 0; len = 0; adj = false; last = count } :: toks
  (Array.ofList (List.rev toks), List.rev comments)

let lex (src: string) = fst (lexComments src)

// ---------------------------------------------------------------- formatter

let openers = Set.ofList [ "("; "["; "[|"; "{"; "[<" ]
let closers = Set.ofList [ ")"; "]"; "|]"; "}"; ">]" ]

// where spacing carries meaning (f(x) vs f (x), f -x, 9.58<s>, x?, list<int>) or is a matter of
// taste the source already settled, it stays as written
let asWritten = Set.ofList [ "("; ")"; "<"; ">"; "."; "?"; "^"; "|"; "~-"; ">>"; ":"; "<-" ]

let isOperand tok =
  match tok with
  | KId _ | KInt _ | KFloat _ | KStr _ | KInterp _ | KTyVar _ -> true
  | KKw ("true" | "false") -> true
  | KSym s -> Set.contains s closers
  | _ -> false

// the source text of a token (layout tokens and the lexer's implied `;` have none)
let textOf (lines: array<string>) (t: Token) =
  if t.col <= 0 || t.line < 1 || t.line > Array.length lines then None
  else
    let l = lines.[t.line - 1]
    let start = t.col - 1
    if start + t.len > String.length l then None
    else
      let text = String.sub l start t.len
      match t.tok with
      | KSym ";" when text <> ";" -> None
      | KNewline | KIndent | KDedent | KEof -> None
      | _ -> Some text

let symText t =
  match t with
  | KSym s -> s
  | KKw k -> k
  | _ -> ""

// tight: inside a.[i] or between < > of type arguments and measures, where spacing stays as written
let space (prev: Token) (cur: Token) (unaryMinus: bool) (tight: bool) =
  let p = symText prev.tok
  let c = symText cur.tok
  if unaryMinus then ""
  else if tight || Set.contains p asWritten || Set.contains c asWritten || isPrefixOp p then (if cur.adj then "" else " ")
  else if Set.contains p openers && Set.contains c closers then ""
  else if p = "[<" || c = ">]" then ""
  else if Set.contains p openers || Set.contains c closers then " "
  else if c = "," || c = ";" then ""
  else " "

// whether the innermost open bracket's first block took its level
let topTook opened =
  match opened with
  | (_, _, took) :: _ -> took
  | [] -> false

// a '-' that doesn't follow an operand is a negation
let negates (prev: option<Token * string>) =
  match prev with
  | Some (p, _) -> not (isOperand p.tok)
  | None -> true

let render (level: int) (ts: list<Token * string>) =
  let mutable out = String.repeat (2 * level) " "
  let mutable prev = None
  let mutable unaryNext = false
  let mutable tight = 0 // open a.[ … ] and f64< … > groups on this line
  for (t, text) in ts do
    match prev with
    | Some (p, _) -> out <- out + space p t unaryNext (tight > 0)
    | None -> ()
    out <- out + text
    if (text = "]" || text = ">") && tight > 0 then tight <- tight - 1
    match prev with
    | Some (_, ".") when text = "[" -> tight <- tight + 1
    | Some _ when text = "<" && t.adj -> tight <- tight + 1
    | _ -> ()
    unaryNext <- text = "-" && negates prev
    prev <- Some (t, text)
  out

// a hole's column in $"…" moves with the indentation
let kindOf (t: Token) =
  match t.tok with
  | KInterp parts -> KInterp (List.map (fun (e, s, _) -> (e, s, 0)) parts)
  | k -> k

let kinds (ts: array<Token>) = List.map kindOf (List.filter (fun t -> t.tok <> KEof) (Array.toList ts))

// Formats a source file; Error when the result would lex differently (a formatter bug).
let format (source: string) : result<string, string> =
  let src = String.replace source "\r\n" "\n"
  let lines = Array.ofList (String.split "\n" src)
  let (toks, comments) = lexComments src
  let commentAt = Map.ofList (List.map (fun (l, c, text) -> (l, (c, String.trim text))) comments)
  // each code line: its indentation level and its tokens with their text
  let mutable code = HashMap.empty ()
  let mutable layout = 0
  let mutable current = -1
  let mutable lineToks = []
  let mutable lineLevel = 0
  let mutable lastLine = 0
  // each open bracket: the line it opened on, whether a block opened inside it yet, and whether
  // that block took the bracket's level, so `(fun x ->` with its body below is one level in
  let mutable opened = []
  let mutable absorbed = 0
  // the lines after the first of a string that spans lines are its text: they stay as written
  let mutable verbatim = Set.empty ()
  for t in toks do
    for l in t.line + 1 .. t.last do
      verbatim <- Set.add l verbatim
  for t in toks do
    match t.tok with
    | KIndent ->
      layout <- layout + 1
      match opened with
      | (line, false, _) :: rest ->
        if line = lastLine then
          opened <- (line, true, true) :: rest
          absorbed <- absorbed + 1
        else opened <- (line, true, false) :: rest
      | _ -> ()
    | KDedent -> layout <- layout - 1
    | _ when Set.contains t.line verbatim -> ()
    | _ ->
      match textOf lines t with
      | None -> ()
      | Some text ->
        if t.line <> current then
          if current > 0 then code <- HashMap.add current (lineLevel, List.rev lineToks) code
          lineToks <- []
          current <- t.line
          // a closer lines up with its opener's line, unless a block took its level
          let closesOwnLevel = Set.contains (symText t.tok) closers && not (List.isEmpty opened) && not (topTook opened)
          lineLevel <- layout + List.length opened - absorbed - (if closesOwnLevel then 1 else 0)
        lineToks <- (t, text) :: lineToks
        lastLine <- t.line
        let s = symText t.tok
        if Set.contains s openers then opened <- (t.line, false, false) :: opened
        else if Set.contains s closers && not (List.isEmpty opened) then
          if topTook opened then absorbed <- absorbed - 1
          opened <- List.tail opened
  if current > 0 then code <- HashMap.add current (lineLevel, List.rev lineToks) code
  let count = Array.length lines
  let lineCode = code
  let nextLevel (from: int) =
    let mutable level = None
    let mutable l = from
    while Option.isNone level && l <= count do
      match HashMap.tryFind l lineCode with
      | Some (lv, _) -> level <- Some lv
      | None -> ()
      l <- l + 1
    Option.defaultValue 0 level
  let mutable out = []
  let mutable blank = 0
  for l in 1 .. count do
    let text =
      if Set.contains l verbatim then Some lines.[l - 1]
      else
        match (HashMap.tryFind l code, Map.tryFind l commentAt) with
        | (Some (level, ts), Some (_, c)) -> Some (render level ts + " " + c)
        | (Some (level, ts), None) -> Some (render level ts)
        | (None, Some (_, c)) -> Some (String.repeat (2 * nextLevel l) " " + c) // a comment on its own line
        | _ -> None
    match text with
    | Some t ->
      if blank > 0 && not (List.isEmpty out) then out <- "" :: out
      blank <- 0
      out <- t :: out
    | None -> blank <- blank + 1
  let result = String.join "\n" (List.rev out) + "\n"
  if kinds toks = kinds (lex result) then Ok result
  else Error "formatting would change the program's tokens (a zs fmt bug; the file was left alone)"

// ---------------------------------------------------------------- test

let sample = """// a messy file
type Point = {x:f64;y:f64}
let   norm (p:Point)=Math.sqrt(p.x*p.x+p.y*p.y)


let rec fact n =
    if n<=1 then 1
    else n*fact(n-1)
let  main ( ) =
    let xs=[1;2;3]   // some numbers
    let ys = xs |> List.map(fun x ->
                 x*2)
    let a = [| 1 ; 2 |]
    println $"{a.[ 0 ]} {fact 5} {norm {x=3.0;y=4.0}} {-1} {List.sum ys}"
    match xs with
    |[]->println "none"
    |x::_ -> println(string x)
        // a deeper comment
    let r = { x = 1.0
              y = 2.0 }
    let neg = f -x
    0
"""

let main () =
  match format sample with
  | Ok s -> print s
  | Error e -> println e
  match File.readAllText "tests/format_port.zs" with
  | Ok src ->
    match format src with
    | Ok s -> println $"own source formats to itself: {s = src}"
    | Error e -> println e
  | Error e -> println e
  0
