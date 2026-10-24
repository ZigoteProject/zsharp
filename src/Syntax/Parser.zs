/// The parser (0019): a file's tokens to its tree and its AST, by recursive descent, as the F#
/// compiler's parser made them (`v0.5`; the two were compared on every file before it went). Where
/// a token is missing, it reports that and puts a missing token in the tree; where it can't go
/// on, it reports and skips into an Error node, to the end of the line at the block's
/// indentation. A mistake is reported once: no error is reported at a token an earlier error was
/// at or skipped to. An AST node's place is its token's index in the tree's tokens; an
/// interpolated string's holes are parsed from tokens of their own, added to the tree's (in no
/// node), so their places are in the tree too.
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
    /// the missing tokens' indices
    missingAt: Buffer<int>
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
    missingCount: int
    splitCount: int
    diagCount: int
    errorCount: int
    quietAt: int }

// a parser of toks from `start` to its end of the file at `eof` (a hole's tokens are the file's)
let private make (src: Source.Source) (toks: Buffer<Token>) (start: int) (eof: int) : P =
  { src = src
    s = src.text
    toks = toks
    eof = eof
    pos = ref start
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
    missingAt = Buffer.empty
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

// an identifier's name (``for`` is for)
let private idName (p: P) (i: int) : string =
  let t = p.toks.[i]
  if t.length > 4 && String.byte p.s t.offset = u8 96 then
    String.sub p.s (t.offset + 2) (t.length - 4)
  else
    Token.text p.s t

// a type variable's name, without its quote
let private tyVarName (p: P) (i: int) : string =
  let t = p.toks.[i]
  String.sub p.s (t.offset + 1) (t.length - 1)

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
    missingCount = Buffer.length p.missingAt
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
  Buffer.truncate s.missingCount p.missingAt
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

// the span of the line an offset is on, with no column (-1): its first character's
let private lineSpan (src: Source.Source) (offset: int) : Span =
  let line = Source.lineOf src offset
  let mutable o = src.lines.[line]
  while o < String.length src.text && String.byte src.text o = u8 32 do
    o <- o + 1
  { file = src.file; offset = o; length = -1 }

// an error about the line token i is on (the F# compiler's errors that have no column)
let private failAt (p: P) (i: int) (message: string) =
  p.errors.Value <- p.errors.Value + 1
  if i > p.quiet.Value then
    Buffer.push (error (lineSpan p.src p.toks.[i].offset) message) p.diags
    p.quiet.Value <- max i p.pos.Value

// how the current token reads in a message
let private found (p: P) : string =
  let t = current p
  match t.kind with
  | Semi when t.length = 0 -> "';'"
  | Negate -> "'~-'"
  | _ -> describe t.kind (Token.text p.s t)

let private err (p: P) (what: string) =
  reportAt p p.pos.Value ("expected " + what + ", found " + found p)

let private errAt (p: P) (message: string) = reportAt p p.pos.Value message

// a token expected here and not found: zero-width, where the next one starts
let private missing (p: P) (k: Kind) =
  Buffer.push (Buffer.length p.toks) p.missingAt
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

// ------------------------------------------------------------ the AST's pieces

// an expression at token i, or with no place of its own
let private ex (shape: Ast.ExprShape) (i: int) : Ast.Expr = Ast.expr shape i

let private plain (shape: Ast.ExprShape) : Ast.Expr = Ast.expr shape (-1)

// e with from's place, when from has one
let private copyPos (from: Ast.Expr) (e: Ast.Expr) : Ast.Expr =
  if from.at >= 0 then { e with at = from.at } else e

let private listOf (b: Buffer<'a>) : list<'a> = Array.toList (Buffer.toArray b)

// a :: b
let private cons (a: Ast.Expr) (b: Ast.Expr) : Ast.Expr =
  plain (Ast.Call("::", [ plain (Ast.Tuple [ a; b ]) ]))

// an integer token's value (0 after reporting one that doesn't fit)
let private intOf (p: P) (i: int) : i64 =
  match Literal.intValue (textOf p i) with
  | Ok v -> v
  | Error e ->
    failAt p i e
    0

// ------------------------------------------------------------ types

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

// whether token i is an operator of `>`s only, four or more (closing nested type arguments)
let private isGtRun (p: P) (i: int) : bool =
  let t = p.toks.[i]
  let mutable all = t.kind = Op && t.length > 3
  for j in t.offset .. t.offset + t.length - 1 do
    if String.byte p.s j <> u8 62 then
      all <- false
  all

// one `>` closing a type argument list, from a `>>`, a `>>>` or a longer run too
let private closeAngle (p: P) =
  match peek p with
  | Gt -> advance p
  | Compose -> split p Gt
  | ShiftRight -> split p Compose
  | Op when isGtRun p p.pos.Value -> split p (if p.toks.[p.pos.Value].length = 4 then ShiftRight else Op)
  | _ ->
    err p "'>'"
    missing p Gt

/// A unit of measure: m, m/s^2, kg m/s^2, 'u, 1 (inside <...> after a numeric type).
let rec private measure (p: P) : Ast.SType =
  start p Tree.Measure
  let m = product p
  finish p
  Ast.STMeasure m

and private product (p: P) : list<string * bool * int> =
  let mutable m = term p
  let mutable go = true
  while go do
    match peek p with
    | Star ->
      advance p
      m <- List.append m (term p)
    | Slash ->
      advance p
      m <- List.append m (List.map (fun (u, v, e) -> (u, v, -e)) (term p))
    | Id
    | TyVar
    | LParen -> m <- List.append m (term p) // juxtaposition multiplies: kg m
    | _ -> go <- false
  m

and private term (p: P) : list<string * bool * int> =
  let unitTerm =
    match peek p with
    | Id ->
      let u = idName p p.pos.Value
      advance p
      [ (u, false, 1) ]
    | TyVar ->
      let v = tyVarName p p.pos.Value
      advance p
      [ (v, true, 1) ]
    | Int when textIs p p.pos.Value "1" ->
      advance p
      []
    | LParen ->
      advance p
      let m = product p
      expect p RParen "')'"
      m
    | _ ->
      skip p "unit of measure"
      []
  if peek p = Caret then
    advance p
    let neg = peek p = Minus || peek p = Negate
    if neg then
      advance p
    if peek p = Int then
      let k = int (intOf p p.pos.Value)
      advance p
      let k = if neg then -k else k
      List.map (fun (u, v, e) -> (u, v, e * k)) unitTerm
    else
      skip p "exponent"
      unitTerm
  else
    unitTerm

let private typeVar (p: P) : string =
  if peek p = TyVar then
    let v = tyVarName p p.pos.Value
    advance p
    v
  else
    err p "type parameter"
    missing p TyVar
    ""

// the identifier here, its name read (and "" for a missing one)
let private name (p: P) : string =
  if peek p = Id then
    let n = idName p p.pos.Value
    advance p
    n
  else
    err p "identifier"
    missing p Id
    ""

let rec private tyAtom (p: P) : Ast.SType =
  let at = here p
  let first =
    match peek p with
    | Id when peek2 p = Lt && isNumericName p p.pos.Value ->
      let n = textOf p p.pos.Value
      start p Tree.TypeName
      advance p
      advance p
      let m = measure p
      closeAngle p
      finish p
      Ast.STName(n, [ m ])
    | TyVar ->
      let v = tyVarName p p.pos.Value
      advance p
      Ast.STVar v
    | Int ->
      // fixed<u8, 16>'s length (a number is a type argument of fixed only)
      let n = intOf p p.pos.Value
      advance p
      Ast.STName($"{n}", [])
    | Id when peek2 p = Id && textIs p p.pos.Value "dyn" ->
      // dyn Trait: a value of any type that implements the trait
      start p Tree.TypeName
      advance p
      let n = name p
      finish p
      Ast.STName("dyn", [ Ast.STName(n, []) ])
    | Id ->
      let n = idName p p.pos.Value
      advance p
      if peek p = Lt then
        startAt p at Tree.TypeName
        advance p
        let args = Buffer.empty
        Buffer.push (ty p) args
        while peek p = Comma do
          advance p
          Buffer.push (ty p) args
        closeAngle p
        finish p
        Ast.STName(n, listOf args)
      else
        Ast.STName(n, [])
    | LParen ->
      start p Tree.TypeParen
      advance p
      let t = ty p
      expect p RParen "')'"
      finish p
      t
    | _ ->
      skip p "type"
      Ast.STName("", [])
  // postfix application: int list, string option
  let mutable t = first
  while peek p = Id do
    startAt p at Tree.TypeName
    t <- Ast.STName(name p, [ t ])
    finish p
  t

and private tupleTy (p: P) : Ast.SType =
  let at = here p
  let first = tyAtom p
  if peek p = Star then
    startAt p at Tree.TypeTuple
    let items = Buffer.empty
    Buffer.push first items
    while peek p = Star do
      advance p
      Buffer.push (tyAtom p) items
    finish p
    Ast.STTuple(listOf items)
  else
    first

and private ty (p: P) : Ast.SType =
  let at = here p
  let t = tupleTy p
  if peek p = Arrow then
    startAt p at Tree.TypeFun
    advance p
    let r = ty p
    finish p
    Ast.STFun(t, r)
  else if peek p = Slash then
    // the effects after a function's result: / E, / 'e, / <E, F | 'e>, / <>
    startAt p at Tree.TypeRow
    advance p
    let r =
      match peek p with
      | NotEq ->
        advance p
        Ast.STRow(t, [], None)
      | TyVar ->
        let v = tyVarName p p.pos.Value
        advance p
        Ast.STRow(t, [], Some v)
      | Lt ->
        advance p
        let labels = Buffer.empty
        Buffer.push (label p) labels
        while peek p = Comma do
          advance p
          Buffer.push (label p) labels
        let tail =
          if peek p = Bar then
            advance p
            if peek p = TyVar then
              let v = tyVarName p p.pos.Value
              advance p
              Some v
            else
              err p "a row variable ('e)"
              missing p TyVar
              None
          else
            None
        closeAngle p
        Ast.STRow(t, listOf labels, tail)
      | _ -> Ast.STRow(t, [ label p ], None)
    finish p
    r
  else
    t

// an effect in a row: a named type
and private label (p: P) : Ast.SType =
  let t = tyAtom p
  match t with
  | Ast.STName _ -> ()
  | _ -> err p "an effect"
  t

let private optTy (p: P) : option<Ast.SType> =
  if peek p = Colon then
    start p Tree.Annotation
    advance p
    let t = ty p
    finish p
    Some t
  else
    None

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

let private plainPat (shape: Ast.PatShape) : Ast.Pat = Ast.pat shape (-1)

// a :: rest, as a pattern
let private patCons (a: Ast.Pat) (rest: Ast.Pat) : Ast.Pat =
  plainPat (Ast.PIdent("::", Some(plainPat (Ast.PTuple [ a; rest ]))))

let rec private pattern (p: P) : Ast.Pat =
  let at = here p
  let mutable q = orPat p
  while peek p = As do
    startAt p at Tree.PatternAs
    advance p
    q <- plainPat (Ast.PAs(q, name p))
    finish p
  q

// before '->', a line starting with '|' continues the or-pattern
and private orPat (p: P) : Ast.Pat =
  let at = here p
  let mutable q = tuplePat p
  let mutable chain = false
  while peek p = Bar || (peek p = Newline && peek2 p = Bar) do
    if not chain then
      chain <- true
      startAt p at Tree.PatternOr
    if peek p = Newline then
      advance p
    advance p
    q <- plainPat (Ast.POr(q, tuplePat p))
  if chain then
    finish p
  q

and private tuplePat (p: P) : Ast.Pat =
  let at = here p
  let first = consPat p
  if peek p = Comma then
    startAt p at Tree.PatternTuple
    let items = Buffer.empty
    Buffer.push first items
    while peek p = Comma do
      advance p
      Buffer.push (consPat p) items
    finish p
    plainPat (Ast.PTuple(listOf items))
  else
    first

and private consPat (p: P) : Ast.Pat =
  let at = here p
  let head = appPat p
  if peek p = Cons then
    startAt p at Tree.PatternCons
    advance p
    let tail = consPat p
    finish p
    patCons head tail
  else
    head

and private appPat (p: P) : Ast.Pat =
  if peek p = Id && startsPatAtom (peek2 p) && isCaseName p p.pos.Value then
    start p Tree.PatternCase
    let c = idName p p.pos.Value
    advance p
    let args = Buffer.empty
    while startsPatAtom (peek p) do
      Buffer.push (patAtom p) args
    finish p
    match listOf args with
    | [ a ] -> plainPat (Ast.PIdent(c, Some a))
    | ps -> plainPat (Ast.PIdent(c, Some(plainPat (Ast.PArgs ps))))
  else
    patAtom p

and private patAtom (p: P) : Ast.Pat =
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
    let q = patAtomOf p
    finish p
    q
  | None -> patAtomOf p

and private patAtomOf (p: P) : Ast.Pat =
  let t = peek p
  let ti = p.pos.Value
  if not (startsPatAtom t) then
    skip p "pattern"
    plainPat Ast.PWild
  else
    advance p
    match t with
    | Id when textIs p ti "_" -> plainPat Ast.PWild
    | Id -> Ast.pat (Ast.PIdent(idName p ti, None)) ti
    | Int -> plainPat (Ast.PInt(intOf p ti))
    | Char ->
      match Literal.charValue (textOf p ti) with
      | Ok c -> plainPat (Ast.PChar c)
      | Error e ->
        failAt p ti e
        plainPat Ast.PWild
    | Str ->
      match Literal.stringValue (textOf p ti) with
      | Ok s -> plainPat (Ast.PStr s)
      | Error e ->
        failAt p ti e
        plainPat Ast.PWild
    | Minus
    | Negate ->
      if peek p = Int then
        let n = intOf p p.pos.Value
        advance p
        plainPat (Ast.PInt(-n))
      else
        skip p "integer"
        plainPat Ast.PWild
    | True -> plainPat (Ast.PBool true)
    | False -> plainPat (Ast.PBool false)
    | LBrace ->
      // a record pattern: { field = pattern; ... } (line breaks separate fields too)
      let fields = Buffer.empty
      let mutable go = true
      while go && peek p <> RBrace && peek p <> Eof do
        let before = p.pos.Value
        let fi = p.pos.Value
        let f = name p
        expect p Equals "'='"
        Buffer.push (f, fi, pattern p) fields
        if peek p = Semi then
          advance p
        else if peek p <> RBrace then
          err p "';' or '}'"
          go <- false
        if p.pos.Value = before then
          go <- false
      expect p RBrace "'}'"
      if Buffer.length fields = 0 then
        failAt p p.pos.Value "a record pattern names at least one field: { x = x }"
      plainPat (Ast.PRecord(listOf fields))
    | LBrack ->
      let items = Buffer.empty
      let mutable go = true
      while go && peek p <> RBrack && peek p <> Eof do
        let before = p.pos.Value
        Buffer.push (pattern p) items
        if peek p = Semi then
          advance p
        if p.pos.Value = before then
          go <- false
      expect p RBrack "']'"
      List.fold (fun acc q -> patCons q acc) (plainPat (Ast.PIdent("[]", None))) (List.rev (listOf items))
    | LParen ->
      if peek p = RParen then
        advance p
        plainPat Ast.PUnit
      else if peek p = Id && peek2 p = Equals then
        // a constructor's fields by name: Rect(h = h)
        let fields = Buffer.empty
        let mutable go = true
        while go && peek p <> RParen && peek p <> Eof do
          let before = p.pos.Value
          let f = name p
          expect p Equals "'='"
          Buffer.push (f, pattern p) fields
          if peek p = Comma || peek p = Semi then
            advance p
          else if peek p <> RParen then
            err p "',' or ')'"
            go <- false
          if p.pos.Value = before then
            go <- false
        expect p RParen "')'"
        plainPat (Ast.PNamed(listOf fields))
      else
        let q = pattern p
        expect p RParen "')'"
        q
    | _ -> plainPat Ast.PWild

/// A function parameter: x, _, (), (x: T), (pattern), [pattern] or { record pattern }.
let private param (p: P) : Ast.Param =
  if peek p = LParen && ahead p 1 = Id && ahead p 2 = Colon then
    start p Tree.Parameter
    advance p
    let xi = p.pos.Value
    let x = name p
    advance p
    let t = ty p
    expect p RParen "')'"
    finish p
    ({ param = Ast.pat (Ast.PIdent(x, None)) xi; ann = Some t } : Ast.Param)
  else
    ({ param = patAtom p; ann = None } : Ast.Param)

let private startsParam (k: Kind) : bool =
  match k with
  | Id
  | LParen
  | LBrack
  | LBrace -> true
  | _ -> false

let private parameters (p: P) : list<Ast.Param> =
  let ps = Buffer.empty
  while startsParam (peek p) do
    Buffer.push (param p) ps
  listOf ps

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

// a compound assignment's operator: x += 1 is x <- x + 1
let private compoundOp (k: Kind) : string =
  match k with
  | PlusEq -> "+"
  | MinusEq -> "-"
  | StarEq -> "*"
  | SlashEq -> "/"
  | PercentEq -> "%"
  | AndBitsEq -> "&&&"
  | OrBitsEq -> "|||"
  | XorBitsEq -> "^^^"
  | _ -> ""

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

// a place `<-` can assign: a name, a field of a place, an element of one; a receiver that isn't
// a place, and an index, are bound to temporaries once ($place<token>.<n>), in order
let rec private place (p: P) (oi: int) (temps: Buffer<string * Ast.Expr>) (e: Ast.Expr) : option<Ast.Expr> =
  match e.e with
  | Ast.Var _ -> Some e
  | Ast.Field(r, f) -> Some(plain (Ast.Field(receiver p oi temps r, f)))
  | Ast.Index(a, i) ->
    let a = receiver p oi temps a
    Some(plain (Ast.Index(a, bound oi temps i)))
  | Ast.At inner
  | Ast.AtLine inner -> place p oi temps inner
  | _ -> None

and private receiver (p: P) (oi: int) (temps: Buffer<string * Ast.Expr>) (e: Ast.Expr) : Ast.Expr =
  match e.e with
  | Ast.Var _
  | Ast.Field _
  | Ast.Index _ ->
    match place p oi temps e with
    | Some r -> r
    | None -> bound oi temps e
  | _ -> bound oi temps e

and private bound (oi: int) (temps: Buffer<string * Ast.Expr>) (e: Ast.Expr) : Ast.Expr =
  match e.e with
  | Ast.Var _
  | Ast.Lit _ -> e
  | _ ->
    let t = $"$place{oi}.{Buffer.length temps}"
    Buffer.push (t, e) temps
    plain (Ast.Var t)

let rec private block (p: P) : Ast.Expr =
  if peek p = Indent then
    start p Tree.Block
    advance p
    let e = seq p
    dedent p "end of block"
    finish p
    e
  else
    // a one-line block is a statement too, so its errors have a position
    let si = p.pos.Value
    match taskForm p with
    | Some e -> ex (Ast.At e) si
    | None ->
      let at = here p
      let e = expr p
      ex (Ast.At(assignment p at e)) si

/// In a task's body: `return e` (the task's result), `return! t` and `do! t` (waiting for t);
/// None for anything else.
and private taskForm (p: P) : option<Ast.Expr> =
  if p.inTask.Value = 0 then
    None
  else if isWord p "return" then
    // return! t: the task t's result, which at the end of the body is t handed this task's
    // waiter ($awaitLast)
    start p Tree.Return
    advance p
    let awaitLast = bang p
    let b = block p
    finish p
    Some(if awaitLast then plain (Ast.Call("$awaitLast", [ b ])) else b)
  else if peek p = Do && bangAt p 1 then
    start p Tree.DoBang
    advance p
    advance p
    let b = block p
    finish p
    Some(plain (Ast.Call("$await", [ b ])))
  else
    None

// `!` right after a keyword: let!, do!, return!, yield!
and private bang (p: P) : bool =
  if bangAt p 0 && adjacent p then
    advance p
    true
  else
    false

/// After an expression lhs from `at`: `lhs <- rhs`, and compound assignment, `lhs += rhs`: lhs
/// <- lhs + rhs with the place evaluated once, its receiver and index bound first.
and private assignment (p: P) (at: int) (lhs: Ast.Expr) : Ast.Expr =
  let k = peek p
  if k = LArrow then
    startAt p at Tree.Assign
    advance p
    let rhs = expr p
    finish p
    plain (Ast.Assign(lhs, rhs))
  else if compoundOp k <> "" then
    let oi = p.pos.Value
    let s = textOf p oi
    startAt p at Tree.Assign
    advance p
    let rhs = expr p
    finish p
    let temps = Buffer.empty
    match place p oi temps lhs with
    | Some target ->
      let assign = ex (Ast.Assign(target, plain (Ast.Bin(compoundOp k, target, rhs)))) oi
      List.fold (fun acc (t, v) -> plain (Ast.Let(plainPat (Ast.PIdent(t, None)), None, v, acc))) assign (List.rev (listOf temps))
    | None ->
      failAt p oi (s + " needs a place <- can assign: a let mutable, a ref's .Value, an element or a field")
      plain (Ast.Assign(lhs, rhs))
  else
    lhs

/// After a binding at token ln: the rest of the block, from the next line.
and private rest (p: P) (ln: int) : Ast.Expr =
  if peek p = Newline then
    advance p
    seq p
  else
    failAt p ln "'let' must be followed by an expression on the next line"
    plain Ast.UnitLit

/// A block's statements.
and private seq (p: P) : Ast.Expr =
  let si = p.pos.Value
  let stmt (e: Ast.Expr) = ex (Ast.At e) si
  if isWord p "use" && peek2 p = Id then
    // use x = e: x is disposed (Dispose.dispose) after the rest of the block; in a task, also if
    // the task is cancelled before then
    start p Tree.Use
    advance p
    let xi = p.pos.Value
    let x = name p
    expect p Equals "'='"
    let v = block p
    finish p
    let after =
      if peek p = Newline then
        advance p
        seq p
      else
        failAt p si "'use' must be followed by the rest of the block on the next line"
        plain Ast.UnitLit
    let binder = Ast.pat (Ast.PIdent(x, None)) xi
    let var (n: string) = plain (Ast.Var n)
    let letIn (n: string) (v: Ast.Expr) (body: Ast.Expr) =
      plain (Ast.Let(plainPat (Ast.PIdent(n, None)), None, v, body))
    if p.inTask.Value > 0 then
      let id = $"$use{xi}"
      let onCancel =
        plain (Ast.Call(Ast.libraryName "Threading.Task.disposeOnCancel", [ var "$cancel"; var x ]))
      let disposed =
        plain (Ast.Call(Ast.libraryName "Threading.Task.disposed", [ var "$cancel"; var id; var x ]))
      stmt (plain (Ast.Let(binder,
            None,
            v,
            letIn id onCancel (letIn "$use" after (plain (Ast.Seq(disposed, var "$use")))))))
    else
      let dispose = plain (Ast.Call(Ast.libraryName "Dispose.dispose", [ var x ]))
      stmt (plain (Ast.Let(binder,
            None,
            v,
            letIn "$use" after (plain (Ast.Seq(dispose, var "$use"))))))
  else if p.inTask.Value > 0 && peek p = Let && bangAt p 1 then
    // let! p = t: the rest once the task t has given its result
    start p Tree.LetBang
    advance p
    advance p
    let q = pattern p
    expect p Equals "'='"
    let v = block p
    finish p
    stmt (plain (Ast.Let(q, None, plain (Ast.Call("$await", [ v ])), rest p si)))
  else if p.inTask.Value > 0 && (isWord p "return" || (peek p = Do && bangAt p 1)) then
    // return e: the block's (and the task's) result, last; do! t: then the rest
    let isReturn = isWord p "return"
    let e =
      match taskForm p with
      | Some e -> stmt e
      | None -> plain Ast.UnitLit
    if peek p = Newline then
      if isReturn then
        failAt p p.pos.Value "nothing can follow return in a task"
      advance p
      plain (Ast.Seq(e, seq p))
    else
      statementEnd p e
  else if peek p = Let then
    start p Tree.Let
    advance p
    let isRec = peek p = Rec
    if isRec then
      advance p
    if peek p = Mutable then
      advance p
      let x = name p
      let ann = optTy p
      expect p Equals "'='"
      let v = block p
      finish p
      stmt (plain (Ast.LetMut(x, ann, v, rest p si)))
    else if peek p = LParen && operatorAhead p then
      // a local operator: let (<+>) a b = …
      advance p
      let fi = p.pos.Value
      let f = operatorName p
      localFun p si isRec f fi
    else if peek p = Id && (isRec || startsLower p p.pos.Value) && not (textIs p p.pos.Value "_") && startsParam (peek2 p) then
      let fi = p.pos.Value
      let f = name p
      localFun p si isRec f fi
    else
      let q = pattern p
      let ann = optTy p
      expect p Equals "'='"
      let v = block p
      finish p
      match questioned v with
      | Some(qe, inner) when Option.isNone ann ->
        stmt (copyPos qe (plain (Ast.TryBind(q, inner, rest p si))))
      | _ -> stmt (plain (Ast.Let(q, ann, v, rest p si)))
  else
    let at = here p
    let e = assignment p at (expr p)
    match e.e with
    | Ast.Question inner when peek p = Newline ->
      advance p
      stmt (copyPos e (plain (Ast.TryBind(plainPat Ast.PWild, inner, seq p))))
    | _ -> statementEnd p (stmt e)

// `e?` or a statement holding just it: the Question and what it applies to
and private questioned (v: Ast.Expr) : option<Ast.Expr * Ast.Expr> =
  match v.e with
  | Ast.Question inner -> Some(v, inner)
  | Ast.At q ->
    match q.e with
    | Ast.Question inner -> Some(q, inner)
    | _ -> None
  | _ -> None

// after a statement e: the next one on the next line, or the block's end
and private statementEnd (p: P) (e: Ast.Expr) : Ast.Expr =
  if peek p = Newline then
    advance p
    plain (Ast.Seq(e, seq p))
  else if peek p <> Dedent && peek p <> Eof then
    err p "end of block"
    recover p false
    if peek p = Newline then
      advance p
      plain (Ast.Seq(e, seq p))
    else
      e
  else
    e

/// At `let (`: whether an operator and `)` follow.
and private operatorAhead (p: P) : bool =
  peek2 p <> Bar && isOperatorText p (min (p.pos.Value + 1) p.eof) && ahead p 2 = RParen

/// The operator of `(op)` after its `(`; a built-in one can't be defined.
and private operatorName (p: P) : string =
  let s = textOf p p.pos.Value
  if not (Lexer.isCustomOp s) then
    failAt p p.pos.Value ("'" + s + "' is built in and can't be redefined; give the custom operator another name, such as '" + s + ".'")
  advance p
  expect p RParen "')'"
  s

/// A local function after its name: parameters, body, and any `and` functions joined to it.
and private localFun (p: P) (si: int) (isRec: bool) (f: string) (fi: int) : Ast.Expr =
  let stmt (e: Ast.Expr) = ex (Ast.At e) si
  let ps = parameters p
  let ret = optTy p
  expect p Equals "'='"
  let body = block p
  if peek p = Newline && peek2 p = And then
    // let rec f … and g …: functions that call each other
    if not isRec then
      failAt p p.pos.Value "functions joined with 'and' call each other: write 'let rec f … and g …'"
    let members = Buffer.empty
    Buffer.push (ex (Ast.LetFun(f, true, ps, ret, body, plain Ast.UnitLit)) fi) members
    while peek p = Newline && peek2 p = And do
      advance p
      advance p
      let gi = p.pos.Value
      let g = name p
      let gps = parameters p
      if List.isEmpty gps then
        failAt p p.pos.Value "'and' defines a function: and g x = …"
      let gret = optTy p
      expect p Equals "'='"
      let gbody = block p
      Buffer.push (ex (Ast.LetFun(g, true, gps, gret, gbody, plain Ast.UnitLit)) gi) members
    finish p
    stmt (plain (Ast.LetRecGroup(listOf members, rest p si)))
  else
    finish p
    stmt (ex (Ast.LetFun(f, isRec, ps, ret, body, rest p si)) fi)

and private expr (p: P) : Ast.Expr =
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
    let e = exprForm p
    finish p
    e
  | None -> exprForm p

and private exprForm (p: P) : Ast.Expr =
  let si = p.pos.Value
  match peek p with
  | Id when p.inSeq.Value > 0 && isWord p "yield" ->
    // in a seq { }: yield e performs Yield.yield e; yield! s yields s's elements
    advance p
    if bang p then
      ex (Ast.AtLine(plain (Ast.Call("$yieldAll", [ expr p ])))) si
    else
      ex (Ast.AtLine(plain (Ast.Call("$yield", [ expr p ])))) si
  | Id when isWord p "try" && (peek2 p = Indent || peek2 p = Newline) ->
    errAt p "there's no try … with: a function that can fail returns a result (match on it, or use ? inside result { }), or throws a Throw effect, which Throw.catch turns into a result"
    pipe p
  | If ->
    advance p
    let c = expr p
    expect p Then "'then'"
    let t = block p
    if peek p = Newline && peek2 p = Else then
      advance p
    if peek p = Else then
      advance p
      plain (Ast.If(c, t, Some(block p)))
    else
      plain (Ast.If(c, t, None))
  | Match ->
    advance p
    let s = expr p
    expect p With "'with'"
    plain (Ast.Match(s, cases p))
  | Handle ->
    // handle e with | E.op p…, k -> … | return p -> …: e's operations of E given meaning
    advance p
    let body =
      if peek p = Indent then
        start p Tree.Block
        advance p
        let e = seq p
        dedent p "end of block"
        finish p
        if peek p = Newline then
          advance p
        e
      else
        expr p
    expect p With "'with'"
    let (ops, ret) = handleCases p
    plain (Ast.Handle(body, ops, ret))
  | Function ->
    // function | p -> … | q -> …: fun x -> match x with …, x a fresh name
    advance p
    let x = $"$function{si}"
    plain (Ast.Lambda([ ({ param = plainPat (Ast.PIdent(x, None)); ann = None } : Ast.Param) ],
        plain (Ast.Match(plain (Ast.Var x), cases p))))
  | Fun ->
    advance p
    let ps = parameters p
    if List.isEmpty ps then
      err p "parameter"
    expect p Arrow "'->'"
    plain (Ast.Lambda(ps, block p))
  | Unsafe ->
    // unsafe e, or unsafe and an indented block: raw pointer operations allowed inside
    advance p
    plain (Ast.Unsafe(block p))
  | While ->
    advance p
    let c = expr p
    expect p Do "'do'"
    plain (Ast.While(c, block p))
  | For ->
    advance p
    // for x in …, or for <pattern> in xs (a fresh name, taken apart at the top of the body)
    let named = peek p = Id
    let x = if named then name p else $"$for{p.pos.Value}"
    let destructure = if named then None else Some(pattern p)
    expect p In "'in'"
    let a = pipe p
    if peek p = Do then
      advance p
      let body = block p
      match destructure with
      | Some q -> plain (Ast.ForIn(x, a, plain (Ast.Let(q, None, plain (Ast.Var x), body))))
      | None -> plain (Ast.ForIn(x, a, body))
    else if Option.isSome destructure then
      failAt p p.pos.Value "a pattern needs 'for … in <collection> do'; a range loop takes a name"
      plain Ast.UnitLit
    else
      expect p DotDot "'..'"
      let b = pipe p
      let (step, b) =
        if peek p = DotDot then
          advance p
          (Some b, pipe p)
        else
          (None, b)
      expect p Do "'do'"
      plain (Ast.For(x, a, step, b, block p))
  | _ -> pipe p

/// A match's cases, after its `with` (or after `function`).
and private cases (p: P) : list<Ast.Clause> = casesWith p 0 ""

// a clause's body: 0 a block, 1 a list expression's, 2 a computation expression's
and private clauseBody (p: P) (how: int) (builder: string) : Ast.Expr =
  if how = 0 then block p else if how = 1 then compBlock p else ceBlock p builder

/// `| p when g -> e`, on one line each or in an indented block, the first '|' optional.
and private casesWith (p: P) (how: int) (builder: string) : list<Ast.Clause> =
  let indented = peek p = Indent
  if indented then
    advance p
  let found = Buffer.empty
  if peek p = Newline && peek2 p = Bar then
    advance p
  Buffer.push (clause p how builder) found
  while peek p = Bar || (peek p = Newline && peek2 p = Bar) do
    if peek p = Newline then
      advance p
    Buffer.push (clause p how builder) found
  if indented then
    dedent p "end of block"
  listOf found

and private clause (p: P) (how: int) (builder: string) : Ast.Clause =
  start p Tree.Clause
  if peek p = Bar then
    advance p
  let q = pattern p
  let guard =
    if peek p = When then
      advance p
      Some(expr p)
    else
      None
  expect p Arrow "'->'"
  let body = clauseBody p how builder
  finish p
  { pattern = q; guard = guard; body = body }

/// A handle's clauses: `| E.op p…, k -> body` for an operation (its arguments' patterns, then
/// the resumption's name, `_` when it's never resumed), `| return p -> body` for the result.
and private handleCases (p: P) : list<Ast.OpClause> * option<Ast.Pat * Ast.Expr> =
  let indented = peek p = Indent
  if indented then
    advance p
  let ops = Buffer.empty
  let mutable ret = None
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
        let q = pattern p
        expect p Arrow "'->'"
        if Option.isSome ret then
          errAt p "a handle has one return clause"
        ret <- Some(q, block p)
      else if peek p = Id then
        // the operation's name: its position is a reference to the operation
        let oi = p.pos.Value
        let op = name p
        let args = Buffer.empty
        let mutable more = true
        while more && peek p <> Comma do
          if startsPatAtom (peek p) then
            Buffer.push (patAtom p) args
          else
            err p "the operation's argument pattern, then ', k ->' (the resumption)"
            more <- false
        expect p Comma "','"
        let k = name p
        expect p Arrow "'->'"
        Buffer.push ({ op = op; opAt = oi; args = listOf args; k = k; opBody = block p } : Ast.OpClause) ops
      else
        skip p "an operation (Effect.op p…, k -> …) or return p -> …"
      finish p
  if indented then
    dedent p "end of block"
  (listOf ops, ret)

/// A list or array expression's body, after `[` or `[|`, up to its closer: `for`s, `if`s,
/// `let`s and `match`es whose statements `yield e` or `yield! xs` (or do something), and
/// `for x in xs -> e` for `for x in xs do yield e`.
and private comprehension (p: P) (isArray: bool) (close: Kind) (what: string) : Ast.Expr =
  // its yields are its own, also inside a seq { }
  let outer = p.inSeq.Value
  p.inSeq.Value <- 0
  let body = compSeq p close
  p.inSeq.Value <- outer
  expect p close what
  plain (Ast.ListComp(isArray, body))

// statements one after another (`;`, or a line break) until `stop`: a `let` takes the rest
and private compSeq (p: P) (stop: Kind) : Ast.Expr =
  if peek p = Let then
    start p Tree.Let
    advance p
    let q = pattern p
    let ann = optTy p
    expect p Equals "'='"
    let v = block p
    finish p
    if peek p = Newline || peek p = Semi || peek p = In then
      advance p
    plain (Ast.Let(q, ann, v, compSeq p stop))
  else
    let first = compStmt p
    if peek p = Newline || peek p = Semi then
      advance p
      if peek p = stop then first else plain (Ast.Seq(first, compSeq p stop))
    else
      first

/// The body of a list expression's `for`, `if` or match case: an indented block, or one
/// statement.
and private compBlock (p: P) : Ast.Expr =
  if peek p = Indent then
    start p Tree.Block
    advance p
    let e = compSeq p Dedent
    dedent p "end of block"
    finish p
    e
  else
    compStmt p

and private compStmt (p: P) : Ast.Expr =
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
    let e = compForm p
    finish p
    e
  | None -> compForm p

and private compForm (p: P) : Ast.Expr =
  let si = p.pos.Value
  let stmt (e: Ast.Expr) = ex (Ast.At e) si
  match peek p with
  | For ->
    advance p
    let named = peek p = Id
    let x = if named then name p else $"$for{p.pos.Value}"
    let destructure = if named then None else Some(pattern p)
    expect p In "'in'"
    let a = pipe p
    if peek p = DotDot then
      advance p
      let b = pipe p
      let (step, b) =
        if peek p = DotDot then
          advance p
          (Some b, pipe p)
        else
          (None, b)
      if Option.isSome destructure then
        failAt p si "a range loop takes a name"
      stmt (plain (Ast.For(x, a, step, b, compBody p)))
    else
      let b = compBody p
      match destructure with
      | Some q -> stmt (plain (Ast.ForIn(x, a, plain (Ast.Let(q, None, plain (Ast.Var x), b)))))
      | None -> stmt (plain (Ast.ForIn(x, a, b)))
  | If ->
    advance p
    let c = expr p
    expect p Then "'then'"
    let t = compBlock p
    if peek p = Newline && peek2 p = Else then
      advance p
    if peek p = Else then
      advance p
      stmt (plain (Ast.If(c, t, Some(compBlock p))))
    else
      stmt (plain (Ast.If(c, t, None)))
  | Match ->
    advance p
    let s = expr p
    expect p With "'with'"
    stmt (plain (Ast.Match(s, casesWith p 1 "")))
  | Id when isWord p "yield" ->
    advance p
    if bang p then stmt (plain (Ast.YieldAll(expr p))) else stmt (plain (Ast.Yield(expr p)))
  | _ ->
    let at = here p
    stmt (assignment p at (expr p))

// a list expression's `for` body: `-> e` (yielding e), or `do` and a body that yields
and private compBody (p: P) : Ast.Expr =
  if peek p = Arrow then
    advance p
    let yi = p.pos.Value
    start p Tree.Yield
    let b = block p
    finish p
    ex (Ast.At(plain (Ast.Yield b))) yi
  else
    expect p Do "'do' or '->'"
    compBlock p

// an expression without sequencing: the loosest level is ||
and private pipe (p: P) : Ast.Expr = orE p

// the levels from the loosest: 0 ||, 1 &&, 2 the comparisons, |> and >>, 3 |||, 4 ^^^, 5 &&&,
// 6 <<< and >>>, 7 :: and @, 8 + and -, 9 * / %, 10 **, 11 the prefix operators
and private level (p: P) (n: int) : Ast.Expr =
  match n with
  | 0 -> orE p
  | 1 -> andE p
  | 2 -> cmpE p
  | 7 -> consE p
  | 10 -> powE p
  | 11 -> unary p
  | _ -> binary p n

/// The right operand of a binary operator: a lambda there extends to the end, as in
/// `m >>= fun x -> …`.
and private operand (p: P) (n: int) : Ast.Expr =
  if peek p = Fun || peek p = Function then expr p else level p n

and private orE (p: P) : Ast.Expr =
  let at = here p
  let l = andE p
  if peek p = OrElse then
    startAt p at Tree.Infix
    advance p
    let r = orE p
    finish p
    plain (Ast.If(l, plain (Ast.BoolLit true), Some r))
  else
    l

and private andE (p: P) : Ast.Expr =
  let at = here p
  let l = cmpE p
  if peek p = AndAlso then
    startAt p at Tree.Infix
    advance p
    let r = andE p
    finish p
    plain (Ast.If(l, r, Some(plain (Ast.BoolLit false))))
  else
    l

/// Left-associative operators at a level, and the custom operators of the + and * levels.
and private binary (p: P) (n: int) : Ast.Expr =
  let at = here p
  let mutable l = level p (n + 1)
  let custom = if n = 8 then 2 else if n = 9 then 3 else -1
  let mutable chain = false
  let mutable go = true
  while go do
    let k = peek p
    let oi = p.pos.Value
    if isOperatorOf n k then
      if not chain then
        chain <- true
        startAt p at Tree.Infix
      let s = textOf p oi
      advance p
      l <- plain (Ast.Bin(s, l, level p (n + 1)))
    else if k = Op && (textIs p oi "++" || textIs p oi "--") && (peek2 p = Newline || peek2 p = Dedent || peek2 p = Eof) then
      let s = textOf p oi
      let c = String.sub s 0 1
      errAt p ("'" + s + "' isn't an operator: write x <- x " + c + " 1, or x " + c + "= 1")
      go <- false
    else if custom >= 0 && isInfix p && opLevel p = custom then
      if not chain then
        chain <- true
        startAt p at Tree.Infix
      let s = textOf p oi
      advance p
      l <- ex (Ast.Call(s, [ l; operand p (n + 1) ])) oi
    else
      go <- false
  if chain then
    finish p
  l

// as in F#, |>, >>, the comparisons and the custom operators starting with < > = | & $ share
// one left-associative level: x |> parse >>= validate is (x |> parse) >>= validate
and private cmpE (p: P) : Ast.Expr =
  let at = here p
  let mutable l = level p 3
  let mutable chain = false
  let mutable go = true
  while go do
    let k = peek p
    let oi = p.pos.Value
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
      let s = textOf p oi
      advance p
      if comparison then
        l <- plain (Ast.Bin(s, l, level p 3))
      else if k = PipeRight then
        // x |> f a  ==>  f a x
        let f = operand p 3
        let piped =
          match f.e with
          | Ast.Lambda([ q ], body) -> plain (Ast.Let(q.param, q.ann, l, body)) // x |> fun p -> body: let p = x, typed in order
          | Ast.Var g -> copyPos f (plain (Ast.Call(g, [ l ])))
          | Ast.Call(g, args) -> plain (Ast.Call(g, List.append args [ l ]))
          | Ast.App(h, args) -> plain (Ast.App(h, List.append args [ l ]))
          | _ -> plain (Ast.App(f, [ l ]))
        l <- piped
      else if k = Compose then
        // f >> g  ==>  fun x -> g (f x)
        let r = operand p 3
        let c = plain (Ast.Var "$c")
        l <- plain (Ast.Lambda([ ({ param = plainPat (Ast.PIdent("$c", None)); ann = None } : Ast.Param) ], plain (Ast.App(r, [ plain (Ast.App(l, [ c ])) ]))))
      else
        l <- ex (Ast.Call(s, [ l; operand p 3 ])) oi
    else
      go <- false
  if chain then
    finish p
  l

// right-associative ::, @ and custom operators starting with @ or ^
and private consE (p: P) : Ast.Expr =
  let at = here p
  let l = level p 8
  let k = peek p
  let oi = p.pos.Value
  if k = Cons then
    startAt p at Tree.Infix
    advance p
    let r = consE p
    finish p
    cons l r
  else if k = Append then
    startAt p at Tree.Infix
    advance p
    let r = consE p
    finish p
    plain (Ast.Call(Ast.libraryName "Collections.List.append", [ l; r ]))
  else if isInfix p && opLevel p = 1 then
    let s = textOf p oi
    startAt p at Tree.Infix
    advance p
    let r = operand p 7
    finish p
    ex (Ast.Call(s, [ l; r ])) oi
  else
    l

// right-associative custom operators starting with **
and private powE (p: P) : Ast.Expr =
  let at = here p
  let l = unary p
  let oi = p.pos.Value
  if isInfix p && opLevel p = 4 then
    let s = textOf p oi
    startAt p at Tree.Infix
    advance p
    let r = operand p 10
    finish p
    ex (Ast.Call(s, [ l; r ])) oi
  else
    l

and private unary (p: P) : Ast.Expr =
  match peek p with
  | Minus
  | Negate ->
    start p Tree.Prefix
    advance p
    let e = plain (Ast.Neg(unary p))
    finish p
    e
  | NotBits ->
    // bitwise not: x ^^^ (all ones)
    start p Tree.Prefix
    advance p
    let e = plain (Ast.Bin("^^^", unary p, plain (Ast.Lit -1)))
    finish p
    e
  | Not ->
    start p Tree.Prefix
    advance p
    let e = plain (Ast.Not(unary p))
    finish p
    e
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
and private app (p: P) : Ast.Expr =
  let at = here p
  let head = atom p
  let e =
    if startsAtom p then
      startAt p at Tree.Apply
      let args = Buffer.empty
      while startsAtom p do
        Buffer.push (atom p) args
      finish p
      match head.e with
      | Ast.Var f -> copyPos head (plain (Ast.Call(f, listOf args)))
      | _ -> plain (Ast.App(head, listOf args))
    else
      head
  if peek p = Question then
    let qi = p.pos.Value
    startAt p at Tree.Question
    advance p
    finish p
    ex (Ast.Question e) qi // errors about it point at the `?`
  else
    e

and private atom (p: P) : Ast.Expr =
  let at = here p
  let mutable e = primary p
  let mutable go = true
  while go do
    if peek p = LParen && adjacent p then
      // high-precedence application: f(x), x.M(a, b).N
      startAt p at Tree.Apply
      let arg = primary p
      finish p
      let applied =
        match e.e with
        | Ast.Var f -> copyPos e (plain (Ast.Call(f, [ arg ])))
        | Ast.Call(f, args) -> plain (Ast.Call(f, List.append args [ arg ]))
        | _ -> plain (Ast.App(e, [ arg ]))
      e <- applied
    else if peek p = Dot then
      advance p
      if peek p = LBrack then
        // a.[i], or a slice: a.[i..j], a.[..j], a.[i..]
        startAt p at Tree.Index
        advance p
        if peek p = DotDot then
          advance p
          let j = expr p
          expect p RBrack "']'"
          e <- plain (Ast.Slice(e, None, Some j))
        else
          let i = expr p
          if peek p = DotDot then
            advance p
            let j = if peek p = RBrack then None else Some(expr p)
            expect p RBrack "']'"
            e <- plain (Ast.Slice(e, Some i, j))
          else
            expect p RBrack "']'"
            e <- plain (Ast.Index(e, i))
        finish p
      else
        startAt p at Tree.Field
        let fi = p.pos.Value
        // after a dot, a name that reads as qualified (x.Value.index: Value.index is one token, as
        // it starts with a capital) is one field after another
        for f in String.split "." (name p) do
          e <- ex (Ast.Field(e, f)) fi
        finish p
    else
      go <- false
  e

and private items (p: P) (close: Kind) (what: string) : list<Ast.Expr> =
  let xs = Buffer.empty
  let mutable go = true
  while go && peek p <> close && peek p <> Eof do
    Buffer.push (expr p) xs
    if peek p = Semi then
      advance p
    else if peek p <> close then
      err p ("';' or " + what)
      go <- false
  expect p close what
  listOf xs

and private primary (p: P) : Ast.Expr =
  if not (startsAtom p) then
    skip p "expression"
    plain Ast.UnitLit
  else
    let k = peek p
    let ti = p.pos.Value
    let at = here p
    advance p
    match k with
    | Int -> measured p at (plain (Ast.Lit(intOf p ti)))
    | Char ->
      match Literal.charValue (textOf p ti) with
      | Ok c -> plain (Ast.CharLit c)
      | Error e ->
        failAt p ti e
        plain (Ast.CharLit 0)
    | Float -> measured p at (plain (Ast.FloatLit(Literal.floatValue (textOf p ti))))
    | Str ->
      match Literal.stringValue (textOf p ti) with
      | Ok s -> plain (Ast.StrLit s)
      | Error e ->
        failAt p ti e
        plain (Ast.StrLit "")
    | Interp -> interpolate p ti
    | Id when ceAhead p ->
      let e = computation p ti
      wrap p at Tree.Computation
      e
    | Id -> ex (Ast.Var(idName p ti)) ti
    | True -> plain (Ast.BoolLit true)
    | False -> plain (Ast.BoolLit false)
    | LBrace ->
      let e = record p
      wrap p at Tree.Record
      e
    | Negate ->
      let e = plain (Ast.Neg(atom p))
      wrap p at Tree.Prefix
      e
    | Op ->
      // a prefix operator: !r, ~~x
      let e = ex (Ast.Call(textOf p ti, [ atom p ])) ti
      wrap p at Tree.Prefix
      e
    | LBrack when peek p = For || isWord p "yield" ->
      let e = comprehension p false RBrack "']'"
      wrap p at Tree.ListComp
      e
    | LBrackBar when peek p = For || isWord p "yield" ->
      let e = comprehension p true BarRBrack "'|]'"
      wrap p at Tree.ArrayComp
      e
    | LBrack ->
      let e =
        List.fold (fun acc x -> cons x acc) (plain (Ast.Var "[]")) (List.rev (items p RBrack "']'"))
      wrap p at Tree.List
      e
    | LBrackBar ->
      let e = plain (Ast.ArrayLit(items p BarRBrack "'|]'"))
      wrap p at Tree.Array
      e
    | LParen when peek2 p = RParen && (peek p = Op || isBuiltinOperator (peek p)) ->
      // an operator as a function: (>>=), or (+) for fun a b -> a + b
      let oi = p.pos.Value
      let s = textOf p oi
      let custom = peek p = Op
      advance p
      advance p
      wrap p at Tree.OperatorValue
      if custom then
        ex (Ast.Var s) oi
      else
        let a = plain (Ast.Var "$a")
        let b = plain (Ast.Var "$b")
        let body =
          if s = "::" then cons a b
          else if s = "@" then plain (Ast.Call(Ast.libraryName "Collections.List.append", [ a; b ]))
          else plain (Ast.Bin(s, a, b))
        let par (n: string) : Ast.Param =
          ({ param = plainPat (Ast.PIdent(n, None)); ann = None } : Ast.Param)
        plain (Ast.Lambda([ par "$a"; par "$b" ], body))
    | LParen when peek p = RParen ->
      advance p
      wrap p at Tree.Unit
      plain Ast.UnitLit
    | LParen ->
      let first = expr p
      if peek p = Comma then
        let xs = Buffer.empty
        Buffer.push first xs
        while peek p = Comma do
          advance p
          Buffer.push (expr p) xs
        expect p RParen "')'"
        wrap p at Tree.Tuple
        plain (Ast.Tuple(listOf xs))
      else if peek p = Colon then
        // (e: T)
        advance p
        let t = ty p
        expect p RParen "')'"
        wrap p at Tree.Typed
        plain (Ast.Typed(first, t))
      else
        expect p RParen "')'"
        wrap p at Tree.Paren
        first
    | _ -> plain Ast.UnitLit

// 9.58<s>: a measure right after a number literal (from `at`), if one parses there
and private measured (p: P) (at: int) (lit: Ast.Expr) : Ast.Expr =
  if peek p = Lt && adjacent p then
    let saved = save p
    startAt p at Tree.Measured
    advance p
    let m = measure p
    if peek p = Gt && p.errors.Value = saved.errorCount then
      advance p
      finish p
      plain (Ast.Measured(lit, m))
    else
      restore p saved
      lit
  else
    lit

// $"a {x} b": "a " + show x + " b", each hole's expression parsed from its own tokens
and private interpolate (p: P) (ti: int) : Ast.Expr =
  let t = p.toks.[ti]
  match Literal.pieces (textOf p ti) with
  | Error e ->
    failAt p ti e
    plain (Ast.StrLit "")
  | Ok pieces ->
    let parts = Buffer.empty
    for piece in pieces do
      match piece with
      | Literal.Text s -> if s <> "" then Buffer.push (plain (Ast.StrLit s)) parts
      | Literal.Hole(code, from) -> Buffer.push (hole p ti code (t.offset + from)) parts
    let joined =
      match listOf parts with
      | [] -> plain (Ast.StrLit "")
      | first :: others -> List.fold (fun acc e -> plain (Ast.Bin("+", acc, e))) first others
    // forces type string
    plain (Ast.Bin("+", plain (Ast.StrLit ""), joined))

// a hole {e}, {e,width}, {e:spec} or {e,width:spec} (0024), its text at offset `from` in the file
and private hole (p: P) (ti: int) (text: string) (from: int) : Ast.Expr =
  let cut = holeEnd text
  let code = if cut < 0 then text else String.sub text 0 cut
  let rest = if cut < 0 then "" else String.sub text cut (String.length text - cut)
  let colon =
    match String.indexOf ":" rest with
    | Some k -> k
    | None -> -1
  let width =
    if rest = "" || String.byte rest 0 = u8 58 then None
    else if colon < 0 then Some(String.sub rest 1 (String.length rest - 1))
    else Some(String.sub rest 1 (colon - 1))
  let spec =
    if rest = "" then None
    else if String.byte rest 0 = u8 58 then Some(String.sub rest 1 (String.length rest - 1))
    else if colon < 0 then None
    else Some(String.sub rest (colon + 1) (String.length rest - colon - 1))
  let widthValue =
    match width with
    | Some w ->
      match (Int.parse (String.trim w) : option<int>) with
      | Some n -> Some n
      | None ->
        failAt p ti ("a hole's width is a number: {x,10}, or {x,-10} to pad on the right, not '," + w + "' (a tuple in a hole is written {(a, b)})")
        None
    | None -> None
  match spec with
  | Some sp when not (isSpec sp) ->
    failAt p ti ("a format specifier is a letter and at most two digits, as {x:F2} or {n:X8}, not ':" + sp + "'")
  | _ -> ()
  let e = holeExpr p ti code from
  // Show's and Format's, whatever `string` names where the hole is
  let shown =
    match spec with
    | Some sp -> plain (Ast.Call("$format", [ e; plain (Ast.StrLit sp) ]))
    | None -> plain (Ast.Call(Ast.libraryName "Show.show", [ e ]))
  match widthValue with
  | Some w when w < 0 ->
    plain (Ast.Call(Ast.libraryName "Text.String.padRight", [ plain (Ast.Lit(i64 (-w))); shown ]))
  | Some w ->
    plain (Ast.Call(Ast.libraryName "Text.String.padLeft", [ plain (Ast.Lit(i64 w)); shown ]))
  | None -> shown

// a hole's expression: its text lexed into tokens added to the tree's, at their places in the
// file, and parsed there; its first error is the string's line's (as in the F# compiler)
and private holeExpr (p: P) (ti: int) (code: string) (from: int) : Ast.Expr =
  let sub = Source.make p.src.file p.src.path code
  let (toks, lexed) = collect (fun () -> Lexer.lex sub)
  let base = Buffer.length p.toks
  for t in toks do
    Buffer.push { t with offset = t.offset + from } p.toks
  let h = make p.src p.toks base (base + Array.length toks - 1)
  start h Tree.File
  let e = expr h
  if peek h <> Eof then
    err h "end of expression"
  let found = Array.append lexed (Buffer.toArray h.diags)
  if Array.length found > 0 then
    failAt p ti found.[0].message
  e

/// After `{`: `{ f = e; … }` or `{ e with f = e; … }`.
and private record (p: P) : Ast.Expr =
  if peek p = Id && peek2 p = Equals then
    plain (Ast.RecordLit(fields p))
  else
    let e = expr p
    if peek p = With then
      advance p
    else
      errAt p "braces don't make a block: a function body is its indented lines, and { } makes a record ({ x = 1; y = 2 } or { r with x = 1 })"
    plain (Ast.Update(e, fields p))

and private fields (p: P) : list<Ast.FieldValue> =
  let items = Buffer.empty
  let mutable go = true
  while go do
    let before = p.pos.Value
    start p Tree.FieldValue
    let fi = p.pos.Value
    let f = name p
    expect p Equals "'='"
    let v = expr p
    Buffer.push ({ field = f; nameAt = fi; value = v } : Ast.FieldValue) items
    finish p
    if peek p = Semi then
      advance p
    go <- peek p <> RBrace && peek p <> Eof && p.pos.Value <> before
  expect p RBrace "'}'"
  listOf items

/// `w { … }` after its name (token ti), a computation expression (DESIGN §4): its statements
/// become calls of the builder module's functions (W.Builder: task { } uses Task.Builder):
/// `let!` and `do!` bind, `return` ret, `use` using, `for` forEach, and an `if` without
/// `else`, or a body ending in a plain statement, zero. `return!` is the computation itself.
/// The whole body is given to delay as a function, so a cold computation (a task) runs it when
/// it runs. seq { } and task { } are bodies in direct style.
and private computation (p: P) (ti: int) : Ast.Expr =
  let w = textOf p ti
  let first = int (String.byte w 0)
  let builder =
    (if first >= 97 && first <= 122 then String.ofByte (u8 (first - 32)) else String.sub w 0 1) + String.sub w 1 (String.length w - 1) + ".Builder."
  let unitParam : Ast.Param = ({ param = plainPat Ast.PUnit; ann = None } : Ast.Param)
  advance p
  let e =
    if w = "seq" then
      // a sequence: its body in direct style, run when the sequence is consumed; a yield
      // anywhere in it (in a lambda too) is the Yield effect's, yield! another's elements
      let outerTask = p.inTask.Value
      p.inSeq.Value <- p.inSeq.Value + 1
      p.inTask.Value <- 0
      let body = ceBody p
      p.inSeq.Value <- p.inSeq.Value - 1
      p.inTask.Value <- outerTask
      ex (Ast.AtLine(plain (Ast.Call("$seq", [ plain (Ast.Lambda([ unitParam ], body)) ])))) ti
    else if w = "task" then
      // a task: its body in direct style, with let!, do! and return!, which the compiler makes
      // a state machine of ($task, $await)
      p.inTask.Value <- p.inTask.Value + 1
      let body = ceBody p
      p.inTask.Value <- p.inTask.Value - 1
      ex (Ast.AtLine(plain (Ast.Call("$task", [ plain (Ast.Lambda([ unitParam ], body)) ])))) ti
    else
      let body = ceBlock p builder
      ex (Ast.AtLine(plain (Ast.Call(builder + "delay", [ plain (Ast.Lambda([ unitParam ], body)) ])))) ti
  expect p RBrace "'}'"
  e

// a seq's or a task's body: an indented block, or one statement
and private ceBody (p: P) : Ast.Expr =
  if peek p = Indent then
    start p Tree.Block
    advance p
    let e = seq p
    dedent p "end of block"
    finish p
    e
  else
    block p

/// A block in a computation expression: after `then`, `else`, `do` or `->`.
and private ceBlock (p: P) (builder: string) : Ast.Expr =
  if peek p = Indent then
    start p Tree.Block
    advance p
    let e = ceStmts p builder true
    dedent p "end of block"
    finish p
    e
  else
    ceStmts p builder false

/// A computation expression's statements: with `many`, every statement of the block (one per
/// line), else one (a block on the line it starts).
and private ceStmts (p: P) (builder: string) (many: bool) : Ast.Expr =
  let si = p.pos.Value
  let stmt (e: Ast.Expr) = ex (Ast.At e) si
  let call (f: string) (args: list<Ast.Expr>) = plain (Ast.Call(builder + f, args))
  let lam (q: Ast.Pat) (body: Ast.Expr) =
    plain (Ast.Lambda([ ({ param = q; ann = None } : Ast.Param) ], body))
  let unitPat = plainPat Ast.PUnit
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
  let r =
    match peek p with
    | Let when bangAt p 1 ->
      advance p
      advance p
      let q = pattern p
      expect p Equals "'='"
      let v = block p
      stmt (call "bind" [ v; lam q (needNext p builder closed many si "let!") ])
    | Do when bangAt p 1 ->
      advance p
      advance p
      let v = block p
      let after =
        match ceNext p builder closed many with
        | Some r -> r
        | None -> call "ret" [ plain Ast.UnitLit ]
      stmt (call "bind" [ v; lam unitPat after ])
    | Id when isWord p "return" ->
      advance p
      let e = if bang p then block p else call "ret" [ block p ]
      if many && peek p = Newline then
        failAt p p.pos.Value "nothing can follow return in a computation expression"
      stmt e
    | Id when isWord p "use" && peek2 p = Id ->
      advance p
      let xi = p.pos.Value
      let x = name p
      expect p Equals "'='"
      let v = block p
      let after =
        match ceNext p builder closed many with
        | Some r -> r
        | None -> call "zero" [ plain Ast.UnitLit ]
      stmt (call "using" [ v; lam (Ast.pat (Ast.PIdent(x, None)) xi) after ])
    | For when forEachAhead p ->
      // for x in xs do: the builder's forEach; a range (for i in a .. b) is a plain loop
      advance p
      let q = pattern p
      expect p In "'in'"
      let xs = pipe p
      expect p Do "'do'"
      let body = ceBlock p builder
      thenRest p builder closed many stmt (call "forEach" [ xs; lam q body ])
    | If ->
      advance p
      let c = expr p
      expect p Then "'then'"
      let t = ceBlock p builder
      if peek p = Newline && peek2 p = Else then
        advance p
      let e =
        if peek p = Else then
          advance p
          ceBlock p builder
        else
          call "zero" [ plain Ast.UnitLit ]
      thenRest p builder closed many stmt (plain (Ast.If(c, t, Some e)))
    | Match ->
      advance p
      let s = expr p
      expect p With "'with'"
      let cs = casesWith p 2 builder
      thenRest p builder closed many stmt (plain (Ast.Match(s, cs)))
    | Let ->
      // a plain let: a value, or a local function
      advance p
      let isRec = peek p = Rec
      if isRec then
        advance p
      if peek p = Id && (isRec || startsLower p p.pos.Value) && not (textIs p p.pos.Value "_") && startsParam (peek2 p) then
        let fi = p.pos.Value
        let f = name p
        let ps = parameters p
        let ret = optTy p
        expect p Equals "'='"
        let body = block p
        stmt (ex (Ast.LetFun(f, isRec, ps, ret, body, needNext p builder closed many si "let")) fi)
      else
        let q = pattern p
        let ann = optTy p
        expect p Equals "'='"
        let v = block p
        stmt (plain (Ast.Let(q, ann, v, needNext p builder closed many si "let")))
    | _ ->
      // a plain statement (of type unit)
      let at = here p
      let e = assignment p at (expr p)
      match ceNext p builder closed many with
      | Some after -> stmt (plain (Ast.Seq(e, after)))
      | None -> stmt (plain (Ast.Seq(e, call "zero" [ plain Ast.UnitLit ])))
  if not closed.Value then
    closed.Value <- true
    finish p
  r

// after a statement of a computation expression: its node ended, then the statements after it
and private ceNext (p: P) (builder: string) (closed: ref<bool>) (many: bool) : option<Ast.Expr> =
  if not closed.Value then
    closed.Value <- true
    finish p
  if many && peek p = Newline then
    advance p
    Some(ceStmts p builder true)
  else
    None

and private needNext (p: P) (builder: string) (closed: ref<bool>) (many: bool) (si: int) (what: string) : Ast.Expr =
  match ceNext p builder closed many with
  | Some r -> r
  | None ->
    failAt p si ("a computation expression can't end with " + what + ": return something after it")
    plain Ast.UnitLit

// a statement giving the builder's unit, then the rest
and private thenRest (p: P) (builder: string) (closed: ref<bool>) (many: bool) (stmt: Ast.Expr -> Ast.Expr) (e: Ast.Expr) : Ast.Expr =
  match ceNext p builder closed many with
  | Some after ->
    stmt (plain (Ast.Call(builder + "bind", [ e; plain (Ast.Lambda([ ({ param = plainPat Ast.PUnit
                      ann = None } : Ast.Param) ], after)) ])))
  | None -> stmt e

// at `for` in a computation expression: whether `for p in xs do` follows (tried, and undone)
and private forEachAhead (p: P) : bool =
  let saved = save p
  advance p
  pattern p |> ignore
  let ok =
    if peek p = In then
      advance p
      pipe p |> ignore
      peek p = Do
    else
      false
  restore p saved
  ok

// ------------------------------------------------------------ declarations

let private caseField (p: P) : option<string> * Ast.SType =
  // payload field: optional 'name:' then a type
  if peek p = Id && peek2 p = Colon then
    let n = idName p p.pos.Value
    advance p
    advance p
    (Some n, tyAtom p)
  else
    (None, tyAtom p)

let private unionCase (p: P) : Ast.Case =
  start p Tree.Case
  if peek p = Bar then
    advance p
  let c = name p
  let fields = Buffer.empty
  if peek p = Of then
    advance p
    Buffer.push (caseField p) fields
    while peek p = Star do
      advance p
      Buffer.push (caseField p) fields
  finish p
  { case = c; fields = listOf fields }

let private typeBody (p: P) : Ast.TypeBody =
  if peek p = Member || peek p = Static then
    // only members: a type with no values
    Ast.UnionTy []
  else if peek p = LBrace then
    start p Tree.RecordBody
    advance p
    let fields = Buffer.empty
    let mutable go = true
    while go do
      let before = p.pos.Value
      if peek p = Mutable then
        errAt p "record fields can't be mutable: a record is a value; change one with { r with x = … }, bind it with let mutable, or make the field a ref<T>"
        advance p
      start p Tree.Field
      let fi = p.pos.Value
      let f = name p
      expect p Colon "':'"
      let t = ty p
      let def =
        if peek p = Equals then
          advance p
          Some(expr p)
        else
          None
      finish p
      Buffer.push ({ name = f; fieldAt = fi; ty = t; default = def } : Ast.RecordField) fields
      if peek p = Semi then
        advance p
      go <- peek p <> RBrace && peek p <> Eof && p.pos.Value <> before
    expect p RBrace "'}'"
    finish p
    Ast.RecordTy(listOf fields)
  else
    start p Tree.UnionBody
    let cases = Buffer.empty
    if peek p = Newline && peek2 p = Bar then
      advance p
    Buffer.push (unionCase p) cases
    while peek p = Bar || (peek p = Newline && peek2 p = Bar) do
      if peek p = Newline then
        advance p
      Buffer.push (unionCase p) cases
    finish p
    Ast.UnionTy(listOf cases)

let private memberDecl (p: P) : Ast.Member =
  start p Tree.Member
  let mi = p.pos.Value
  let isStatic = peek p = Static
  if isStatic then
    advance p
  expect p Member "'member'"
  let (self, mname) =
    if isStatic then
      (None, name p)
    else
      let a = name p
      match String.indexOf "." a with
      | Some k -> (Some(String.sub a 0 k), String.sub a (k + 1) (String.length a - k - 1)) // `V.Name` lexes as one qualified identifier
      | None ->
        expect p Dot "'.'"
        (Some a, name p)
  let pars =
    if peek p = LParen then
      advance p
      let ps = Buffer.empty
      let mutable go = true
      while go && peek p <> RParen && peek p <> Eof do
        let before = p.pos.Value
        let optional = peek p = Question
        if optional then
          advance p
        let n = name p
        let t = optTy p
        let d =
          if peek p = Equals then
            if not optional then
              failAt p p.pos.Value ("a parameter with a default must be optional: write ?" + n + " = ...")
            advance p
            Some(expr p)
          else
            None
        Buffer.push ({ mname = n; mty = t; optional = optional; mdefault = d } : Ast.MemberParam) ps
        if peek p = Comma then
          advance p
        else if peek p <> RParen then
          err p "',' or ')'"
          go <- false
        if p.pos.Value = before then
          go <- false
      expect p RParen "')'"
      Some(listOf ps)
    else
      None
  let ret = optTy p
  expect p Equals "'='"
  let body = block p
  finish p
  { memberName = mname
    isStatic = isStatic
    self = self
    mpars = pars
    mret = ret
    mbody = body
    mat = mi }

let private isMemberStart (k: Kind) : bool =
  match k with
  | Member
  | Static
  | With -> true
  | _ -> false

/// Members after a type body: optional `with`, on following (possibly indented) lines.
let private members (p: P) : list<Ast.Member> =
  let ms = Buffer.empty
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
    | Static -> Buffer.push (memberDecl p) ms
    | _ -> go <- false
  for _ in 1 .. opened do
    dedent p "end of members"
  listOf ms

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
let private definitions (p: P) : list<Ast.Definition> =
  let defs = Buffer.empty
  while peek p = Let do
    let di = p.pos.Value
    advance p
    let f = name p
    let ps = parameters p
    let ret = optTy p
    expect p Equals "'='"
    let body = block p
    Buffer.push ({ defAt = di; dname = f; dpars = ps; dret = ret; dbody = body } : Ast.Definition) defs
    if peek p = Newline then
      advance p
  listOf defs

let private typeParams (p: P) : list<string> =
  let tps = Buffer.empty
  if peek p = Lt then
    advance p
    Buffer.push (typeVar p) tps
    while peek p = Comma do
      advance p
      Buffer.push (typeVar p) tps
    closeAngle p
  listOf tps

// after `type` or `and`: a record, a union, an alias, or members for an existing type
let private typeDef (p: P) (ln: int) : Ast.Decl =
  let isPrivate = peek p = Private
  if isPrivate then
    advance p
  let n = name p
  if peek p = LParen then
    errAt p "classes aren't in Z#: a type is a record { … }, a union | … or an alias; put its functions in a module, or add members to a record with `with`"
  let tps = typeParams p
  let d =
    if peek p = With then
      Ast.TypeExt(n, tps, members p)
    else if peek p = Newline || peek p = Eof then
      // [<Measure>] type m
      Ast.TypeDecl(n, [], Ast.UnionTy [], [])
    else if peek p = Equals && aliasAhead p then
      advance p
      Ast.TypeAlias(n, tps, ty p)
    else
      expect p Equals "'='"
      let indented = peek p = Indent
      if indented then
        advance p
      let body = typeBody p
      let inner = members p
      if indented then
        dedent p "end of block"
      Ast.TypeDecl(n, tps, body, List.append inner (members p))
  if isPrivate then Ast.decl (Ast.Private(Ast.decl d ln)) ln else Ast.decl d ln

// type Name …, and the types joined to it with `and`
let private typeDecl (p: P) (ln: int) : Ast.Decl =
  advance p
  let first = typeDef p ln
  if peek p = Newline && peek2 p = And then
    // type A = … and B = …: types that name each other
    let members = Buffer.empty
    Buffer.push first members
    while peek p = Newline && peek2 p = And do
      advance p
      let al = p.pos.Value
      advance p
      Buffer.push (typeDef p al) members
    Ast.decl (Ast.TypeGroup(listOf members)) ln
  else
    first

// extern name : t1 -> t2 -> … -> ret, with `...` for a C function's variadic arguments
let private externDecl (p: P) (ln: int) : Ast.Decl =
  advance p
  let n = name p
  expect p Colon "':'"
  let items = Buffer.empty
  let item () =
    if peek p = Ellipsis then
      advance p
      Buffer.push None items
    else
      Buffer.push (Some(tupleTy p)) items
  item ()
  while peek p = Arrow do
    advance p
    item ()
  let all = listOf items
  let count = List.length all
  let pars = List.take (count - 1) all
  let variadic = List.exists Option.isNone pars
  let ret =
    match List.last all with
    | Some t -> t
    | None ->
      failAt p ln "'...' cannot be the return type"
      Ast.STName("unit", [])
  if variadic && Option.isSome (List.last pars) then
    failAt p ln "'...' must be the last parameter"
  let args =
    pars |> List.choose id |> List.filter (fun (t: Ast.SType) -> t <> Ast.STName("unit", []))
  Ast.decl (Ast.Extern(n, args, variadic, ret)) ln

// let at the top level: a value, a function (and the functions joined to it with `and`), an
// operator or an active pattern
let private letDecl (p: P) (ln: int) : Ast.Decl =
  advance p
  let isRec = peek p = Rec
  if isRec then
    advance p
  let isPrivate = peek p = Private
  if isPrivate then
    advance p
  let ni = p.pos.Value
  let (ni, n) =
    if peek p = LParen && peek2 p = Bar then
      // an active pattern: (|Even|Odd|) or (|Int|_|)
      advance p
      advance p
      let names = Buffer.empty
      Buffer.push (name p) names
      while peek p = Bar && peek2 p <> RParen do
        advance p
        Buffer.push (name p) names
      expect p Bar "'|'"
      expect p RParen "')'"
      (ni, "|" + String.join "|" (listOf names) + "|")
    else if peek p = LParen && operatorAhead p then
      advance p
      let oi = p.pos.Value
      (oi, operatorName p)
    else
      (ni, name p)
  let ps = parameters p
  let wrapPrivate (yes: bool) (d: Ast.Decl) = if yes then Ast.decl (Ast.Private d) d.dat else d
  if List.isEmpty ps then
    // a top-level value: let name [: T] = expr
    if isRec then
      failAt p ln "'let rec' needs parameters; a value can't refer to itself"
    let ann = optTy p
    expect p Equals "'='"
    let v = { Ast.decl (Ast.Value(n, ann, block p)) ln with named = ni }
    wrapPrivate isPrivate v
  else
    let ret = optTy p
    expect p Equals "'='"
    let f = { Ast.decl (Ast.Fun(n, isRec, ps, ret, block p)) ln with named = ni }
    let first = wrapPrivate isPrivate f
    if peek p = Newline && peek2 p = And then
      // let rec f … and g …: functions that call each other
      if not isRec then
        failAt p p.pos.Value "functions joined with 'and' call each other: write 'let rec f … and g …'"
      let members = Buffer.empty
      Buffer.push first members
      while peek p = Newline && peek2 p = And do
        advance p
        let gl = p.pos.Value
        advance p
        let gPrivate = peek p = Private
        if gPrivate then
          advance p
        let gi = p.pos.Value
        let g = name p
        let gps = parameters p
        if List.isEmpty gps then
          failAt p gl "'and' defines a function: and g x = …"
        let gret = optTy p
        expect p Equals "'='"
        let gf = { Ast.decl (Ast.Fun(g, true, gps, gret, block p)) gl with named = gi }
        Buffer.push (wrapPrivate gPrivate gf) members
      Ast.decl (Ast.FunGroup(listOf members)) ln
    else
      first

let rec private decl (p: P) : Ast.Decl =
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
    let d = declOf p
    finish p
    d
  | None -> declOf p

and private declOf (p: P) : Ast.Decl =
  let ln = p.pos.Value
  match peek p with
  | LBrackLt ->
    // [<Name; Name(arg, arg)>] before a declaration
    start p Tree.Attributes
    advance p
    let attrs = Buffer.empty
    let mutable go = true
    while go && peek p <> GtRBrack && peek p <> Eof do
      let before = p.pos.Value
      let n = name p
      let args = Buffer.empty
      if peek p = Str then
        // [<Export "name">]
        match Literal.stringValue (textOf p p.pos.Value) with
        | Ok s -> Buffer.push s args
        | Error e -> failAt p p.pos.Value e
        advance p
      else if peek p = LParen then
        advance p
        while go && peek p <> RParen && peek p <> Eof do
          if peek p = Id then
            Buffer.push (idName p p.pos.Value) args
            advance p
          else if peek p = Str then
            match Literal.stringValue (textOf p p.pos.Value) with
            | Ok s -> Buffer.push s args
            | Error e -> failAt p p.pos.Value e
            advance p
          else
            skip p "attribute argument"
            go <- false
          if peek p = Comma then
            advance p
        expect p RParen "')'"
      Buffer.push (n, listOf args) attrs
      if peek p = Semi then
        advance p
      if p.pos.Value = before then
        go <- false
    expect p GtRBrack "'>]'"
    finish p
    if peek p = Newline then
      advance p
    Ast.decl (Ast.Attrs(listOf attrs, decl p)) ln
  | Open ->
    advance p
    Ast.decl (Ast.Open(name p)) ln
  | Namespace ->
    // namespace Collections: the file's types and modules are Collections.Name (one namespace
    // can span files, like a module header that several files share)
    advance p
    Ast.decl (Ast.ModuleHeader(name p)) ln
  | Module ->
    advance p
    let n = name p
    if peek p = Equals then
      // module Inner =, then its declarations, indented
      advance p
      expect p Indent "indented declarations"
      let decls = Buffer.empty
      while peek p <> Dedent && peek p <> Eof do
        let before = p.pos.Value
        Buffer.push (decl p) decls
        if peek p = Newline then
          advance p
        if p.pos.Value = before then
          bump p
      dedent p "end of module"
      Ast.decl (Ast.NestedModule(n, listOf decls)) ln
    else
      Ast.decl (Ast.ModuleHeader n) ln
  | Derive when ahead p 3 = Id ->
    // derive Json = ToJson, FromJson: a name for several derives
    advance p
    let n = name p
    expect p Equals "'='"
    let ms = Buffer.empty
    Buffer.push (name p) ms
    while peek p = Comma do
      advance p
      Buffer.push (name p) ms
    Ast.decl (Ast.DeriveGroup(n, listOf ms)) ln
  | Derive ->
    // derive Json = let toJson (x: 'self) = ...
    advance p
    let n = name p
    expect p Equals "'='"
    expect p Indent "indented 'let' definitions"
    let defs = definitions p
    dedent p "end of derive"
    Ast.decl (Ast.Derive(n, defs)) ln
  | Type -> typeDecl p ln
  | Trait ->
    // trait Show<'a> = abstract show : 'a -> string ...; trait Iter<'c, 'a> = …
    advance p
    let n = name p
    expect p Lt "'<'"
    let tps = Buffer.empty
    Buffer.push (typeVar p) tps
    while peek p = Comma do
      advance p
      Buffer.push (typeVar p) tps
    closeAngle p
    expect p Equals "'='"
    expect p Indent "indented 'abstract' declarations"
    let methods = Buffer.empty
    while peek p = Abstract do
      advance p
      let m = name p
      expect p Colon "':'"
      Buffer.push (m, ty p) methods
      if peek p = Newline then
        advance p
    dedent p "end of trait"
    Ast.decl (Ast.Trait(n, listOf tps, listOf methods)) ln
  | Effect ->
    // effect Yield<'a> = abstract yield : 'a -> unit …
    advance p
    let n = name p
    let tps = typeParams p
    expect p Equals "'='"
    let indented = peek p = Indent
    if indented then
      advance p
    let ops = Buffer.empty
    while peek p = Abstract do
      advance p
      // its position: the operation's definition
      let oi = p.pos.Value
      let m = name p
      expect p Colon "':'"
      Buffer.push (m, oi, ty p) ops
      if indented && peek p = Newline then
        advance p
    if Buffer.length ops = 0 then
      err p "'abstract' operations (abstract op : T -> R)"
    if indented then
      dedent p "end of effect"
    Ast.decl (Ast.Effect(n, tps, listOf ops)) ln
  | Impl ->
    // impl Show<Point> = let show p = ...; impl Iter<list<'a>, 'a> = …
    advance p
    let tr = name p
    expect p Lt "'<'"
    let head = ty p
    let others = Buffer.empty
    while peek p = Comma do
      advance p
      Buffer.push (ty p) others
    closeAngle p
    expect p Equals "'='"
    expect p Indent "indented 'let' definitions"
    let defs = definitions p
    dedent p "end of impl"
    Ast.decl (Ast.Impl(tr, head, listOf others, defs)) ln
  | Id when isWord p "import" ->
    // import c "header.h"
    advance p
    if not (isWord p "c") then
      failAt p ln "expected 'c' after 'import': import c \"header.h\""
      Ast.decl (Ast.ImportC "") ln
    else
      advance p
      if peek p = Str then
        let h =
          match Literal.stringValue (textOf p p.pos.Value) with
          | Ok s -> s
          | Error _ -> ""
        advance p
        Ast.decl (Ast.ImportC h) ln
      else
        failAt p ln "expected a header name: import c \"header.h\""
        Ast.decl (Ast.ImportC "") ln
  | Extern -> externDecl p ln
  | Let -> letDecl p ln
  | _ ->
    err p "'let', 'type' or 'extern'"
    recover p false
    Ast.decl (Ast.Open "") ln

// the tree the parser made
let private tree (p: P) : Tree.Tree =
  { tokens = Buffer.toArray p.toks
    lexed = p.eof + 1
    missing = Buffer.toArray p.missingAt
    kinds = Buffer.toArray p.kinds
    firsts = Buffer.toArray p.firsts
    counts = Buffer.toArray p.counts
    children = Buffer.toArray p.children
    parents = Buffer.toArray p.parents
    starts = Buffer.toArray p.starts
    ends = Buffer.toArray p.ends }

// the tree, the declarations and what's wrong in them, with no effects: so the parser's
// functions are their pure instances, whoever calls it
let private parseAll (src: Source.Source) (toks: array<Token>) : Tree.Tree * list<Ast.Decl> * array<Diagnostic> / <> =
  let p = make src (Buffer.ofArray toks) 0 (Array.length toks - 1)
  start p Tree.File
  let decls = Buffer.empty
  while peek p <> Eof do
    let before = p.pos.Value
    Buffer.push (decl p) decls
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
  (tree p, listOf decls, Buffer.toArray p.diags)

/// A file's tree and declarations, from its tokens; what's wrong in them is reported, and they
/// are made anyway.
let parse (src: Source.Source) (toks: array<Token>) : Tree.Tree * list<Ast.Decl> / Report =
  let (t, decls, diags) = parseAll src toks
  for d in diags do
    Report.diagnostic d
  (t, decls)
