// Loops over an array, a list and a string: one loop each, the body in place, nothing allocated
// (tests/iter/loops.sh checks the IR).
let sumList (xs: list<int>) =
  let mutable t = 0
  for x in xs do
    t <- t + x
  t

let sumArray (a: array<int>) =
  let mutable t = 0
  for x in a do
    t <- t + x
  t

let count (s: string) =
  let mutable n = 0
  for c in s do
    n <- n + 1
  n

let main () =
  println $"{sumList [ 1; 2 ]} {sumArray [| 3 |]} {count "ab"}"
  0
