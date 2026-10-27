// Arithmetic over a loop's variable that overflows at its fifth step: the loop's checked copy
// runs, and stops there
let main () =
  let mutable a = Array.create 8 0
  let step = 2305843009213693952
  println "before"
  for j in 0 .. 7 do
    a.[j] <- j * step
  println $"{a.[1]}"
  0
