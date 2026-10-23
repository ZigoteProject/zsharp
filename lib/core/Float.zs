/// Floating-point numbers.
module Float

/// The number `s` writes: an optional sign, digits with an optional `.` and fraction, an
/// optional exponent (`1.5e-3`), or `inf` and `nan`; nothing else (no spaces, no `1,5`). The
/// type is the result's (`f32` or `f64`, `f64` when nothing else says).
let parse (s: string) : option<'a> =
  let (ok, x) = Native.parseFloat s
  if ok then Some x else None
