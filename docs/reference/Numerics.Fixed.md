# Numerics.Fixed

Fixed-point numbers (0015): `q7`, `q15` and `q31`, the formats CMSIS-DSP and the chips'
saturating instructions use, each a number in [-1, 1) as a signed integer over 2^7, 2^15 or
2^31. Every operation saturates (a result past the range is the nearest end), and a product
is rounded half up, as the chips' rounding multiplies do; `Show` prints the decimal with as
many digits as the format needs to tell neighbours apart. A format is a one-case union, so it
is its integer's size (decision 66) and allocates nothing.

## Types

### `q7`

```zsharp
type q7
```

A number in [-1, 1) as an `i8` over 128: a step of 2^-7 (CMSIS's `q7_t`).

#### `Q7`

```zsharp
| Q7 of i8
```

The integer underneath: the value times 128.

### `q15`

```zsharp
type q15
```

A number in [-1, 1) as an `i16` over 32768: a step of 2^-15 (CMSIS's `q15_t`).

#### `Q15`

```zsharp
| Q15 of i16
```

The integer underneath: the value times 32768.

### `q31`

```zsharp
type q31
```

A number in [-1, 1) as an `i32` over 2147483648: a step of 2^-31 (CMSIS's `q31_t`).

#### `Q31`

```zsharp
| Q31 of i32
```

The integer underneath: the value times 2^31.

## Derives and impls

### `impl Add<q7>`

```zsharp
impl Add<q7>
```

`+` and `Add.zero` on `q7`, saturating.

### `impl Num<q7>`

```zsharp
impl Num<q7>
```

`-`, `*`, `/`, `%` and negation on `q7`, saturating.

### `impl Show<q7>`

```zsharp
impl Show<q7>
```

A `q7` prints as its decimal (`Q7.show`).

### `impl Add<q15>`

```zsharp
impl Add<q15>
```

`+` and `Add.zero` on `q15`, saturating.

### `impl Num<q15>`

```zsharp
impl Num<q15>
```

`-`, `*`, `/`, `%` and negation on `q15`, saturating.

### `impl Show<q15>`

```zsharp
impl Show<q15>
```

A `q15` prints as its decimal (`Q15.show`).

### `impl Add<q31>`

```zsharp
impl Add<q31>
```

`+` and `Add.zero` on `q31`, saturating.

### `impl Num<q31>`

```zsharp
impl Num<q31>
```

`-`, `*`, `/`, `%` and negation on `q31`, saturating.

### `impl Show<q31>`

```zsharp
impl Show<q31>
```

A `q31` prints as its decimal (`Q31.show`).

## Functions

### `Q7.zero`

```zsharp
let zero
```

0.

### `Q7.min`

```zsharp
let min
```

-1, the least value.

### `Q7.max`

```zsharp
let max
```

1 − 2^-7, the greatest value.

### `Q7.step`

```zsharp
let step
```

2^-7, one step.

### `Q7.raw`

```zsharp
Q7.raw : q7 -> i8
```

The integer underneath (the value times 128), for tables in raw form and for C.

### `Q7.ofRaw`

```zsharp
Q7.ofRaw : i8 -> q7
```

The value whose integer underneath is `r`.

### `Q7.add`

```zsharp
Q7.add : q7 -> q7 -> q7
```

`a + b`, saturating.

### `Q7.sub`

```zsharp
Q7.sub : q7 -> q7 -> q7
```

`a - b`, saturating.

### `Q7.mul`

```zsharp
Q7.mul : q7 -> q7 -> q7
```

`a * b`, rounded half up and saturating: `-1 * -1` is `Q7.max`.

### `Q7.mulAdd`

```zsharp
Q7.mulAdd : q7 -> q7 -> q7 -> q7
```

`a * b + c` with one rounding, saturating.

### `Q7.div`

```zsharp
Q7.div : q7 -> q7 -> q7
```

`a / b`, saturating; by zero panics.

### `Q7.rem`

```zsharp
Q7.rem : q7 -> q7 -> q7
```

`a % b`, the integers' remainder (both sides have the same scale), computed wider so `min %
-step` is 0 rather than an overflow; by zero panics.

### `Q7.neg`

```zsharp
Q7.neg : q7 -> q7
```

`-a`, saturating: `-Q7.min` is `Q7.max`.

### `Q7.abs`

```zsharp
Q7.abs : q7 -> q7
```

The magnitude, saturating: `Q7.abs Q7.min` is `Q7.max`.

### `Q7.clamp`

```zsharp
Q7.clamp : q7 -> q7 -> q7 -> q7
```

`x` within `lo` and `hi`.

### `Q7.ofInt`

```zsharp
Q7.ofInt : int -> q7
```

The nearest value to `n`, saturating: -1, 0, and `Q7.max` for anything above.

### `Q7.ofFloat`

```zsharp
Q7.ofFloat : f64 -> q7
```

The nearest value to `x`, saturating; 0 for a NaN.

### `Q7.toFloat`

```zsharp
Q7.toFloat : q7 -> f64
```

The value as a float, exactly.

### `Q7.toF32`

```zsharp
Q7.toF32 : q7 -> f32
```

The value as an `f32`, exactly.

### `Q7.show`

```zsharp
Q7.show : q7 -> string
```

The decimal, three digits, rounded half up: `0.250`, `-1.000`, `0.992` for `Q7.max`.

### `Q15.zero`

```zsharp
let zero
```

0.

### `Q15.min`

```zsharp
let min
```

-1, the least value.

### `Q15.max`

```zsharp
let max
```

1 − 2^-15, the greatest value.

### `Q15.step`

```zsharp
let step
```

2^-15, one step.

### `Q15.raw`

```zsharp
Q15.raw : q15 -> i16
```

The integer underneath (the value times 32768), for tables in raw form and for C.

### `Q15.ofRaw`

```zsharp
Q15.ofRaw : i16 -> q15
```

The value whose integer underneath is `r`.

### `Q15.add`

```zsharp
Q15.add : q15 -> q15 -> q15
```

`a + b`, saturating.

### `Q15.sub`

```zsharp
Q15.sub : q15 -> q15 -> q15
```

`a - b`, saturating.

### `Q15.mul`

```zsharp
Q15.mul : q15 -> q15 -> q15
```

`a * b`, rounded half up and saturating: `-1 * -1` is `Q15.max`.

### `Q15.mulAdd`

```zsharp
Q15.mulAdd : q15 -> q15 -> q15 -> q15
```

`a * b + c` with one rounding, saturating.

### `Q15.div`

```zsharp
Q15.div : q15 -> q15 -> q15
```

`a / b`, saturating; by zero panics.

### `Q15.rem`

```zsharp
Q15.rem : q15 -> q15 -> q15
```

`a % b`, the integers' remainder (both sides have the same scale), computed wider so `min %
-step` is 0 rather than an overflow; by zero panics.

### `Q15.neg`

```zsharp
Q15.neg : q15 -> q15
```

`-a`, saturating: `-Q15.min` is `Q15.max`.

### `Q15.abs`

```zsharp
Q15.abs : q15 -> q15
```

The magnitude, saturating: `Q15.abs Q15.min` is `Q15.max`.

### `Q15.clamp`

```zsharp
Q15.clamp : q15 -> q15 -> q15 -> q15
```

`x` within `lo` and `hi`.

### `Q15.ofInt`

```zsharp
Q15.ofInt : int -> q15
```

The nearest value to `n`, saturating: -1, 0, and `Q15.max` for anything above.

### `Q15.ofFloat`

```zsharp
Q15.ofFloat : f64 -> q15
```

The nearest value to `x`, saturating; 0 for a NaN.

### `Q15.toFloat`

```zsharp
Q15.toFloat : q15 -> f64
```

The value as a float, exactly.

### `Q15.toF32`

```zsharp
Q15.toF32 : q15 -> f32
```

The value as an `f32`, exactly.

### `Q15.ofQ7`

```zsharp
Q15.ofQ7 : q7 -> q15
```

A `q7` as a `q15`: exact.

### `Q15.toQ7`

```zsharp
Q15.toQ7 : q15 -> q7
```

The nearest `q7`, rounded half up and saturating.

### `Q15.show`

```zsharp
Q15.show : q15 -> string
```

The decimal, five digits, rounded half up: `0.25000`, `-1.00000`, `0.99997` for `Q15.max`.

### `Q31.zero`

```zsharp
let zero
```

0.

### `Q31.min`

```zsharp
let min
```

-1, the least value.

### `Q31.max`

```zsharp
let max
```

1 − 2^-31, the greatest value.

### `Q31.step`

```zsharp
let step
```

2^-31, one step.

### `Q31.raw`

```zsharp
Q31.raw : q31 -> i32
```

The integer underneath (the value times 2^31), for tables in raw form and for C.

### `Q31.ofRaw`

```zsharp
Q31.ofRaw : i32 -> q31
```

The value whose integer underneath is `r`.

### `Q31.add`

```zsharp
Q31.add : q31 -> q31 -> q31
```

`a + b`, saturating.

### `Q31.sub`

```zsharp
Q31.sub : q31 -> q31 -> q31
```

`a - b`, saturating.

### `Q31.mul`

```zsharp
Q31.mul : q31 -> q31 -> q31
```

`a * b`, rounded half up and saturating: `-1 * -1` is `Q31.max`.

### `Q31.mulAdd`

```zsharp
Q31.mulAdd : q31 -> q31 -> q31 -> q31
```

`a * b + c` with one rounding, saturating (the 64-bit sum saturates too, so a result past
the range is the nearest end).

### `Q31.div`

```zsharp
Q31.div : q31 -> q31 -> q31
```

`a / b`, saturating; by zero panics.

### `Q31.rem`

```zsharp
Q31.rem : q31 -> q31 -> q31
```

`a % b`, the integers' remainder (both sides have the same scale), computed wider so `min %
-step` is 0 rather than an overflow; by zero panics.

### `Q31.neg`

```zsharp
Q31.neg : q31 -> q31
```

`-a`, saturating: `-Q31.min` is `Q31.max`.

### `Q31.abs`

```zsharp
Q31.abs : q31 -> q31
```

The magnitude, saturating: `Q31.abs Q31.min` is `Q31.max`.

### `Q31.clamp`

```zsharp
Q31.clamp : q31 -> q31 -> q31 -> q31
```

`x` within `lo` and `hi`.

### `Q31.ofInt`

```zsharp
Q31.ofInt : int -> q31
```

The nearest value to `n`, saturating: -1, 0, and `Q31.max` for anything above.

### `Q31.ofFloat`

```zsharp
Q31.ofFloat : f64 -> q31
```

The nearest value to `x`, saturating; 0 for a NaN.

### `Q31.toFloat`

```zsharp
Q31.toFloat : q31 -> f64
```

The value as a float, exactly.

### `Q31.toF32`

```zsharp
Q31.toF32 : q31 -> f32
```

The value as an `f32`, rounded (an `i32` doesn't fit its mantissa).

### `Q31.ofQ7`

```zsharp
Q31.ofQ7 : q7 -> q31
```

A `q7` as a `q31`: exact.

### `Q31.ofQ15`

```zsharp
Q31.ofQ15 : q15 -> q31
```

A `q15` as a `q31`: exact.

### `Q31.toQ7`

```zsharp
Q31.toQ7 : q31 -> q7
```

The nearest `q7`, rounded half up and saturating.

### `Q31.toQ15`

```zsharp
Q31.toQ15 : q31 -> q15
```

The nearest `q15`, rounded half up and saturating.

### `Q31.show`

```zsharp
Q31.show : q31 -> string
```

The decimal, ten digits, rounded half up: `0.2500000000`, `-1.0000000000`,
`0.9999999995` for `Q31.max`.

