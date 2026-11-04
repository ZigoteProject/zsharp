// fixed-point numbers on a chip (0015): the same corners and roundings as on the host, a q15
// FIR tap in mulAdd, and the decimals printed with no float
let main () =
  let half = Q15.ofFloat 0.5
  println $"{Q15.min * Q15.min = Q15.max} {Q15.min - Q15.step = Q15.min} {-Q15.min = Q15.max} {half * half} {Q15.step * half} {Q15.ofFloat 0.75 / Q15.ofFloat -0.5}"
  println $"{Q15.max} {Q15.ofFloat 0.1} {Q7.max} {Q7.ofFloat 0.5 * Q7.ofFloat 0.5} {Q31.max} {Q31.ofFloat 0.5 * Q31.ofFloat 0.5} {Q31.toQ15 (Q31.ofFloat 0.1)}"
  let taps = [| Q15.ofFloat 0.25; Q15.ofFloat 0.5; Q15.ofFloat 0.25 |]
  let samples = [| Q15.ofFloat 0.1; Q15.ofFloat 0.2; Q15.ofFloat 0.3 |]
  let mutable acc = Q15.zero
  for i in 0 .. 2 do
    acc <- Q15.mulAdd taps.[i] samples.[i] acc
  println $"{acc} {List.sum [ half; half; half ]} {sizeof<q15>}"
  0
