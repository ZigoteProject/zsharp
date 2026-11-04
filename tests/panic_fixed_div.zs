// a fixed-point division by zero panics, as an integer's does (decision 4)
let main () =
  println $"{Q15.ofFloat 0.5 / Q15.ofFloat 0.25}"
  println $"{Q15.ofFloat 0.5 / Q15.zero}"
  0
