// A function given to another thread can't reach a top-level ref, even through the functions
// it calls: every thread would change it at once.
let hits = ref 0

let bump () = hits.Value <- hits.Value + 1

let main () =
  Parallel.for 0 10 (fun i -> bump ())
  println $"{hits.Value}"
