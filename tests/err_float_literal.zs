// an exponent without its digits is an error, not 0.0 (a typo for 1.5e-3)
let main () =
  let tolerance = 1.5e
  println $"{tolerance}"
  0
