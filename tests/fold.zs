// constants folded at compile time (0015 step 4): arithmetic, comparisons, conversions and
// Math.round on literals give what the code would compute, so a fixed-point value of a literal
// is a constant; what wouldn't fit its type stays as written, to overflow at run time
open Numerics

let main () =
  println $"{3 + 4 * 2} {7 / 2} {-7 % 3} {1.5 * 2.0} {10 - 3 = 7} {2.5 < 2.4} {i8 -3} {float 7} {Math.round 2.5} {Math.round 3.5} {i32 65537} {u8 200} {"a" + "b"}"
  println $"{Q15.ofFloat 0.5} {Q15.ofFloat -0.25} {Q7.ofFloat 0.5} {Q31.ofFloat 0.1}"
  let big = 2147483647
  println $"{big + 1}"
  0
