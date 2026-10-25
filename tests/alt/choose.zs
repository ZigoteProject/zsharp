// Alt.choose commits exactly one branch: the earliest that can happen now, else the first to
// become ready; the others leave the queues they waited in. A sync never meets itself. Under
// three producers and three consumers choosing between three channels, every value sent is
// received exactly once.

// a pseudo-random sequence (an LCG): the next state from this one
let next (x: int) = (x * 1103515245 + 12345) % 2147483648

let producer (chs: array<Ch<int>>) (p: int) (n: int) =
  task {
    let mutable r = p + 1
    for i in 1 .. n do
      r <- next r
      let v = p * n + i
      do! Ch.send chs.[r / 65536 % 3] v
      if r / 65536 % 7 = 0 then do! Task.yield ()
    return ()
  }

let consumer (chs: array<Ch<int>>) (seen: Buffer<bool>) (twice: ref<int>) (n: int) =
  task {
    let mutable sum = 0
    for i in 1 .. n do
      // rotated, so each channel is sometimes first
      let j = i % 3
      let! v =
        Alt.sync (Alt.choose [ Ch.take chs.[j]
            Ch.take chs.[(j + 1) % 3]
            Ch.take chs.[(j + 2) % 3] ])
      if seen.[v] then twice.Value <- twice.Value + 1
      seen.[v] <- true
      sum <- sum + v
    return sum
  }

let main () =
  println $"left bias: {Task.run (Alt.sync (Alt.choose [ Alt.always "a"; Alt.always "b" ]))}"

  // both have a giver waiting: the choice takes a's, and b's is still there
  let a = Ch.make ()
  let b = Ch.make ()
  let two =
    Task.run (Task.scope (fun s ->
        task {
          Task.start s (Ch.send a 1) |> ignore
          Task.start s (Ch.send b 2) |> ignore
          let! x =
            Alt.sync (Alt.choose [ Alt.map (fun x -> $"a {x}") (Ch.take a)
                Alt.map (fun x -> $"b {x}") (Ch.take b) ])
          let! y = Ch.receive b
          return $"took {x}, b still has {y}"
        }))
  println $"one of two: {two}"

  // a choice waiting on a and b commits on a: its taker on b is gone, so a send on b waits
  let left =
    Task.run (Task.scope (fun s ->
        task {
          Task.start s (Alt.sync (Alt.choose [ Ch.take a; Ch.take b ])) |> ignore
          do! Ch.send a 1
          return! Task.timeout 10 (Task.map (fun () -> "sent") (Ch.send b 5))
        }))
  println $"loser left b's queue: send on b: {left}"

  // alone on c, a choice to give or take there can't meet itself
  let c = Ch.make ()
  let branches =
    [ Alt.map (fun () -> "gave") (Ch.give c 1)
      Alt.map (fun (x: int) -> "took") (Ch.take c)
      Alt.map (fun () -> "timed out") (Alt.after 10) ]
  let self = Alt.choose branches
  println $"self: alone, choose [give c 1; take c; after 10]: {Task.run (Alt.sync self)}"

  let none: list<Alt<int>> = []
  println $"choose []: {Task.run (Task.timeout 5 (Alt.sync (Alt.choose none)))}"

  // both branches wait on one promise: it's delivered once
  let p = Task.promise ()
  let deliveries = ref 0
  let count (x: int) = deliveries.Value <- deliveries.Value + 1
  Task.run (Task.scope (fun s ->
      task {
        Task.start s (Alt.sync (Alt.choose [ Alt.map count (Alt.wait p)
              Alt.map count (Alt.wait p) ]))
        |> ignore
        Task.fulfill p 1
        do! Task.sleep 1
        return ()
      }))
  println $"two waits on one promise: {deliveries.Value} delivery"

  let n = 10000
  let chs = [| Ch.make (); Ch.make (); Ch.make () |]
  let seen = Buffer.create (3 * n + 1) false
  let twice = ref 0
  let sums =
    Task.run (Task.scope (fun s ->
        task {
          for q in 0 .. 2 do
            Task.start s (producer chs q n) |> ignore
          let x = Task.start s (consumer chs seen twice n)
          let y = Task.start s (consumer chs seen twice n)
          let z = Task.start s (consumer chs seen twice n)
          let! sx = Task.wait x
          let! sy = Task.wait y
          let! sz = Task.wait z
          return sx + sy + sz
        }))
  let mutable received = 0
  for v in 1 .. 3 * n do
    if seen.[v] then received <- received + 1
  println $"exactly once: {received} received, each value once: {twice.Value = 0}, sum {sums}"
  0
