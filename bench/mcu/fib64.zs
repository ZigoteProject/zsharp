// the same Fibonacci on Z#'s default int (64-bit): the cost of a 64-bit int on a 32-bit chip
let rec fib n = if n < 2 then n else fib (n - 1) + fib (n - 2)

let main () =
  let t0 = Runtime.ticks ()
  let r = fib 24
  let t1 = Runtime.ticks ()
  println $"fib64 result={r} ticks={t1 - t0}"
  0
