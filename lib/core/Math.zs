/// Arithmetic beyond the operators. Besides these, built into the compiler for `f64` and `f32`:
/// `sqrt`, `floor`, `ceil`, `round` (half to even, as F#'s), `trunc`, `exp`, `log` (natural),
/// `log2`, `log10`, `sin`, `cos`, `tan`, `pow` and `atan2`: an instruction where the target has
/// one, else libm's function.
module Math

/// The absolute value: `x` without its sign (named apart from C's `abs`, which programs often
/// import). For integers, the most negative value has none, so it overflows (and panics).
let abs x = if x < Add.zero then -x else x

/// `x` kept within `low` and `high`: `low` when it's below, `high` when it's above.
let clamp low high x = if x < low then low else if x > high then high else x

/// π, as an `f64` or an `f32`, whichever the use needs.
let pi = 3.141592653589793

/// e, the base of natural logarithms, as an `f64` or an `f32`.
let e = 2.718281828459045
