// The pool's one worker going to sleep as jobs are forked (test.sh runs this with ZS_WORKERS=2):
// the main thread waits in a channel for each job it forks, which only the worker can run, so a
// wake-up lost hangs it. Each fork follows a pause of up to 100 µs, which lands it anywhere in
// the worker's way to sleep.

let main () =
  let ch = Channel.make 0
  let mutable seed = 1
  let mutable sum = 0

  for i in 1 .. 30000 do
    seed <- (seed * 1103515245 + 12345) % 2147483648
    let pause = u64 (seed / 256 % 100000)
    let sw = Stopwatch.startNew ()

    while sw.ElapsedNanoseconds < pause do
      ()

    let (got, ()) = Parallel.both (fun () -> Channel.receive ch) (fun () -> Channel.send ch i)

    match got with
    | Some x -> sum <- sum + x
    | None -> ()

  println $"30000 jobs, each run by the worker: {sum = 30000 * 30001 / 2}"
