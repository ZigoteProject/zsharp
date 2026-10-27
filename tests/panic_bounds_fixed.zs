// An index without the loop variable, out of bounds: the loop's checked copy stops at it
let main () =
  let mutable a = Array.create 4 0
  let k = 4
  println "before"
  for i in 0 .. 3 do
    a.[k] <- i
  println $"{a.[0]}"
  0
