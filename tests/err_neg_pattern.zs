// a negative pattern is signed, as a negative literal is: at an unsigned type it's an error, not a
// case that never matches (or matches the wrapped value)
let f (x: u8) =
  match x with
  | -1 -> "minus one"
  | _ -> "other"

let main () =
  println (f (u8 255))
  0
