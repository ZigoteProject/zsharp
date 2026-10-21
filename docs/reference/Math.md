# Math

Arithmetic beyond the operators.

## Functions

### `Math.abs`

```zsharp
Math.abs : 'a -> 'a when 'a : Add, 'a : Num, 'a : Ord
```

The absolute value: `x` without its sign (named apart from C's `abs`, which programs often
import). For integers, the most negative value has none, so it overflows (and panics).

### `Math.sqrt`

```zsharp
Math.sqrt : 'a -> 'a
```

The square root of an `f64` or `f32` (NaN for a negative number): one instruction where the hardware has it.

