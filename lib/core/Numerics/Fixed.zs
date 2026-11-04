/// Fixed-point numbers (0015): `q7`, `q15` and `q31`, the formats CMSIS-DSP and the chips'
/// saturating instructions use, each a number in [-1, 1) as a signed integer over 2^7, 2^15 or
/// 2^31. Every operation saturates (a result past the range is the nearest end), and a product
/// is rounded half up, as the chips' rounding multiplies do; `Show` prints the decimal with as
/// many digits as the format needs to tell neighbours apart. A format is a one-case union, so it
/// is its integer's size (decision 66) and allocates nothing.
namespace Numerics

/// A number in [-1, 1) as an `i8` over 128: a step of 2^-7 (CMSIS's `q7_t`).
type q7 =
  /// The integer underneath: the value times 128.
  | Q7 of i8

/// A number in [-1, 1) as an `i16` over 32768: a step of 2^-15 (CMSIS's `q15_t`).
type q15 =
  /// The integer underneath: the value times 32768.
  | Q15 of i16

/// A number in [-1, 1) as an `i32` over 2147483648: a step of 2^-31 (CMSIS's `q31_t`).
type q31 =
  /// The integer underneath: the value times 2^31.
  | Q31 of i32

/// Functions on `q7`.
module Q7 =
  // a wide result into the format's range; a product, a product plus a value or a quotient of
  // two q7 fits 32 bits, the chips' word
  let private saturate (w: i32) : q7 =
    if w > i32 127 then Q7(i8 127) else if w < i32 -128 then Q7(i8 -128) else Q7(i8 w)

  /// 0.
  let zero = Q7(i8 0)

  /// -1, the least value.
  let min = Q7(i8 -128)

  /// 1 − 2^-7, the greatest value.
  let max = Q7(i8 127)

  /// 2^-7, one step.
  let step = Q7(i8 1)

  /// The integer underneath (the value times 128), for tables in raw form and for C.
  let raw (Q7 r) : i8 = r

  /// The value whose integer underneath is `r`.
  let ofRaw (r: i8) : q7 = Q7 r

  /// `a + b`, saturating.
  let add (Q7 a) (Q7 b) : q7 = Q7(Int.saturatingAdd a b)

  /// `a - b`, saturating.
  let sub (Q7 a) (Q7 b) : q7 = Q7(Int.saturatingSub a b)

  /// `a * b`, rounded half up and saturating: `-1 * -1` is `Q7.max`.
  [<Wrapping>]
  let mul (Q7 a) (Q7 b) : q7 = saturate ((i32 a * i32 b + i32 64) >>> i32 7)

  /// `a * b + c` with one rounding, saturating.
  [<Wrapping>]
  let mulAdd (Q7 a) (Q7 b) (Q7 c) : q7 =
    saturate ((i32 a * i32 b + (i32 c <<< i32 7) + i32 64) >>> i32 7)

  /// `a / b`, saturating; by zero panics.
  [<Wrapping>]
  let div (Q7 a) (Q7 b) : q7 = saturate ((i32 a <<< i32 7) / i32 b)

  /// `a % b`, the integers' remainder (both sides have the same scale); by zero panics.
  let rem (Q7 a) (Q7 b) : q7 = Q7(a % b)

  /// `-a`, saturating: `-Q7.min` is `Q7.max`.
  let neg (Q7 a) : q7 = Q7(Int.saturatingSub (i8 0) a)

  /// The magnitude, saturating: `Q7.abs Q7.min` is `Q7.max`.
  let abs (x: q7) : q7 = if raw x < i8 0 then neg x else x

  /// `x` within `lo` and `hi`.
  let clamp (lo: q7) (hi: q7) (x: q7) : q7 = if x < lo then lo else if x > hi then hi else x

  /// The nearest value to `n`, saturating: -1, 0, and `Q7.max` for anything above.
  let ofInt (n: int) : q7 = if n >= 1 then max else if n <= -1 then min else zero

  /// The nearest value to `x`, saturating; 0 for a NaN.
  let ofFloat (x: f64) : q7 =
    if x <> x then
      zero
    else
      let r = Math.round (x * 128.0)
      if r >= 127.0 then max else if r <= -128.0 then min else Q7(i8 (i64 r))

  /// The value as a float, exactly.
  let toFloat (Q7 a) : f64 = f64 a / 128.0

  /// The value as an `f32`, exactly.
  let toF32 (Q7 a) : f32 = f32 a / f32 128.0

  /// The decimal, three digits, rounded half up: `0.250`, `-1.000`, `0.992` for `Q7.max`.
  let show (Q7 a) : string =
    let negative = a < i8 0
    let mag = if negative then i64 0 - i64 a else i64 a
    let whole0 = mag >>> i64 7
    let scaled0 = ((mag &&& i64 127) * i64 1000 + i64 64) >>> i64 7
    let (whole, scaled) =
      if scaled0 >= i64 1000 then (whole0 + i64 1, scaled0 - i64 1000) else (whole0, scaled0)
    $"{(if negative then "-" else "")}{whole}.{String.padLeftWith 3 '0' (string scaled)}"

