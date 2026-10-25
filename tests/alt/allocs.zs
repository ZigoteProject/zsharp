// A message through a channel allocates the same whatever the stream's length (Ch.take's event
// is made once, with the channel, so syncing on it costs only the sync), and a sync's
// dropped branches give back what they took: a timer set and dropped every round, or a taker
// left behind a waiter that stays at the head of its queue (compacted away), takes no more
// system memory in the second half of a run than it had by the first. A branch under Alt.map
// that can't happen allocates nothing, and tasks that finish oldest first, or drop their wait
// on a promise oldest first, cost the same each however many there are.

let sender (c: Ch<int>) (n: int) =
  task {
    for i in 1 .. n do
      do! Ch.send c i
    return ()
  }

// through Ch.receive, or through Alt.sync (Ch.take c), whose event isn't made afresh
let receiver (viaTake: bool) (c: Ch<int>) (n: int) =
  task {
    let mutable sum = 0
    for i in 1 .. n do
      let! x = if viaTake then Alt.sync (Ch.take c) else Ch.receive c
      sum <- sum + x
    return sum
  }

// sends after a turn of the loop each, so the other side is waiting by then
let lateSender (c: Ch<int>) (n: int) =
  task {
    for i in 1 .. n do
      do! Task.yield ()
      do! Ch.send c i
    return ()
  }

// allocations per message of a stream of n
let perMessage (viaTake: bool) (n: int) =
  let c = Ch.make ()
  let before = Runtime.allocations ()
  Task.run (Task.scope (fun s ->
      task {
        Task.start s (sender c n) |> ignore
        return! receiver viaTake c n
      })) |> ignore
  (Runtime.allocations () - before) / n

// 2n rounds of choose [take c; after 60000], each waiting until the giver comes (a timer set and
// dropped every round): the system memory taken in the second n
let timers (n: int) =
  let c = Ch.make ()
  Task.run (Task.scope (fun s ->
      task {
        Task.start s (lateSender c (2 * n)) |> ignore
        let mutable mid = 0
        for i in 1 .. 2 * n do
          if i = n + 1 then mid <- Runtime.mallocs ()
          let! x = Alt.sync (Alt.choose [ Ch.take c; Alt.map (fun () -> 0) (Alt.after 60000) ])
          ()
        return Runtime.mallocs () - mid
      }))

// 2n rounds of choose [take a; take b; take wake] woken by wake, while another task waits on
// a throughout: a's queue keeps that live waiter at its head, and the dropped ones behind it
let losers (n: int) =
  let a = Ch.make ()
  let b = Ch.make ()
  let wake = Ch.make ()
  Task.run (Task.scope (fun s ->
      task {
        Task.start s (Ch.receive a) |> ignore
        Task.start s (lateSender wake (2 * n)) |> ignore
        let mutable mid = 0
        for i in 1 .. 2 * n do
          if i = n + 1 then mid <- Runtime.mallocs ()
          let! x = Alt.sync (Alt.choose [ Ch.take a; Ch.take b; Ch.take wake ])
          ()
        let taken = Runtime.mallocs () - mid
        do! Ch.send a 1
        return taken
      }))

// n syncs on a choice of k takes (each under Alt.map, or not), only the last of which has a
// giver waiting: allocations per sync
let choice (mapped: bool) (k: int) (n: int) =
  let chs = Array.init k (fun _ -> Ch.make ())
  let any =
    Alt.choose (List.init k (fun j ->
        if mapped then Alt.map (fun (x: int) -> x + 1) (Ch.take chs.[j]) else Ch.take chs.[j]))
  Task.run (Task.scope (fun s ->
      task {
        Task.start s (sender chs.[k - 1] n) |> ignore
        do! Task.yield ()
        let before = Runtime.allocations ()
        for i in 1 .. n do
          let! x = Alt.sync any
          ()
        return (Runtime.allocations () - before) / n
      }))

// n tasks, each in a choice of its own channel and a promise that's never fulfilled (or only its
// channel), woken oldest first: so each is the oldest left on the scope's cancellation, and on
// the promise, when it finishes. Allocations per task
let oldestFirst (onPromise: bool) (n: int) =
  let chs = Array.init n (fun _ -> Ch.make ())
  let pr: Promise<int> = Task.promise ()
  let before = Runtime.allocations ()
  Task.run (Task.scope (fun s ->
      task {
        for i in 0 .. n - 1 do
          let own = Ch.take chs.[i]
          Task.start s (Alt.sync (if onPromise then Alt.choose [ Alt.wait pr; own ] else own))
          |> ignore
        for i in 0 .. n - 1 do
          do! Ch.send chs.[i] 1
        return ()
      }))
  (Runtime.allocations () - before) / n

let main () =
  println $"send/receive: {perMessage false 1000} and {perMessage false 100000} allocations per message for 1,000 and 100,000 messages"
  println $"Alt.sync (Ch.take c) in place of Ch.receive: {perMessage true 100000 - perMessage false 100000} allocations per message more"
  println $"take or after 60000, 2 x 100000 rounds: second half took system memory: {timers 100000 > 0}"
  println $"losers behind a live head waiter, 2 x 100000 rounds: second half took system memory: {losers 100000 > 0}"
  let plain = choice false 64 10000
  println $"64 branches under Alt.map, the last ready: {choice true 64 10000 - plain} allocation per sync more than without (the commit's)"
  println $"1,000 and 10,000 tasks finishing oldest first: {oldestFirst false 1000} and {oldestFirst false 10000} allocations each"
  println $"and dropping their wait on a promise: {oldestFirst true 1000} and {oldestFirst true 10000} allocations each"
  0
