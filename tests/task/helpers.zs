// Task.blocking's helper thread ends with its Task.run, and what it took from the system for its
// objects (a chunk of the pool) is left to the next thread to start: 100 runs take a chunk or
// two, where each kept its own 64 KB to the end (6.4 MB).
let main () =
  let before = Runtime.mallocs ()
  let mutable total = 0
  for i in 1 .. 100 do
    total <- total + Task.run (Task.blocking (fun () -> String.length (string (i * 1000))))
  println $"{total} {Runtime.mallocs () - before < 10}"
  0
