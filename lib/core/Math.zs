/// Arithmetic beyond the operators.
module Math

/// The absolute value: `x` without its sign (named apart from C's `abs`, which programs often
/// import). For integers, the most negative value has none, so it overflows (and panics).
let abs x = if x < Add.zero then -x else x
