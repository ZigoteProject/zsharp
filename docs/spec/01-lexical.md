# 1. Lexical structure

A source file is a sequence of bytes, read as UTF-8, with the extension `.zs`. The lexer turns
it into tokens, line by line; layout (indentation and line breaks) becomes tokens too
([§1.9](#19-layout-the-offside-rule)).

## 1.1 Source text

- **Lines** end at a line feed (U+000A). Source files are stored with LF line ends.
- **Blanks:** the space (U+0020) separates tokens and is otherwise ignored, except where a
  rule below says *adjacent* (no space, and no line break, before a token).
- **Tabs:** a line must not begin with a tab (`tabs are not allowed for indentation`).
- **Beyond ASCII:** any byte of a character beyond ASCII counts as a letter, so identifiers
  may hold any non-ASCII characters; string, character and comment text is not interpreted.
- A byte that starts no token is an error (`unexpected character`), and lexing goes on.

## 1.2 Comments

```text
comment     = '//' { any character but a line feed } ;
doc-comment = '///' { any character but a line feed } ;
```

A comment runs to the end of its line. There are no block comments (`(* … *)` is not one).
A line holding only a comment is blank for layout.

A run of `///` lines directly above a declaration, a union case or a record field is its
**documentation**: Markdown that tools show, and whose fenced `zsharp` blocks `zs test --doc`
runs. Documentation has no effect on a program's meaning.

## 1.3 Identifiers

```text
ID        = ident | qualified | quoted ;
ident     = ( letter | '_' ) { letter | digit | '_' } ;
qualified = upper-ident '.' ident { '.' ident } ;        one token
quoted    = '``' { any character but a line feed } '``' ;
TYVAR     = "'" letter { letter | digit | '_' } ;
letter    = 'A'…'Z' | 'a'…'z' | any byte ≥ 0x80 ;
```

- An identifier must not be a keyword ([§1.4](#14-keywords)), unless quoted:
  ``Parallel.``for`` `` names the function `for`.
- `_` alone is the wildcard in a pattern and not a name.
- **Qualified names are one token.** An identifier starting with an ASCII upper-case letter,
  followed directly by `.` and a letter, continues through the dot: `List.map` and
  `Geometry.Shape.Circle` are single tokens. After a lower-case identifier a dot is the member
  access operator ([§5.5](05-expressions.md#55-postfix-forms)).
- **Case is significant twice:**
  - in a pattern, a name that starts with an upper-case ASCII letter, or is qualified, is a
    case name when arguments follow it ([§6.2](06-patterns.md#62-forms));
  - a `let` with parameters defines a function only when its name starts with a lower-case
    letter, `_` or a non-ASCII character (or after `let rec`); otherwise it is a pattern
    binding of a case ([§4.1](04-declarations.md#41-let)).
- A **type variable** is written with a leading quote: `'a`, `'key`. An apostrophe is not
  otherwise part of a name (`x'` is not an identifier).

## 1.4 Keywords

The reserved words:

```text
abstract  and     as      derive  do       effect    else     extern  false
for       fun     function        if       impl      in       let     match
member    module  mutable         namespace         not      of      open
private   rec     static  then    trait    true      type     unsafe  when
while     with
```

The **contextual words** are ordinary identifiers that a construct reads specially in one
position: `use`, `return`, `yield`, `handle`, `import`, `assert`, `dyn`, `sizeof`, `alignof`,
`offsetof`, the builder names `task` and `seq` before `{`, the provider name `c` after
`import`, and `try`, which is rejected with advice where F# would begin a `try … with`. Each
is defined with its construct.

## 1.5 Symbols and operators

Operators are made of the **operator characters**

```text
!  $  %  &  *  +  -  .  /  <  =  >  ?  @  ^  |  ~
```

The lexer takes the longest run of them (stopping before `//` and before `$"`), and the run
is one of the language's symbols below or else a **custom operator**
([§5.7](05-expressions.md#57-custom-operators)).

```text
arithmetic      +   -   *   /   %
comparison      =   <>  <   >   <=  >=
boolean         &&  ||                      (and the keyword not)
bitwise         &&& ||| ^^^ <<< >>> ~~~
lists           ::  @
functions       |>  >>  ->
assignment      <-  +=  -=  *=  /=  %=  &&&=  |||=  ^^^=
ranges          ..
other           .   ?   |   ^   ...
punctuation     (   )   [   ]   [|  |]  [<  >]  {   }   ,   ;   :
```

Three rules settle what a run of operator characters is:

1. **A trailing sign splits off.** When a run longer than one character ends in `+` or `-`,
   the run without it is a symbol, and an identifier character or `(` follows directly, the
   sign is its own token: `x=-1` is `x = -1` and `a*-b` is `a * -b`.
2. **Closing angle brackets split.** Where a type argument list is being closed, `>>`,
   `>>>` and longer runs of `>` are read one `>` at a time: `list<option<int>>`.
3. **Negation of an argument.** A `-` with a space before it and none after, following an
   operand (an identifier, a literal, `)`, `]` or `|]`), negates what follows instead of
   subtracting: `f -x` applies `f` to `-x`, while `f - x` and `f-x` subtract.

`!=`, `++` and `--` are not symbols; the reference implementation rejects them with advice
(`<>`, `x += 1`).

## 1.6 Numeric literals

```text
INT    = digit { digit | '_' }
       | '0' ( 'x' | 'X' ) hex   { hex   | '_' }
       | '0' ( 'b' | 'B' ) bin   { bin   | '_' }
       | '0' ( 'o' | 'O' ) oct   { oct   | '_' } ;
FLOAT  = digit { digit | '_' } '.' digit { digit | '_' } [ exponent ]
       | digit { digit | '_' } exponent ;
exponent = ( 'e' | 'E' ) [ '+' | '-' ] digit { digit } ;
```

- `_` separates digits and has no meaning: `1_000_000`, `0xFFFF_FFFF`.
- A float literal has digits on both sides of its point, or an exponent, or both: `1.0`,
  `0.5`, `2.5e-3`, `1e5`. `1.` and `.5` are not float literals.
- A decimal integer literal must fit a signed 64-bit integer; a literal in another radix may
  use all 64 bits (`0xFFFF_FFFF_FFFF_FFFF`). A larger literal is an error.
- Literals have no sign and no type suffix: `-5` is the negation of `5`
  ([§5.6](05-expressions.md#56-operators)), and a literal's type comes from its context
  ([§3.9](03-types.md#39-literals)).
- A numeric literal directly followed by `<` and a unit of measure, with no space, is a
  measured literal: `9.58<s>`, `5<ns>` ([§3.6](03-types.md#36-units-of-measure)).

## 1.7 Character literals

```text
CHAR   = "'" ( character | escape ) "'" ;
escape = '\n' | '\r' | '\t' | '\0' | '\\' | '\"' | "\'" | '\u{' hex { hex } '}' ;
```

A character literal holds one Unicode scalar value: `'a'`, `'é'`, `'\n'`, `'\u{1F600}'`. A
`\u{…}` escape must name a scalar value (at most `10FFFF`, not a surrogate). A quote followed
by a letter with no closing quote two characters on is a type variable (`'a`), not a
character.

## 1.8 String literals

```text
STR    = '"' { character | escape } '"'
       | '"""' { any character } '"""'
       | 'b"' { character | escape } '"' ;
INTERP = '$"' { character | escape | '{{' | '}}' | hole } '"' ;
hole   = '{' expression [ ',' width ] [ ':' format ] '}' ;
```

- **A plain string** `"…"` reads the escapes of [§1.7](#17-character-literals). It may span
  lines; its line breaks are part of it. Its value is the UTF-8 bytes of its characters.
- **A raw string** `"""…"""` is its text as written: no escapes, quotes allowed.
- **A byte string** `b"…"` is a `span<u8>` over the literal's bytes, a constant
  ([§5.2](05-expressions.md#52-literals)). The letter `b` directly before a quote always
  starts one.
- **An interpolated string** `$"…"` reads escapes, writes a brace as `{{` or `}}`, and
  evaluates each hole ([§5.2](05-expressions.md#52-literals)). A hole may contain braces
  (`{f { x = 1 }}`) and string literals, and must end on the line it starts on. There is no
  raw interpolated form.
- An unterminated string or hole is an error.

## 1.9 Layout (the offside rule)

Z# has no block delimiters and no statement terminators: indentation groups, as in F#'s light
syntax. The lexer measures each non-blank line's **indentation** (its leading spaces) and
emits three zero-width layout tokens.

**Outside brackets**, with a stack of indentations that starts as `[0]`:

| The line's indentation is | Tokens emitted before the line |
|---|---|
| greater than the top of the stack | `INDENT`; the indentation is pushed |
| equal to it | `NEWLINE` |
| less than it | a `DEDENT` per level popped, then `NEWLINE`; it must then equal the new top (`inconsistent indentation`) |

- The first line of a file must start at column 1.
- Blank lines, comment-only lines and the lines inside a multi-line string emit nothing.
- At the end of the file, a `DEDENT` closes each open level.

**Continuation lines.** A line whose first token is `|>`, `||`, `&&`, `|||`, `&&&`, `^^^` or
an infix custom operator continues the previous line: it emits no layout token, whatever its
indentation.

```fsharp
let total =
  orders
  |> List.filter isOpen        // continues `orders`
  |> List.sumBy price
```

**Inside brackets** (`( )`, `[ ]`, `[| |]`, `[< >]`, `{ }`), line breaks are not significant,
with two exceptions:

1. **Blocks.** When a line inside a bracket ends in `->`, `then`, `else`, `do`, or the `{` of
   a computation expression (`{` directly after an identifier), and the next line is indented
   more than the line before it, an `INDENT` opens a block there. Lines inside it emit
   `NEWLINE`, `INDENT` and `DEDENT` as at the top level, and the bracket's closer (or a line
   indented less than the block) closes it.

   ```fsharp
   xs |> List.map (fun x ->
     let y = x * 2
     y + 1)
   ```

2. **Separators.** Directly inside `{ }` or `[ ]` (not in such a block), a new line is a `;`
   unless the previous token is `;`, the opening bracket or `with`. So the fields of a record
   and the items of a list may be written one per line.

   ```fsharp
   let config =
     { host = "localhost"
       port = 8080 }
   ```

*Note.* Because a new line directly inside `( )` or `[| |]` is not a separator, array items
on separate lines need `;` between them unless the array is written with a `for` body.

## 1.10 Token classes

For the grammar of the later chapters the tokens are: `ID`, `TYVAR`, `INT`, `FLOAT`, `CHAR`,
`STR`, `INTERP`, the keywords, the symbols, `OP` (a custom operator), `NEWLINE`, `INDENT`,
`DEDENT` and the end of the file.
