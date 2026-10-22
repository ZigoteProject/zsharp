// The pool from any thread, and jobs that wait for each other in a channel.

// every worker at once: n iterations that each wait (spinning, for at most a minute) until all
// n have started, so they pass only if n threads run them at the same time
let together (n: int) =
  let arrived = Atomic.make 0
  let passed = Atomic.make 0

  Parallel.for 0 n (fun _ ->
    Atomic.add arrived 1 |> ignore
    let sw = Stopwatch.startNew ()

    while Atomic.get arrived < n && sw.ElapsedMilliseconds < 60000 do
      ()

    if Atomic.get arrived = n then
      Atomic.add passed 1 |> ignore)

  Atomic.get passed = n

let main () =
  let n = Parallel.workers ()

  // started by a task on another thread's loop (not the thread that started the pool): its
  // iterations run on every worker, not only on that thread
  let fromTask = Task.run (Task.spawn (fun () -> task { return together n }))
  println $"Parallel.for in a spawned task, every worker at once: {fromTask}"

  // a channel of capacity 0: a send waits for a receiver to take its value. Half the jobs send,
  // half receive; senders waiting for receivers that no thread is left to run get a spare
  // worker each, so every value arrives
  let ch = Channel.make 0
  let got = Atomic.make 0

  Parallel.for 0 (2 * n) (fun i ->
    if i < n then
      Channel.send ch (i + 1)
    else
      match Channel.receive ch with
      | Some x -> Atomic.add got x |> ignore
      | None -> ())

  println $"through a channel of capacity 0, every value: {Atomic.get got = n * (n + 1) / 2}"

  // two jobs, one sending 1,000 values one at a time, the other summing them
  let pipe = Channel.make 0

  let produce () =
    for i in 1 .. 1000 do
      Channel.send pipe i

    Channel.close pipe

  let consume () =
    let mutable sum = 0
    let mutable more = true

    while more do
      match Channel.receive pipe with
      | Some x -> sum <- sum + x
      | None -> more <- false

    sum

  let (_, total) = Parallel.both produce consume

  println $"two jobs passing 1,000 values: {total}"
  0
