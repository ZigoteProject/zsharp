# Simd.Arm

aarch64's SIMD intrinsics (NEON): instructions the portable vectors don't name. An
extension's (`dotBytes16`, dotprod) needs `--cpu` or `[<Target>]`. Its functions are built
into the compiler.

## Functions

### `Simd.Arm.dotBytes16`

```zsharp
Simd.Arm.dotBytes16 : i32x4 -> i8x16 -> i8x16 -> i32x4
```

`acc` plus, per i32 lane, the dot product of 4 i8s of `a` and of `b` (the dotprod extension's sdot).

### `Simd.Arm.pairwiseAdd4`

```zsharp
Simd.Arm.pairwiseAdd4 : f32x4 -> f32x4 -> f32x4
```

Pairs added: a0+a1, a2+a3, b0+b1, b2+b3 (NEON's faddp).

### `Simd.Arm.recipEstimate4`

```zsharp
Simd.Arm.recipEstimate4 : f32x4 -> f32x4
```

An estimate of 1 / x per lane, to 8 bits (NEON's frecpe).

### `Simd.Arm.rsqrtEstimate4`

```zsharp
Simd.Arm.rsqrtEstimate4 : f32x4 -> f32x4
```

An estimate of 1 / sqrt x per lane, to 8 bits (NEON's frsqrte).

### `Simd.Arm.tableLookup16`

```zsharp
Simd.Arm.tableLookup16 : i8x16 -> i8x16 -> i8x16
```

The bytes of `a` the indices in `b` pick; an index past 15 gives 0 (NEON's tbl).

