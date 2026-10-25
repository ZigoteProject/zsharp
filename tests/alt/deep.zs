// Long runs of syncs keep the stack and memory bounded: every continuation goes through
// Task.complete, which posts once they nest deeply, and polling, blocking and a sync's guards
// are loops. Rendezvous between two tasks and around a ring of 1000, a chain of 1000 nested
// guards, choices over 10,000 branches, 1,000,000 syncs that commit at once, 50,000 maps on
// one event, a map over a choice nested 50,000 deep, and a cascade of 50,000 nacks, each sync
// waiting for the one before it to give up.

let pinger (ping: Ch<int>) (pong: Ch<int>) (n: int) =
  task {
    let mutable total = 0
    for i in 1 .. n do
      do! Ch.send ping i
      let! x = Alt.sync (Ch.take pong)
      total <- total + x - i
    return total
  }

let ponger (ping: Ch<int>) (pong: Ch<int>) (n: int) =
  task {
    for i in 1 .. n do
      let! x = Ch.receive ping
      do! Alt.sync (Ch.give pong (x + 1))
    return ()
  }

// a ring member: passes the token on until it has gone round `hops` times, then a stop (a
// negative count of the members that have stopped) goes round once
let runner (chs: array<Ch<int>>) (i: int) (hops: int) (passed: ref<int>) =
  task {
    let n = Array.length chs
    let next = chs.[(i + 1) % n]
    let mutable running = true
    while running do
      let! v = Ch.receive chs.[i]
      if v < 0 then
        running <- false
        if -v < n - 1 then do! Ch.send next (v - 1)
      else if v = hops then
        passed.Value <- v
        running <- false
        do! Ch.send next (-1)
      else
        do! Ch.send next (v + 1)
    return ()
  }

let rec nest (n: int) : Alt<int> =
  if n = 0 then
    Alt.always 0
  else
    Alt.guard (task { return Alt.map (fun x -> x + 1) (nest (n - 1)) })

let rec ready (n: int) (acc: int) : Task<int> =
  task {
    let! x = Alt.sync (Alt.always 1)
    if n = 1 then return acc + x else return! ready (n - 1) (acc + x)
  }

// a sync waiting for prev (the nack of the one before it), or for quit under a nack of its own
// it posts to the box
let link (box: Mailbox<Alt<unit>>) (prev: Alt<unit>) (quit: Ch<unit>) =
  task {
    let mine =
      Alt.withNack (fun n ->
        Mailbox.post box n
        Alt.map (fun () -> 0) (Ch.take quit))
    return! Alt.sync (Alt.choose [ Alt.map (fun () -> 1) prev; mine ])
  }

let main () =
  let ping = Ch.make ()
  let pong = Ch.make ()
  let rounds =
    Task.run (Task.scope (fun s ->
        task {
          Task.start s (ponger ping pong 200000) |> ignore
          return! pinger ping pong 200000
        }))
  println $"ping-pong: {rounds} round trips"

  let chs = Array.init 1000 (fun _ -> Ch.make ())
  let passed = ref 0
  Task.run (Task.scope (fun s ->
      task {
        for i in 0 .. 999 do
          Task.start s (runner chs i 200000 passed) |> ignore
        do! Ch.send chs.[0] 0
        return ()
      }))
  println $"ring of 1000 tasks: token passed {passed.Value} times"

  println $"1000 nested guards and maps: {Task.run (Alt.sync (nest 1000))}"

  let quiet = Ch.make ()
  let takes = List.init 10000 (fun _ -> Alt.map (fun (x: int) -> "take") (Ch.take quiet))
  let wide = Alt.choose (List.append takes [ Alt.always "always" ])
  println $"choose over 10000 never-ready takes and always: {Task.run (Alt.sync wide)}"

  let many = Array.init 10000 (fun _ -> Ch.make ())
  let branches =
    List.init 10000 (fun i ->
      Alt.map (fun () -> if i = 9999 then "last" else "other") (Ch.take many.[i]))
  let last =
    Task.run (Task.scope (fun s ->
        task {
          let p = Task.start s (Alt.sync (Alt.choose branches))
          do! Ch.send many.[9999] ()
          return! Task.wait p
        }))
  println $"choose over 10000 channels, a give on the last: {last}"

  let looped =
    Task.run (task {
        let mutable total = 0
        for i in 1 .. 1000000 do
          let! x = Alt.sync (Alt.always 1)
          total <- total + x
        return total
      })
  println $"1000000 syncs on always in a for loop: {looped}"
  println $"1000000 syncs on always through return!: {Task.run (ready 1000000 0)}"

  let mutable mapped = Alt.always 0
  for i in 1 .. 50000 do
    mapped <- Alt.map (fun x -> x + 1) mapped
  println $"50000 maps on always: {Task.run (Alt.sync mapped)}"
  let m = Ch.make ()
  let mutable taken = Ch.take m
  for i in 1 .. 50000 do
    taken <- Alt.map (fun x -> x + 1) taken
  let blocked = taken
  let viaTake =
    Task.run (Task.scope (fun s ->
        task {
          let p = Task.start s (Alt.sync blocked)
          do! Ch.send m 0
          return! Task.wait p
        }))
  println $"50000 maps on a take that waits: {viaTake}"

  // a choice built a branch at a time, with a guard in it, nests (it can't be flattened)
  let mutable nested = Alt.guard (task { return Alt.always 0 })
  for i in 1 .. 50000 do
    nested <- Alt.choose [ nested; Alt.withNack (fun _ -> Alt.never ()) ]
  println $"a map over a choice nested 50000 deep: {Task.run (Alt.sync (Alt.map (fun x -> x + 1) nested))}"

  let box = Mailbox.make ()
  let quit = Ch.make ()
  let cascade =
    Task.run (Task.scope (fun s ->
        task {
          let first = Ch.make ()
          let mutable prev = Ch.take first
          let links = Buffer.empty
          for i in 1 .. 50000 do
            Buffer.push (Task.start s (link box prev quit)) links
            let! n = Alt.sync (Mailbox.take box)
            prev <- n
          do! Ch.send first ()
          let mutable total = 0
          for p in links do
            let! x = Task.wait p
            total <- total + x
          return total
        }))
  println $"a cascade of 50000 nacks: {cascade} gave up"
  0
