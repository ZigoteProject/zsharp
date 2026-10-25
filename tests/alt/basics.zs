// Threading.Alt's basics: a Ch meets a giver with a taker (the side that waited goes on first),
// in order, and Ch.send/receive agree with Alt.sync on give/take; always, after and never, a
// biased choice, map, values that aren't Share, a Mailbox's order, and a promise as an event.

// a for loop of sends, and one of receives summing them
let sender (c: Ch<int>) (n: int) =
  task {
    for i in 1 .. n do
      do! Ch.send c i
    return ()
  }

let receiver (c: Ch<int>) (n: int) =
  task {
    let mutable sum = 0
    for i in 1 .. n do
      let! x = Ch.receive c
      sum <- sum + x
    return sum
  }

// the same through events
let giver (c: Ch<int>) (n: int) =
  task {
    for i in 1 .. n do
      do! Alt.sync (Ch.give c i)
    return ()
  }

let taker (c: Ch<int>) (n: int) =
  task {
    let mutable sum = 0
    for i in 1 .. n do
      let! x = Alt.sync (Ch.take c)
      sum <- sum + x
    return sum
  }

let main () =
  // the taker waits; the send meets it, and the taker goes on first
  let c = Ch.make ()
  Task.run (Task.scope (fun s ->
      task {
        Task.start s (task {
            let! x = Ch.receive c
            println $"taker got {x}"
            return ()
          }) |> ignore
        do! Ch.send c 7
        println "giver done"
        return ()
      }))

  // the giver waits
  Task.run (Task.scope (fun s ->
      task {
        Task.start s (task {
            do! Ch.send c 8
            println "giver done"
            return ()
          }) |> ignore
        let! x = Ch.receive c
        println $"taker got {x}"
        return ()
      }))

  // three givers wait, and are met in the order they came
  let fifo =
    Task.run (Task.scope (fun s ->
        task {
          for i in 1 .. 3 do
            Task.start s (Ch.send c i) |> ignore
          let! a = Ch.receive c
          let! b = Ch.receive c
          let! d = Ch.receive c
          return $"{a} {b} {d}"
        }))
  println $"fifo: {fifo}"

  let n = 100000
  let streamed =
    Task.run (Task.scope (fun s ->
        task {
          Task.start s (sender c n) |> ignore
          return! receiver c n
        }))
  println $"stream: {n} messages, sum {streamed}"
  let synced =
    Task.run (Task.scope (fun s ->
        task {
          Task.start s (giver c n) |> ignore
          return! taker c n
        }))
  println $"alt and send agree: {synced = streamed}"

  println $"always {Task.run (Alt.sync (Alt.always 3))}"
  let first =
    Alt.sync (Alt.choose [ Alt.map (fun () -> "after 0") (Alt.after 0); Alt.always "always" ])
  println $"after 0 before always: {Task.run first}"
  let timer =
    Alt.sync (Alt.choose [ Alt.map (fun (x: int) -> "never") (Alt.never ())
        Alt.map (fun () -> "timer") (Alt.after 5) ])
  println $"never loses to after 5: {Task.run timer}"
  println $"map: {Task.run (Alt.sync (Alt.map (fun x -> x * 2) (Alt.always 7)))}"

  // a ref and a closure: not Share, so no thread's channel could carry them
  let refs = Ch.make ()
  let funs = Ch.make ()
  let (r, f) =
    Task.run (Task.scope (fun s ->
        task {
          Task.start s (Ch.send refs (ref 5)) |> ignore
          Task.start s (Alt.sync (Ch.give funs (fun () -> 6))) |> ignore
          let! r = Ch.receive refs
          let! f = Alt.sync (Ch.take funs)
          return (r, f)
        }))
  println $"not Share: ref {r.Value}, closure {f ()}"

  // two posts before the loop runs, and one once the taker waits for it
  let m = Mailbox.make ()
  Mailbox.post m 1
  Mailbox.post m 2
  let got =
    Task.run (Task.scope (fun s ->
        task {
          let p = Task.start s (task {
              let! a = Alt.sync (Mailbox.take m)
              let! b = Alt.sync (Mailbox.take m)
              let! d = Alt.sync (Mailbox.take m)
              return $"{a} {b} {d}"
            })
          Mailbox.post m 3
          return! Task.wait p
        }))
  println $"mailbox: {got}"

  // a promise fulfilled while a sync waits on it, and one fulfilled already
  let later = Task.promise ()
  let already = Task.promise ()
  Task.fulfill already 4
  let (x, y) =
    Task.run (Task.scope (fun s ->
        task {
          let p = Task.start s (Alt.sync (Alt.wait later))
          Task.fulfill later 9
          let! x = Task.wait p
          let! y = Alt.sync (Alt.wait already)
          return (x, y)
        }))
  println $"promise: {x} later, {y} already"
  0
