/// Tokens (decision 78): a token is its kind, an offset and a length into its source, so a
/// token array is three words a token and nothing to free. Its text is the source's. Layout
/// tokens (a line's start at a block's indentation, a deeper or shallower line, the `;` a line
/// break makes inside `{ }` and `[ ]`) have no text: their length is 0.

/// What a token is.
type Kind =
  | Int
  | Float
  | Str
  | Interp
  | Id
  | TyVar
  | Char
  /// A character the lexer doesn't know, reported.
  | Bad
  | Newline
  | Indent
  | Dedent
  | Eof
  | Let
  | Rec
  | If
  | Then
  | Else
  | Extern
  | True
  | False
  | Not
  | Match
  | With
  | When
  | Type
  | Of
  | As
  | Fun
  | Function
  | For
  | In
  | Do
  | While
  | Mutable
  | Member
  | Static
  | Trait
  | Impl
  | Abstract
  | Derive
  | Open
  | Module
  | Namespace
  | Private
  | And
  | Unsafe
  | Effect
  /// `&&&=`
  | AndBitsEq
  /// `|||=`
  | OrBitsEq
  /// `^^^=`
  | XorBitsEq
  /// `&&&`
  | AndBits
  /// `|||`
  | OrBits
  /// `^^^`
  | XorBits
  /// `<<<`
  | ShiftLeft
  /// `>>>`
  | ShiftRight
  /// `~~~`
  | NotBits
  /// `...`
  | Ellipsis
  /// `..`
  | DotDot
  /// `->`
  | Arrow
  /// `<-`
  | LArrow
  /// `+=`
  | PlusEq
  /// `-=`
  | MinusEq
  /// `*=`
  | StarEq
  /// `/=`
  | SlashEq
  /// `%=`
  | PercentEq
  /// `|>`
  | PipeRight
  /// `|]`
  | BarRBrack
  /// `[|`
  | LBrackBar
  /// `[<`
  | LBrackLt
  /// `>]`
  | GtRBrack
  /// `::`
  | Cons
  /// `>>`
  | Compose
  /// `<>`
  | NotEq
  /// `<=`
  | LtEq
  /// `>=`
  | GtEq
  /// `&&`
  | AndAlso
  /// `||`
  | OrElse
  /// `?`
  | Question
  | LParen
  | RParen
  | LBrace
  | RBrace
  | LBrack
  | RBrack
  | Comma
  /// `;`, written or made by a line break inside `{ }` or `[ ]`
  | Semi
  /// `|`
  | Bar
  | Dot
  | Colon
  /// `=`
  | Equals
  | Lt
  | Gt
  | Plus
  | Minus
  | Star
  | Slash
  | Percent
  /// `@`
  | Append
  /// `^`
  | Caret
  /// `-` negating an argument, as in `f -x`
  | Negate
  /// a custom operator: `>>=`, `<|>`, `.>>`, the `!` of `!x`
  | Op

/// A token: its kind, and where its text is in the source.
type Token = { kind: Kind; offset: int; length: int }

/// A token's text.
let text (src: string) (t: Token) : string = String.sub src t.offset t.length

/// The keyword a word is, or Id.
let keyword (w: string) : Kind =
  match w with
  | "let" -> Let
  | "rec" -> Rec
  | "if" -> If
  | "then" -> Then
  | "else" -> Else
  | "extern" -> Extern
  | "true" -> True
  | "false" -> False
  | "not" -> Not
  | "match" -> Match
  | "with" -> With
  | "when" -> When
  | "type" -> Type
  | "of" -> Of
  | "as" -> As
  | "fun" -> Fun
  | "function" -> Function
  | "for" -> For
  | "in" -> In
  | "do" -> Do
  | "while" -> While
  | "mutable" -> Mutable
  | "member" -> Member
  | "static" -> Static
  | "trait" -> Trait
  | "impl" -> Impl
  | "abstract" -> Abstract
  | "derive" -> Derive
  | "open" -> Open
  | "module" -> Module
  | "namespace" -> Namespace
  | "private" -> Private
  | "and" -> And
  | "unsafe" -> Unsafe
  | "effect" -> Effect
  | _ -> Id

/// The symbol a run of operator characters is, or Op for a custom operator (None when it isn't
/// one: all dots, or empty).
let symbol (s: string) : option<Kind> =
  match s with
  | "&&&=" -> Some AndBitsEq
  | "|||=" -> Some OrBitsEq
  | "^^^=" -> Some XorBitsEq
  | "&&&" -> Some AndBits
  | "|||" -> Some OrBits
  | "^^^" -> Some XorBits
  | "<<<" -> Some ShiftLeft
  | ">>>" -> Some ShiftRight
  | "~~~" -> Some NotBits
  | "..." -> Some Ellipsis
  | ".." -> Some DotDot
  | "->" -> Some Arrow
  | "<-" -> Some LArrow
  | "+=" -> Some PlusEq
  | "-=" -> Some MinusEq
  | "*=" -> Some StarEq
  | "/=" -> Some SlashEq
  | "%=" -> Some PercentEq
  | "|>" -> Some PipeRight
  | "|]" -> Some BarRBrack
  | ">]" -> Some GtRBrack
  | ">>" -> Some Compose
  | "<>" -> Some NotEq
  | "<=" -> Some LtEq
  | ">=" -> Some GtEq
  | "&&" -> Some AndAlso
  | "||" -> Some OrElse
  | "?" -> Some Question
  | "|" -> Some Bar
  | "." -> Some Dot
  | "=" -> Some Equals
  | "<" -> Some Lt
  | ">" -> Some Gt
  | "+" -> Some Plus
  | "-" -> Some Minus
  | "*" -> Some Star
  | "/" -> Some Slash
  | "%" -> Some Percent
  | "@" -> Some Append
  | "^" -> Some Caret
  | _ -> None

/// Whether a kind is one of the language's own symbols (not a custom operator).
let isSymbol (k: Kind) : bool =
  match k with
  | Op -> false
  | _ -> true

/// How a token kind reads in a message: `'let'`, `end of line`.
let describe (k: Kind) (text: string) : string =
  match k with
  | Int
  | Float -> text
  | Str
  | Interp -> "string literal"
  | Char -> "character literal"
  | TyVar -> text
  | Newline -> "end of line"
  | Indent -> "indented block"
  | Dedent -> "end of block"
  | Eof -> "end of file"
  | _ -> "'" + text + "'"

/// A token as `zs tokens` and `zs tree` print it in both compilers: its offset, its length and
/// its text, or a layout token's name.
let display (src: string) (t: Token) : string =
  match t.kind with
  | Newline -> $"{t.offset} 0 <newline>"
  | Indent -> $"{t.offset} 0 <indent>"
  | Dedent -> $"{t.offset} 0 <dedent>"
  | Eof -> $"{t.offset} 0 <eof>"
  | Semi when t.length = 0 -> $"{t.offset} 0 <;>"
  | Negate -> $"{t.offset} 1 ~-"
  | _ -> $"{t.offset} {t.length} {text src t}"
