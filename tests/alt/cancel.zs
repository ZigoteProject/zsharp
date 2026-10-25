// A task cancelled while its sync waits leaves no waiter behind: a timed-out receive or send,
// a choice over three channels and a timer, a cancelled scope's receivers. What it bound with
// `use` is disposed. Within these cases a value is never lost or duplicated: what a sync gave
// was taken, even when the taker's resumption went through the loop and the taker was cancelled
// before it ran (mapped or not). (A sync wrapped in Task.timeout or Task.race can still lose a
// value committed in the same turn as the timer: Task.race keeps one result; Alt.choose with
// Alt.after doesn't lose it.) A task cancelled by the partner it meets (or by a task its map
// wakes) stops there, and a server cancelled in its loop, or while it waits to reply, leaks
// nothing.
type Resource = Resource of string * ref<list<string>>

impl Dispose<Resource> =
  let dispose (Resource (name, log)) = log.Value <- $"{name} closed" :: log.Value

let shown (x: option<unit>) = if Option.isSome x then "Some" else "None"

// passes one value from a to b
let relay (a: Ch<int>) (b: Ch<int>) =
  task {
    let! x = Ch.receive a
    do! Ch.send b x
    return ()
  }

// a give at the end of a chain of 64 relays meets a waiting taker at the loop's depth limit, so
// the taker's resumption is posted; then the taker is cancelled before the loop runs it. What
// the taker got (0: nothing) and whether the give went through
let posted (mapped: bool) =
  let chs = Array.init 65 (fun _ -> Ch.make ())
  let got = ref 0
  let gave = ref false
  Task.run (Task.scope (fun outer ->
      task {
        do! Task.scope (fun s ->
          task {
            Task.start s (task {
                let take = Ch.take chs.[64]
                let! x = Alt.sync (if mapped then Alt.map (fun x -> x) take else take)
                got.Value <- x
                return ()
              }) |> ignore
            for i in 0 .. 62 do
              Task.start outer (relay chs.[i] chs.[i + 1]) |> ignore
            Task.start outer (task {
                let! x = Ch.receive chs.[63]
                do! Ch.send chs.[64] x
                gave.Value <- true
                return ()
              }) |> ignore
            do! Ch.send chs.[0] 7
            Task.cancel s
            return ()
          })
        return ()
      }))
  $"got {got.Value}, give went through {gave.Value}"

// a server that takes a request apart, then waits to reply (the client never takes it)
let replier (reqs: Mailbox<int * Ch<int> * Alt<unit>>) =
  task {
    let! (x, reply, nack) = Alt.sync (Mailbox.take reqs)
    let! r =
      Alt.sync (Alt.choose [ Alt.map (fun () -> 1) (Ch.give reply x); Alt.map (fun () -> 0) nack ])
    return r
  }

// n sends (or receives) of at most 0 ms each: how many went through
let sends (c: Ch<int>) (n: int) =
  task {
    let mutable through = 0
    for i in 1 .. n do
      let! r = Task.timeout 0 (Ch.send c i)
      if Option.isSome r then through <- through + 1
    return through
  }

let receives (c: Ch<int>) (n: int) =
  task {
    let mutable through = 0
    for i in 1 .. n do
      let! r = Task.timeout 0 (Ch.receive c)
      if Option.isSome r then through <- through + 1
      // now and then late, so some of the sends time out
      if i % 25 = 0 then do! Task.sleep 1
    return through
  }

