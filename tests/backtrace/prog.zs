// a panic's backtrace names the Z# functions on the way (tests/backtrace/run.sh): recursion keeps
// the frames apart (an inlined call has none)
let rec depth (n: int) : int = if n = 0 then panic "boom" else 1 + depth (n - 1)

let main () =
  println $"{depth 2}"
  0
