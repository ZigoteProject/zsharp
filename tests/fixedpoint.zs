// fixed-point numbers (0015): q7, q15 and q31, each saturating, products rounded half up, Show's
// decimals round-tripping through ofFloat; the same cases at each format
let half = Q15.ofFloat 0.5

let main () =
  // q15: the corners
  println $"{Q15.min * Q15.min = Q15.max} {Q15.min - Q15.step = Q15.min} {-Q15.min = Q15.max} {Q15.abs Q15.min = Q15.max} {Q15.max + Q15.step = Q15.max}"
  // a product's rounding (a tie rounds up), a sum, a quotient, a remainder, mulAdd
  println $"{half * half} {Q15.step * half} {Q15.ofFloat 0.25 + Q15.ofFloat 0.5} {Q15.ofFloat 0.75 / Q15.ofFloat -0.5} {Q15.ofFloat 0.3 / half} {Q15.ofFloat 0.7 % Q15.ofFloat 0.4} {Q15.mulAdd half half (Q15.ofFloat 0.5)}"
  // printing, parsing back, and the integers underneath
  println $"{Q15.max} {Q15.min} {Q15.ofFloat 0.1} {Q15.toFloat (Q15.ofFloat 0.1)} {Q15.raw (Q15.ofFloat -0.5)} {Q15.ofRaw (i16 1)} {Q15.ofInt 1} {Q15.ofInt -3} {Q15.ofFloat 2.0 = Q15.max} {Q15.ofFloat (0.0 / 0.0)}"
  println $"{List.map (fun s -> Q15.ofFloat (Option.get (Float.parse s)) = Q15.ofFloat (Option.get (Float.parse s))) [ "0.25000"; "0.99997" ]} {Q15.ofFloat (Option.get (Float.parse (string Q15.max))) = Q15.max}"
  // sums saturate like the operator; clamp; sizes
  println $"{List.sum [ half; half; half ]} {Q15.clamp (Q15.ofFloat -0.5) half (Q15.ofFloat 0.9)} {sizeof<q7>} {sizeof<q15>} {sizeof<q31>}"
  // q7 and q31: the same corners and rounding, and the conversions between the formats
  println $"{Q7.min * Q7.min = Q7.max} {-Q7.min = Q7.max} {Q7.max} {Q7.ofFloat 0.5 * Q7.ofFloat 0.5} {Q7.step * Q7.ofFloat 0.5} {Q15.ofQ7 (Q7.ofFloat 0.25)} {Q15.toQ7 (Q15.ofFloat 0.3)} {Q15.toQ7 Q15.max = Q7.max}"
  // the remainder of the minimum by minus a step is 0, not an overflow, at each format
  println $"{Q7.min % -Q7.step} {Q15.min % -Q15.step} {Q31.min % -Q31.step}"
  println $"{Q31.min * Q31.min = Q31.max} {-Q31.min = Q31.max} {Q31.max} {Q31.min} {Q31.ofFloat 0.5 * Q31.ofFloat 0.5} {Q31.step * Q31.ofFloat 0.5} {Q31.mulAdd Q31.min Q31.min Q31.max = Q31.max} {Q31.toQ15 (Q31.ofQ15 half) = half} {Q31.toQ7 Q31.max = Q7.max} {Q31.toQ15 (Q31.ofFloat 0.1)}"
  0
