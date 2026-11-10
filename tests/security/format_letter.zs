// A specifier made at run time with a letter the number doesn't take panics, as the compiler's
// check of a hole refuses it (0024): D is for integers (a float's D2 was quietly its G2)
let main () =
  let spec = String.concat [ "D"; "2" ]
  println (Format.format 7 spec)
  println (Format.format 2.5 spec)
  0