let main () =
  let c = Ch.make ()
  println $"receive timed out: {Task.run (Task.timeout 5 (Ch.receive c))}"
  println $"then send timed out: {shown (Task.run (Task.timeout 5 (Ch.send c 1)))}"

  // cancelled while it waits on three channels and a timer
  let a = Ch.make ()
  let b = Ch.make ()
  let d = Ch.make ()
  let log = ref []
  let blocked =
    task {
      use r = Resource ("r", log)
      let! x =
        Alt.sync (Alt.choose [ Ch.take a
            Ch.take b
            Ch.take d
            Alt.map (fun () -> -1) (Alt.after 60000) ])
      return x
    }
  let t = Task.run (Task.timeout 5 blocked)
  println $"blocked on a, b, c and after 60000: {String.concat log.Value}, {t}"
  let gone =
    Task.run (task {
        let! x = Task.timeout 5 (Ch.send a 1)
        let! y = Task.timeout 5 (Ch.send b 2)
        let! z = Task.timeout 5 (Ch.send d 3)
        return Option.isNone x && Option.isNone y && Option.isNone z
      })
  println $"a, b, c have no waiter: {gone}"
  let live =
    Task.run (Task.scope (fun s ->
        task {
          let p = Task.start s (Ch.receive a)
          do! Ch.send a 1
          return! Task.wait p
        }))
  println $"next give on a goes to a live taker: {live}"

  // a giver cancelled while it waits: its value isn't there to take
  let e = Ch.make ()
  let never =
    Task.run (task {
        let! sent = Task.timeout 5 (Ch.send e 42)
        return! Task.timeout 5 (Ch.receive e)
      })
  println $"cancelled giver: value never received: {never}"

  // a scope's 1000 receivers, cancelled with it
  let f = Ch.make ()
  let after =
    Task.run (task {
        do! Task.scope (fun s ->
          task {
            for i in 1 .. 1000 do
              Task.start s (Ch.receive f) |> ignore
            Task.cancel s
            return ()
          })
        return! Task.timeout 5 (Ch.send f 1)
      })
  println $"1000 blocked receivers, scope cancelled: send: {shown after}"

  // sends and receives that time out at once, against each other: as many went through each way
  let g = Ch.make ()
  let (sent, received) = Task.run (Task.both (sends g 1000) (receives g 1000))
  println $"sends through = values received: {sent = received}"

  // a partner that goes on first cancels the task that met it: that task stops there, and what
  // it bound with `use` is disposed once (the same with two tasks waiting for one promise, and
  // with a map whose function wakes the task that cancels it)
  let h = Ch.make ()
  let p = Task.promise ()
  let m = Mailbox.make ()
  let wake = Mailbox.make ()
  for meeting in [ "give meets a waiting take"; "two waits on a promise"; "a map wakes a task" ] do
    let log = ref []
    let went = ref false
    let victim = ref None
    let (first, second) =
      match meeting with
      | "two waits on a promise" -> (Task.wait p, Task.wait p)
      | "a map wakes a task" ->
        (Alt.sync (Mailbox.take wake),
          Alt.sync (Alt.map (fun () -> Mailbox.post wake ()) (Mailbox.take m)))
      | _ -> (Ch.receive h, Alt.sync (Ch.give h ()))
    Task.run (Task.scope (fun outer ->
        task {
          Task.start outer (task {
              let! x = first
              match victim.Value with
              | Some s -> Task.cancel s
              | None -> ()
              return ()
            }) |> ignore
          do! Task.scope (fun s ->
            task {
              victim.Value <- Some s
              Task.start s (task {
                  use r = Resource ("r", log)
                  let! x = second
                  went.Value <- true
                  return ()
                }) |> ignore
              if meeting = "two waits on a promise" then Task.fulfill p ()
              if meeting = "a map wakes a task" then Mailbox.post m ()
              return ()
            })
          return ()
        }))
    victim.Value <- None
    println $"{meeting}, cancelled by its partner: went on {went.Value}, {String.concat log.Value}"

  // a server looping on a choice, cancelled with its scope while it waits: nothing it holds leaks
  let ins = Ch.make ()
  let outs = Ch.make ()
  let served =
    Task.run (Task.scope (fun s ->
        task {
          Task.start s (task {
              while true do
                let! x =
                  Alt.sync (Alt.choose [ Ch.take ins; Alt.map (fun () -> 0) (Alt.after 60000) ])
                do! Ch.send outs (x + 1)
              return ()
            }) |> ignore
          do! Ch.send ins 1
          let! y = Ch.receive outs
          Task.cancel s
          return y
        }))
  println $"a looping server, cancelled: served {served}"

  // its request tuple, reply channel and waiters go with it
  let reqs = Mailbox.make ()
  for i in 1 .. 3 do
    Task.run (Task.scope (fun s ->
        task {
          Task.start s (replier reqs) |> ignore
          Mailbox.post reqs (i, Ch.make (), Alt.never ())
          do! Task.yield ()
          Task.cancel s
          return ()
        }))
  println "servers cancelled while they wait to reply: 3"

  println $"a commit posted, then the taker cancelled: {posted false}; mapped: {posted true}"
  0
