# 3. Types

Z# is statically typed. Every expression has one type, found by inference
([§3.10](#310-inference)); annotations are optional almost everywhere.

## 3.1 Type syntax

```text
type       = tuple-type [ '->' type | '/' row ] ;
tuple-type = atom-type { '*' atom-type } ;
atom-type  = ( TYVAR
             | ID [ '<' type-arg { ',' type-arg } '>' ]
             | number-type '<' measure '>'
             | 'dyn' ID
             | '(' type ')' )
             { ID } ;                                  postfix application: int list
type-arg   = type | INT ;                              INT only as fixed's length
row        = '<>' | TYVAR | label | '<' label { ',' label } [ '|' TYVAR ] '>' ;
label      = ID [ '<' type { ',' type } '>' ] ;
```

- `->` is right-associative: `a -> b -> c` is `a -> (b -> c)`.
- `*` binds tighter than `->`: `int * string -> bool` takes a pair.
- A row follows a function's result: `a -> b / E` is the function from `a` to `b` that may
  perform `E` ([§3.8](#38-effect-rows)).
- Postfix application is F#'s older spelling: `int list` is `list<int>`, and
  `string option list` is `list<option<string>>`.
- `float` and `double` name `f64`; `c_int` names `i32`.

## 3.2 Numbers

| Type | Values |
|---|---|
| `i8` `i16` `i32` `i64` | two's-complement signed integers of 8, 16, 32 and 64 bits |
| `u8` `u16` `u32` `u64` | unsigned integers of those widths |
| `int` | the signed machine word: 64 bits on a 64-bit target, 32 on a 32-bit target |
| `usize` | the unsigned machine word |
| `f32` `f64` | IEEE 754 binary32 and binary64 |

- `int` is a type of its own, not an alias of `i64` or `i32`.
- **No implicit conversion** exists between number types, in any direction: `1 + 2.0` and
  comparing a `u8` with an `i32` are errors. A conversion is a call of the function named as
  the target type ([§12.1](12-builtins.md#121-the-prelude)).
- Arithmetic and its overflow rules are in [§5.6](05-expressions.md#56-operators).

## 3.3 Other primitive types

| Type | Values |
|---|---|
| `bool` | `true`, `false` |
| `char` | a Unicode scalar value (32 bits). It has equality, ordering, hashing and printing, no arithmetic; `int c` and `char n` convert |
| `string` | an immutable sequence of bytes, by convention UTF-8. Its length is in bytes |
| `unit` | the one value `()` |
| `cstr` | a C string, `const char *` ([§11.1](11-low-level.md#111-c-interop)) |
| `cptr` | an opaque C pointer |
| vectors and masks | `f32x4`, `i32x8`, `u8x16`, …, `mask4`, … ([§11.5](11-low-level.md#115-simd)) |

## 3.4 Structured types

**Tuples.** `T1 * T2 * … * Tn` (n ≥ 2) is the type of `(e1, e2, …, en)`. A tuple is a value;
tuples of different sizes are different types. There is no one-element tuple.

**Functions.** `A -> B` ([§3.7](#37-function-types)).

**Named types** are declared by `type` ([§4.3](04-declarations.md#43-type-declarations)):
records, unions, and aliases. A named type may have type parameters, written
`Name<T1, …, Tn>`; every use must give all of them. Two record or union types with different
names are different types, whatever their definitions; an alias is the type it names.

**Built-in generic types.** These type constructors are built in; their operations are in
the library modules of the same names.

| Type | What it is | Defined in |
|---|---|---|
| `option<'a>` | `None` or `Some x` | prelude ([§12.1](12-builtins.md#121-the-prelude)) |
| `result<'a, 'e>` | `Ok x` or `Error e` | prelude |
| `list<'a>` | an immutable singly linked list: `[]` or `x :: xs` | built in |
| `array<'a>` | a value array with copy-on-write | [§10.2](10-execution.md#102-values-and-cells) |
| `fixed<'a, N>` | exactly `N` elements held inline; `N` is an integer literal ≥ 1 | [§11.3](11-low-level.md#113-layout) |
| `span<'a>` | a window into an array, a string's bytes or a `Buffer` | [§10.2](10-execution.md#102-values-and-cells) |
| `Buffer<'a>` | a shared, growable, mutable array | §10.2 |
| `ref<'a>` | a mutable cell | §10.2 |
| `weak<'a>` | a reference that does not keep its object alive | [§10.4](10-execution.md#104-lifetime) |
| `Atomic<'a>`, `Mutex<'a>`, `Channel<'a>`, `Spsc<'a>` | cells made for threads and interrupt handlers | [§10.6](10-execution.md#106-threads-and-share) |
| `share<F>`, `callback<F>`, `fnptr<F>` | function kinds | [§3.7](#37-function-types) |
| `ptr<'a>` | a raw pointer | [§11.2](11-low-level.md#112-unsafe) |
| `dyn Trait` | a value of any type implementing `Trait` | [§7.4](07-traits.md#74-dyn) |

`fixed` is the only type that takes a number as an argument; there are no type-level numbers
elsewhere, and the length is not a type variable.

Types defined by the library with no special standing in the language (`Map`, `Set`,
`HashMap`, `Seq`, `Task`, …) are ordinary records and unions.

## 3.5 Type variables and constraints

A type variable `'a` stands for any type. A type with variables is **generic**; a generic
definition is used at any types that satisfy its **constraints**:

- a **trait constraint** `'a : Trait`: the type must implement the trait
  ([chapter 7](07-traits.md)). A trait with further parameters carries them:
  `'c : Iter<int>`;
- a **literal constraint**: the type of a numeric literal must be a number type of the
  literal's kind ([§3.9](#39-literals)).

Constraints are always inferred; there is no syntax to write one. Tools display them after the
type: `'a -> string when 'a : Describe`.

A type variable written in an annotation names one type throughout the declaration it is
written in. It does not by itself make the declaration generic: inference decides
([§3.10](#310-inference)).

Generic definitions are compiled by **monomorphization**: each use at different types is its
own instance, so generics have no run-time representation and no run-time cost.

## 3.6 Units of measure

A number type may carry a unit: `f64<m/s>`, `i64<ns>`.

```text
measure = unit-term { [ '*' | '/' ] unit-term } ;       juxtaposition multiplies
unit-term = ( ID | TYVAR | '1' | '(' measure ')' ) [ '^' [ '-' ] INT ] ;
```

- A unit is declared by `[<Measure>] type name` with no definition.
- `1` is the dimensionless unit; `f64<1>` is `f64`.
- Units form an abelian group: products, quotients and integer powers, compared up to the
  group's laws, so `m/s * s` is `m` and `kg m/s^2` is `m kg s^-2`.
- **Typing:** `+`, `-`, comparison and `%` need both operands at the same unit; `*` multiplies
  the units and `/` divides them. A function may be generic in a unit (`f64<'u>`), inferred
  like any type variable.
- A literal with a unit, `9.58<s>` (no space before `<`), takes its number type from its
  context like any literal: `let d: i64<ns> = 5<ns>`.
- The conversion functions take numbers without a unit. A unit is attached by multiplying by
  a measured one (`x * 1.0<m>`) and removed by dividing by it (`d / 1.0<m>`).
- Units are checked at compile time and erased: `f64<m>` is an `f64` at run time.

## 3.7 Function types

`A -> B` is the type of a function taking an `A` and giving a `B`.

- **Functions are curried.** A function of several parameters has the type
  `A1 -> A2 -> … -> B`, and applying it to fewer arguments gives a function of the rest.
- A function taking a tuple, `A1 * A2 -> B`, is a function of one parameter.
- A function type carries the **row** of effects a call may perform
  ([§3.8](#38-effect-rows)); a type written without one is read as in §3.8.
- Functions have no equality, ordering, hashing or printing.

There are four **kinds** of function. They differ in what the function may hold and who may
call it; the plain kind is the default.

| Type | What it is | May capture | Called |
|---|---|---|---|
| `A -> B` | a closure | anything, except a `let mutable` | anywhere on its thread |
| `share<A -> B>` | a closure another thread may run | only `Share` values ([§10.6](10-execution.md#106-threads-and-share)) | as a function, on any thread |
| `callback<A -> B>` | a closure lent to C for the length of a call, as a function pointer with user data | anything | by C, on the thread that passed it; `callback<share<A -> B>>` on any thread |
| `fnptr<A -> B>` | a bare C function pointer, no captured state | nothing | inside `unsafe` |

- Where a `share<F>` or `callback<F>` is expected, a lambda, a local function or a named
  function of type `F` is accepted and checked at that point
  ([§5.11](05-expressions.md#511-implicit-conversions)).
- A `share<F>` is used wherever an `F` is expected.
- `share`, `callback` and `fnptr` functions must perform no effect.

## 3.8 Effect rows

A **row** is the set of effects a function may perform when called
([chapter 8](08-effects.md)).

| Written | Meaning |
|---|---|
| `B / E` | performs `E` |
| `B / <E, F>` | performs `E` and `F` |
| `B / <E \| 'e>` | performs `E` and whatever `'e` is |
| `B / 'e` | performs whatever `'e` is |
| `B / <>` | performs nothing |

- A row is a list of **labels** (an effect's name with its type arguments) ending either
  closed or in a **row variable**. Order is not significant between different effects. The
  same effect may occur twice; the first is the one the innermost handler takes.
- **The row is on the last arrow.** In `A -> B -> C / E`, giving the first argument performs
  nothing; giving the second may perform `E`.
- **A function type written without a row** is read by where it is written:
  - in a `let`'s parameter or result annotation: a fresh row variable, joined to the
    function's own row (the function performs what its argument performs), or the inferred
    row for the function's own result;
  - in a type declaration (a field, a case) or an effect's operation: the empty row. A type
    cannot be polymorphic in a row it does not name;
  - in a trait's method: the arrows of its function arguments and the method's own last arrow
    share one row variable ([§7.1](07-traits.md#71-traits)).
- A written row is checked: a function declared `/ <>` whose body performs an effect is an
  error.

**Display.** Tools show an inferred row as written above, except that a function's own row
variable is not shown where it only connects its function arguments to its result:
`List.iter` is shown as `('a -> unit) -> list<'a> -> unit`, standing for
`('a -> unit / 'e) -> list<'a> -> unit / 'e`. An argument that must perform nothing is shown
with `/ <>`.

## 3.9 Literals

| Literal | Type |
|---|---|
| integer | any integer type the context requires; `int` when the context requires none |
| float | `f32` or `f64` as the context requires; `f64` when it requires none |
| `-` applied to an integer literal | one constant of a **signed** integer type |
| character | `char` |
| string `"…"`, `"""…"""`, `$"…"` | `string`; a plain literal is a `cstr` where one is required |
| byte string `b"…"` | `span<u8>` |
| `true`, `false` | `bool` |
| `()` | `unit` |

- An integer literal is never a float, and a float literal never an integer.
- A negative literal at an unsigned type is an error (`let a : u8 = -1`).
  `-0x8000_0000_0000_0000` is `i64`'s least value.
- An unannotated top-level constant that is a number keeps its literal constraint: each use
  takes the type it needs ([§4.2](04-declarations.md#42-top-level-values)).

*Deviation.* An integer literal that does not fit its type should be an error. At 0.7 it is
accepted and truncated to the type's width without a diagnostic: `let a : u8 = 300` is `44`.
Programs must not rely on this.

## 3.10 Inference

Types are inferred by Hindley–Milner unification, extended with trait constraints, units of
measure (abelian-group unification) and rows (scoped labels).

**Generalization.** A definition's type is generalized over the type, unit and row variables
left free once it is checked:

- **Top-level functions** are generalized, with their inferred constraints. The members of a
  `let rec … and` group are generalized together and share their variables.
- **Top-level values** are generalized only when they are constants
  ([§4.2](04-declarations.md#42-top-level-values)): `let empty : Map<'k, 'v> = MapLeaf` is a
  map of any type. A startup value must have one type (`a top-level value of type … must be a
  constant to be generic; make it a function, or give it a type`).
- **Local definitions are not generalized.** A local `let f x = …` has one type in its
  function: every use must agree. A function used at several types is declared at the top
  level.

  ```fsharp
  let main () =
    let id x = x
    let a = id 1
    let b = id "a"      // error: expected int, got string
    0
  ```

**Order of checking.** Inference goes through a function's body in order, with these
refinements, which decide whether a program needs an annotation:

- **Member access is type-directed.** `e.name` needs the type of `e` known at that point,
  from an annotation or from what precedes; otherwise the access is resolved among the record
  types in scope, and failing that it is an error asking for an annotation
  ([§5.5](05-expressions.md#55-postfix-forms)).
- **Lambda arguments are checked last.** In a call, an argument that is a lambda without
  parameter annotations is checked after the call's other arguments, with the parameter types
  the call then expects. So both `xs |> List.map (fun s -> s.Length)` and
  `List.map (fun s -> s.Length) xs` are accepted. A lambda with annotated parameters is
  checked in its place.
- **An expected type flows inward** through `if` and `match` branches, the tail of a `let`,
  tuple, list and array elements, and the arguments of functions, constructors and C calls. It
  selects a record literal's type ([§5.4](05-expressions.md#54-records)), a literal's number
  type, and the conversions of [§5.11](05-expressions.md#511-implicit-conversions).

**Annotations.** `(e : T)` in an expression, `(x : T)` on a parameter, `: T` after a
function's parameters (its result) and after a `let`'s pattern assert the type. An annotation
is required only where the rules above say the type must be known.

**Defaults.** After a top-level declaration is checked, a literal constraint left unresolved
becomes `int` or `f64` ([§3.9](#39-literals)), except in a constant, which keeps it.
