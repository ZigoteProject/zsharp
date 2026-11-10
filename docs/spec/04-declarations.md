# 4. Declarations

```text
declaration = [ attributes [ NEWLINE ] ]
              ( let-decl | type-decl | trait-decl | impl-decl | derive-decl | effect-decl
              | extern-decl | import | open | nested-module | assert-decl ) ;
```

Declarations appear at the top level of a file and inside nested modules. Traits, impls and
derives are in [chapter 7](07-traits.md), effects in [chapter 8](08-effects.md), `extern` in
[§11.1](11-low-level.md#111-c-interop), modules and `open` in
[chapter 2](02-programs.md). A module must not declare the same name twice in one kind
(`'x' is already defined`); shadowing is for local bindings only.

## 4.1 `let`

```text
let-decl  = 'let' [ 'rec' ] [ 'private' ] binder { parameter } [ ':' type ] '=' block
            { NEWLINE 'and' [ 'private' ] ID parameter { parameter } [ ':' type ] '=' block }
          | 'let' [ 'private' ] pattern [ ':' type ] '=' block ;
binder    = ID | '(' OP ')' | active-pattern-name ;
parameter = ID | '_' | '(' ')' | '(' ID ':' type { ',' ID ':' type } ')'
          | '(' pattern ')' | '[' … ']' | '{' … '}' ;        an atomic pattern
block     = expression | INDENT statements DEDENT ;
```

**Functions.** A `let` with one or more parameters defines a function.

- Each parameter is a name, `_`, `()`, an annotated name `(x: T)`, or an atomic pattern
  ([§6.3](06-patterns.md#63-where-patterns-appear)), which must match every value of its type.
- `(a: T1, b: T2)` is **one** parameter of the tuple type `T1 * T2`; each part must have its
  type.
- The type after the parameters is the result's, optionally with its row
  (`: int / Throw<string>`).
- The function's type is generalized ([§3.10](03-types.md#310-inference)).
- Named, optional and default arguments are for members only ([§4.5](#45-members)).

**Recursion.** A function may call itself only when declared `let rec`
(`'fact' calls itself: declare it with let rec`). Functions that call each other are joined:

```fsharp
let rec isEven n = if n = 0 then true else isOdd (n - 1)
and isOdd n = if n = 0 then false else isEven (n - 1)
```

`and` requires `let rec`, and each member must have parameters; a value cannot refer to
itself.

**Operators.** `let (op) a b = …` defines the custom operator `op`
([§5.7](05-expressions.md#57-custom-operators)); a built-in operator cannot be defined this
way. **Active patterns** are defined with `let (|A|B|) x = …`
([§6.5](06-patterns.md#65-active-patterns)).

**Local `let`** has the same forms inside a block ([§5.8](05-expressions.md#58-blocks-and-bindings)),
with two differences: a local function is not generalized, and a local name may be shadowed.

## 4.2 Top-level values

A `let` without parameters at the top level declares a value. Its initializer decides what
kind of value it is ([§2.5](02-programs.md#25-top-level-values-and-startup)).

**Constants.** The initializer is a **constant expression**: built from literals, the
arithmetic, comparison and bitwise operators, `if`, union constructors, records, tuples,
conversion functions, layout facts ([§11.3](11-low-level.md#113-layout)), library functions
the compiler folds on literals, and other constants.

- A constant has no storage and no initialization order: each use is the value.
- An unannotated number constant takes at each use the type that use needs, like a literal:
  with `let limit = 10`, `u8 1 + limit` and `i64 1 + limit` are both accepted. An integer
  constant is still never a float.
- A constant whose type has type variables is generic: `let empty : Map<'k, 'v> = MapLeaf`.
- A constant's names are resolved where it is declared.

**Static tables.** A top-level array or list literal whose elements are constants (numbers,
bools, strings, and records, tuples and unions of constants), a record or tuple holding such
tables, and a boxed union value of constants, is one object in the program's image. It is
immutable and shared by every use; writing to a `let mutable` copy of a static array copies
it first, as with any shared array ([§10.2](10-execution.md#102-values-and-cells)).

**Startup values.** Any other initializer is evaluated once at startup, in order
([§2.5](02-programs.md#25-top-level-values-and-startup)). A startup value

- has exactly one type (it is not generalized);
- may be a cell: `let counter = ref 0` is one `ref` shared by every use, and a `Buffer` of
  one element type likewise. `Buffer.empty` alone, being generic, is a constant: a new
  `Buffer` at each use;
- is an error in a library, and an error under `--no-heap` when it allocates.

**Patterns.** `let (a, b) = e` at the top level declares each of the pattern's variables as a
top-level value. The pattern must match every value of its type. When `e` is a tuple
expression, each variable is declared from its own part, so parts that are constants are
constants.

**There is no top-level `let mutable`.** Mutable state at the top level is a `ref`, a
`Buffer`, an `Atomic`, or another cell.

## 4.3 Type declarations

```text
type-decl  = 'type' type-def { NEWLINE 'and' type-def } ;
type-def   = [ 'private' ] ID [ type-params ]
             ( '=' type                                           alias
             | '=' record-body [ members ]
             | '=' union-body [ members ]
             | 'with' members                                     extension
             | (nothing) ) ;                                      a unit of measure
type-params = '<' TYVAR { ',' TYVAR } '>' ;
record-body = '{' field { ';' field } [ ';' ] '}' ;
field       = [ attributes ] ID ':' type [ '=' expression ] ;
union-body  = [ '|' ] case { '|' case } ;
case        = ID [ 'of' case-field { '*' case-field } ] ;
case-field  = [ ID ':' ] atom-type ;
```

A body may follow `=` on the same line or as an indented block. A type names itself and the
types declared above it; types that name each other are joined with `and`.

### Records

A record type has named **fields**, each with a type.

- A record is a value: it has no identity, and its fields cannot be assigned through an
  immutable binding. A field cannot be declared `mutable`.
- **Defaults.** A field may have a default expression. It may use the fields declared before
  it, and its names are resolved in the record's module. A record expression may leave such a
  field out ([§5.4](05-expressions.md#54-records)); the default is then evaluated there, each
  time. A field of `option` type is not optional unless it has a default (`= None`).
- Two record types must not contain each other by value, directly or through other records
  (`record 'Point' contains itself through another record; make one of them a union`).

### Unions

A union type has **cases**; a value is one case with its fields.

- A case has zero or more fields, written after `of` and separated by `*`. Fields may be
  named. Field types are atomic: a function or tuple type is parenthesized.
- A case name is a **constructor**: a constant for a case without fields, and a function of
  the fields for the others, taking them as one tuple: `Rect (2.0, 3.0)`, or by name,
  `Rect(w = 2.0, h = 3.0)` ([§5.3](05-expressions.md#53-tuples-and-constructors)).
- A union with a single case must write its `|` when the case has no fields
  (`type Marker = | Marker`); otherwise the declaration is an alias.
- Union fields have no defaults.
- A union may be recursive.

### Aliases

`type Name<…> = T`, where `T` is a type expression on the same line that is neither a record
body nor cases, declares an **alias**: `Name` is the type `T` wherever it is written
(`type Duration = i64<ns>`, `type Pair<'a> = 'a * 'a`). An alias has no members of its own.

### Units of measure

`[<Measure>] type m` with no definition declares the unit `m`
([§3.6](03-types.md#36-units-of-measure)).

### Structural operations

Every record, union and tuple type has equality (`=`, `<>`), ordering (`<`, `compare`),
hashing (`hash`) and printing (`string`, interpolation), provided all its parts have them:

- equality and hashing are field by field;
- ordering compares records and tuples field by field in declaration order, and unions by
  case in declaration order, then by fields;
- printing writes the value as its expression: `{ x = 1; y = 2 }`, `Rect (1, 2)`, `Some 1`.

These are the automatic derives of [§7.5](07-traits.md#75-derive). A type holding a function
has none of them, and using one is an error where it is used. `[<NoEquality>]` removes
equality and hashing and `[<NoComparison>]` ordering; an `impl` replaces any of them.

## 4.4 Representation attributes

Attributes on a type declaration select a representation; each is specified with its topic.

| Attribute | On | Chapter |
|---|---|---|
| `[<CLayout>]` | a non-generic record or union: C's layout | [§11.3](11-low-level.md#113-layout) |
| `[<Bits>]`, `[<Bits n>]` | a non-generic record: one unsigned integer of bit fields | [§11.4](11-low-level.md#114-bare-metal) |
| `[<Derive(A, B)>]` | a record or union: the named derives | [§7.5](07-traits.md#75-derive) |
| `[<NoEquality>]`, `[<NoComparison>]` | any type | [§4.3](#structural-operations) |
| `[<Cyclic>]` | any type: silences the `cycle` warning | [§10.4](10-execution.md#104-lifetime) |

Without an attribute, a type's representation is the implementation's
([§10.3](10-execution.md#103-representation)).

## 4.5 Members

```text
members = [ 'with' ] { member } ;
member  = 'member' ID '.' ID [ member-params ] [ ':' type ] '=' block
        | 'static' 'member' ID [ member-params ] [ ':' type ] '=' block ;
member-params = '(' [ member-param { ',' member-param } ] ')' ;
member-param  = [ '?' ] ID [ ':' type ] [ '=' expression ] ;
```

Members follow a record's or union's body, or extend an existing type with
`type T with …`, built-in types included (`type string with member s.Shout = s + "!"`).

- **Instance members** name their receiver: `member v.Length = …`. Without parameters the
  member is a **property**, read as `v.Length`; with a parenthesized parameter list it is a
  **method**, called as `v.Dot(w)`.
- **Static members** have no receiver and are named through the type: `Vec.Zero`,
  `Http.Get(url)`.
- **No overloading:** a type has at most one member of a name, and a member must not have the
  name of one of the type's fields.
- A type declared with members only (no fields, no cases) has no values; it groups static
  members.
- A member may perform effects, as a function may.

**Named and optional arguments.** In a method call, arguments are given in parentheses,
separated by commas.

- `name = value` is a **named argument** when `name` is one of the method's parameters.
  Positional arguments come first; a parameter is given at most once.
- `?name: T` declares an **optional parameter**. Inside the method, it has type `option<T>`,
  and an omitted argument is `None`.
- `?name: T = e` declares an optional parameter with a **default**. Inside the method it has
  type `T`. The default is evaluated at the call, each time it is needed, after the
  arguments given, and may use the parameters before it.
- Only an optional parameter may have a default.

```fsharp
type Http =
  static member Get(url: string, ?timeout: int = 30, ?headers: list<string * string>) = …

Http.Get("https://example.org", timeout = 5)
```

## 4.6 Attributes

```text
attributes = '[<' attribute { ';' attribute } '>]' ;
attribute  = ID [ STR | INT | '(' attr-arg { ',' attr-arg } ')' ] ;
attr-arg   = ID | STR ;
```

An attribute list precedes a declaration, on the same line or the line above, or precedes a
field of a `[<Bits>]` record. The attributes are a fixed set
([§12.3](12-builtins.md#123-attributes)); programs cannot define attributes, and an unknown
attribute or one on a declaration it does not apply to is an error.

## 4.7 Top-level `assert`

```text
assert-decl = 'assert' expression ;
```

A top-level `assert e` is checked when compiling if `e` is a constant expression, and a false
one is an error stating what it read (`assert fails when compiling: sizeof<Packet> = 16 is
false (sizeof<Packet> is 20)`). Otherwise it is evaluated at startup in declaration order, and
a false one panics.

## 4.8 Documentation and tests

- `///` comments above a declaration are its documentation ([§1.2](01-lexical.md#12-comments)).
- A top-level value of type `Testing.Test` or `list<Testing.Test>` marked `[<Tests>]` is part
  of its file's tests. Tests are ordinary values built with the library's `test`, `testList`,
  `testProperty`, …; the language adds only the attribute.

## 4.9 Imports and providers

```text
import = 'import' 'c' STR
       | 'import' ID STR
       | 'import' ID '(' STR { ',' ID '=' import-const } ')' ;
import-const = STR | INT | FLOAT | 'true' | 'false' ;
```

An `import` declares what a **provider** derives from an external source at compile time.

- **Placement.** A bare `import` declares the provided names in the enclosing module, where
  they shadow the prelude's. `module M = import …` puts them in the module `M`.
- **Meaning.** A provider is a program that reads the source (and its options) and writes Z#
  source text: a module of ordinary declarations, which is then checked as if it were a file
  of the program. Nothing of the provider exists at run time. The program is rebuilt when the
  source changes.
- **Built-in providers:**

  | Provider | Source | Provides |
  |---|---|---|
  | `c` | a C header | externs, `[<CLayout>]` types and constants ([§11.1](11-low-level.md#111-c-interop)) |
  | `json` | a sample document | record types with JSON derives, and a parser |
  | `csv` | a file with rows | a row record and a reader; options `separator`, `hasHeaders`, `types` |
  | `sql` | a schema | a record per table; option `queries` for typed queries |
  | `svd` | a chip's SVD file | a module per peripheral, each register a `[<Bits>]` record; option `only` |

- **Other providers.** `import name …` with any other name runs the program
  `zs-provider-<name>` from `PATH`, or a dependency whose manifest has a `[provider]` section.
- A source path is relative to the importing file. Options are constants.
- A name that a provider declares cannot be renamed in the program; change the source.

`[<Link "name">]` before `import c` links a library or a C file with the program
([§11.1](11-low-level.md#111-c-interop)).
