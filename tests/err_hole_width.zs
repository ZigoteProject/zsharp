// a hole's width past a million is an error, not the compiler's overflow negating the lowest int
let main () =
  let x = 1
  println $"{x,-9223372036854775808}"
  0
