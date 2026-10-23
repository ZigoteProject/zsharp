/// The parser (0019): a file's tokens to its tree, by recursive descent, as the F# compiler's
/// parser makes it (one tree for both: `compiler/tests/parser.sh` compares them). It makes the
/// tree only; the AST is a view of it. Where a token is missing, it reports that and puts a
/// missing token in the tree; where it can't go on, it reports and skips into an Error node, to
/// the end of the line at the block's indentation. A mistake is reported once: no error is
/// reported at a token an earlier error was at or skipped to.
open Token
open Diag.Diagnostic
open Diag.Report

// the parser's state: the tokens and where it is in them, the tree so far, what it found wrong
type private P =
  { src: Source.Source
    s: string
    /// the lexer's tokens, then the ones the parser makes
    toks: Buffer<Token>
    /// the end of the file's token
    eof: int
    pos: ref<int>
    /// the open nodes, innermost last: their kinds, and where their children start in `stack`
    openKinds: Buffer<Tree.Kind>
    openAt: Buffer<int>
    /// the children of the open nodes, in order
    stack: Buffer<int>
    /// the nodes made, as `Tree` has them
    kinds: Buffer<Tree.Kind>
    firsts: Buffer<int>
    counts: Buffer<int>
    children: Buffer<int>
    parents: Buffer<int>
    starts: Buffer<int>
    ends: Buffer<int>
    /// the `>>`s split, and what each was
    splitAt: Buffer<int>
    splitWas: Buffer<Token>
    diags: Buffer<Diagnostic>
    /// the errors found, reported or not (a trial fails on one)
    errors: ref<int>
    /// the last token an error was at or skipped to: none at or before it is reported
    quiet: ref<int>
    /// inside a task { }'s body, and inside a seq { }
    inTask: ref<int>
    inSeq: ref<int> }

// where the parser was, to go back to after a trial
type private Saved =
  { atToken: int
    openDepth: int
    stackLength: int
    nodeCount: int
    childCount: int
    tokenCount: int
    splitCount: int
    diagCount: int
    errorCount: int
    quietAt: int }

let private make (src: Source.Source) (toks: array<Token>) : P =
  { src = src
    s = src.text
    toks = Buffer.ofArray toks
    eof = Array.length toks - 1
    pos = ref 0
    openKinds = Buffer.empty
    openAt = Buffer.empty
    stack = Buffer.empty
    kinds = Buffer.empty
    firsts = Buffer.empty
    counts = Buffer.empty
    children = Buffer.empty
    parents = Buffer.empty
    starts = Buffer.empty
    ends = Buffer.empty
    splitAt = Buffer.empty
    splitWas = Buffer.empty
    diags = Buffer.empty
    errors = ref 0
    quiet = ref (-1)
    inTask = ref 0
    inSeq = ref 0 }

// ------------------------------------------------------------ reading tokens

let private peek (p: P) : Kind = p.toks.[p.pos.Value].kind

// the kind of the token k ahead (the end of the file's, past it)
let private ahead (p: P) (k: int) : Kind = p.toks.[min (p.pos.Value + k) p.eof].kind

let private peek2 (p: P) : Kind = ahead p 1

let private current (p: P) : Token = p.toks.[p.pos.Value]

// a token's text
let private textOf (p: P) (i: int) : string = Token.text p.s p.toks.[i]

// whether token i's text is w
let private textIs (p: P) (i: int) (w: string) : bool =
  let t = p.toks.[i]
  if t.length <> String.length w then
    false
  else
    let mutable same = true
    let mutable k = 0
    while same && k < t.length do
      if String.byte p.s (t.offset + k) <> String.byte w k then
        same <- false
      k <- k + 1
    same

// whether the token k ahead is the word w (yield, return, use: words, not keywords)
let private wordAt (p: P) (k: int) (w: string) : bool =
  let i = min (p.pos.Value + k) p.eof
  p.toks.[i].kind = Id && textIs p i w

let private isWord (p: P) (w: string) : bool = wordAt p 0 w

// whether the token k ahead is `!`
let private bangAt (p: P) (k: int) : bool =
  let i = min (p.pos.Value + k) p.eof
  p.toks.[i].kind = Op && textIs p i "!"

// whether the current token has no space before it: f(x), let!, 9.58<s>
let private adjacent (p: P) : bool =
  let o = (current p).offset
  o > 0 && String.byte p.s (o - 1) <> u8 32 && String.byte p.s (o - 1) <> u8 10

// the first character of an identifier (inside ``…`` for a quoted one)
let private firstChar (p: P) (i: int) : int =
  let t = p.toks.[i]
  let c = int (String.byte p.s t.offset)
  if c = 96 && t.length > 2 then int (String.byte p.s (t.offset + 2)) else c

// a name a function is defined with: lower case or `_` first (a letter beyond ASCII counts)
let private startsLower (p: P) (i: int) : bool =
  let c = firstChar p i
  (c >= 97 && c <= 122) || c = 95 || c >= 128

// a case's name in a pattern: upper case first, or qualified
let private isCaseName (p: P) (i: int) : bool =
  let c = firstChar p i
  let t = p.toks.[i]
  let mutable dot = false
  for k in t.offset .. t.offset + t.length - 1 do
    if String.byte p.s k = u8 46 then
      dot <- true
  (c >= 65 && c <= 90) || dot

// whether token i is operator characters only (a symbol or a custom operator)
let private isOperatorText (p: P) (i: int) : bool =
  let t = p.toks.[i]
  let mutable all = t.length > 0
  for k in t.offset .. t.offset + t.length - 1 do
    if not (Lexer.isOpChar (int (String.byte p.s k))) then
      all <- false
  all

// the current custom operator is a prefix one (!r, ~~x), an infix one (>>=)
let private isPrefix (p: P) : bool = peek p = Op && Lexer.isPrefixOp (textOf p p.pos.Value)

let private isInfix (p: P) : bool = peek p = Op && Lexer.isInfixOp (textOf p p.pos.Value)

// a custom operator's precedence, as F#'s: by its first character after any dots
let private opLevel (p: P) : int =
  let t = current p
  let stop = t.offset + t.length
  let mutable k = t.offset
  while k < stop && String.byte p.s k = u8 46 do
    k <- k + 1
  if k >= stop then
    0
  else
    let c = int (String.byte p.s k)
    if c = 42 && k + 1 < stop && String.byte p.s (k + 1) = u8 42 then 4
    else if c = 64 || c = 94 then 1
    else if c = 43 || c = 45 then 2
    else if c = 42 || c = 47 || c = 37 then 3
    else 0

// ------------------------------------------------------------ building the tree

let private start (p: P) (k: Tree.Kind) =
  Buffer.push k p.openKinds
  Buffer.push (Buffer.length p.stack) p.openAt

// how many children the open node has so far: startAt makes a node of them from a point on,
// for a construct found after its first part (an operator after its left operand)
let private here (p: P) : int = Buffer.length p.stack - p.openAt.[Buffer.length p.openAt - 1]

let private startAt (p: P) (at: int) (k: Tree.Kind) =
  let from = p.openAt.[Buffer.length p.openAt - 1] + at
  Buffer.push k p.openKinds
  Buffer.push from p.openAt

// the open node ends: it's made, and becomes a child of the one around it
let private finish (p: P) =
  let k = Buffer.removeLast p.openKinds
  let from = Buffer.removeLast p.openAt
  let stop = Buffer.length p.stack
  let id = Buffer.length p.kinds
  Buffer.push k p.kinds
  Buffer.push (Buffer.length p.children) p.firsts
  Buffer.push (stop - from) p.counts
  Buffer.push (-1) p.parents
  let mutable lo = -1
  let mutable hi = -1
  for i in from .. stop - 1 do
    let c = p.stack.[i]
    Buffer.push c p.children
    if c >= 0 then
      p.parents.[c] <- id
      if p.ends.[c] > p.starts.[c] then
        if lo < 0 then
          lo <- p.starts.[c]
        hi <- p.ends.[c]
    else
      let t = p.toks.[-1 - c]
      if t.length > 0 then
        if lo < 0 then
          lo <- t.offset
        hi <- t.offset + t.length
  if lo < 0 then
    lo <- (current p).offset
    hi <- lo
  Buffer.push lo p.starts
  Buffer.push hi p.ends
  Buffer.truncate from p.stack
  Buffer.push id p.stack

