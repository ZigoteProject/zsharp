# Math

Arithmetic beyond the operators. Besides these, built into the compiler for `f64` and `f32`:
`sqrt`, `floor`, `ceil`, `round` (half to even, as F#'s), `trunc`, `exp`, `log` (natural),
`log2`, `log10`, `sin`, `cos`, `tan`, `pow` and `atan2`: an instruction where the target has
one, else libm's function.

## Functions

### `Math.abs`

```zsharp
Math.abs : 'a -> 'a when 'a : Add, 'a : Num, 'a : Ord
```

The absolute value: `x` without its sign (named apart from C's `abs`, which programs often
import). For integers, the most negative value has none, so it overflows (and panics).

### `Math.clamp`

```zsharp
Math.clamp : 'a -> 'a -> 'a -> 'a when 'a : Ord
```

`x` kept within `low` and `high`: `low` when it's below, `high` when it's above.

### `Math.pi`

```zsharp
let pi
```

π, as an `f64` or an `f32`, whichever the use needs.

### `Math.e`

```zsharp
let e
```

e, the base of natural logarithms, as an `f64` or an `f32`.

### `Math.atan2`

```zsharp
Math.atan2 : 'a -> 'a -> 'a
```

The angle of the point (`x`, `y`) from the x axis, in radians from -π to π: `atan2 y x`, y first, as C's.

### `Math.ceil`

```zsharp
Math.ceil : 'a -> 'a
```

The smallest whole number not below `x`, as an `f64` or `f32`.

### `Math.cos`

```zsharp
Math.cos : 'a -> 'a
```

The cosine of an angle in radians.

### `Math.exp`

```zsharp
Math.exp : 'a -> 'a
```

e to the power `x`.

### `Math.floor`

```zsharp
Math.floor : 'a -> 'a
```

The largest whole number not above `x`, as an `f64` or `f32`.

### `Math.log`

```zsharp
Math.log : 'a -> 'a
```

The natural logarithm (NaN below zero, minus infinity at zero).

### `Math.log10`

```zsharp
Math.log10 : 'a -> 'a
```

The base-10 logarithm.

### `Math.log2`

```zsharp
Math.log2 : 'a -> 'a
```

The base-2 logarithm.

### `Math.pow`

```zsharp
Math.pow : 'a -> 'a -> 'a
```

`x` to the power `y`: `pow 2.0 10.0` is 1024.

### `Math.round`

```zsharp
Math.round : 'a -> 'a
```

The nearest whole number, halves to the even one (`round 2.5` is 2), as F#'s `round`.

### `Math.sin`

```zsharp
Math.sin : 'a -> 'a
```

The sine of an angle in radians.

### `Math.sqrt`

```zsharp
Math.sqrt : 'a -> 'a
```

The square root of an `f64` or `f32` (NaN for a negative number): one instruction where the hardware has it.

### `Math.tan`

```zsharp
Math.tan : 'a -> 'a
```

The tangent of an angle in radians.

### `Math.trunc`

```zsharp
Math.trunc : 'a -> 'a
```

`x` without its fraction: toward zero.

