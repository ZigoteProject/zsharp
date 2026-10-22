# Simd.X86

x86-64's SIMD intrinsics: instructions the portable vectors don't name. Each needs its CPU
feature (SSE2's every x86-64 has): build with `--cpu`, or mark the function `[<Target>]` or
`[<Multiversion>]`. Its functions are built into the compiler.

## Functions

### `Simd.X86.hadd4`

```zsharp
Simd.X86.hadd4 : f32x4 -> f32x4 -> f32x4
```

Pairs added: a0+a1, a2+a3, b0+b1, b2+b3 (SSE3's haddps).

### `Simd.X86.hadd8`

```zsharp
Simd.X86.hadd8 : f32x8 -> f32x8 -> f32x8
```

Pairs added within each 128-bit half (AVX's vhaddps).

### `Simd.X86.maddPairs16`

```zsharp
Simd.X86.maddPairs16 : i16x16 -> i16x16 -> i32x8
```

pmaddwd over 256 bits (AVX2's vpmaddwd).

### `Simd.X86.maddPairs8`

```zsharp
Simd.X86.maddPairs8 : i16x8 -> i16x8 -> i32x4
```

The products of the i16 lanes, adjacent pairs added into i32s (SSE2's pmaddwd).

### `Simd.X86.movemask4`

```zsharp
Simd.X86.movemask4 : f32x4 -> i32
```

The lanes' sign bits as the low bits of an i32 (SSE's movmskps).

### `Simd.X86.movemask8`

```zsharp
Simd.X86.movemask8 : f32x8 -> i32
```

The lanes' sign bits as the low bits of an i32 (AVX's vmovmskps).

### `Simd.X86.movemaskBytes16`

```zsharp
Simd.X86.movemaskBytes16 : i8x16 -> i32
```

The bytes' top bits as the low bits of an i32 (SSE2's pmovmskb).

### `Simd.X86.movemaskBytes32`

```zsharp
Simd.X86.movemaskBytes32 : i8x32 -> i32
```

The bytes' top bits as an i32 (AVX2's vpmovmskb).

### `Simd.X86.rcp4`

```zsharp
Simd.X86.rcp4 : f32x4 -> f32x4
```

An estimate of 1 / x per lane, to within 1.5 × 2^-12 (SSE's rcpps).

### `Simd.X86.rcp8`

```zsharp
Simd.X86.rcp8 : f32x8 -> f32x8
```

An estimate of 1 / x per lane, to within 1.5 × 2^-12 (AVX's vrcpps).

### `Simd.X86.rsqrt4`

```zsharp
Simd.X86.rsqrt4 : f32x4 -> f32x4
```

An estimate of 1 / sqrt x per lane, to within 1.5 × 2^-12 (SSE's rsqrtps).

### `Simd.X86.rsqrt8`

```zsharp
Simd.X86.rsqrt8 : f32x8 -> f32x8
```

An estimate of 1 / sqrt x per lane, to within 1.5 × 2^-12 (AVX's vrsqrtps).

### `Simd.X86.sadBytes16`

```zsharp
Simd.X86.sadBytes16 : u8x16 -> u8x16 -> u64x2
```

The sums of absolute differences of each 8 bytes, as u64s (SSE2's psadbw).

### `Simd.X86.sadBytes32`

```zsharp
Simd.X86.sadBytes32 : u8x32 -> u8x32 -> u64x4
```

psadbw over 256 bits (AVX2's vpsadbw).

### `Simd.X86.shuffleBytes16`

```zsharp
Simd.X86.shuffleBytes16 : i8x16 -> i8x16 -> i8x16
```

The bytes of `a` the indices in `b` pick; an index with its top bit set gives 0 (SSSE3's pshufb).

### `Simd.X86.shuffleBytes32`

```zsharp
Simd.X86.shuffleBytes32 : i8x32 -> i8x32 -> i8x32
```

pshufb within each 128-bit half (AVX2's vpshufb).

