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
  // a number of any length, a literal or parsed, rounds as strtod rounds it: pi to 450 places
  // is pi (past 400 characters the literal was 0.0, and Float.parse None)
  let pi =
    3.141592653589793238462643383279502884197169399375105820974944592307816406286208998628034825342117067982148086513282306647093844609550582231725359408128481117450284102701938521105559644622948954930381964428810975665933446128475648233786783165271201909145648566923460348610454326648213393607260249141273724587006606315588174881520920962829254091715364367892590360011330530548820466521384146951941511609433057270365759591953092186117381932611793105118548
  println $"{pi} {Float.parse ("1." + String.repeat 450 "0")}"
  0