/// `+` and `Add.zero` on `q7`, saturating.
impl Add<q7> =
  let add (a: q7) (b: q7) : q7 = Q7.add a b
  let zero = Q7.zero

/// `-`, `*`, `/`, `%` and negation on `q7`, saturating.
impl Num<q7> =
  let sub (a: q7) (b: q7) : q7 = Q7.sub a b
  let mul (a: q7) (b: q7) : q7 = Q7.mul a b
  let div (a: q7) (b: q7) : q7 = Q7.div a b
  let rem (a: q7) (b: q7) : q7 = Q7.rem a b
  let neg (a: q7) : q7 = Q7.neg a

/// A `q7` prints as its decimal (`Q7.show`).
impl Show<q7> =
  let show (x: q7) : string = Q7.show x

/// Functions on `q15`.
module Q15 =
  // a product, a product plus a value or a quotient of two q15 fits 32 bits, the chips' word,
  // and can't overflow, so those functions are [<Wrapping>]: no checks in a filter's loop
  let private saturate (w: i32) : q15 =
    if w > i32 32767 then Q15(i16 32767) else if w < i32 -32768 then Q15(i16 -32768) else Q15(i16 w)

  /// 0.
  let zero = Q15(i16 0)

  /// -1, the least value.
  let min = Q15(i16 -32768)

  /// 1 − 2^-15, the greatest value.
  let max = Q15(i16 32767)

  /// 2^-15, one step.
  let step = Q15(i16 1)

  /// The integer underneath (the value times 32768), for tables in raw form and for C.
  let raw (Q15 r) : i16 = r

  /// The value whose integer underneath is `r`.
  let ofRaw (r: i16) : q15 = Q15 r

  /// `a + b`, saturating.
  let add (Q15 a) (Q15 b) : q15 = Q15(Int.saturatingAdd a b)

  /// `a - b`, saturating.
  let sub (Q15 a) (Q15 b) : q15 = Q15(Int.saturatingSub a b)

  /// `a * b`, rounded half up and saturating: `-1 * -1` is `Q15.max`.
  [<Wrapping>]
  let mul (Q15 a) (Q15 b) : q15 = saturate ((i32 a * i32 b + i32 0x4000) >>> i32 15)

  /// `a * b + c` with one rounding, saturating.
  [<Wrapping>]
  let mulAdd (Q15 a) (Q15 b) (Q15 c) : q15 =
    saturate ((i32 a * i32 b + (i32 c <<< i32 15) + i32 0x4000) >>> i32 15)

  /// `a / b`, saturating; by zero panics.
  [<Wrapping>]
  let div (Q15 a) (Q15 b) : q15 = saturate ((i32 a <<< i32 15) / i32 b)

  /// `a % b`, the integers' remainder (both sides have the same scale); by zero panics.
  let rem (Q15 a) (Q15 b) : q15 = Q15(a % b)

  /// `-a`, saturating: `-Q15.min` is `Q15.max`.
  let neg (Q15 a) : q15 = Q15(Int.saturatingSub (i16 0) a)

  /// The magnitude, saturating: `Q15.abs Q15.min` is `Q15.max`.
  let abs (x: q15) : q15 = if raw x < i16 0 then neg x else x

  /// `x` within `lo` and `hi`.
  let clamp (lo: q15) (hi: q15) (x: q15) : q15 = if x < lo then lo else if x > hi then hi else x

  /// The nearest value to `n`, saturating: -1, 0, and `Q15.max` for anything above.
  let ofInt (n: int) : q15 = if n >= 1 then max else if n <= -1 then min else zero

  /// The nearest value to `x`, saturating; 0 for a NaN.
  let ofFloat (x: f64) : q15 =
    if x <> x then
      zero
    else
      let r = Math.round (x * 32768.0)
      if r >= 32767.0 then max else if r <= -32768.0 then min else Q15(i16 (i64 r))

  /// The value as a float, exactly.
  let toFloat (Q15 a) : f64 = f64 a / 32768.0

  /// The value as an `f32`, exactly.
  let toF32 (Q15 a) : f32 = f32 a / f32 32768.0

  /// A `q7` as a `q15`: exact.
  let ofQ7 (Q7 a) : q15 = Q15(i16 a <<< i16 8)

  /// The nearest `q7`, rounded half up and saturating.
  let toQ7 (Q15 a) : q7 = Q7.ofRaw (if a >= i16 32640 then i8 127 else i8 ((a + i16 128) >>> i16 8))

  /// The decimal, five digits, rounded half up: `0.25000`, `-1.00000`, `0.99997` for `Q15.max`.
  let show (Q15 a) : string =
    let negative = a < i16 0
    let mag = if negative then i64 0 - i64 a else i64 a
    let whole0 = mag >>> i64 15
    let scaled0 = ((mag &&& i64 32767) * i64 100000 + i64 16384) >>> i64 15
    let (whole, scaled) =
      if scaled0 >= i64 100000 then (whole0 + i64 1, scaled0 - i64 100000) else (whole0, scaled0)
    $"{(if negative then "-" else "")}{whole}.{String.padLeftWith 5 '0' (string scaled)}"

