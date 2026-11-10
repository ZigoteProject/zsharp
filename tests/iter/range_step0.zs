// A Range's step of 0 counts nowhere: a panic, not a loop calling f forever on the start
let main () =
  let still: Iter.Range = { start = 5; stop = 0; step = 0 }
  println "before"
  Iter.iter (fun (x: int) -> println $"{x}") still
  0
