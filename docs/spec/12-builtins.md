# 12. Built-in names

This chapter lists what is in scope in every module without an `open`, and the fixed sets the
language defines: attributes and warnings. The library proper is documented in
[the library reference](../reference/README.md).

## 12.1 The prelude

### Types

| Type | Declaration |
|---|---|
| the primitive types | [§3.2](03-types.md#32-numbers), [§3.3](03-types.md#33-other-primitive-types) |
| the built-in generic types | [§3.4](03-types.md#34-structured-types) |
| `option<'a>` | `None \| Some of 'a` |
| `result<'a, 'e>` | `Ok of 'a \| Error of 'e` |
| `list<'a>` | `[]` and `::`, with fields `head` and `tail` |
| `float`, `double`, `c_int` | aliases of `f64`, `f64`, `i32` |

### Traits and effects

`Add`, `Num`, `Eq`, `Ord`, `Show`, `Format`, `Hash`, `Dispose`, `Iter` and `Diff`
([§7.6](07-traits.md#76-the-prelude-traits)); the effects `Yield` and `Throw`
([§8.6](08-effects.md#86-the-built-in-effects)); the derives `Eq`, `Ord`, `Hash`, `Show` and
`Diff` ([§7.5](07-traits.md#75-derive)).

### Functions

| Name | Type | Meaning |
|---|---|---|
| `print`, `println`, `eprintln` | `string -> unit` | write to standard output (with a line end) or standard error |
| `string` | `'a -> string` when `'a : Show` | `Show.show` |
| `compare` | `'a -> 'a -> int` when `'a : Ord` | `Ord.compare` |
| `hash` | `'a -> int` when `'a : Hash` | `Hash.hash` |
| `min`, `max` | `'a -> 'a -> 'a` when `'a : Ord` | |
| `id` | `'a -> 'a` | |
| `fst`, `snd` | `'a * 'b -> 'a`, `'a * 'b -> 'b` | |
| `ignore` | `'a -> unit` | discards a value |
| `ref` | `'a -> ref<'a>` | a new cell |
| `panic`, `failwith` | `string -> 'a` | panics ([§10.5](10-execution.md#105-panics)) |
| `assert` | `bool -> unit` | panics when false ([§5.9](05-expressions.md#59-control-flow)) |
| `int`, `i8`, `i16`, `i32`, `i64`, `u8`, `u16`, `u32`, `u64`, `usize`, `f32`, `f64`, `float`, `c_int` | `'a -> T`, `'a` a number or `char` | conversion, below |
| `char` | `'a -> char`, `'a` an integer or `char` | the character with that code |

The other methods of the prelude traits (`show`, `format`, `dispose`, `forEach`, `diff`) are
in scope by name; `Add`'s, `Num`'s and `Eq`'s are reached through their operators or
qualified (`Add.zero`).

`not` is a keyword ([§5.6](05-expressions.md#56-operators)), not a function.

### Conversions

A conversion function converts between any two number types (and from `char` to a number):

| From → to | Result |
|---|---|
| integer → wider integer of the same signedness | the same value |
| integer → any other integer type | the value **modulo 2^width** of the target (two's complement); it never panics |
| integer → float | the nearest representable value |
| float → integer | truncated toward zero, **saturating** at the target type's bounds; NaN gives 0 |
| float → float | the nearest representable value |
| `char` → integer | its code point, then as integer → integer |
| integer → `char` | the scalar value with that code |

A conversion's argument is a number without a unit of measure
([§3.6](03-types.md#36-units-of-measure)).

### Names with advice

The reference implementation recognizes names from other languages and reports what to write
instead: `printfn`, `sprintf`, `failwithf`, `raise`, `null`, `async`, `.ToString()`, a
`.Value` on an option, `!x`, `x++`, `try … with`, classes. These are diagnostics, not
language features.

## 12.2 Library modules the language names

Some syntax is defined in terms of library functions. A conforming library provides them
with these meanings; the syntax always refers to the library's, whatever a program defines
under the same name.

| Syntax | Refers to |
|---|---|
| `xs @ ys` | `Collections.List.append` |
| `$"{x}"`, `$"{x:F2}"`, `{x,8}` | `Show.show`, `Format.format`, `Text.String.padLeft` / `padRight` |
| `b"…"` | `Text.String.bytes` |
| `use x = e` | `Dispose.dispose` |
| `for x in c` | `Iter.forEach` |
| `w { … }` | `W.Builder.delay`, `bind`, `ret`, `zero`, `using`, `forEach` |
| `task { }` | `Threading.Task` |
| `seq { }`, `yield` | `Collections.Seq`, `Yield` |
| `[<Tests>]` | `Testing.Test`, `Testing.Runner` |
| `derive` bodies | `Shape.*` ([§7.5](07-traits.md#75-derive)) |

## 12.3 Attributes

The attributes are a closed set. Syntax: [§4.6](04-declarations.md#46-attributes).

| Attribute | On | Argument | Meaning | See |
|---|---|---|---|---|
| `Measure` | a type with no body | | declares a unit of measure | [§3.6](03-types.md#36-units-of-measure) |
| `Derive` | a record or union | derive names | applies the derives | [§7.5](07-traits.md#75-derive) |
| `NoEquality` | a type | | no automatic `Eq` and `Hash` | [§4.3](04-declarations.md#structural-operations) |
| `NoComparison` | a type | | no automatic `Ord` | §4.3 |
| `Cyclic` | a type | | the program breaks this type's cycles | [§10.4](10-execution.md#104-lifetime) |
| `CLayout` | a non-generic record or union | | C layout; a union is a C union | [§11.3](11-low-level.md#113-layout) |
| `Bits` | a non-generic record | optional width | a bit-field record | [§11.4](11-low-level.md#114-bare-metal) |
| `Bit`, `Width` | a field of a `Bits` record | a number | the field's lowest bit; its width | §11.4 |
| `Export` | a function | optional C name | exported to C | [§11.1](11-low-level.md#111-c-interop) |
| `Link` | an `import c` | a library or file | linked with the program | §11.1 |
| `Unsafe` | a function | | callable only in `unsafe` | [§11.2](11-low-level.md#112-unsafe) |
| `Wrapping` | a function | | its integer `+ - *` wrap | [§5.6](05-expressions.md#56-operators) |
| `FastMath` | a function | | relaxed float arithmetic | [§11.5](11-low-level.md#115-simd) |
| `Target` | a function | CPU features | compiled for those features | §11.5 |
| `Multiversion` | a function | feature sets | a version per set, chosen at run time | §11.5 |
| `NoAlloc` | a function | | must not touch the heap | §11.4 |
| `Interrupt` | a `unit -> unit` function | a line | an interrupt handler | §11.4 |
| `Section` | a top-level value | a section name | where its storage is placed | §11.4 |
| `Align` | a top-level value | a power of two | its storage's alignment | §11.4 |
| `Tests` | a top-level value | | part of the file's tests | [§4.8](04-declarations.md#48-documentation-and-tests) |
| `NoWarn` | any declaration | warning names | silences them in the declaration | [§12.4](#124-warnings) |

- `Wrapping`, `FastMath`, and one of `Target` or `Multiversion` may be combined on a
  function; `Section` and `Align` on a value; the type attributes among themselves. `Target`
  and `Multiversion` exclude each other.
- An attribute with a missing or malformed argument, an unknown attribute, or an attribute on
  a declaration it does not apply to, is an error.

## 12.4 Warnings

A warning does not stop translation. Each has a name, shown in brackets after its message.

| Name | Given when |
|---|---|
| `unused-value` | a statement that is not last in its block has a value that is not `unit` |
| `cycle` | a type's values can form a reference cycle through a cell ([§10.4](10-execution.md#104-lifetime)) |
| `stale-input` | a provided module was taken from the cache because its provider could not run |

- `[<NoWarn "name">]` on a declaration silences `unused-value` and `cycle` within it. A
  `NoWarn` without a name, or with an unknown one, is an error.
- Under `--strict`, any warning fails the build.
- Unreachable clauses and inexhaustive matches are errors, not warnings
  ([§6.4](06-patterns.md#64-exhaustiveness-and-redundancy)).

## 12.5 Environment

The reference implementation reads these at run time; they do not change a program's meaning:
`ZS_BACKTRACE=0` (no backtrace on a panic), `ZS_ABORT=1` (a panic calls `abort`),
`ZS_LEAKCHECK=1` (report live objects at exit), `ZS_STATS=1` (report allocation statistics),
`ZS_WORKERS=n` (the thread pool's size).
