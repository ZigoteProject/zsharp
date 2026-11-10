# 5. Expressions

Z# is an expression language: every construct below has a value, and a function's body is an
expression. Constructs evaluated for their effect have type `unit`.

## 5.1 Evaluation

Evaluation is **strict** and **left to right**:

- the operands of an operator, the arguments of an application, the elements of a tuple, list
  or array, and the fields of a record expression are evaluated in the order written (a
  record's fields in the order of the expression, not of the declaration);
- the function part of an application is evaluated before its arguments;
- defaults for omitted record fields and omitted optional arguments are evaluated after the
  values given, in declaration order;
- only `&&`, `||`, `if`, `match`, loops and function bodies leave an operand unevaluated.

Evaluation of an expression either produces a value, **panics**
([§10.5](10-execution.md#105-panics)), does not terminate, or **performs an effect**
operation whose handler does not resume it ([chapter 8](08-effects.md)).

## 5.2 Literals

The literal forms are those of [chapter 1](01-lexical.md), typed by
[§3.9](03-types.md#39-literals).

**Interpolated strings.** `$"… {e} …"` is a `string`: the literal text and, for each hole,
the text of its value, concatenated in order.

```text
hole = '{' expression [ ',' width ] [ ':' format ] '}' ;
```

- `{e}` is `string e`: `e`'s type must implement `Show`
  ([§7.6](07-traits.md#76-the-prelude-traits)).
- `{e:F}` formats through `Format` with the specifier `F`: a letter and at most two digits.
  The specifiers are `F`, `N`, `E`, `G` for floats and `F`, `N`, `D`, `X`, `x`, `B`, `b` for
  integers, each with an optional precision or width (`{x:F2}`, `{n:X8}`). A specifier the value's type
  does not have is an error.
- `{e,w}` pads the text to `w` characters, on the left when `w` is positive and on the right
  when it is negative; `{e,w:F}` combines both. The width is an integer literal.
- The expression ends at the first `,` or `:` outside brackets and literals (`::` excepted),
  so a tuple or an annotated expression in a hole is parenthesized: `{(a, b)}`.
- Holes are evaluated left to right.

**Byte strings.** `b"…"` is a `span<u8>` over the literal's bytes: a constant, with nothing
copied or allocated.

**Measured literals.** `9.58<s>` is the number at the unit `s`
([§3.6](03-types.md#36-units-of-measure)).

## 5.3 Tuples and constructors

```text
tuple       = '(' expression ',' expression { ',' expression } ')' ;
unit        = '(' ')' ;
paren       = '(' expression ')' ;
annotated   = '(' expression ':' type ')' ;
```

- A tuple expression is parenthesized. (A `match` scrutinee and a pattern may omit the
  parentheses.)
- `(e : T)` is `e`, required to have type `T`.

**Union cases.** A case name is an expression:

- a case without fields is its value: `None`, `Leaf`;
- a case with fields is applied to them: one field as `Some x`; several as one tuple,
  `Rect (2.0, 3.0)`, or by name, `Rect(w = 2.0, h = 3.0)`, in any order, every field given;
- a case with fields, unapplied, is a function (`List.map Some xs`).

A case is found by the scope rules of [§2.4](02-programs.md#24-name-resolution) and may be
qualified by its type or module (`Shape.Circle`).

## 5.4 Records

```text
record  = '{' field-init { ';' field-init } [ ';' ] '}'
        | '{' expression 'with' field-init { ';' field-init } [ ';' ] '}' ;
field-init = ID '=' expression ;
```

**Construction.** `{ f1 = e1; …; fn = en }` builds a record.

- **Which type.** If a record type is expected where the expression is written
  ([§3.10](03-types.md#310-inference)), it is that type. Otherwise the fields given must
  identify a record type among those in scope
  ([§2.4](02-programs.md#24-name-resolution)): the candidates are the types having all the
  fields given, and whose other fields all have defaults; the nearest scope wins, then the
  later declaration.
- Every field without a default must be given; no field may be given twice; a field the type
  lacks is an error.
- An omitted field takes its default, evaluated after the fields given.

**Update.** `{ r with f1 = e1; … }` is a record of `r`'s type with the fields given replaced
and the others copied from `r`. `r` is evaluated first and is unchanged.

**Field access.** `e.f` ([§5.5](#55-postfix-forms)).

*Note.* Braces never delimit a block; `{ … }` after an identifier, opening a computation
expression, is the other use of braces ([chapter 9](09-computations.md)).

## 5.5 Postfix forms

```text
postfix = atom { '.' ID | '.' '[' index ']' | '(' … ')' } ;        '(' adjacent to what precedes
index   = expression | [ expression ] '..' [ expression ] ;
```

Postfix forms bind tighter than application: `f x.y` is `f (x.y)`.

**Member access `e.name`.** With the type of `e` known ([§3.10](03-types.md#310-inference)),
`name` is, in this order: a field of its record type; a member of its type
([§4.5](04-declarations.md#45-members)); for a `ref`, `Value`; for a `[<CLayout>]` union, a
case, in `unsafe` ([§11.3](11-low-level.md#113-layout)). With the type unknown, `name` is
looked up as a field of the record types in scope (the nearest, then the latest declared);
if none has it, the access is an error asking for an annotation.

**High-precedence application `f(x)`.** An opening parenthesis directly after an expression,
with no space, applies it and binds as tightly as `.`: `v.Scale(2.0).Len`, `f(x).y`. This is
how methods are called; the parenthesized argument of a method is its argument list
([§4.5](04-declarations.md#45-members)).

**Indexing `e.[i]`.** Defined for `array`, `Buffer`, `span` and `fixed`, with `i : int`,
counting from 0. An index outside the bounds panics. Lists, strings and maps are not indexed
by `.[ ]`; their modules have functions for it.

**Slicing `e.[i..j]`, `e.[..j]`, `e.[i..]`.** Both bounds are inclusive; an omitted bound is
the first or last index.

| Of | The slice is |
|---|---|
| an `array` or a `span` | a `span` over the same storage, read-only |
| a `Buffer` | a `Buffer` sharing its storage: writes are seen through both |
| a `string` | a `string`, by byte offsets, which must fall between characters |

A slice outside the bounds, or a string slice inside a character, panics.

## 5.6 Operators

From loosest to tightest:

| Level | Operators | Associativity |
|---|---|---|
| 0 | `\|\|` | right |
| 1 | `&&` | right |
| 2 | `=` `<>` `<` `>` `<=` `>=`, `\|>`, `>>`, custom operators of this level | left |
| 3 | `\|\|\|` | left |
| 4 | `^^^` | left |
| 5 | `&&&` | left |
| 6 | `<<<` `>>>` | left |
| 7 | `::`, `@`, custom operators starting with `@` or `^` | right |
| 8 | `+` `-`, custom operators starting with `+` or `-` | left |
| 9 | `*` `/` `%`, custom operators starting with `*`, `/` or `%` | left |
| 10 | custom operators starting with `**` | right |
| 11 | prefix `-`, `~~~`, `not` | |
| 12 | application `f x y`; then a postfix `?` over the whole application | left |
| 13 | postfix forms ([§5.5](#55-postfix-forms)); prefix custom operators | |

*Note.* Differences from other languages worth stating: the bitwise operators bind tighter
than comparison (`x &&& mask = 0` is `(x &&& mask) = 0`), and `|>` and the comparisons share
a level.

A `fun` or `function` as the right operand of a binary operator extends to the end of the
expression: `m >>= fun x -> …`.

### Arithmetic

`+` is the `Add` trait's operation, and `-`, `*`, `/`, `%` and prefix `-` are `Num`'s
([§7.6](07-traits.md#76-the-prelude-traits)). Both operands and the result have one type. For
the built-in number types:

| | Integers | Floats |
|---|---|---|
| `+` `-` `*` | exact; a result outside the type **panics** (`integer overflow`) | IEEE 754 |
| `/` | truncates toward zero; division by zero panics; `MIN / -1` panics | IEEE 754 (`1.0 / 0.0` is infinity) |
| `%` | the remainder with the dividend's sign (`-7 % 2` is `-1`); by zero panics | IEEE 754 remainder of truncated division |
| prefix `-` | negation; `-MIN` panics | negation |

- **Overflow is checked in every build**, optimized ones included. Unsigned subtraction below
  zero is overflow.
- In a function marked `[<Wrapping>]`, integer `+`, `-` and `*` wrap modulo 2^width, in the
  lambdas written inside it too; negation and division keep their checks.
- In a function marked `[<FastMath>]`, float `+ - * /` may be reassociated and may assume no
  NaN or infinity.
- `Int.wrappingAdd`, `Int.checkedAdd`, `Int.saturatingAdd` and their `Sub` and `Mul` state a
  different behaviour at one operation.
- `+` on strings concatenates. `+` is not defined on `char`.
- Operands with units of measure follow [§3.6](03-types.md#36-units-of-measure).
- SIMD vectors: [§11.5](11-low-level.md#115-simd).

### Comparison

`=` and `<>` are the `Eq` trait's; `<`, `>`, `<=`, `>=` are `Ord`'s. Both operands have one
type, and the result is `bool`.

- Equality is structural ([§4.3](04-declarations.md#structural-operations)); there is no
  reference equality.
- Strings are compared by their bytes.
- Floats follow IEEE 754 for the operators: a NaN is unequal to everything, itself included,
  and every ordered comparison with a NaN is `false`.

### Boolean

`a && b` is `if a then b else false`, and `a || b` is `if a then true else b`: the right
operand is evaluated only when needed. `not e` negates a `bool`.

### Bitwise

`&&&`, `|||`, `^^^` and `~~~` (and, or, exclusive or, complement) are defined on the integer
types, both operands of one type.

`a <<< n` and `a >>> n` shift `a` by `n` bits; `n` has the type of `a`. The count is taken
modulo the type's width, so a shift never panics; bits shifted out are lost. `>>>` is
arithmetic (sign-extending) on signed types and logical on unsigned types.

### Lists

`x :: xs` is the list with head `x` and tail `xs`. `xs @ ys` is `xs` followed by `ys`
(`List.append`).

### Functions

- `x |> f` is `f x`. More precisely the piped value becomes the **last** argument of the
  call written on the right: `x |> f a b` is `f a b x`.
- `f >> g` is `fun x -> g (f x)`.
- `(op)` is a built-in binary operator as a function of two arguments, for
  `+ - * / % = <> < > <= >= &&& ||| ^^^ <<< >>> @ ::`.

There is no `<|`, `<<` or `**` unless a program defines them.

## 5.7 Custom operators

A run of operator characters that is not one of the language's symbols is a custom operator,
defined by `let (op) a b = …` (infix) or `let (op) a = …` (prefix) and used like any
function; `(op)` names it. An operator that is not defined is an error.

- **Prefix operators** start with `~`, or with `!` (but are not `!=`). They apply to the
  postfix expression that follows and bind tighter than application: `f !r` is `f (!r)`.
- **Infix operators** are all the others. Their level and associativity come from their first
  character after any leading dots:

  | First characters | Level |
  |---|---|
  | `**` | 10, right-associative |
  | `*` `/` `%` | 9 |
  | `+` `-` | 8 |
  | `@` `^` | 7, right-associative |
  | anything else (`<` `>` `=` `\|` `&` `$` `!` `?` `~` `.`) | 2 |

- A line starting with an infix custom operator continues the previous line
  ([§1.9](01-lexical.md#19-layout-the-offside-rule)).

## 5.8 Blocks and bindings

A **block** is one expression on a line, or an indented sequence of statements. Its value is
that of its last statement.

```text
statements = statement { NEWLINE statement } ;
statement  = 'let' pattern [ ':' type ] '=' block                      then the rest
           | 'let' [ 'rec' ] ID parameter { parameter } [ ':' type ] '=' block
             { NEWLINE 'and' ID parameter { parameter } [ ':' type ] '=' block }
           | 'let' 'mutable' ID [ ':' type ] '=' block
           | 'use' ID '=' block
           | place '<-' expression
           | place assign-op expression
           | expression ;
```

- A binding's scope is the rest of its block. A block must not end with a binding.
- **A statement that is not last must have type `unit`.** Otherwise its value is discarded
  with the warning `unused-value`; `ignore e` discards a value explicitly.
- `let p = e in body` is the binding as an expression, for use within a line.

**`let` with a pattern** binds the pattern's variables to the parts of the value. The pattern
must match every value of its type ([§6.4](06-patterns.md#64-exhaustiveness-and-redundancy)).

**Local functions** are as in [§4.1](04-declarations.md#41-let). A local function is a
closure: it may use the variables in scope, with the capture rule below. It is not
generalized.

**Mutable variables.** `let mutable x = e` declares a variable that `<-` may assign.

- A mutable variable **cannot be captured by a closure**: using one inside a lambda or a
  local function is an error (`mutable variable 'n' cannot be captured by a closure; use a
  ref cell`). The bodies of `for` and `while` loops, `match` clauses and the clauses of a
  `handle` are not closures in this sense and may read and assign the enclosing function's
  mutable variables.
- A `ref` cell is the value to capture: `let r = ref 0`, `r.Value`, `r.Value <- 1`.

**Assignment.**

```text
place     = ID | place '.' ID | place '.' '[' expression ']' ;
assign-op = '+=' | '-=' | '*=' | '/=' | '%=' | '&&&=' | '|||=' | '^^^=' ;
```

`place <- e` has type `unit`. A place is:

| Place | Requirement | Meaning |
|---|---|---|
| `x` | `x` is a `let mutable` | `x` now holds the value |
| `r.Value` | `r : ref<T>` | the cell now holds the value |
| `a.[i]` | `a` is a `let mutable` array or `fixed`, or any `Buffer` or a span over one | that element is replaced ([§10.2](10-execution.md#102-values-and-cells)) |
| `x.f` | `x` is a `let mutable` record (or a field or element of one) | `x` now holds the record with `f` replaced |

`place op= e` is `place <- place op e` with the place's receiver and index evaluated once:
`a.[next ()] += 1` calls `next` once.

Assigning through an immutable binding is an error, as is `x = e` written as a statement to
mean assignment.

**`use`.** `use x = e` binds `x` and guarantees `Dispose.dispose x` is called when the rest
of the block is left: at its end, and when an effect operation whose handler does not resume
passes over it ([§8.4](08-effects.md#84-handlers)). Several `use`s are disposed newest first.
`x`'s type must implement `Dispose`. A panic disposes nothing.

## 5.9 Control flow

**Conditionals.**

```text
if = 'if' expression 'then' block [ 'else' block ] ;
```

The condition is a `bool` (a number is not a condition). With `else`, both branches have one
type, the expression's. Without it, the branch must have type `unit`. `else if` chains; there
is no `elif`.

**Matching.** `match` and `function` are in [chapter 6](06-patterns.md).

**Loops.** Every loop has type `unit`, and its body must too.

```text
while = 'while' expression 'do' block ;
for   = 'for' ID 'in' expression '..' expression [ '..' expression ] 'do' block
      | 'for' pattern 'in' expression 'do' block ;
```

- `while c do body` evaluates `c`, and while it is `true`, the body and `c` again.
- `for i in a .. b do body` runs the body with `i` from `a` up to and including `b`, by 1;
  nothing when `a > b`. The bounds are evaluated once, and are of one integer type.
- `for i in a .. s .. b do body` steps by `s`, which may be negative (down to `b`); the
  values are `a`, `a + s`, … while they have not passed `b`.
- `for p in c do body` runs the body for each element of `c`, whose type must implement
  `Iter` ([§7.6](07-traits.md#76-the-prelude-traits)): lists, arrays, `Buffer`s, spans,
  strings (by character), options, maps (key–value pairs in key order), sets, `Seq`s and any
  type with an impl. The pattern must match every element.
- There is no `break` or `continue`. A loop ends early through its condition, through a
  function that returns from a recursive helper, or through an effect.

**Lambdas.**

```text
lambda   = 'fun' parameter { parameter } '->' block ;
function = 'function' clauses ;                           fun x -> match x with clauses
```

A lambda's parameters are those of a `let` ([§4.1](04-declarations.md#41-let)). Its body
extends as far as possible. A lambda is a closure and captures the variables it uses by
value; it cannot capture a `let mutable`.

**Application.** `f a1 … an` applies `f` to arguments, by juxtaposition. Each argument is a
postfix expression (anything larger is parenthesized).

- Applying a function of `m` parameters to `n < m` arguments gives a function of the rest
  (partial application); to `n > m`, the result is applied to the remaining arguments.
- A record expression may be given as the argument on the following line, indented.
- A call in tail position is a **tail call**: a function that calls itself, or another
  function of the same signature, as the last thing it does runs in constant stack space, in
  every build. This is guaranteed for direct calls among top-level functions.

**Early return `e?`.** A postfix `?` applies to the whole application before it
(`parse s?` is `(parse s)?`). It is allowed in two positions only: as the whole right side of
a `let` without an annotation, `let p = e?`, and as a whole statement, `e?`.

- With `e : result<T, E>`: if `e` is `Ok v`, the binding continues with `v`; if it is
  `Error x`, the rest of the block is skipped and the block's value is `Error x`.
- With `e : option<T>`: `Some v` continues with `v`; `None` makes the block's value `None`.
- The rest of the block must therefore have the same kind of type: `result<_, E>` with the
  same error type `E`, or an `option`. Errors are not converted, and `option` and `result`
  are not mixed.
- The block left is the innermost enclosing block of the function or lambda; a `for` body is
  a function of its own for this purpose.

**`unsafe`.** `unsafe e`, or `unsafe` and an indented block, is `e`, in which the unsafe
operations are permitted ([§11.2](11-low-level.md#112-unsafe)).

**`handle`**, **`task { }`**, **`seq { }`** and other computation expressions:
[chapters 8](08-effects.md) and [9](09-computations.md).

**`assert`.** `assert e` panics when `e : bool` is `false`, with the file, the line and the
expression's text; when `e` is a comparison, also both sides and where they first differ.
`panic msg` panics with a message and has any type.

**Layout facts.** `sizeof<T>`, `alignof<T>` and `offsetof<T> "field"`:
[§11.3](11-low-level.md#113-layout).

## 5.10 Lists, arrays and ranges

```text
list   = '[' [ expression { ';' expression } [ ';' ] ] ']'
       | '[' expression '..' expression [ '..' expression ] ']'
       | '[' comprehension ']' ;
array  = the same between '[|' and '|]' ;
comprehension = comp-stmt { ( ';' | NEWLINE ) comp-stmt } ;
comp-stmt = 'for' pattern 'in' expression ( '->' expression | 'do' comp-block )
          | 'for' ID 'in' expression '..' expression [ '..' expression ] ( '->' … | 'do' … )
          | 'if' expression 'then' comp-block [ 'else' comp-block ]
          | 'match' expression 'with' clauses
          | 'let' pattern '=' expression
          | 'yield' expression | 'yield' '!' expression
          | expression ;
```

- `[ e1; …; en ]` is the list of the values in order; `[| … |]` the array. All elements have
  one type. Items are separated by `;` or, in `[ ]`, by line breaks.
- `[ a .. b ]` and `[ a .. s .. b ]` are the list of the values a `for` over that range
  visits; an empty range gives `[]`.
- A **list expression** begins with `for` or `yield`. Its body is run, and the result holds
  the values it **yields**, in order: `yield e` yields one value, `yield! xs` each element of
  a list, and `for … -> e` is `for … do yield e`. A statement that is not a yield must have
  type `unit`.

```fsharp
let evens = [ for x in xs do if x % 2 = 0 then yield x * x ]
let grid  = [| for y in 0 .. h - 1 do
                 for x in 0 .. w - 1 -> (x, y) |]
```

## 5.11 Implicit conversions

Z# has no numeric or user-defined implicit conversions. Where the **expected type** is known
([§3.10](03-types.md#310-inference)), exactly these conversions are inserted:

| An expression of type | is accepted where the expected type is |
|---|---|
| `array<T>`, `Buffer<T>` | `span<T>` |
| `T` implementing `Tr` | `dyn Tr` ([§7.4](07-traits.md#74-dyn)) |
| `A -> B` (a lambda or a named function) | `share<A -> B>`, `callback<A -> B>`, with their checks |
| `share<F>` | `F` |
| a string literal or a `string` | `cstr`, in a C call ([§11.1](11-low-level.md#111-c-interop)) |

No conversion is inserted the other way (`Array.ofSpan` copies a span into an array).