// a node of the children from `at` on, ended at once
let private wrap (p: P) (at: int) (k: Tree.Kind) =
  startAt p at k
  finish p

let private advance (p: P) =
  let i = p.pos.Value
  if i < p.eof then
    Buffer.push (-1 - i) p.stack
    p.pos.Value <- i + 1

let private save (p: P) : Saved =
  { atToken = p.pos.Value
    openDepth = Buffer.length p.openKinds
    stackLength = Buffer.length p.stack
    nodeCount = Buffer.length p.kinds
    childCount = Buffer.length p.children
    tokenCount = Buffer.length p.toks
    splitCount = Buffer.length p.splitAt
    diagCount = Buffer.length p.diags
    errorCount = p.errors.Value
    quietAt = p.quiet.Value }

// back to where a trial started, the tokens it split as they were
let private restore (p: P) (s: Saved) =
  p.pos.Value <- s.atToken
  Buffer.truncate s.openDepth p.openKinds
  Buffer.truncate s.openDepth p.openAt
  Buffer.truncate s.stackLength p.stack
  Buffer.truncate s.nodeCount p.kinds
  Buffer.truncate s.nodeCount p.firsts
  Buffer.truncate s.nodeCount p.counts
  Buffer.truncate s.nodeCount p.parents
  Buffer.truncate s.nodeCount p.starts
  Buffer.truncate s.nodeCount p.ends
  Buffer.truncate s.childCount p.children
  while Buffer.length p.splitAt > s.splitCount do
    let i = Buffer.removeLast p.splitAt
    p.toks.[i] <- Buffer.removeLast p.splitWas
  Buffer.truncate s.tokenCount p.toks
  Buffer.truncate s.diagCount p.diags
  p.errors.Value <- s.errorCount
  p.quiet.Value <- s.quietAt

// a `>>` (or `>>>`) closing a type argument list: its first `>` goes into the tree, the rest
// stays to be read
let private split (p: P) (rest: Kind) =
  let i = p.pos.Value
  let t = p.toks.[i]
  Buffer.push (-1 - Buffer.length p.toks) p.stack
  Buffer.push { kind = Gt; offset = t.offset; length = 1 } p.toks
  Buffer.push i p.splitAt
  Buffer.push t p.splitWas
  p.toks.[i] <- { kind = rest; offset = t.offset + 1; length = t.length - 1 }

// ------------------------------------------------------------ errors

// an error at token i, unless an earlier one was there or skipped past it
let private reportAt (p: P) (i: int) (message: string) =
  p.errors.Value <- p.errors.Value + 1
  if i > p.quiet.Value then
    let t = p.toks.[i]
    Buffer.push (error { file = p.src.file; offset = t.offset; length = t.length } message) p.diags
    p.quiet.Value <- max i p.pos.Value

// an error about the line token i is on, at its first character (the F# compiler's errors
// that have no column)
let private failAt (p: P) (i: int) (message: string) =
  p.errors.Value <- p.errors.Value + 1
  if i > p.quiet.Value then
    let line = Source.lineOf p.src p.toks.[i].offset
    let mutable o = p.src.lines.[line]
    while o < String.length p.s && String.byte p.s o = u8 32 do
      o <- o + 1
    Buffer.push (error { file = p.src.file; offset = o; length = -1 } message) p.diags
    p.quiet.Value <- max i p.pos.Value

// how the current token reads in a message
let private found (p: P) : string =
  let t = current p
  match t.kind with
  | Semi when t.length = 0 -> "';'"
  | Negate -> "'~-'"
  | _ -> describe t.kind (Token.text p.s t)

let private err (p: P) (what: string) = reportAt p p.pos.Value ("expected " + what + ", found " + found p)

let private errAt (p: P) (message: string) = reportAt p p.pos.Value message

// a token expected here and not found: zero-width, where the next one starts
let private missing (p: P) (k: Kind) =
  Buffer.push (-1 - Buffer.length p.toks) p.stack
  Buffer.push { kind = k; offset = (current p).offset; length = 0 } p.toks

let private expect (p: P) (k: Kind) (what: string) =
  if peek p = k then
    advance p
  else
    err p what
    missing p k

let private ident (p: P) = expect p Id "identifier"

// after an error: the tokens to the end of the line at this block's indentation (with
// `closers`, not past a closing bracket) in an Error node; nothing to there is reported again
let private recover (p: P) (closers: bool) =
  start p Tree.Error
  let mutable depth = 0
  let mutable go = true
  while go do
    match peek p with
    | Eof -> go <- false
    | Indent ->
      depth <- depth + 1
      advance p
    | Newline
    | Dedent when depth = 0 -> go <- false
    | Dedent ->
      depth <- depth - 1
      advance p
    | RParen
    | RBrack
    | RBrace
    | BarRBrack
    | GtRBrack when closers && depth = 0 -> go <- false
    | _ -> advance p
  finish p
  p.quiet.Value <- max p.quiet.Value p.pos.Value

// what can't be parsed here: an error, and the rest of the line in an Error node
let private skip (p: P) (what: string) =
  err p what
  recover p true

// one token in an Error node, so a loop goes on
let private bump (p: P) =
  start p Tree.Error
  advance p
  finish p

// the end of an indented block: what's before its Dedent is reported and skipped
let private dedent (p: P) (what: string) =
  if peek p <> Dedent && peek p <> Eof then
    err p what
    start p Tree.Error
    let mutable depth = 0
    while peek p <> Eof && (peek p <> Dedent || depth > 0) do
      if peek p = Indent then
        depth <- depth + 1
      else if peek p = Dedent then
        depth <- depth - 1
      advance p
    finish p
    p.quiet.Value <- max p.quiet.Value p.pos.Value
  expect p Dedent what

// ------------------------------------------------------------ types

// what a type is, for the checks that need it
let private tyName = 0

let private tyVar = 1

let private tyOther = 2

let private isNumericName (p: P) (i: int) : bool =
  match textOf p i with
  | "int"
  | "i8"
  | "i16"
  | "i32"
  | "i64"
  | "u8"
  | "u16"
  | "u32"
  | "u64"
  | "usize"
  | "f32"
  | "f64"
  | "float"
  | "c_int" -> true
  | _ -> false

// one `>` closing a type argument list, from a `>>` or a `>>>` too
let private closeAngle (p: P) =
  match peek p with
  | Gt -> advance p
  | Compose -> split p Gt
  | ShiftRight -> split p Compose
  | _ ->
    err p "'>'"
    missing p Gt

/// A unit of measure: m, m/s^2, kg m/s^2, 'u, 1 (inside <...> after a numeric type).
let rec private measure (p: P) =
  start p Tree.Measure
  product p
  finish p

and private product (p: P) =
  term p
  let mutable go = true
  while go do
    match peek p with
    | Star
    | Slash ->
      advance p
      term p
    | Id
    | TyVar
    | LParen -> term p
    | _ -> go <- false

and private term (p: P) =
  match peek p with
  | Id
  | TyVar -> advance p
  | Int when textIs p p.pos.Value "1" -> advance p
  | LParen ->
    advance p
    product p
    expect p RParen "')'"
  | _ -> skip p "unit of measure"
  if peek p = Caret then
    advance p
    if peek p = Minus || peek p = Negate then
      advance p
    if peek p = Int then advance p else skip p "exponent"

let private typeVar (p: P) =
  if peek p = TyVar then
    advance p
  else
    err p "type parameter"
    missing p TyVar

let rec private tyAtom (p: P) : int =
  let at = here p
  let first =
    match peek p with
    | Id when peek2 p = Lt && isNumericName p p.pos.Value ->
      start p Tree.TypeName
      advance p
      advance p
      measure p
      closeAngle p
      finish p
      tyName
    | TyVar ->
      advance p
      tyVar
    | Int ->
      // fixed<u8, 16>'s length
      advance p
      tyName
    | Id when peek2 p = Id && textIs p p.pos.Value "dyn" ->
      // dyn Trait: a value of any type that implements the trait
      start p Tree.TypeName
      advance p
      ident p
      finish p
      tyName
    | Id ->
      advance p
      if peek p = Lt then
        startAt p at Tree.TypeName
        advance p
        ty p |> ignore
        while peek p = Comma do
          advance p
          ty p |> ignore
        closeAngle p
        finish p
      tyName
    | LParen ->
      start p Tree.TypeParen
      advance p
      let t = ty p
      expect p RParen "')'"
      finish p
      t
    | _ ->
      skip p "type"
      tyOther
  // postfix application: int list, string option
  let mutable kind = first
  while peek p = Id do
    startAt p at Tree.TypeName
    advance p
    finish p
    kind <- tyName
  kind

