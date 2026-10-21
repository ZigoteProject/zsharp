// Integer overflow panics in every build; Int.wrapping* wrap around on purpose.
let main () =
  let big = 9223372036854775807
  println $"wrapping: {Int.wrappingAdd big 1} {Int.wrappingMul (u8 200) (u8 2)} {Int.wrappingSub (i8 -128) (i8 1)}"
  let h = Int.wrappingMul 1000000007 1000000007000
  println $"hash-style: {h}"
  println $"fits: {big - 1 + 1} {u8 255 - u8 255}"
  println "before"
  println $"{big + 1}"
  0
