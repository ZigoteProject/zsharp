# 15. SIMD

## Vectors

A SIMD vector holds a few numbers that one instruction works on at once. `f32x8` is 8 `f32`s
(256 bits), `u8x16` 16 bytes (128 bits), and every number type has one at 128, 256 and 512 bits.
A CPU without 256-bit vectors does a `f32x8`'s work as two 128-bit halves, and one without SIMD
lane by lane, so the same code runs everywhere.
- **Arithmetic:** `+ - * / %` work lane by lane. Integer vectors wrap around on overflow, as SIMD instructions do (integer division still panics on a zero lane).
- **Bits:** `&&& ||| ^^^` on integer vectors, and `<<<` and `>>>` by an `int` for every lane.
- **Functions:** each type's are in a module named after it (`F32x8.splat`, `I32x4.load`): `splat` and `init` make one, `load` and `store` move lanes from and into an array of its numbers, `get` and `set` a lane, and `sum`, `reduceMin` and `reduceMax` combine the lanes.

```zsharp
let main () =
  let a = F32x4.init (fun i -> f32 (i + 1))
  let b = F32x4.splat (f32 10.0)
  println $"{a + b} {a * b} {F32x4.sum a}"
  let squares = F32x4.load [| f32 1.0; f32 4.0; f32 9.0; f32 16.0 |] 0
  println $"{F32x4.sqrt squares}"
  0
```

```text
<11, 12, 13, 14> <10, 20, 30, 40> 10
<1, 2, 3, 4>
```

A loop over an array takes 8 elements at a time, and the rest one at a time. Here two
accumulators let one multiply-add start before the last has finished:

```zsharp
let dot (a: array<f32>) (b: array<f32>) : f32 =
  let n = Array.length a
  let mutable acc = F32x8.splat (f32 0.0)
  let mutable i = 0
  while i + 8 <= n do
    acc <- F32x8.mulAdd (F32x8.load a i) (F32x8.load b i) acc
    i <- i + 8
  let mutable total = F32x8.sum acc
  while i < n do
    total <- total + a.[i] * b.[i]
    i <- i + 1
  total

let main () =
  let a = Array.init 20 (fun i -> f32 i)
  println $"{dot a a}"
  0
```

```text
2470
```

**Bounds:** `load` and `store` check that every lane is in the array. In a `for` loop over an
index (`for x in 0 .. 8 .. last`), loads at the index plus or minus values the loop doesn't
change are checked once, before the loop.

## Masks

Comparing two vectors lane by lane gives a mask: `mask4` for 4 lanes. `select` takes each lane
from one vector or the other, and `any`, `all` and `count` say how many lanes are true.

```zsharp
let main () =
  let v = I32x8.init (fun i -> i32 (i * 3 - 7))
  let positive = I32x8.greaterThan v (I32x8.splat (i32 0))
  println $"{v}"
  println $"{Mask8.count positive} positive; clamped {I32x8.select positive v (I32x8.splat (i32 0))}"
  println $"{I32x8.shuffle v v [| 7; 6; 5; 4; 3; 2; 1; 0 |]}"
  0
```

```text
<-7, -4, -1, 2, 5, 8, 11, 14>
5 positive; clamped <0, 0, 0, 2, 5, 8, 11, 14>
<14, 11, 8, 5, 2, -1, -4, -7>
```

`shuffle a b indices` picks lanes by index, 0 up from `a`'s and then on from `b`'s. The indices
are an array literal of constants, since the instruction takes them so.

## Floats, CPUs and intrinsics

**`[<FastMath>]`:** floats follow IEEE 754 exactly by default, so a loop summing floats adds
them in order, which LLVM can't vectorize. A function marked `[<FastMath>]` lets LLVM reorder its
float arithmetic and assume it meets no NaN or infinity, so such a loop vectorizes.

**CPUs:** a build is for the target's baseline: on x86-64 that's SSE2, so a `f32x8` takes two
instructions. `--cpu` names the processor to compile for:
- `--cpu x86-64-v3` (AVX2 and FMA, most x86-64 CPUs since 2015), or `--cpu native` for the machine building it.
- `[<Target "avx2,fma">]` compiles one function for those features. Calling it on a CPU without them crashes.
- `[<Multiversion("avx2,fma", "sse4.2")>]` compiles a version for each, and one for the baseline. The first call picks the first version the CPU has.

**Intrinsics:** `Simd.X86` and `Simd.Arm` have instructions the portable vectors don't name,
such as `Simd.X86.rsqrt8` (an estimate of `1 / sqrt x`) or `Simd.Arm.tableLookup16`. Each is for
its architecture only. One that needs a CPU feature beyond the baseline is a compile error
without `--cpu`, `[<Target>]` or `[<Multiversion>]`:

```fsharp
let main () =
  let v = F32x4.splat (f32 1.0)
  println $"{Simd.X86.hadd4 v v}"
  // error: Simd.X86.hadd4 needs the CPU feature sse3: build with --cpu (x86-64-v3, say),
  // or mark the function [<Target "sse3">] (or [<Multiversion>])
```

**Speed:** on the phase 8 benchmarks (`bench/simd`: a dot product, n-body and a blur), Z#'s
vectors run within 10% of C with AVX or NEON intrinsics, from one source on x86-64 and on
aarch64.
