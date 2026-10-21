# Math

Arithmetic beyond the operators.

## Functions

### `Math.abs`

```zsharp
Math.abs : 'a -> 'a when 'a : Add, 'a : Num, 'a : Ord
```

The absolute value: `x` without its sign (named apart from C's `abs`, which programs often
import). For integers, the most negative value has none, so it overflows (and panics).

