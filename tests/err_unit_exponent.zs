// a unit's exponent past a million is an error at it, not the compiler's overflow: negating the
// lowest int, or multiplying out a power of a power (parsed too; a build shows the first error)
[<Measure>] type m

let main () =
  let d: f64<m^-0x8000000000000000> = 1.0
  let e: f64<(m^2)^0x4000000000000000> = 1.0
  println $"{d} {e}"
  0
