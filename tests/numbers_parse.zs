// Int.parse, Int.parseRadix and Float.parse (0024): the result's type decides the width and the
// range; anything but a number is None
let main () =
  let a: option<u8> = Int.parse "255"
  let b: option<u8> = Int.parse "256"
  let c: option<i8> = Int.parse "-128"
  let d: option<u64> = Int.parse "18446744073709551615"
  let e: option<int> = Int.parseRadix 16 "-FF"
  let f: option<u16> = Int.parseRadix 2 "1010"
  println $"{a} {b} {c} {d} {e} {f} {Int.parse "12x"} {Int.parse "+7"} {Int.parse ""} {Int.parse "1_000"} {Int.parse "0x10"}"
  let g: option<f32> = Float.parse "0.5"
  println $"{g} {Float.parse "1e3"} {Float.parse "-2.5E-1"} {Float.parse " 1"} {Float.parse "1,5"} {Float.parse "nan"} {Float.parse "inf"}"
  println $"{String.parseInt "-3"} {String.parseFloat "2.5"} {String.parseFloat "nope"}"
  0
