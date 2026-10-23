# Float

Floating-point numbers.

## Functions

### `Float.parse`

```zsharp
Float.parse : string -> option<'a>
```

The number `s` writes: an optional sign, digits with an optional `.` and fraction, an
optional exponent (`1.5e-3`), or `inf` and `nan`; nothing else (no spaces, no `1,5`). The
type is the result's (`f32` or `f64`, `f64` when nothing else says).

### `Float.ofBits`

```zsharp
Float.ofBits : u64 -> f64
```

The number whose IEEE 754 bits these are (`Float.toBits` gives them).

### `Float.toBits`

```zsharp
Float.toBits : f64 -> u64
```

The number's 64 bits, as IEEE 754 lays them out (`Float.ofBits` gives it back).

