// Jobs that wait for a thread outside the pool, more of them than the pool has spare threads:
// they wait until it lets go or catches up, rather than being taken for jobs that wait for each
// other (that was a panic).

let main () =
  // this thread holds a mutex for half a second while the pool's jobs, a thousand updates, want it
  let m = Mutex.make 0

  let hold () =
    Mutex.update m (fun x ->
      let sw = Stopwatch.startNew ()

      while sw.ElapsedMilliseconds < 500 do
        ()

      x + 1000)

  let crowd () = Parallel.for 0 1000 (fun _ -> Mutex.update m (fun x -> x + 1) |> ignore)
  Parallel.both hold crowd |> ignore
  println $"every update: {Mutex.get m}"

  // this thread takes what the pool's jobs send, twenty thousand values through a channel of one
  let ch = Channel.make 1

  let drain () =
    let mutable sum = 0
    let mutable more = true

    while more do
      match Channel.receive ch with
      | Some x -> sum <- sum + x
      | None -> more <- false

    sum

  let send () =
    Parallel.for 0 20000 (fun i -> Channel.send ch i)
    Channel.close ch

  let (total, _) = Parallel.both drain send
  println $"every value through the channel: {total}"
  0
