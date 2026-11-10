// A float literal with an exponent and no fraction (track G, defect 2): 1e-3, as F# reads it
let main () =
  let a = 1e-3
  let b: f32 = 2E3
  let c = 5e+2
  println $"{a} {b} {c} {1.5e-3} {1e0 + 1.0}"
  // not exponents: a name after an integer is still a name
  let e2 = 7
  println $"{[ 1; e2 ]}"
