// Task.blocking's helper thread ends with its Task.run, and what it took from the system for its
// objects (a chunk of the pool) is left to the next thread to start: 100 runs whose helper
// allocates take a chunk or two more than 100 whose helper doesn't, where each kept its own
// 64 KB to the end (100 more). A run's own frames are mallocs too, the same in both.
let main () =
  let quiet = Runtime.mallocs ()
  let mutable sum = 0
  for i in 1 .. 100 do
    sum <- sum + Task.run (Task.blocking (fun () -> i * 1000))
  let plain = Runtime.mallocs () - quiet
  let before = Runtime.mallocs ()
  let mutable total = 0
  for i in 1 .. 100 do
    total <- total + Task.run (Task.blocking (fun () -> String.length (string (i * 1000))))
  let allocating = Runtime.mallocs () - before
  println $"{total} {sum > 0 && allocating - plain < 10}"
  0
