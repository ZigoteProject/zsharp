// Float.parse on a chip and on WebAssembly, where the runtime reads the number itself
// (rt-embedded.c, not strtod): an exponent past an int's range saturates, to infinity or 0 as
// strtod gives, where it wrapped (1e4294967306 was 1e10, 1e2147483648 was 1, 5e-4294967296 was
// 5); and the mantissa's digits count toward where a number runs out of range (a cap of 400
// steps left 1 and 100 zeros e-450 at 1e-300)
let parsed (s: string) : f64 =
  match Float.parse s with
  | Some x -> x
  | None -> -1.0

let main () =
  let inf = 1.0 / 0.0
  println $"{parsed "1e4294967306" = inf} {parsed "1e2147483648" = inf}"
  println $"{parsed "1e-4294967306" = 0.0} {parsed "5e-4294967296" = 0.0}"
  let manyDigits = "1" + String.repeat 100 "0" + "e-450"
  let manyDecimals = "0." + String.repeat 100 "0" + "1e450"
  println $"{parsed manyDigits = 0.0} {parsed manyDecimals = inf}"
  println $"{parsed "1.5e3" = 1500.0} {parsed "-2.5e2" = -250.0} {parsed "1e00000000003" = 1000.0}"
  0
