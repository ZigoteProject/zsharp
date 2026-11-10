# 11. Low-level programming

This chapter specifies the features that reach outside the safe language: C, raw memory,
machine layout, bare-metal hardware and SIMD.

## 11.1 C interop

### Externs

```text
extern-decl = 'extern' ID ':' extern-type { '->' extern-type } ;
extern-type = tuple-type | '...' ;
```

```fsharp
extern puts   : cstr -> c_int
extern printf : cstr -> ... -> c_int
extern rand   : unit -> c_int
```

- `extern f : T1 -> … -> Tn -> R` declares the C function `f`, linked by that name, with the
  target's C calling convention.
- A `unit` parameter stands for no parameters (`void`); a `unit` result for `void`.
- `...` as the last parameter declares a variadic function; extra arguments are passed with
  C's default promotions.
- An extern is called like any function, with all its arguments. It has the empty row.
- A C name is global to the program: it is reachable bare from any module, and through the
  module that declares it.
- **Calling C is unchecked**: the declaration is trusted, and what the C function does is
  outside the language's guarantees.

### Types that cross

| Z# | C |
|---|---|
| `i8` … `i64`, `u8` … `u64`, `f32`, `f64` | the fixed-width types |
| `int`, `usize` | `intptr_t`, `size_t` (the machine word) |
| `c_int` (`i32`) | `int` |
| `bool` | `bool` |
| `unit` | `void` |
| `cstr` | `const char *`, NUL-terminated |
| `cptr` | any other pointer, opaque |
| `ptr<T>` | `T *` ([§11.2](#112-unsafe)) |
| a `[<CLayout>]` record or union | the struct or union, **by value** |
| `fixed<T, N>` in a `[<CLayout>]` record | `T field[N]` |
| a `[<Bits>]` record | its unsigned integer |
| `span<T>` (parameters only) | a pointer and a length, two arguments |
| `callback<A -> R>` | a function pointer and a `void *` user argument |
| `fnptr<A -> B -> R>` | `R (*)(A, B)` |
| any other counted value (a list, a closure, a boxed union, a `dyn`) | an opaque `zs_handle` |

- A `string` or a string literal passed as a `cstr` goes as a pointer to its bytes, valid for
  the call. A `cstr` returned by C is a pointer the program does not own;
  `String.ofCStr` copies it.
- A type not in the table cannot cross (`type UserId cannot cross the C boundary`): a record
  without `[<CLayout>]`, a tuple, an unboxed union.
- Structs by value follow the target's ABI exactly, as a C compiler would pass them.
- **Callbacks.** A Z# function passed as a `callback<F>` is lent for the duration of the
  call: C must not keep it. C must call it on the thread that passed it (a panic otherwise),
  unless the parameter is `callback<share<F>>`.
- **Handles.** A handle returned to C is owned by the caller, which releases it with
  `zs_release`; a handle passed to C is lent for the call and kept with `zs_retain`. A handle
  to a `Share` value may be used on any thread; any other on the thread that made it.

### Importing headers

`import c "header.h"` ([§4.9](04-declarations.md#49-imports-and-providers)) declares what the
header itself declares:

| C | Z# |
|---|---|
| a function | an extern |
| a struct, named or `typedef`'d | a `[<CLayout>]` record |
| a union | a `[<CLayout>]` union |
| an enum's values; `#define`s of numbers, strings and struct literals | constants |
| an enum type | `i32` |
| `char *` / any other pointer / a function pointer | `cstr` / `cptr` / `fnptr<…>` |
| `long` / `long long` | the machine word / `i64` |
| an array field / an array parameter | `fixed<T, N>` / a pointer |

Not imported, with an error at a use explaining why: arrays without a length, structs with
bit fields, unnamed members, `static inline` functions, opaque structs by value.

`[<Link "name">]` before an `import c` links the library `name`, or compiles and links the
named `.c` file, or links the named object or archive.

### Exporting

`[<Export "name">]` on a top-level function gives it the C symbol `name` (its own name
without an argument) and the C calling convention.

- The function must not be generic, must perform no effect, and its parameter and result
  types must be types that cross.
- A **library build** produces an archive or shared object and a C header declaring the
  exports, the `[<CLayout>]` types (with size assertions), the handle functions and
  `zs_set_panic_hook`.
- A library has no startup ([§2.5](02-programs.md#25-top-level-values-and-startup)).
- A panic in a library ends the host process; the hook runs first and must not call back
  into the library.

## 11.2 `unsafe`

```text
unsafe = 'unsafe' block ;
```

Inside an `unsafe` expression, and nowhere else, a program may:

- call the raw-pointer operations: `Ptr.read`, `write`, `readUnaligned`, `writeUnaligned`,
  `add`, `diff`, `alloc`, `free`, `cast`; and make a span over raw memory (`Span.ofPtr`);
- call a `fnptr<…>` value;
- read a `[<CLayout>]` union's case ([§11.3](#113-layout));
- call a function marked `[<Unsafe>]`.

`unsafe` covers the text of its expression. It does not make the enclosing function unsafe to
call: `[<Unsafe>]` on a function does that, for a function that trusts its arguments, and
such a function's own raw operations are still written in `unsafe`.

- `ptr<T>` is a raw pointer to a `T` that crosses to C: a number, `bool`, a `[<CLayout>]`
  type or another pointer. `Ptr.null`, `Ptr.isNull` and `Ptr.toCPtr` are safe.
- **Undefined behaviour.** Inside `unsafe`, the program is responsible for what the language
  otherwise guarantees: a read or write through an invalid pointer, a wrong `cast`, reading
  a union case that was not written, or calling a function pointer with the wrong type has
  undefined behaviour. So has an `extern` call that breaks the C function's contract, and an
  `Mmio` access to an address that is not a register.
- Safe code remains safe around a *correct* `unsafe` expression.

## 11.3 Layout

### `[<CLayout>]` records

A `[<CLayout>]` record is laid out as the target's C compiler lays out a struct with the same
fields in the same order. It must not be generic, and its fields must be types that cross
([§11.1](#types-that-cross)). In the language it is an ordinary record.

### `[<CLayout>]` unions

A `[<CLayout>]` union is a C union: no tag; each case has exactly one field and is a view of
the same bytes. Its size is the largest case's and its alignment the strictest.

- Constructing a case writes its field and zeroes the remaining bytes.
- A case is read as `unsafe u.Case`.
- It has no `match`, equality, ordering, hashing or printing.

### `fixed<'a, N>`

A value array of exactly `N` elements, stored inline ([§3.4](03-types.md#34-structured-types)).
`N` is a positive integer literal. It is indexed and iterated like an array, and has the
structural operations element by element.

### Layout facts

```text
layout-fact = ( 'sizeof' | 'alignof' ) '<' type '>'
            | 'offsetof' '<' type '>' STR ;                '<' adjacent to the word
```

`sizeof<T>`, `alignof<T>` and `offsetof<T> "field"` are `int` constant expressions: the size,
alignment and field offset of `T` in bytes on the target. For a `[<CLayout>]` type they are
C's; for any other type they describe the reference implementation's representation
([§10.3](10-execution.md#103-representation)) and are implementation-defined. In a generic
function they are known when it is instantiated.

With a top-level `assert` ([§4.7](04-declarations.md#47-top-level-assert)), they check a
layout at compile time: `assert (sizeof<Packet> = 20)`.

## 11.4 Bare metal

On a target without an operating system, the language is the same, with Core only
([§2.8](02-programs.md#28-library-tiers-and-targets)), `int` of the target's word, and these
additional features. The attributes are errors on other targets where noted.

**Memory-mapped registers.** `Mmio.read8`, `read32`, `write8` and `write32` take an address
(`usize`) and perform one volatile access of that width. They are unchecked
([§11.2](#112-unsafe)). A register address is typically a constant, which costs nothing.

**`[<Bits>]` records.** `[<Bits>]` or `[<Bits n>]` (`n` = 8, 16, 32 or 64) on a non-generic
record makes it one unsigned integer whose fields are bit fields.

- Field types are `bool` (1 bit), a union without fields (as many bits as its cases need),
  and `u8` … `u64` (their width).
- Fields are placed from bit 0 upward in declaration order. `[<Bit k>]` on a field places it
  at bit `k`, and the next field follows it; `[<Width w>]` gives it `w` bits.
- The record is used as any record: construction, `{ r with f = v }`, field access, patterns.
  Writing a value too wide for its field panics; reading an enum field whose bits name no
  case panics.
- Equality, ordering and hashing are the integer's. `Bits.toU32`/`ofU32` (and the other
  widths) convert, checked against the record's width at compile time.

**Interrupt handlers.** `[<Interrupt n>]` (a line's number) or `[<Interrupt "NAME">]` (a
line of the target board, or a core exception such as `"HardFault"` or `"SysTick"`) on a
top-level function installs it as the handler. It is an error on a target that has no
interrupt table.

- Its type is `unit -> unit`, and it performs no effect.
- It is checked as a `share<unit -> unit>` ([§10.6](10-execution.md#106-threads-and-share)):
  it shares state with the program only through `Atomic`, `Spsc` and `Signal`.
- It is implicitly `[<NoAlloc>]`.

**`[<NoAlloc>]`.** A function so marked must not allocate or free heap memory, itself or
through anything it calls; otherwise it is an error naming the call chain to the allocation.
The check is conservative: calling a function value, performing an effect, building a
string, a closure with captures or a boxed union, writing a shared array, and dropping the
last reference to a heap value all count. Externs count as not allocating. The check is on
the program after the optimizations that the language defines as allocation-free (small
unions unboxed, fused list pipelines), independent of the optimization level.

**`--no-heap`** applies the check to the whole program and builds it without a heap.

**Placement.** On a top-level static table, or a top-level `ref` or `Buffer.create` with
constant arguments:

- `[<Section ".name">]` places its storage in that linker section. A `.noinit` section is
  neither loaded nor zeroed at reset, and holds plain values only.
- `[<Align n>]` aligns it to `n` bytes, a power of two from 8 to 4096.

**CPU.** `Cpu.critical f` runs `f` with interrupts masked; `Cpu.wfi` and the other functions
of `Cpu` are single instructions. `Irq.enable`, `disable`, `pend` and `wait` control and wait
for interrupt lines.

## 11.5 SIMD

**Vector types.** For every number type `T` and every width of 128, 256 and 512 bits there is
a built-in type `T`x`N` of `N` lanes: `f32x4`, `f32x8`, `f32x16`, `f64x2`, `i8x16`, `u8x32`,
`i32x8`, …. The **mask types** `mask2` … `mask64` have one boolean per lane.

- Vectors are plain values and are `Share`. There is no vector literal: a vector is made by
  the functions of its module, named as the type capitalized (`F32x8.splat`, `F32x8.init`,
  `F32x8.load`).
- **Operators** act lane by lane: `+ - * / %` on all vectors; `&&& ||| ^^^` on integer
  vectors; `<<< >>>` on integer vectors with an `int` count applied to every lane. `=` and
  `<>` compare whole vectors and give a `bool`; lane comparisons are functions that give
  masks.
- Integer lanes **wrap** on overflow (unlike scalars); integer division panics when any lane
  of the divisor is zero.
- `shuffle`'s indices are an array literal of constants.
- There are no functions generic over vector types.

**Function attributes.**

| Attribute | Meaning |
|---|---|
| `[<FastMath>]` | the function's float `+ - * /` may be reordered and may assume no NaN or infinity |
| `[<Target "avx2,fma">]` | the function is compiled for those CPU features; calling it on a CPU without them is undefined |
| `[<Multiversion("avx2,fma", "sse4.2")>]` | one version per feature set and one for the baseline; the first call selects by the running CPU |

The intrinsics of `Simd.X86` and `Simd.Arm` are available only on their architecture. One
that needs a feature beyond the target's baseline is an error unless the build's CPU or the
enclosing function's `[<Target>]` or `[<Multiversion>]` provides it.
