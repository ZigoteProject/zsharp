# Proposal 0015: fixed-point numbers: `q7`, `q15` and `q31`

| | |
|---|---|
| **Status** | Approved in principle as a Core library (decision 66 is its one language change), after phase 11 |
| **Decided at** | the third design review ([ROADMAP](../../ROADMAP.md#third-design-review-)): it passes decision 39 (it replaces hand-written shifts, rounding and saturation, and needs no runtime), and nothing in the language but untagged one-case unions |
| **Builds** | track M item 10 ([ROADMAP](../../ROADMAP.md#microcontrollers-m)), after phase 11 |
| **Rests on** | decisions 4 (overflow traps; wrapping is explicit), 25 (the SIMD API) and 53 (no type-level numbers beyond `fixed`) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §8](../../DESIGN.md#8-simd) |
| **Related** | [0024 library API](0024-library-api.md) (`Int.saturatingAdd/Sub/Mul`), [0004 C layout](0004-c-layout.md) (why no `fix<i, f>`), [0013 bit fields](0013-bit-fields.md), [0014 placement](0014-placement.md) (coefficient tables in flash), [0012 interrupts, `[<NoAlloc>]` and intrinsics](0012-interrupts-noalloc-intrinsics.md) (filters in handlers) |

- [x] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

Three fixed-point number types in Core, the formats CMSIS-DSP and the Cortex-M's saturating instructions use: `q7` (an `i8` with 7 fraction bits), `q15` (an `i16`, 15) and `q31` (an `i32`, 31), each a value in [-1, 1). They are library types, one-case unions over the integer with `Add`, `Num`, `Eq`, `Ord`, `Hash` and `Show`, so `a * x + b` reads as arithmetic and saturates instead of trapping or wrapping. The operations compile to the chips' instructions where they exist (the M4's DSP extension) and to a few integer instructions where they don't (the M0+), on top of [0024](0024-library-api.md)'s `Int.saturatingAdd`, `Sub` and `Mul`. No new syntax, no literal form, no type-level numbers.

```fsharp
let a = Q15.ofFloat 0.25            // 8192, folded at compile time
let b = Q15.ofFloat 0.75

let lowPass (xs: span<q15>) =
  let mutable y = Q15.zero
  for x in xs do
    y <- a * x + b * y                // saturating; no allocation
  y
```

## Motivation

**DSP without an FPU.** A Cortex-M0+ has no floating-point unit; an `f32` multiply is a library call of tens of instructions. Filters, control loops and audio on such chips run in fixed point: a sample is an `i16` meaning `n / 32768`, a product is shifted back by 15 bits, and a sum that leaves the range sticks at the end instead of wrapping, because a clipped sample is a small error and an inverted one is a loud one. The M4's DSP extension has instructions for exactly this (`QADD16`, `QSUB16`, `SMLABB`, `SSAT`), and CMSIS-DSP's whole API is in `q7_t`, `q15_t` and `q31_t`.

**By hand, in Z# today:** `i16` arithmetic traps on overflow (decision 4), `Int.wrappingAdd` wraps, and neither saturates; the shift, the rounding and the saturation are written at every multiply and wrong at the edges (`-1 * -1` overflows an `i16` by one); and an `i16` that means 0.5 looks like 16384, so nothing stops adding a sample to a count. With the types, the scale is in the type, the operators do the right thing, and the compiler emits the instructions.

**Without the feature:** `[<Wrapping>]` functions with hand-written shifts and clamps, or a C file calling CMSIS-DSP through `import c`, which works and keeps the kernel out of Z#.

## Detailed design

### The types

```fsharp
type q7 = Q7 of i8        // n / 128,        step 2^-7
type q15 = Q15 of i16     // n / 32768,      step 2^-15
type q31 = Q31 of i32     // n / 2147483648, step 2^-31
```

- **In Core** (`lib/core/Q7.zs`, `Q15.zs`, `Q31.zs`), so every target has them; a module per type holds the functions, as `Int` does.
- **Representation: a one-case union has no tag.** A plain union is `{ tag, fields }` today (`llty`, src/Codegen.fs ~552 in the main tree), which would make a `q15` eight bytes. The rule becomes: a union with one case is its fields alone, so `q15` is an `i16` in registers, arrays, records and C structs (`int16_t`, CMSIS's `q15_t`, through [0004](0004-c-layout.md)'s layouts), and every newtype (`type UserId = UserId of int`) gains the same. It's a small extension of decision 8: a new decision row, numbered by the coordinator.
- **Plain values:** no allocation anywhere, so a filter over a `span<q15>` is `[<NoAlloc>]` and may run in an interrupt handler ([0012](0012-interrupts-noalloc-intrinsics.md)).
- **Derived:** `Eq`, `Ord` and `Hash` come from the automatic derives over the integer (decision 10), and the integer's order is the value's. `Show` is written by hand and replaces the derived one, as `tests/traits.zs`'s `impl Show<Vec>` does for a record.
- **No implicit conversions,** as between `int` and `f64`: `q15 + i16` is a type error; `Q15.ofRaw` and `Q15.raw` cross.

### Arithmetic

Every operation saturates: a result past the range is the nearest end, `Q15.max` (1 − 2^-15) or `Q15.min` (-1). A product is rounded half up (half a step added, then an arithmetic shift), which is what the chips' rounding multiplies do. The table is `q15`'s; `q7` and `q31` are the same with 16- and 64-bit intermediates.

| Operation | Computed as | On the M4 (DSP extension) | On the M0+ |
|---|---|---|---|
| `a + b`, `a - b` | `Int.saturatingAdd`/`Sub` on the raws (LLVM `llvm.sadd.sat.i16`, which the ARM backend lowers to the DSP instruction) | `QADD16`/`QSUB16`, one instruction | a 32-bit add and a clamp, about six (estimate) |
| `a * b` | `sat16 ((i32 a * i32 b + 0x4000) >>> 15)` | `SMULBB`, an add, `SSAT`: three | `MULS`, shifts and a clamp, about eight (estimate) |
| `Q15.mulAdd a b c` (`a * b + c`, one rounding) | `sat16 ((i32 a * i32 b + (i32 c <<< 15) + 0x4000) >>> 15)` | `SMLABB`, `SSAT` | the multiply plus an add |
| `a / b` | `sat16 ((i32 a <<< 15) / i32 b)`; by zero panics (decision 4) | `SDIV`, `SSAT` | a runtime division (no divider) |
| `a % b` | the raws' remainder (exact: both sides have the same scale) | | |
| `-a` | `Int.saturatingSub 0 a`, so `-Q15.min = Q15.max` | | |

- **Why the rounding is written out:** LLVM has `llvm.smul.fix.sat` and `llvm.sdiv.fix.sat` with a scale argument, but their rounding direction is unspecified; Z# emits the add and the shift so a result is the same on every target, and LLVM matches the pattern to the instructions above where they exist.
- **`q31`'s product** needs a 64-bit intermediate: `SMULL` and shifts on the M4; on the M0+, whose multiplier is 32×32→32, a runtime routine of some twenty instructions (estimate), the cost CMSIS-DSP pays there too (*Unresolved questions*).
- **`Add.zero`** is `Q15.zero`, so `List.sum` and `Array.sum` over `q15` saturate like the operator.

### Conversions, constants and printing

| Function | Type | Meaning |
|---|---|---|
| `Q15.ofFloat` | `f64 -> q15` | the nearest value, saturating; folded at compile time on a literal, as the number conversions are, so a coefficient table is a constant and lives in flash ([0014](0014-placement.md)) |
| `Q15.toFloat`, `Q15.toF32` | `q15 -> f64`, `q15 -> f32` | exact (an `i16` fits either mantissa); `Q31.toF32` rounds |
| `Q15.ofInt` | `int -> q15` | saturating: `-1`, `0`, and `Q15.max` for anything above |
| `Q15.ofRaw`, `Q15.raw` | `i16 -> q15`, `q15 -> i16` | the integer underneath, for tables written in raw form and for C |
| `Q15.ofQ7`, `Q15.ofQ31`, `Q15.toQ7`, `Q15.toQ31` | between formats | a shift; narrowing rounds and saturates |
| `Q15.zero`, `Q15.min`, `Q15.max`, `Q15.step` | `q15` | 0, -1, 1 − 2^-15, 2^-15 |
| `Q15.mulAdd`, `Q15.abs`, `Q15.clamp` | | as the table above; `Q15.abs Q15.min = Q15.max` |

- **No literal form.** `0.5q15` would be new syntax (decision 34) for what `Q15.ofFloat 0.5` says at no run-time cost.
- **`Show`** prints the decimal with as many digits as the format needs to tell neighbours apart and to round-trip through `Q15.ofFloat (Float.parse s)`: three for `q7`, five for `q15`, ten for `q31`: `0.25000`, `-1.00000`, `0.99997`. It's integer arithmetic, a digit at a time, so printing costs no float on the M0+. `Q15.raw` is there for the integer.

### SIMD

Decision 49 keeps vector functions in a module per vector type, so the integer vector modules gain the saturating forms, and a `q15` buffer is loaded as its raw integers:

- **`I16x8.saturatingAdd`, `saturatingSub`** (and the same at every integer vector type): LLVM `llvm.sadd.sat.v8i16`, one instruction on NEON (`sqadd`) and SSE2 (`paddsw`).
- **`I16x8.mulQ15`:** `(a * b + 0x4000) >>> 15` per lane, saturated: NEON's `sqrdmulh` exactly; SSSE3's `pmulhrsw` with a fix-up for a `-1 * -1` lane (estimate: one compare and select per vector). `I8x16.mulQ7` and `I32x4.mulQ31` likewise (NEON has both; x86 has neither, and LLVM scalarizes).
- **Loading:** `q15` and `i16` share a representation, so `Q15.raws : array<q15> -> array<i16>` and `Q15.ofRaws` are builtins that emit nothing; `I16x8.load (Q15.raws xs) i` loads eight samples. The same over spans ([0003](0003-spans-and-slices.md)).
- **On the chips** there is no vector unit: LLVM scalarizes to the DSP instructions (`QADD16` adds two lanes at once). Vectors matter for the same kernel's tests on the host and for an aarch64 board.

### Why not `fix<i, f>`

A general format needs numbers as type arguments beyond `fixed`'s size, where decision 53 draws the line ([0004](0004-c-layout.md)): a product of `fix<2, 14>` and `fix<4, 12>` is a `fix<6, 26>`, so multiplication needs type-level arithmetic or a scale at every call. No hardware has instructions for those formats; the DSP extensions and CMSIS-DSP have `q7`, `q15` and `q31`, and three named types cover that API. A program with another format (a 16.16 for a coordinate system) writes it as a one-case union over `i32` with the same impls in a page, which the representation rule makes free.

### Order of implementation

1. **One-case unions without a tag:** `llty` and `plainField` (src/Codegen.fs ~552 and ~582 in the main tree), with the derives and debug info following. Test: an `array<q15>` of 1,024 elements has a heap peak of 2 KB plus headers under QEMU, and `sizeof<q15>` is 2 once [0004](0004-c-layout.md)'s `sizeof` exists.
2. **`Int.saturatingAdd/Sub/Mul`** at every width: [0024](0024-library-api.md) owns them; they're the dependency.
3. **The types and impls** in `lib/core/Q7.zs`, `Q15.zs` and `Q31.zs`, with `///` docs and reference pages; `tests/fixedpoint.zs` runs the same cases at each format: `-1 * -1 = max`, `min - step = min`, `-min = max`, a tie's rounding, `Show`'s round trip, and a `.out` test with the division-by-zero panic.
4. **Folding `ofFloat` on literals,** the `raws` builtins, and the vector functions.
5. **The exit test:** `bench/mcu/fir.zs` in `q15` on the `cortex-m0plus` against a C version in CMSIS-DSP's style, within track M's ratios; a `q15` filter marked `[<NoAlloc>]` compiles.

## Drawbacks

- **Saturation hides mistakes:** a filter whose gain is too high clips silently where `int` would trap. That's the semantics DSP wants and the one the instructions have; `Show` and the tests make it visible. Nothing here changes `int`.
- **Three types, three modules,** with the same functions each: what three sizes of a format cost in a language without type-level numbers. One test runs every case at each format, so they can't drift.
- **`q31` products are slow on the M0+,** as they are in C there.
- **A representation change** for one-case unions touches every program with a newtype: no source changes, and a step of its own with its own test, but a change under everything.

## Alternatives

- **Units of measure on integers** (`i16<q15>`): units are erased and don't change `+`'s meaning, which would still trap, and `x * y` would be an `i16<q15 q15>`, a type with no use. Not chosen.
- **A record** `{ raw: i16 }`: has the two-byte layout today without the representation rule, and reads as `x.raw` everywhere; the one-case union is F#'s newtype idiom, and the rule helps every newtype. Not chosen.
- **A general `fix<i, f>`:** above; decision 53. Not chosen.
- **Wrapping arithmetic** with explicit `Q15.saturate` calls afterwards: the wrapped intermediate is already wrong; every DSP library saturates at the operation. Not chosen.
- **Calling CMSIS-DSP through `import c`:** works for whole kernels today and stays available (a `span<q15>` is an `int16_t *` and a length); it doesn't give a Z# expression `a * x + b`. Not chosen as the design, kept as the interop.
- **A literal suffix** (`0.5q15`, as C's `0.5f`): new syntax under decision 34 for what a folded conversion gives. Not chosen.
- **Doing nothing:** `[<Wrapping>]` and shifts by hand. `bench/mcu`'s `fir` avoids the question by using `f32` on the M4F; the M0+ has no such out.

## Compatibility

- **Not a breaking change:** new library types and modules under Core's names, which a program's own `q15` shadows (decision 37's precedence). The one-case union rule changes no program's meaning, only its layout, which only C sees ([0004](0004-c-layout.md)): a one-case union field in a `[<CLayout>]` record was a struct with a tag and becomes the field, a change to make before anyone depends on the old layout.
- **An older compiler** doesn't have the modules: `Q15` is an unknown name, the ordinary error.
- **Compiled binaries:** none to consider; packages are source (decision 27).
- **The library:** three modules in Core, each with docs, a reference page, a test and a Cortex-M0+ build, track S's rule for every addition.
- **Microcontrollers:** the point; `Int.saturating*` lowers to the DSP instructions on the M4 and to integer code on the M0+.
- **C:** `q15` crosses as `int16_t`, `array<q15>` and `span<q15>` as `int16_t *` and a length, so CMSIS-DSP's functions are callable.

## Pragmatics

### Diagnostics

Nothing special: saturation is documented, not an error. The ordinary ones apply:

| Situation | Error |
|---|---|
| mixing a `q15` and an integer | `right operand of '+': expected q15, got i16` (the usual mismatch; `Q15.ofRaw` converts) |
| `Q15.ofFloat 2.0` | no error: saturates to `Q15.max`; a warning for an out-of-range literal is [0021](0021-warnings.md)'s to name once warnings exist |
| `a / Q15.zero` | at run time, `panic: division by zero`, as for integers (decision 4) |
| `Q15.min * Q15.min` | no error: `Q15.max` |

### Tooling

- **`zs lsp`:** hover shows `y : q15` and the `Q15` functions' `///` docs; completion after `Q15.` lists them; inlay hints show `q15` on bindings; definition opens `lib/core/Q15.zs`. All from the checker, with no build run.
- **The tree-sitter grammar** gains nothing: `q15` is a type name and `Q15` a module.
- **`zs doc`:** three reference pages, `Q7.md`, `Q15.md` and `Q31.md`, next to [`Int.md`](../reference/Int.md).
- **gdb** ([0011](0011-debug-info-profiles-traces.md)): a one-case union shows as its field under the type's name; a pretty-printer for the decimal is a line in 0011's script.

### Performance

- **Per operation,** the table above: on the M4 one instruction for `+` and `-` and three for `*`; on the M0+ about six and eight (estimates). The exit test measures `fir` in `q15` against C.
- **Nothing hidden:** no allocation, no calls, no checks beyond the array's bounds; `[<FastMath>]` and `[<Wrapping>]` change nothing here, since the saturation is in the impls.
- **Constants:** `Q15.ofFloat 0.1` on a literal is the integer at compile time; a table of them is in flash ([0014](0014-placement.md)).
- **Vectors:** one instruction per eight lanes for `+`, `-` and `mulQ15` on NEON; the same on SSSE3 plus the fix-up.

### Scaling

| Dimension | Typical | Upper bound |
|---|---|---|
| samples in a buffer | 256–4,096 | the heap ([0014](0014-placement.md)); spans don't copy |
| filter taps | 32 | 1,024 |
| formats | 3 | 3 (another is a user type in a page) |
| vector width | 8 lanes (`i16x8`) | 32 (`i16x32`) |

### Culture-aware formatting and parsing

- **Invariant.** `Show` prints `.` as the decimal point and no grouping, as `Show` does for `f64`; `Float.parse` ([0024](0024-library-api.md)) reads the same form back, so the round trip holds in every locale.

## Unresolved questions

1. **Rounding of products.** Chosen: half up (half a step added, then the shift), what `sqrdmulh`, `pmulhrsw` and the M4's rounding multiplies do; the alternative, half to even, has no instruction and costs a compare per multiply. CMSIS-DSP truncates in some functions (`arm_mult_q15`), so results differ from it in the last bit.
2. **`q31` on the M0+.** Chosen: a 64-bit intermediate through the runtime's multiply, correct and slow; the alternative, three 16×16 partial products in Z#, is faster and a page of code to get right.
3. **`Show`.** Chosen: the decimal with a fixed count of digits; the alternative prints the raw integer (`Q15 8192`), which the derived `Show` would give and which `Q15.raw` keeps available.
4. **Accumulators.** A dot product over a thousand `q15` samples saturates early at `q15`; CMSIS-DSP accumulates in `q63`. Chosen: nothing beyond `mulAdd` now; the alternative adds `Q15.dot : span<q15> -> span<q15> -> q31` with a wide accumulator when a kernel needs it.

## History

- **2026-10-22:** drafted from track M item 10 (ROADMAP) and decision 53's note on type-level numbers.