and private tupleTy (p: P) : int =
  let at = here p
  let first = tyAtom p
  if peek p = Star then
    startAt p at Tree.TypeTuple
    while peek p = Star do
      advance p
      tyAtom p |> ignore
    finish p
    tyOther
  else
    first

and private ty (p: P) : int =
  let at = here p
  let first = tupleTy p
  if peek p = Arrow then
    startAt p at Tree.TypeFun
    advance p
    ty p |> ignore
    finish p
    tyOther
  else if peek p = Slash then
    // the effects after a function's result: / E, / 'e, / <E, F | 'e>, / <>
    startAt p at Tree.TypeRow
    advance p
    match peek p with
    | NotEq
    | TyVar -> advance p
    | Lt ->
      advance p
      label p
      while peek p = Comma do
        advance p
        label p
      if peek p = Bar then
        advance p
        if peek p = TyVar then
          advance p
        else
          err p "a row variable ('e)"
          missing p TyVar
      closeAngle p
    | _ -> label p
    finish p
    tyOther
  else
    first

// an effect in a row: a named type
and private label (p: P) =
  if tyAtom p <> tyName then
    err p "an effect"

let private optTy (p: P) =
  if peek p = Colon then
    start p Tree.Annotation
    advance p
    ty p |> ignore
    finish p

// ------------------------------------------------------------ patterns

let private startsPatAtom (k: Kind) : bool =
  match k with
  | Id
  | Int
  | Char
  | Str
  | Minus
  | Negate
  | True
  | False
  | LParen
  | LBrack
  | LBrace -> true
  | _ -> false

let rec private pattern (p: P) =
  let at = here p
  orPat p
  while peek p = As do
    startAt p at Tree.PatternAs
    advance p
    ident p
    finish p

// before '->', a line starting with '|' continues the or-pattern
and private orPat (p: P) =
  let at = here p
  tuplePat p
  let mutable chain = false
  while peek p = Bar || (peek p = Newline && peek2 p = Bar) do
    if not chain then
      chain <- true
      startAt p at Tree.PatternOr
    if peek p = Newline then
      advance p
    advance p
    tuplePat p
  if chain then
    finish p

and private tuplePat (p: P) =
  let at = here p
  consPat p
  if peek p = Comma then
    startAt p at Tree.PatternTuple
    while peek p = Comma do
      advance p
      consPat p
    finish p

and private consPat (p: P) =
  let at = here p
  appPat p
  if peek p = Cons then
    startAt p at Tree.PatternCons
    advance p
    consPat p
    finish p

and private appPat (p: P) =
  if peek p = Id && startsPatAtom (peek2 p) && isCaseName p p.pos.Value then
    start p Tree.PatternCase
    advance p
    while startsPatAtom (peek p) do
      patAtom p
    finish p
  else
    patAtom p

and private patAtom (p: P) =
  let k =
    match peek p with
    | LBrace -> Some Tree.PatternRecord
    | LBrack -> Some Tree.PatternList
    | LParen -> Some Tree.PatternParen
    | Minus
    | Negate -> Some Tree.PatternNegative
    | _ -> None
  match k with
  | Some k ->
    start p k
    patAtomOf p
    finish p
  | None -> patAtomOf p

and private patAtomOf (p: P) =
  let t = peek p
  if not (startsPatAtom t) then
    skip p "pattern"
  else
    advance p
    match t with
    | Minus
    | Negate -> if peek p = Int then advance p else skip p "integer"
    | LBrace ->
      // a record pattern: { field = pattern; ... } (line breaks separate fields too)
      let mutable fields = 0
      let mutable go = true
      while go && peek p <> RBrace && peek p <> Eof do
        let before = p.pos.Value
        ident p
        expect p Equals "'='"
        pattern p
        fields <- fields + 1
        if peek p = Semi then
          advance p
        else if peek p <> RBrace then
          err p "';' or '}'"
          go <- false
        if p.pos.Value = before then
          go <- false
      expect p RBrace "'}'"
      if fields = 0 then
        failAt p p.pos.Value "a record pattern names at least one field: { x = x }"
    | LBrack ->
      let mutable go = true
      while go && peek p <> RBrack && peek p <> Eof do
        let before = p.pos.Value
        pattern p
        if peek p = Semi then
          advance p
        if p.pos.Value = before then
          go <- false
      expect p RBrack "']'"
    | LParen ->
      if peek p = RParen then
        advance p
      else if peek p = Id && peek2 p = Equals then
        // named fields of a case: (x = px, y = _)
        let mutable go = true
        while go && peek p <> RParen && peek p <> Eof do
          let before = p.pos.Value
          ident p
          expect p Equals "'='"
          pattern p
          if peek p = Comma || peek p = Semi then
            advance p
          else if peek p <> RParen then
            err p "',' or ')'"
            go <- false
          if p.pos.Value = before then
            go <- false
        expect p RParen "')'"
      else
        pattern p
        expect p RParen "')'"
    | _ -> ()

/// A function parameter: x, _, (), (x: T), (pattern), [pattern] or { record pattern }.
let private param (p: P) =
  if peek p = LParen && ahead p 1 = Id && ahead p 2 = Colon then
    start p Tree.Parameter
    advance p
    ident p
    advance p
    ty p |> ignore
    expect p RParen "')'"
    finish p
  else
    patAtom p

let private startsParam (k: Kind) : bool =
  match k with
  | Id
  | LParen
  | LBrack
  | LBrace -> true
  | _ -> false

// the parameters, and how many
let private parameters (p: P) : int =
  let mutable n = 0
  while startsParam (peek p) do
    param p
    n <- n + 1
  n

// ------------------------------------------------------------ expressions

// after a name, at `{`: whether a computation expression's body follows rather than a record
let private ceAhead (p: P) : bool =
  if peek p <> LBrace then
    false
  else
    match ahead p 1 with
    | Indent
    | Let
    | Do
    | For
    | If
    | Match
    | While -> true
    | Id -> wordAt p 1 "return" || wordAt p 1 "use" || wordAt p 1 "yield"
    | _ -> false

// a built-in binary operator, which `(op)` makes a function of
let private isBuiltinOperator (k: Kind) : bool =
  match k with
  | Plus
  | Minus
  | Star
  | Slash
  | Percent
  | Equals
  | NotEq
  | Lt
  | Gt
  | LtEq
  | GtEq
  | AndBits
  | OrBits
  | XorBits
  | ShiftLeft
  | ShiftRight
  | Append
  | Cons -> true
  | _ -> false

// the operators of a left-associative level (3 to 6, 8 and 9: see `level`)
let private isOperatorOf (n: int) (k: Kind) : bool =
  match k with
  | OrBits -> n = 3
  | XorBits -> n = 4
  | AndBits -> n = 5
  | ShiftLeft
  | ShiftRight -> n = 6
  | Plus
  | Minus -> n = 8
  | Star
  | Slash
  | Percent -> n = 9
  | _ -> false

// a compound assignment: x += 1
let private isCompound (k: Kind) : bool =
  match k with
  | PlusEq
  | MinusEq
  | StarEq
  | SlashEq
  | PercentEq
  | AndBitsEq
  | OrBitsEq
  | XorBitsEq -> true
  | _ -> false

// whether a child of the tree so far is a place `<-` can assign: a name, a field, an element,
// in parentheses too
let rec private isPlace (p: P) (c: int) : bool =
  if c < 0 then
    p.toks.[-1 - c].kind = Id
  else
    match p.kinds.[c] with
    | Tree.Field
    | Tree.Index -> true
    | Tree.Paren -> p.counts.[c] = 3 && isPlace p p.children.[p.firsts.[c] + 1]
    | _ -> false

