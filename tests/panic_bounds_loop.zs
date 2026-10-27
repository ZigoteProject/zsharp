// A write past the end in a loop versioning can't prove: the checked copy runs, and stops there
let main () =
  let mutable a = Array.create 4 0
  println "before"
  for i in 0 .. 4 do
    a.[i] <- i
  println $"{a.[0]}"
  0
