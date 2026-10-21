// Debug info test program (tests/debug/gdb.sh drives gdb over it)
let square (n: int) =
  let result = n * n
  result

let main () =
  let mutable total = 0
  for i in 1 .. 3 do
    let sq = square i
    total <- total + sq
  let ratio = float total / 2.0
  let ok = total = 14
  println $"total {total} ratio {ratio} ok {ok}"
  0
