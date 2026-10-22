// Debug info test program (tests/debug/gdb.sh drives gdb over it)
type Range = { lo: int; hi: int }

type Summary =
  | Small of int
  | Large of int * f64

let square (n: int) =
  let result = n * n
  result

let main () =
  let name = "squares"
  let range = { lo = 1; hi = 3 }
  let mutable total = 0
  for i in range.lo .. range.hi do
    let sq = square i
    total <- total + sq
  let ratio = float total / 2.0
  let ok = total = 14
  let summary = if total > 10 then Large (total, ratio) else Small total
  println $"{name}: total {total} ratio {ratio} ok {ok} {summary}"
  0
