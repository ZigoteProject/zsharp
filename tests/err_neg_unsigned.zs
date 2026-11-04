// a negative literal is a signed integer: at an unsigned type it's an error, not a wrapped value
let main () =
  let x : u8 = -1
  println $"{x}"
  0
