let numbers () =
  for i in 1 .. 3 do Yield.yield i

let main () =
  numbers ()
  0
