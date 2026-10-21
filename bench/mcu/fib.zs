// recursive Fibonacci on i32: call overhead
let rec fib (n: i32) : i32 = if n < 2 then n else fib (n - 1) + fib (n - 2)

let main () =
  let t0 = Runtime.ticks ()
  let r = fib 24
  let t1 = Runtime.ticks ()
  println $"fib result={r} ticks={t1 - t0}"
  0