/// `+` and `Add.zero` on `q15`, saturating.
impl Add<q15> =
  let add (a: q15) (b: q15) : q15 = Q15.add a b
  let zero = Q15.zero

/// `-`, `*`, `/`, `%` and negation on `q15`, saturating.
impl Num<q15> =
  let sub (a: q15) (b: q15) : q15 = Q15.sub a b
  let mul (a: q15) (b: q15) : q15 = Q15.mul a b
  let div (a: q15) (b: q15) : q15 = Q15.div a b
  let rem (a: q15) (b: q15) : q15 = Q15.rem a b
  let neg (a: q15) : q15 = Q15.neg a

/// A `q15` prints as its decimal (`Q15.show`).
impl Show<q15> =
  let show (x: q15) : string = Q15.show x

/// Functions on `q31`.
module Q31 =
  let private saturate (w: i64) : q31 =
    if w > i64 2147483647 then
      Q31(i32 2147483647)
    else if w < i64 -2147483648 then
      Q31(i32 -2147483648)
    else
      Q31(i32 w)

  /// 0.
  let zero = Q31(i32 0)

  /// -1, the least value.
  let min = Q31(i32 -2147483648)

  /// 1 − 2^-31, the greatest value.
  let max = Q31(i32 2147483647)

  /// 2^-31, one step.
  let step = Q31(i32 1)

  /// The integer underneath (the value times 2^31), for tables in raw form and for C.
  let raw (Q31 r) : i32 = r

  /// The value whose integer underneath is `r`.
  let ofRaw (r: i32) : q31 = Q31 r

  /// `a + b`, saturating.
  let add (Q31 a) (Q31 b) : q31 = Q31(Int.saturatingAdd a b)

  /// `a - b`, saturating.
  let sub (Q31 a) (Q31 b) : q31 = Q31(Int.saturatingSub a b)

  /// `a * b`, rounded half up and saturating: `-1 * -1` is `Q31.max`.
  [<Wrapping>]
  let mul (Q31 a) (Q31 b) : q31 = saturate ((i64 a * i64 b + i64 0x40000000) >>> i64 31)

  /// `a * b + c` with one rounding, saturating (the 64-bit sum saturates too, so a result past
  /// the range is the nearest end).
  [<Wrapping>]
  let mulAdd (Q31 a) (Q31 b) (Q31 c) : q31 =
    let sum =
      Int.saturatingAdd (Int.saturatingAdd (i64 a * i64 b) (i64 c <<< i64 31)) (i64 0x40000000)
    saturate (sum >>> i64 31)

  /// `a / b`, saturating; by zero panics.
  [<Wrapping>]
  let div (Q31 a) (Q31 b) : q31 = saturate ((i64 a <<< i64 31) / i64 b)

  /// `a % b`, the integers' remainder (both sides have the same scale); by zero panics.
  let rem (Q31 a) (Q31 b) : q31 = Q31(a % b)

  /// `-a`, saturating: `-Q31.min` is `Q31.max`.
  let neg (Q31 a) : q31 = Q31(Int.saturatingSub (i32 0) a)

  /// The magnitude, saturating: `Q31.abs Q31.min` is `Q31.max`.
  let abs (x: q31) : q31 = if raw x < i32 0 then neg x else x

  /// `x` within `lo` and `hi`.
  let clamp (lo: q31) (hi: q31) (x: q31) : q31 = if x < lo then lo else if x > hi then hi else x

  /// The nearest value to `n`, saturating: -1, 0, and `Q31.max` for anything above.
  let ofInt (n: int) : q31 = if n >= 1 then max else if n <= -1 then min else zero

  /// The nearest value to `x`, saturating; 0 for a NaN.
  let ofFloat (x: f64) : q31 =
    if x <> x then
      zero
    else
      let r = Math.round (x * 2147483648.0)
      if r >= 2147483647.0 then max else if r <= -2147483648.0 then min else Q31(i32 (i64 r))

  /// The value as a float, exactly.
  let toFloat (Q31 a) : f64 = f64 a / 2147483648.0

  /// The value as an `f32`, rounded (an `i32` doesn't fit its mantissa).
  let toF32 (Q31 a) : f32 = f32 (f64 a / 2147483648.0)

  /// A `q7` as a `q31`: exact.
  let ofQ7 (Q7 a) : q31 = Q31(i32 a <<< i32 24)

  /// A `q15` as a `q31`: exact.
  let ofQ15 (Q15 a) : q31 = Q31(i32 a <<< i32 16)

  /// The nearest `q7`, rounded half up and saturating.
  let toQ7 (Q31 a) : q7 =
    Q7.ofRaw (if a >= i32 2139095040 then i8 127 else i8 ((i64 a + i64 8388608) >>> i64 24))

  /// The nearest `q15`, rounded half up and saturating.
  let toQ15 (Q31 a) : q15 =
    Q15.ofRaw (if a >= i32 2147450880 then i16 32767 else i16 ((i64 a + i64 32768) >>> i64 16))

  /// The decimal, ten digits, rounded half up: `0.2500000000`, `-1.0000000000`,
  /// `0.9999999995` for `Q31.max`.
  let show (Q31 a) : string =
    let negative = a < i32 0
    let mag = if negative then i64 0 - i64 a else i64 a
    let mask = i64 2147483647
    let whole0 = mag >>> i64 31
    // five digits at a time: the fraction times 10^10 wouldn't fit a word
    let first = (mag &&& mask) * i64 100000
    let hi0 = first >>> i64 31
    let lo0 = ((first &&& mask) * i64 100000 + i64 1073741824) >>> i64 31
    let (hi1, lo) = if lo0 >= i64 100000 then (hi0 + i64 1, lo0 - i64 100000) else (hi0, lo0)
    let (whole, hi) =
      if hi1 >= i64 100000 then (whole0 + i64 1, hi1 - i64 100000) else (whole0, hi1)
    $"{(if negative then "-" else "")}{whole}.{String.padLeftWith 5 '0' (string hi)}{String.padLeftWith 5 '0' (string lo)}"

/// `+` and `Add.zero` on `q31`, saturating.
impl Add<q31> =
  let add (a: q31) (b: q31) : q31 = Q31.add a b
  let zero = Q31.zero

/// `-`, `*`, `/`, `%` and negation on `q31`, saturating.
impl Num<q31> =
  let sub (a: q31) (b: q31) : q31 = Q31.sub a b
  let mul (a: q31) (b: q31) : q31 = Q31.mul a b
  let div (a: q31) (b: q31) : q31 = Q31.div a b
  let rem (a: q31) (b: q31) : q31 = Q31.rem a b
  let neg (a: q31) : q31 = Q31.neg a

/// A `q31` prints as its decimal (`Q31.show`).
impl Show<q31> =
  let show (x: q31) : string = Q31.show x
