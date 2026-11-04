// Debug info on an optimized build (tests/debug/opt.sh): zs build -g --release keeps the lines
// and the functions the optimizer keeps, so a breakpoint and a backtrace work there
let rec depth (n: int) : int =
  if n = 0 then
    println "bottom"
    0
  else
    1 + depth (n - 1)

let main () =
  println $"{depth 2}"
  0
