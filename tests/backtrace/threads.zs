// panics on several threads at once (tests/backtrace/run.sh): one report, the other threads wait
// for its stop, so the symbol reader and the output aren't raced
let rec depth (n: int) : int = if n = 0 then panic "boom" else 1 + depth (n - 1)

let main () =
  let n = Parallel.workers ()
  let arrived = Atomic.make 0
  Parallel.for 0 n (fun i ->
    Atomic.add arrived 1 |> ignore
    while Atomic.get arrived < n do
      ()
    depth (i % 3) |> ignore)
  0
