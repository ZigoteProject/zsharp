/// The syntax tree (0019): lossless, so every token of a file is in it, layout tokens too, and the
/// text between two tokens (spaces, comments, blank lines) is the source's between their offsets.
/// A node is its kind, its children in order (tokens and nodes) and its span. Nodes are numbered
/// in the order they end, a node's children before it, so the root (`File`) is the last; the ids
/// are dense, and a table keyed by a node is an array. A child is a node's number, or a token's
/// index as `-1 - index`. The tokens are the lexer's, then those the parser made: the first `>`
/// of a `>>` that closes two type argument lists, and the missing ones (expected and not found:
/// zero-width, where they were expected).

/// What a node is: one per construct.
type Kind =
  | File
  /// Tokens skipped where the parser couldn't go on (reported).
  | Error
  | Annotation
  | Apply
  | Array
  | ArrayComp
  | Assign
  | Attributed
  | Attributes
  | Block
  | Case
  | Clause
  | Computation
  | Derive
  | DoBang
  | Effect
  | Extern
  | Field
  | FieldValue
  | For
  | Function
  | Handle
  | If
  | Impl
  | Import
  | Index
  | Infix
  | Lambda
  | Let
  | LetBang
  | List
  | ListComp
  | Match
  | Measure
  | Measured
  | Member
  | Module
  | Namespace
  | Open
  | OperatorValue
  | Parameter
  | Paren
  | PatternAs
  | PatternCase
  | PatternCons
  | PatternList
  | PatternNegative
  | PatternOr
  | PatternParen
  | PatternRecord
  | PatternTuple
  | Prefix
  | Question
  | Record
  | RecordBody
  | Return
  | Trait
  | Tuple
  | Type
  | TypeFun
  | TypeName
  | TypeParen
  | TypeRow
  | TypeTuple
  | Typed
  | UnionBody
  | Unit
  | Unsafe
  | Use
  | While
  | Yield

/// A file's tree.
type Tree =
  { /// The tokens: the lexer's, then the parser's.
    tokens: array<Token.Token>
    /// How many of them the lexer made.
    lexed: int
    /// The missing ones' indices, in order.
    missing: array<int>
    /// The tokens that name a type where one is written (an annotation, a type's body), in order.
    typeNames: array<int>
    /// Per node: its kind.
    kinds: array<Kind>
    /// Per node: where its children start in `children`, and how many it has.
    firsts: array<int>
    counts: array<int>
    /// The nodes' children, each node's together.
    children: array<int>
    /// Per node: the node it's a child of (-1 for the root).
    parents: array<int>
    /// Per node: where its text starts and ends, from its first token with text to its last (the
    /// same offset for a node with none, where the parser was).
    starts: array<int>
    ends: array<int> }

/// The root, `File`.
let root (t: Tree) : int = Array.length t.kinds - 1

/// Whether a child is a token.
let isToken (c: int) : bool = c < 0

/// The index of a token child among the tokens.
let tokenIndex (c: int) : int = -1 - c

/// A node's i-th child.
let child (t: Tree) (n: int) (i: int) : int = t.children.[t.firsts.[n] + i]

/// Whether a token is a missing one: expected there and not found.
let isMissing (t: Tree) (i: int) : bool = i >= t.lexed && Array.contains i t.missing

/// The index of the token whose text holds an offset, or the last before it (-1 for none).
let tokenAt (t: Tree) (offset: int) : int =
  let mutable lo = 0
  let mutable hi = t.lexed - 1
  let mutable found = -1
  while lo <= hi do
    let mid = (lo + hi) / 2
    if t.tokens.[mid].offset <= offset then
      found <- mid
      lo <- mid + 1
    else
      hi <- mid - 1
  // a layout token there has no text: the token with text before it
  while found > 0 && t.tokens.[found].length = 0 do
    found <- found - 1
  found

/// A kind's name: `Let`.
let name (k: Kind) : string =
  let s = show k
  let mutable from = 0
  for i in 0 .. String.length s - 1 do
    if String.byte s i = u8 46 then
      from <- i + 1
  String.sub s from (String.length s - from)

/// The tree as both compilers print it (`zs tree`): a node's kind, then its children two spaces
/// deeper, a token as `zs tokens` prints it.
let print (src: string) (t: Tree) : unit =
  let rec go (indent: string) (n: int) =
    println (indent + name t.kinds.[n])
    for i in 0 .. t.counts.[n] - 1 do
      let c = child t n i
      if c < 0 then
        println (indent + "  " + Token.display src t.tokens.[-1 - c])
      else
        go (indent + "  ") c
  go "" (root t)

/// Whether the tree is lossless: it holds every token the lexer made, once each and in order, so
/// its text (each token's with the source's between them) is the file's.
let lossless (t: Tree) : bool =
  let next = ref 0
  let ok = ref true
  let rec go (n: int) =
    for i in 0 .. t.counts.[n] - 1 do
      let c = child t n i
      if c < 0 then
        let k = -1 - c
        if k < t.lexed then
          if k = next.Value then next.Value <- k + 1 else ok.Value <- false
      else
        go c
  go (root t)
  ok.Value && next.Value = t.lexed
