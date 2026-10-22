// F#: a ref cell can't be shared between threads; use Atomic, Mutex or a result per job
let main () =
  let hits = ref 0
  Parallel.for 0 100 (fun i -> hits.Value <- hits.Value + 1)
  hits.Value
