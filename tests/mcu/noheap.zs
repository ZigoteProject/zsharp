// --no-heap (0012): the whole program checked as [<NoAlloc>], and an image with no heap
let square (x: int) = x * x

let main () =
  let mutable sum = 0
  for i in 1 .. 4 do
    sum <- sum + square i
  println "squares summed"
  sum - 30