// a hole's width or format specifier, where its expression ends: at a ',' or a ':' outside
// brackets and literals (`::` is cons); -1 when it has neither
let private holeEnd (s: string) : int =
  let n = String.length s
  let at (i: int) = if i < n then int (String.byte s i) else -1
  let mutable depth = 0
  let mutable i = 0
  let mutable cut = -1
  while cut < 0 && i < n do
    let c = at i
    if c = 40 || c = 91 || c = 123 then
      depth <- depth + 1
      i <- i + 1
    else if c = 41 || c = 93 || c = 125 then
      depth <- depth - 1
      i <- i + 1
    else if c = 34 || (c = 39 && i + 2 < n && (at (i + 1) = 92 || at (i + 2) = 39)) then
      // a string or a character literal, its escapes skipped
      i <- i + 1
      while i < n && at i <> c do
        if at i = 92 then
          i <- i + 1
        i <- i + 1
      i <- i + 1
    else if (c = 44 || c = 58) && depth = 0 && not (c = 58 && (at (i + 1) = 58 || (i > 0 && at (i - 1) = 58))) then
      cut <- i
    else
      i <- i + 1
  cut

// a format specifier is a letter and at most two digits: F2, X8, G
let private isSpec (s: string) : bool =
  let n = String.length s
  let isLetter (c: int) = (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
  if n < 1 || n > 3 || not (isLetter (int (String.byte s 0))) then
    false
  else
    let mutable digits = true
    for i in 1 .. n - 1 do
      let c = int (String.byte s i)
      if c < 48 || c > 57 then
        digits <- false
    digits

let rec private block (p: P) =
  if peek p = Indent then
    start p Tree.Block
    advance p
    seq p
    dedent p "end of block"
    finish p
  else if not (taskForm p) then
    let at = here p
    expr p
    assignment p at

/// In a task's body: `return e`, `return! t` and `do! t`; whether there was one.
and private taskForm (p: P) : bool =
  if p.inTask.Value = 0 then
    false
  else if isWord p "return" then
    start p Tree.Return
    advance p
    bang p |> ignore
    block p
    finish p
    true
  else if peek p = Do && bangAt p 1 then
    start p Tree.DoBang
    advance p
    advance p
    block p
    finish p
    true
  else
    false

// `!` right after a keyword: let!, do!, return!, yield!
and private bang (p: P) : bool =
  if bangAt p 0 && adjacent p then
    advance p
    true
  else
    false

/// After an expression from `at`: `lhs <- rhs`, or `lhs += rhs` on a place.
and private assignment (p: P) (at: int) =
  let k = peek p
  if k = LArrow then
    startAt p at Tree.Assign
    advance p
    expr p
    finish p
  else if isCompound k then
    let oi = p.pos.Value
    let place = here p - at = 1 && isPlace p p.stack.[Buffer.length p.stack - 1]
    startAt p at Tree.Assign
    advance p
    expr p
    finish p
    if not place then
      failAt p oi (textOf p oi + " needs a place <- can assign: a let mutable, a ref's .Value, an element or a field")

/// After a binding started at token ln: the rest of the block, from the next line.
and private rest (p: P) (ln: int) =
  if peek p = Newline then
    advance p
    seq p
  else
    failAt p ln "'let' must be followed by an expression on the next line"

/// A block's statements.
and private seq (p: P) =
  let ln = p.pos.Value
  if isWord p "use" && peek2 p = Id then
    // use x = e: x is disposed after the rest of the block
    start p Tree.Use
    advance p
    ident p
    expect p Equals "'='"
    block p
    finish p
    if peek p = Newline then
      advance p
      seq p
    else
      failAt p ln "'use' must be followed by the rest of the block on the next line"
  else if p.inTask.Value > 0 && peek p = Let && bangAt p 1 then
    // let! p = t: the rest once the task t has given its result
    start p Tree.LetBang
    advance p
    advance p
    pattern p
    expect p Equals "'='"
    block p
    finish p
    rest p ln
  else if p.inTask.Value > 0 && (isWord p "return" || (peek p = Do && bangAt p 1)) then
    let isReturn = isWord p "return"
    taskForm p |> ignore
    if peek p = Newline then
      if isReturn then
        failAt p p.pos.Value "nothing can follow return in a task"
      advance p
      seq p
    else
      statementEnd p
  else if peek p = Let then
    start p Tree.Let
    advance p
    let isRec = peek p = Rec
    if isRec then
      advance p
    if peek p = Mutable then
      advance p
      ident p
      optTy p
      expect p Equals "'='"
      block p
      finish p
      rest p ln
    else if peek p = LParen && operatorAhead p then
      // a local operator: let (<+>) a b = …
      advance p
      operatorName p
      localFun p ln isRec
    else if peek p = Id && (isRec || startsLower p p.pos.Value) && not (textIs p p.pos.Value "_") && startsParam (peek2 p) then
      advance p
      localFun p ln isRec
    else
      pattern p
      optTy p
      expect p Equals "'='"
      block p
      finish p
      rest p ln
  else
    let at = here p
    expr p
    assignment p at
    statementEnd p

// after a statement: the next one on the next line, or the block's end
and private statementEnd (p: P) =
  if peek p = Newline then
    advance p
    seq p
  else if peek p <> Dedent && peek p <> Eof then
    err p "end of block"
    recover p false
    if peek p = Newline then
      advance p
      seq p

/// At `let (`: whether an operator and `)` follow.
and private operatorAhead (p: P) : bool =
  peek2 p <> Bar && isOperatorText p (min (p.pos.Value + 1) p.eof) && ahead p 2 = RParen

/// The operator of `(op)` after its `(`; a built-in one can't be defined.
and private operatorName (p: P) =
  let s = textOf p p.pos.Value
  if not (Lexer.isCustomOp s) then
    failAt p p.pos.Value ("'" + s + "' is built in and can't be redefined; give the custom operator another name, such as '" + s + ".'")
  advance p
  expect p RParen "')'"

/// A local function after its name: parameters, body, and any `and` functions joined to it.
and private localFun (p: P) (ln: int) (isRec: bool) =
  parameters p |> ignore
  optTy p
  expect p Equals "'='"
  block p
  if peek p = Newline && peek2 p = And then
    if not isRec then
      failAt p p.pos.Value "functions joined with 'and' call each other: write 'let rec f … and g …'"
    while peek p = Newline && peek2 p = And do
      advance p
      advance p
      ident p
      if parameters p = 0 then
        failAt p p.pos.Value "'and' defines a function: and g x = …"
      optTy p
      expect p Equals "'='"
      block p
  finish p
  rest p ln

and private expr (p: P) =
  let k =
    match peek p with
    | Id when p.inSeq.Value > 0 && isWord p "yield" -> Some Tree.Yield
    | If -> Some Tree.If
    | Match -> Some Tree.Match
    | Handle -> Some Tree.Handle
    | Function -> Some Tree.Function
    | Fun -> Some Tree.Lambda
    | Unsafe -> Some Tree.Unsafe
    | While -> Some Tree.While
    | For -> Some Tree.For
    | _ -> None
  match k with
  | Some k ->
    start p k
    exprForm p
    finish p
  | None -> exprForm p

and private exprForm (p: P) =
  match peek p with
  | Id when p.inSeq.Value > 0 && isWord p "yield" ->
    // in a seq { }: yield e performs Yield.yield e; yield! s yields s's elements
    advance p
    bang p |> ignore
    expr p
  | Id when isWord p "try" && (peek2 p = Indent || peek2 p = Newline) ->
    errAt p "there's no try … with: a function that can fail returns a result (match on it, or use ? inside result { }), or throws a Throw effect, which Throw.catch turns into a result"
    pipe p
  | If ->
    advance p
    expr p
    expect p Then "'then'"
    block p
    if peek p = Newline && peek2 p = Else then
      advance p
    if peek p = Else then
      advance p
      block p
  | Match ->
    advance p
    expr p
    expect p With "'with'"
    cases p
  | Handle ->
    // handle e with | E.op p…, k -> … | return p -> …
    advance p
    if peek p = Indent then
      start p Tree.Block
      advance p
      seq p
      dedent p "end of block"
      finish p
      if peek p = Newline then
        advance p
    else
      expr p
    expect p With "'with'"
    handleCases p
  | Function ->
    advance p
    cases p
  | Fun ->
    advance p
    if parameters p = 0 then
      err p "parameter"
    expect p Arrow "'->'"
    block p
  | Unsafe ->
    advance p
    block p
  | While ->
    advance p
    expr p
    expect p Do "'do'"
    block p
  | For ->
    advance p
    // for x in …, or for <pattern> in xs
    let named = peek p = Id
    if named then ident p else pattern p
    expect p In "'in'"
    pipe p
    if peek p = Do then
      advance p
      block p
    else if not named then
      failAt p p.pos.Value "a pattern needs 'for … in <collection> do'; a range loop takes a name"
    else
      expect p DotDot "'..'"
      pipe p
      if peek p = DotDot then
        advance p
        pipe p
      expect p Do "'do'"
      block p
  | _ -> pipe p

/// A match's cases, after its `with`.
and private cases (p: P) = casesWith p 0

// a clause's body: 0 a block, 1 a list expression's, 2 a computation expression's
and private clauseBody (p: P) (how: int) =
  if how = 0 then block p else if how = 1 then compBlock p else ceBlock p

/// `| p when g -> e`, on one line each or in an indented block, the first '|' optional.
and private casesWith (p: P) (how: int) =
  let indented = peek p = Indent
  if indented then
    advance p
  if peek p = Newline && peek2 p = Bar then
    advance p
  clause p how
  while peek p = Bar || (peek p = Newline && peek2 p = Bar) do
    if peek p = Newline then
      advance p
    clause p how
  if indented then
    dedent p "end of block"

and private clause (p: P) (how: int) =
  start p Tree.Clause
  if peek p = Bar then
    advance p
  pattern p
  if peek p = When then
    advance p
    expr p
  expect p Arrow "'->'"
  clauseBody p how
  finish p

/// A handle's clauses: `| E.op p…, k -> body`, and `| return p -> body`.
and private handleCases (p: P) =
  let indented = peek p = Indent
  if indented then
    advance p
  let mutable returns = 0
  let mutable go = true
  while go do
    if peek p = Newline && peek2 p = Bar then
      advance p
    if peek p <> Bar then
      go <- false
    else
      start p Tree.Clause
      advance p
      if isWord p "return" then
        advance p
        pattern p
        expect p Arrow "'->'"
        if returns > 0 then
          errAt p "a handle has one return clause"
        returns <- returns + 1
        block p
      else if peek p = Id then
        advance p
        let mutable args = true
        while args && peek p <> Comma do
          if startsPatAtom (peek p) then
            patAtom p
          else
            err p "the operation's argument pattern, then ', k ->' (the resumption)"
            args <- false
        expect p Comma "','"
        ident p
        expect p Arrow "'->'"
        block p
      else
        skip p "an operation (Effect.op p…, k -> …) or return p -> …"
      finish p
  if indented then
    dedent p "end of block"

/// A list or array expression's body, after `[` or `[|`, up to its closer.
and private comprehension (p: P) (close: Kind) (what: string) =
  // its yields are its own, also inside a seq { }
  let outer = p.inSeq.Value
  p.inSeq.Value <- 0
  compSeq p close
  p.inSeq.Value <- outer
  expect p close what

// statements one after another (`;`, or a line break) until `stop`: a `let` takes the rest
and private compSeq (p: P) (stop: Kind) =
  if peek p = Let then
    start p Tree.Let
    advance p
    pattern p
    optTy p
    expect p Equals "'='"
    block p
    finish p
    if peek p = Newline || peek p = Semi || peek p = In then
      advance p
    compSeq p stop
  else
    compStmt p
    if peek p = Newline || peek p = Semi then
      advance p
      if peek p <> stop then
        compSeq p stop

/// The body of a list expression's `for`, `if` or match case: an indented block, or one
/// statement.
and private compBlock (p: P) =
  if peek p = Indent then
    start p Tree.Block
    advance p
    compSeq p Dedent
    dedent p "end of block"
    finish p
  else
    compStmt p

and private compStmt (p: P) =
  let k =
    match peek p with
    | For -> Some Tree.For
    | If -> Some Tree.If
    | Match -> Some Tree.Match
    | Id when isWord p "yield" -> Some Tree.Yield
    | _ -> None
  match k with
  | Some k ->
    start p k
    compForm p
    finish p
  | None -> compForm p

and private compForm (p: P) =
  let ln = p.pos.Value
  match peek p with
  | For ->
    advance p
    let named = peek p = Id
    if named then ident p else pattern p
    expect p In "'in'"
    pipe p
    if peek p = DotDot then
      advance p
      pipe p
      if peek p = DotDot then
        advance p
        pipe p
      if not named then
        failAt p ln "a range loop takes a name"
    compBody p
  | If ->
    advance p
    expr p
    expect p Then "'then'"
    compBlock p
    if peek p = Newline && peek2 p = Else then
      advance p
    if peek p = Else then
      advance p
      compBlock p
  | Match ->
    advance p
    expr p
    expect p With "'with'"
    casesWith p 1
  | Id when isWord p "yield" ->
    advance p
    bang p |> ignore
    expr p
  | _ ->
    let at = here p
    expr p
    assignment p at

// a list expression's `for` body: `-> e` (yielding e), or `do` and a body that yields
and private compBody (p: P) =
  if peek p = Arrow then
    advance p
    start p Tree.Yield
    block p
    finish p
  else
    expect p Do "'do' or '->'"
    compBlock p

// an expression without sequencing: the loosest level is ||
and private pipe (p: P) = orE p

// the levels from the loosest: 0 ||, 1 &&, 2 the comparisons, |> and >>, 3 |||, 4 ^^^, 5 &&&,
// 6 <<< and >>>, 7 :: and @, 8 + and -, 9 * / %, 10 **, 11 the prefix operators
and private level (p: P) (n: int) =
  match n with
  | 0 -> orE p
  | 1 -> andE p
  | 2 -> cmpE p
  | 7 -> consE p
  | 10 -> powE p
  | 11 -> unary p
  | _ -> binary p n

// the right operand of an operator: a lambda there extends to the end (m >>= fun x -> …)
and private operand (p: P) (n: int) =
  if peek p = Fun || peek p = Function then expr p else level p n

and private orE (p: P) =
  let at = here p
  andE p
  if peek p = OrElse then
    startAt p at Tree.Infix
    advance p
    orE p
    finish p

and private andE (p: P) =
  let at = here p
  cmpE p
  if peek p = AndAlso then
    startAt p at Tree.Infix
    advance p
    andE p
    finish p

/// Left-associative operators at a level, and the custom operators of the + and * levels.
and private binary (p: P) (n: int) =
  let at = here p
  level p (n + 1)
  let custom = if n = 8 then 2 else if n = 9 then 3 else -1
  let mutable chain = false
  let mutable go = true
  while go do
    let k = peek p
    if isOperatorOf n k then
      if not chain then
        chain <- true
        startAt p at Tree.Infix
      advance p
      level p (n + 1)
    else if k = Op && (textIs p p.pos.Value "++" || textIs p p.pos.Value "--") && (peek2 p = Newline || peek2 p = Dedent || peek2 p = Eof) then
      let s = textOf p p.pos.Value
      let c = String.sub s 0 1
      errAt p ("'" + s + "' isn't an operator: write x <- x " + c + " 1, or x " + c + "= 1")
      go <- false
    else if custom >= 0 && isInfix p && opLevel p = custom then
      if not chain then
        chain <- true
        startAt p at Tree.Infix
      advance p
      operand p (n + 1)
    else
      go <- false
  if chain then
    finish p

// as in F#, |>, >>, the comparisons and the custom operators starting with < > = | & $ share
// one left-associative level
and private cmpE (p: P) =
  let at = here p
  level p 3
  let mutable chain = false
  let mutable go = true
  while go do
    let k = peek p
    let comparison =
      match k with
      | Equals
      | NotEq
      | Lt
      | Gt
      | LtEq
      | GtEq -> true
      | _ -> false
    if comparison || k = PipeRight || k = Compose || (isInfix p && opLevel p = 0) then
      if not chain then
        chain <- true
        startAt p at Tree.Infix
      advance p
      if comparison then level p 3 else operand p 3
    else
      go <- false
  if chain then
    finish p

// right-associative ::, @ and custom operators starting with @ or ^
and private consE (p: P) =
  let at = here p
  level p 8
  let k = peek p
  if k = Cons || k = Append then
    startAt p at Tree.Infix
    advance p
    consE p
    finish p
  else if isInfix p && opLevel p = 1 then
    startAt p at Tree.Infix
    advance p
    operand p 7
    finish p

// right-associative custom operators starting with **
and private powE (p: P) =
  let at = here p
  unary p
  if isInfix p && opLevel p = 4 then
    startAt p at Tree.Infix
    advance p
    operand p 10
    finish p

and private unary (p: P) =
  match peek p with
  | Minus
  | Negate
  | NotBits
  | Not ->
    start p Tree.Prefix
    advance p
    unary p
    finish p
  | _ -> app p

and private startsAtom (p: P) : bool =
  match peek p with
  | Int
  | Char
  | Float
  | Str
  | Interp
  | Id
  | True
  | False
  | LParen
  | LBrack
  | LBrackBar
  | LBrace
  | Negate -> true
  | Op -> isPrefix p
  | _ -> false

// `f x?` applies ? to the whole application
and private app (p: P) =
  let at = here p
  atom p
  if startsAtom p then
    startAt p at Tree.Apply
    while startsAtom p do
      atom p
    finish p
  if peek p = Question then
    startAt p at Tree.Question
    advance p
    finish p

and private atom (p: P) =
  let at = here p
  primary p
  let mutable go = true
  while go do
    if peek p = LParen && adjacent p then
      // high-precedence application: f(x), x.M(a, b).N
      startAt p at Tree.Apply
      primary p
      finish p
    else if peek p = Dot then
      advance p
      if peek p = LBrack then
        // a.[i], or a slice: a.[i..j], a.[..j], a.[i..]
        startAt p at Tree.Index
        advance p
        if peek p = DotDot then
          advance p
          expr p
        else
          expr p
          if peek p = DotDot then
            advance p
            if peek p <> RBrack then
              expr p
        expect p RBrack "']'"
        finish p
      else
        startAt p at Tree.Field
        ident p
        finish p
    else
      go <- false

and private items (p: P) (close: Kind) (what: string) =
  let mutable go = true
  while go && peek p <> close && peek p <> Eof do
    expr p
    if peek p = Semi then
      advance p
    else if peek p <> close then
      err p ("';' or " + what)
      go <- false
  expect p close what

and private primary (p: P) =
  if not (startsAtom p) then
    skip p "expression"
  else
    let k = peek p
    let ti = p.pos.Value
    let at = here p
    advance p
    match k with
    | Int
    | Float -> measured p at
    | Interp -> holes p ti
    | Id when ceAhead p ->
      computation p ti
      wrap p at Tree.Computation
    | LBrace ->
      record p
      wrap p at Tree.Record
    | Negate
    | Op ->
      // -x, and a prefix operator: !r, ~~x
      atom p
      wrap p at Tree.Prefix
    | LBrack when peek p = For || isWord p "yield" ->
      comprehension p RBrack "']'"
      wrap p at Tree.ListComp
    | LBrackBar when peek p = For || isWord p "yield" ->
      comprehension p BarRBrack "'|]'"
      wrap p at Tree.ArrayComp
    | LBrack ->
      items p RBrack "']'"
      wrap p at Tree.List
    | LBrackBar ->
      items p BarRBrack "'|]'"
      wrap p at Tree.Array
    | LParen when peek2 p = RParen && (peek p = Op || isBuiltinOperator (peek p)) ->
      // an operator as a function: (>>=), or (+) for fun a b -> a + b
      advance p
      advance p
      wrap p at Tree.OperatorValue
    | LParen when peek p = RParen ->
      advance p
      wrap p at Tree.Unit
    | LParen ->
      expr p
      if peek p = Comma then
        while peek p = Comma do
          advance p
          expr p
        expect p RParen "')'"
        wrap p at Tree.Tuple
      else if peek p = Colon then
        // (e: T)
        advance p
        ty p |> ignore
        expect p RParen "')'"
        wrap p at Tree.Typed
      else
        expect p RParen "')'"
        wrap p at Tree.Paren
    | _ -> ()

// 9.58<s>: a measure right after a number literal (from `at`), if one parses there
and private measured (p: P) (at: int) =
  if peek p = Lt && adjacent p then
    let saved = save p
    startAt p at Tree.Measured
    advance p
    measure p
    if peek p = Gt && p.errors.Value = saved.errorCount then
      advance p
      finish p
    else
      restore p saved

// an interpolated string's holes (token ti), each parsed as an expression for its errors: the
// tree keeps the string as one token, and the view parses its holes again
and private holes (p: P) (ti: int) =
  let t = p.toks.[ti]
  let s = p.s
  let stop = t.offset + t.length - 1
  let mutable i = t.offset + 2
  while i < stop do
    let c = int (String.byte s i)
    if c = 92 then
      i <- i + 2
    else if (c = 123 || c = 125) && i + 1 < stop && int (String.byte s (i + 1)) = c then
      i <- i + 2
    else if c = 123 then
      // the hole may itself contain braces: {f { x = 1 }}
      let from = i + 1
      let mutable depth = 0
      i <- i + 1
      while i < stop && (int (String.byte s i) <> 125 || depth > 0) do
        let d = int (String.byte s i)
        if d = 123 then depth <- depth + 1 else if d = 125 then depth <- depth - 1
        i <- i + 1
      hole p ti from (i - from)
      i <- i + 1
    else
      i <- i + 1

// one hole, at offset `from`: its expression, then a width (,10) or a format specifier (:F2)
and private hole (p: P) (ti: int) (from: int) (length: int) =
  let text = String.sub p.s from length
  let cut = holeEnd text
  let code = if cut < 0 then text else String.sub text 0 cut
  if cut >= 0 then
    let rest = String.sub text cut (length - cut)
    let colon =
      match String.indexOf ":" rest with
      | Some k -> k
      | None -> -1
    let width =
      if String.byte rest 0 = u8 58 then ""
      else if colon < 0 then String.sub rest 1 (String.length rest - 1)
      else String.sub rest 1 (colon - 1)
    let spec =
      if String.byte rest 0 = u8 58 then String.sub rest 1 (String.length rest - 1)
      else if colon < 0 then ""
      else String.sub rest (colon + 1) (String.length rest - colon - 1)
    let hasWidth = String.byte rest 0 = u8 44
    if hasWidth && Option.isNone (Int.parse (String.trim width) : option<int>) then
      failAt p ti ("a hole's width is a number: {x,10}, or {x,-10} to pad on the right, not '," + width + "' (a tuple in a hole is written {(a, b)})")
    else if (String.byte rest 0 = u8 58 || colon >= 0) && not (isSpec spec) then
      failAt p ti ("a format specifier is a letter and at most two digits, as {x:F2} or {n:X8}, not ':" + spec + "'")
  let src = Source.make p.src.file p.src.path code
  let (toks, lexed) = collect (fun () -> Lexer.lex src)
  let h = make src toks
  start h Tree.File
  expr h
  if peek h <> Eof then
    err h "end of expression"
  // its errors, where they are in the file
  for d in Array.append lexed (Buffer.toArray h.diags) do
    p.errors.Value <- p.errors.Value + 1
    if ti > p.quiet.Value then
      Buffer.push { d with at = { d.at with file = p.src.file; offset = d.at.offset + from } } p.diags

/// After `{`: `{ f = e; … }` or `{ e with f = e; … }`.
and private record (p: P) =
  if peek p = Id && peek2 p = Equals then
    fields p
  else
    expr p
    if peek p = With then
      advance p
    else
      errAt p "braces don't make a block: a function body is its indented lines, and { } makes a record ({ x = 1; y = 2 } or { r with x = 1 })"
    fields p

and private fields (p: P) =
  let mutable go = true
  while go do
    let before = p.pos.Value
    start p Tree.FieldValue
    ident p
    expect p Equals "'='"
    expr p
    finish p
    if peek p = Semi then
      advance p
    go <- peek p <> RBrace && peek p <> Eof && p.pos.Value <> before
  expect p RBrace "'}'"

/// `w { … }` after its name (token ti): `seq { }` and `task { }` are bodies in direct style,
/// another builder's statements are calls of its functions.
and private computation (p: P) (ti: int) =
  advance p
  if textIs p ti "seq" then
    let outerTask = p.inTask.Value
    p.inSeq.Value <- p.inSeq.Value + 1
    p.inTask.Value <- 0
    ceBody p
    p.inSeq.Value <- p.inSeq.Value - 1
    p.inTask.Value <- outerTask
  else if textIs p ti "task" then
    p.inTask.Value <- p.inTask.Value + 1
    ceBody p
    p.inTask.Value <- p.inTask.Value - 1
  else
    ceBlock p
  expect p RBrace "'}'"

// a seq's or a task's body: an indented block, or one statement
and private ceBody (p: P) =
  if peek p = Indent then
    start p Tree.Block
    advance p
    seq p
    dedent p "end of block"
    finish p
  else
    block p

/// A block in a computation expression: after `then`, `else`, `do` or `->`.
and private ceBlock (p: P) =
  if peek p = Indent then
    start p Tree.Block
    advance p
    ceStmts p true
    dedent p "end of block"
    finish p
  else
    ceStmts p false

/// A computation expression's statements: with `many`, every statement of the block (one per
/// line), else one.
and private ceStmts (p: P) (many: bool) =
  let ln = p.pos.Value
  let kind =
    match peek p with
    | Let when bangAt p 1 -> Some Tree.LetBang
    | Do when bangAt p 1 -> Some Tree.DoBang
    | Id when isWord p "return" -> Some Tree.Return
    | Id when isWord p "use" && peek2 p = Id -> Some Tree.Use
    | Let -> Some Tree.Let
    | For -> Some Tree.For
    | If -> Some Tree.If
    | Match -> Some Tree.Match
    | _ -> None
  // the statement's node ends before the statements after it
  let closed = ref (Option.isNone kind)
  match kind with
  | Some k -> start p k
  | None -> ()
  match peek p with
  | Let when bangAt p 1 ->
    advance p
    advance p
    pattern p
    expect p Equals "'='"
    block p
    needNext p closed many ln "let!"
  | Do when bangAt p 1 ->
    advance p
    advance p
    block p
    ceNext p closed many |> ignore
  | Id when isWord p "return" ->
    advance p
    bang p |> ignore
    block p
    if many && peek p = Newline then
      failAt p p.pos.Value "nothing can follow return in a computation expression"
  | Id when isWord p "use" && peek2 p = Id ->
    advance p
    ident p
    expect p Equals "'='"
    block p
    ceNext p closed many |> ignore
  | For when forEachAhead p ->
    // for x in xs do: the builder's forEach; a range (for i in a .. b) is a plain loop
    advance p
    pattern p
    expect p In "'in'"
    pipe p
    expect p Do "'do'"
    ceBlock p
    ceNext p closed many |> ignore
  | If ->
    advance p
    expr p
    expect p Then "'then'"
    ceBlock p
    if peek p = Newline && peek2 p = Else then
      advance p
    if peek p = Else then
      advance p
      ceBlock p
    ceNext p closed many |> ignore
  | Match ->
    advance p
    expr p
    expect p With "'with'"
    casesWith p 2
    ceNext p closed many |> ignore
  | Let ->
    // a plain let: a value, or a local function
    advance p
    let isRec = peek p = Rec
    if isRec then
      advance p
    if peek p = Id && (isRec || startsLower p p.pos.Value) && not (textIs p p.pos.Value "_") && startsParam (peek2 p) then
      advance p
      parameters p |> ignore
    else
      pattern p
    optTy p
    expect p Equals "'='"
    block p
    needNext p closed many ln "let"
  | _ ->
    // a plain statement (of type unit)
    let at = here p
    expr p
    assignment p at
    ceNext p closed many |> ignore
  if not closed.Value then
    closed.Value <- true
    finish p

// after a statement of a computation expression: its node ended, then the statements after it;
// whether there were any
and private ceNext (p: P) (closed: ref<bool>) (many: bool) : bool =
  if not closed.Value then
    closed.Value <- true
    finish p
  if many && peek p = Newline then
    advance p
    ceStmts p true
    true
  else
    false

and private needNext (p: P) (closed: ref<bool>) (many: bool) (ln: int) (what: string) =
  if not (ceNext p closed many) then
    failAt p ln ("a computation expression can't end with " + what + ": return something after it")

// at `for` in a computation expression: whether `for p in xs do` follows (tried, and undone)
and private forEachAhead (p: P) : bool =
  let saved = save p
  advance p
  pattern p
  let ok =
    if peek p = In then
      advance p
      pipe p
      peek p = Do
    else
      false
  restore p saved
  ok

// ------------------------------------------------------------ declarations

let private caseField (p: P) =
  // payload field: optional 'name:' then a type
  if peek p = Id && peek2 p = Colon then
    advance p
    advance p
  tyAtom p |> ignore

let private unionCase (p: P) =
  start p Tree.Case
  if peek p = Bar then
    advance p
  ident p
  if peek p = Of then
    advance p
    caseField p
    while peek p = Star do
      advance p
      caseField p
  finish p

let private typeBody (p: P) =
  if peek p = Member || peek p = Static then
    // only members: a type with no values
    ()
  else if peek p = LBrace then
    start p Tree.RecordBody
    advance p
    let mutable go = true
    while go do
      let before = p.pos.Value
      if peek p = Mutable then
        errAt p "record fields can't be mutable: a record is a value; change one with { r with x = … }, bind it with let mutable, or make the field a ref<T>"
        advance p
      start p Tree.Field
      ident p
      expect p Colon "':'"
      ty p |> ignore
      if peek p = Equals then
        advance p
        expr p
      finish p
      if peek p = Semi then
        advance p
      go <- peek p <> RBrace && peek p <> Eof && p.pos.Value <> before
    expect p RBrace "'}'"
    finish p
  else
    start p Tree.UnionBody
    if peek p = Newline && peek2 p = Bar then
      advance p
    unionCase p
    while peek p = Bar || (peek p = Newline && peek2 p = Bar) do
      if peek p = Newline then
        advance p
      unionCase p
    finish p

let private memberDecl (p: P) =
  start p Tree.Member
  let isStatic = peek p = Static
  if isStatic then
    advance p
  expect p Member "'member'"
  if isStatic then
    ident p
  else
    // `V.Name` lexes as one qualified identifier
    let mutable dot = false
    if peek p = Id then
      let t = current p
      for k in t.offset .. t.offset + t.length - 1 do
        if String.byte p.s k = u8 46 then
          dot <- true
    ident p
    if not dot then
      expect p Dot "'.'"
      ident p
  if peek p = LParen then
    advance p
    let mutable go = true
    while go && peek p <> RParen && peek p <> Eof do
      let before = p.pos.Value
      let optional = peek p = Question
      if optional then
        advance p
      let ni = p.pos.Value
      ident p
      optTy p
      if peek p = Equals then
        if not optional then
          failAt p p.pos.Value ("a parameter with a default must be optional: write ?" + textOf p ni + " = ...")
        advance p
        expr p
      if peek p = Comma then
        advance p
      else if peek p <> RParen then
        err p "',' or ')'"
        go <- false
      if p.pos.Value = before then
        go <- false
    expect p RParen "')'"
  optTy p
  expect p Equals "'='"
  block p
  finish p

let private isMemberStart (k: Kind) : bool =
  match k with
  | Member
  | Static
  | With -> true
  | _ -> false

/// Members after a type body: optional `with`, on following (possibly indented) lines.
let private members (p: P) =
  let mutable opened = 0
  let mutable go = true
  while go do
    match peek p with
    | Newline when isMemberStart (peek2 p) -> advance p
    | Indent when isMemberStart (peek2 p) ->
      advance p
      opened <- opened + 1
    | With -> advance p
    | Member
    | Static -> memberDecl p
    | _ -> go <- false
  for _ in 1 .. opened do
    dedent p "end of members"

// at `=` in a type declaration: whether an alias follows, a type on its line (a record is
// { … }, and a union's cases have `|` or `of`)
let private aliasAhead (p: P) : bool =
  match ahead p 1 with
  | LBrace
  | Bar
  | Indent
  | Newline
  | Eof
  | Member
  | Static -> false
  | Id -> not (ahead p 2 = Of || ahead p 2 = Bar)
  | _ -> true

// a derive's or an impl's definitions: `let`s, one per line
let private definitions (p: P) =
  while peek p = Let do
    advance p
    ident p
    parameters p |> ignore
    optTy p
    expect p Equals "'='"
    block p
    if peek p = Newline then
      advance p

let private typeDecl (p: P) =
  advance p
  if peek p = Private then
    advance p
  ident p
  if peek p = LParen then
    errAt p "classes aren't in Z#: a type is a record { … }, a union | … or an alias; put its functions in a module, or add members to a record with `with`"
  if peek p = Lt then
    advance p
    typeVar p
    while peek p = Comma do
      advance p
      typeVar p
    closeAngle p
  if peek p = With then
    members p
  else if peek p = Newline || peek p = Eof then
    // [<Measure>] type m
    ()
  else if peek p = Equals && aliasAhead p then
    advance p
    ty p |> ignore
  else
    expect p Equals "'='"
    let indented = peek p = Indent
    if indented then
      advance p
    typeBody p
    members p
    if indented then
      dedent p "end of block"
    members p

// extern name : t1 -> t2 -> … -> ret, with `...` for a C function's variadic arguments
let private externDecl (p: P) (ln: int) =
  advance p
  ident p
  expect p Colon "':'"
  let items = Buffer.empty
  let item () =
    if peek p = Ellipsis then
      advance p
      Buffer.push true items
    else
      tupleTy p |> ignore
      Buffer.push false items
  item ()
  while peek p = Arrow do
    advance p
    item ()
  let n = Buffer.length items
  let mutable variadic = false
  for i in 0 .. n - 2 do
    if items.[i] then
      variadic <- true
  if items.[n - 1] then
    failAt p ln "'...' cannot be the return type"
  else if variadic && not items.[n - 2] then
    failAt p ln "'...' must be the last parameter"

// let at the top level: a value, a function (and the functions joined to it with `and`), an
// operator or an active pattern
let private letDecl (p: P) (ln: int) =
  advance p
  let isRec = peek p = Rec
  if isRec then
    advance p
  if peek p = Private then
    advance p
  if peek p = LParen && peek2 p = Bar then
    // an active pattern: (|Even|Odd|) or (|Int|_|)
    advance p
    advance p
    ident p
    while peek p = Bar && peek2 p <> RParen do
      advance p
      ident p
    expect p Bar "'|'"
    expect p RParen "')'"
  else if peek p = LParen && operatorAhead p then
    advance p
    operatorName p
  else
    ident p
  if parameters p = 0 then
    if isRec then
      failAt p ln "'let rec' needs parameters; a value can't refer to itself"
    optTy p
    expect p Equals "'='"
    block p
  else
    optTy p
    expect p Equals "'='"
    block p
    if peek p = Newline && peek2 p = And then
      if not isRec then
        failAt p p.pos.Value "functions joined with 'and' call each other: write 'let rec f … and g …'"
      while peek p = Newline && peek2 p = And do
        advance p
        let gl = p.pos.Value
        advance p
        if peek p = Private then
          advance p
        ident p
        if parameters p = 0 then
          failAt p gl "'and' defines a function: and g x = …"
        optTy p
        expect p Equals "'='"
        block p

let rec private decl (p: P) =
  let kind =
    match peek p with
    | LBrackLt -> Some Tree.Attributed
    | Open -> Some Tree.Open
    | Namespace -> Some Tree.Namespace
    | Module -> Some Tree.Module
    | Derive -> Some Tree.Derive
    | Type -> Some Tree.Type
    | Trait -> Some Tree.Trait
    | Effect -> Some Tree.Effect
    | Impl -> Some Tree.Impl
    | Id when isWord p "import" -> Some Tree.Import
    | Extern -> Some Tree.Extern
    | Let -> Some Tree.Let
    | _ -> None
  match kind with
  | Some k ->
    start p k
    declOf p
    finish p
  | None -> declOf p

and private declOf (p: P) =
  let ln = p.pos.Value
  match peek p with
  | LBrackLt ->
    // [<Name; Name(arg, arg)>] before a declaration
    start p Tree.Attributes
    advance p
    let mutable go = true
    while go && peek p <> GtRBrack && peek p <> Eof do
      let before = p.pos.Value
      ident p
      if peek p = Str then
        // [<Export "name">]
        advance p
      else if peek p = LParen then
        advance p
        while go && peek p <> RParen && peek p <> Eof do
          if peek p = Id || peek p = Str then
            advance p
          else
            skip p "attribute argument"
            go <- false
          if peek p = Comma then
            advance p
        expect p RParen "')'"
      if peek p = Semi then
        advance p
      if p.pos.Value = before then
        go <- false
    expect p GtRBrack "'>]'"
    finish p
    if peek p = Newline then
      advance p
    decl p
  | Open
  | Namespace ->
    advance p
    ident p
  | Module ->
    advance p
    ident p
    if peek p = Equals then
      // module Inner =, then its declarations, indented
      advance p
      expect p Indent "indented declarations"
      while peek p <> Dedent && peek p <> Eof do
        let before = p.pos.Value
        decl p
        if peek p = Newline then
          advance p
        if p.pos.Value = before then
          bump p
      dedent p "end of module"
  | Derive when ahead p 3 = Id ->
    // derive Json = ToJson, FromJson: a name for several derives
    advance p
    ident p
    expect p Equals "'='"
    ident p
    while peek p = Comma do
      advance p
      ident p
  | Derive ->
    // derive Json = let toJson (x: 'self) = ...
    advance p
    ident p
    expect p Equals "'='"
    expect p Indent "indented 'let' definitions"
    definitions p
    dedent p "end of derive"
  | Type -> typeDecl p
  | Trait ->
    // trait Show<'a> = abstract show : 'a -> string ...; trait Iter<'c, 'a> = …
    advance p
    ident p
    expect p Lt "'<'"
    typeVar p
    while peek p = Comma do
      advance p
      typeVar p
    closeAngle p
    expect p Equals "'='"
    expect p Indent "indented 'abstract' declarations"
    while peek p = Abstract do
      advance p
      ident p
      expect p Colon "':'"
      ty p |> ignore
      if peek p = Newline then
        advance p
    dedent p "end of trait"
  | Effect ->
    // effect Yield<'a> = abstract yield : 'a -> unit …
    advance p
    ident p
    if peek p = Lt then
      advance p
      typeVar p
      while peek p = Comma do
        advance p
        typeVar p
      closeAngle p
    expect p Equals "'='"
    let indented = peek p = Indent
    if indented then
      advance p
    let mutable ops = 0
    while peek p = Abstract do
      advance p
      ident p
      expect p Colon "':'"
      ty p |> ignore
      ops <- ops + 1
      if indented && peek p = Newline then
        advance p
    if ops = 0 then
      err p "'abstract' operations (abstract op : T -> R)"
    if indented then
      dedent p "end of effect"
  | Impl ->
    // impl Show<Point> = let show p = ...; impl Iter<list<'a>, 'a> = …
    advance p
    ident p
    expect p Lt "'<'"
    ty p |> ignore
    while peek p = Comma do
      advance p
      ty p |> ignore
    closeAngle p
    expect p Equals "'='"
    expect p Indent "indented 'let' definitions"
    definitions p
    dedent p "end of impl"
  | Id when isWord p "import" ->
    // import c "header.h"
    advance p
    if not (isWord p "c") then
      failAt p ln "expected 'c' after 'import': import c \"header.h\""
    else
      advance p
      if peek p = Str then advance p else failAt p ln "expected a header name: import c \"header.h\""
  | Extern -> externDecl p ln
  | Let -> letDecl p ln
  | _ ->
    err p "'let', 'type' or 'extern'"
    recover p false

// the tree the parser made
let private tree (p: P) : Tree.Tree =
  { tokens = Buffer.toArray p.toks
    lexed = p.eof + 1
    kinds = Buffer.toArray p.kinds
    firsts = Buffer.toArray p.firsts
    counts = Buffer.toArray p.counts
    children = Buffer.toArray p.children
    parents = Buffer.toArray p.parents
    starts = Buffer.toArray p.starts
    ends = Buffer.toArray p.ends }

// the tree and what's wrong in it, with no effects: so the parser's functions are their pure
// instances, whoever calls it
let private parseAll (src: Source.Source) (toks: array<Token>) : Tree.Tree * array<Diagnostic> / <> =
  let p = make src toks
  start p Tree.File
  while peek p <> Eof do
    let before = p.pos.Value
    decl p
    if peek p = Newline then
      advance p
    else if peek p <> Eof then
      err p "end of line"
      recover p false
      if peek p = Newline then
        advance p
    if p.pos.Value = before then
      bump p
  // the end of the file, with the text before it
  Buffer.push (-1 - p.eof) p.stack
  finish p
  (tree p, Buffer.toArray p.diags)

/// A file's tree, from its tokens; what's wrong in it is reported, and it has a tree anyway.
let parse (src: Source.Source) (toks: array<Token>) : Tree.Tree / Report =
  let (t, diags) = parseAll src toks
  for d in diags do
    Report.diagnostic d
  t
