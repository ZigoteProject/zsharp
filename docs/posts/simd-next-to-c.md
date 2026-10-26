# SIMD next to C: one source for AVX and NEON

Z# has vector types the way it has `int`: `f32x8` is eight `f32`s in one value, with `+`, `*`,
comparisons that give masks, shuffles and loads, and the compiler gives it to LLVM as a
`<8 x float>`. The same source is one AVX register on x86-64 and two NEON registers on an Arm
core. The question for phase 8 was whether that's as fast as C written with each architecture's
intrinsics.

## A dot product

```fsharp
let dot (a: array<f32>) (b: array<f32>) : f32 =
  let n = Array.length a
  let mutable acc0 = F32x8.splat (f32 0.0)
  let mutable acc1 = F32x8.splat (f32 0.0)
  let mutable i = 0
  // two accumulators, so consecutive multiply-adds don't wait for each other
  while i + 16 <= n do
    acc0 <- F32x8.mulAdd (F32x8.load a i) (F32x8.load b i) acc0
    acc1 <- F32x8.mulAdd (F32x8.load a (i + 8)) (F32x8.load b (i + 8)) acc1
    i <- i + 16
  let mutable total = F32x8.sum (acc0 + acc1)
  while i < n do
    total <- total + a.[i] * b.[i]
    i <- i + 1
  total
```

The C it's measured against has two versions, one with `_mm256_fmadd_ps` and one with
`vfmaq_f32`. The Z# has one: `F32x8.mulAdd` is LLVM's `fma` on whatever the target has. And
`F32x8.load a i` is bounds-checked, as any array access is; in a `for` loop, loop versioning
proves the checks once per loop instead of once per load.

## The numbers

Phase 8's exit test, best of 3 runs, the C built with `-O2` and the same target flags
(x86-64-v3: AVX2 and FMA), the aarch64 builds cross-compiled from the same sources and run under
qemu-user:

| | dot | nbody | blur |
|---|---:|---:|---:|
| x86-64, Z# / C | 65 / 63 ms (1.03) | 83 / 82 ms (1.01) | 77 / 74 ms (1.04) |
| aarch64, Z# / C | 6062 / 6132 ms (0.99) | 14662 / 14722 ms (1.00) | 3266 / 3135 ms (1.04) |

Within 4% of the intrinsics everywhere, from one source per program.

## What else is there

- **Every width:** every number type at 128, 256 and 512 bits (`f32x4` … `u64x8`) and masks,
  with `select`, `shuffle` (constant indices, checked when compiling), conversions, `sqrt`,
  `floor`, `round` and the reductions.
- **`[<FastMath>]`** on a function lets LLVM reassociate its float arithmetic, so plain loops
  with reductions vectorize too.
- **Choosing the CPU:** `--cpu` for the whole program; `[<Target "avx2,fma">]` for one function;
  `[<Multiversion("avx2,fma", "sse4.2")>]` builds a version for each and the baseline, and picks
  one at the first call by asking the CPU.
- **Intrinsics when you need one:** `Simd.X86` (`pshufb`, `pmaddwd`, `movemask`, …) and
  `Simd.Arm` (`tbl`, `sdot`, …). One the build's CPU doesn't have is a compile error naming it.
- **On a microcontroller,** the same types compile lane by lane, with the DSP instructions the
  chip has.

## How this could mislead

- **aarch64 is emulated.** qemu-user's times aren't a real Arm core's; the ratio between two
  programs it runs is the meaningful number.
- **Three kernels.** They're the ones written for phase 8's test: a reduction, an n-body step and
  a 2D stencil. Code that leans on shuffles or gathers hasn't been compared.
- **Laptop timings** (an AMD Ryzen 7 PRO 8840U) move by a few percent between runs.

Reproduce: `./dev bench/simd/run.sh`. The design is [DESIGN.md §8](../../DESIGN.md#8-simd), and
the guide's [SIMD chapter](../guide/15-simd.md) teaches it.
