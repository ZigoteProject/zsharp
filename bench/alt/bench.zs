// Threading.Alt benchmarks: `bench <name>` runs one and prints `name ms allocs/op checksum`
// (bench/alt/run.sh runs them all, next to their Hopac twins in bench/alt/hopac).

// sends from + 1 .. from + n on c
let producer (c: Ch<int>) (from: int) (n: int) =
  task {
    for i in from + 1 .. from + n do
      do! Ch.send c i
    return ()
  }

// 1M round trips: i over one channel, i + 1 back over the other
let pingpong (events: bool) (n: int) =
  let ping = Ch.make ()
  let pong = Ch.make ()
  Task.scope (fun s ->
    task {
      Task.start s (task {
          for i in 1 .. n do
            if events then
              let! x = Alt.sync (Ch.take ping)
              do! Alt.sync (Ch.give pong (x + 1))
            else
              let! x = Ch.receive ping
              do! Ch.send pong (x + 1)
          return ()
        }) |> ignore
      let mutable sum = 0
      for i in 1 .. n do
        if events then
          do! Alt.sync (Ch.give ping i)
          let! y = Alt.sync (Ch.take pong)
          sum <- sum + y
        else
          do! Ch.send ping i
          let! y = Ch.receive pong
          sum <- sum + y
      return (n, sum)
    })

// 10 producers of 100k each into one channel (or mailbox), one consumer
let fanin (n: int) =
  let c = Ch.make ()
  Task.scope (fun s ->
    task {
      for p in 0 .. 9 do
        Task.start s (producer c (p * n) n) |> ignore
      let mutable sum = 0
      for i in 1 .. 10 * n do
        let! x = Ch.receive c
        sum <- sum + x
      return (10 * n, sum)
    })

let faninMailbox (n: int) =
  let m = Mailbox.make ()
  Task.scope (fun s ->
    task {
      for p in 0 .. 9 do
        Task.start s (task {
            for i in p * n + 1 .. p * n + n do
              Mailbox.post m i
              if i % 64 = 0 then do! Task.yield ()
            return ()
          }) |> ignore
      let take = Mailbox.take m
      let mutable sum = 0
      for i in 1 .. 10 * n do
        let! x = Alt.sync take
        sum <- sum + x
      return (10 * n, sum)
    })

// one consumer choosing between k channels, a producer on each: total messages in all
let choose (k: int) (total: int) =
  let chs = Array.init k (fun _ -> Ch.make ())
  let each = total / k
  Task.scope (fun s ->
    task {
      for j in 0 .. k - 1 do
        Task.start s (producer chs.[j] (j * each) each) |> ignore
      let any = Alt.choose (List.init k (fun j -> Ch.take chs.[j]))
      let mutable sum = 0
      for i in 1 .. k * each do
        let! x = Alt.sync any
        sum <- sum + x
      return (k * each, sum)
    })

// the prime sieve: numbers from 2 through a chain of filters, one per prime found
let sieve (primes: int) =
  Task.scope (fun s ->
    task {
      let first = Ch.make ()
      Task.start s (task {
          let mutable i = 2
          while true do
            do! Ch.send first i
            i <- i + 1
          return ()
        }) |> ignore
      let mutable c = first
      let mutable sum = 0
      for n in 1 .. primes do
        let! p = Ch.receive c
        sum <- sum + p
        let input = c
        let output = Ch.make ()
        Task.start s (task {
            while true do
              let! x = Ch.receive input
              if x % p <> 0 then do! Ch.send output x
            return ()
          }) |> ignore
        c <- output
      Task.cancel s
      return (primes, sum)
    })

// 503 tasks in a ring pass a token on, counting it down from hops: the one that gets 0 says who
// it is (1 to 503)
let ring (size: int) (hops: int) =
  let chs = Array.init size (fun _ -> Ch.make ())
  let winner = Task.promise ()
  Task.scope (fun s ->
    task {
      for i in 0 .. size - 1 do
        Task.start s (task {
            let next = chs.[(i + 1) % size]
            let mutable going = true
            while going do
              let! v = Ch.receive chs.[i]
              if v = 0 then
                Task.fulfill winner (i + 1)
                going <- false
              else
                do! Ch.send next (v - 1)
            return ()
          }) |> ignore
      do! Ch.send chs.[0] hops
      let! w = Task.wait winner
      Task.cancel s
      return (hops, w)
    })

// n rounds of choose [take c; after 1000]: the consumer waits each round (it was there first, and
// a waiting side goes on first), so a timer is set and dropped every round
let timeout (n: int) =
  let c = Ch.make ()
  Task.scope (fun s ->
    task {
      let consumer = Task.start s (task {
          let any = Alt.choose [ Ch.take c; Alt.map (fun () -> 0) (Alt.after 1000) ]
          let mutable sum = 0
          for i in 1 .. n do
            let! x = Alt.sync any
            sum <- sum + x
          return sum
        })
      Task.start s (producer c 0 n) |> ignore
      let! sum = Task.wait consumer
      return (n, sum)
    })

// n rounds of a consumer waiting in choose [take a; take b; take wake], woken by a give on wake:
// its takers on a and b are dropped each round
let losers (n: int) =
  let a = Ch.make ()
  let b = Ch.make ()
  let wake = Ch.make ()
  Task.scope (fun s ->
    task {
      let consumer = Task.start s (task {
          let any = Alt.choose [ Ch.take a; Ch.take b; Ch.take wake ]
          let mutable sum = 0
          for i in 1 .. n do
            let! x = Alt.sync any
            sum <- sum + x
          return sum
        })
      Task.start s (producer wake 0 n) |> ignore
      let! sum = Task.wait consumer
      return (n, sum)
    })

// n receives that time out at once (nothing is sent): each waiter is dropped by the cancellation
let cancel (n: int) =
  let c: Ch<int> = Ch.make ()
  task {
    let mutable missed = 0
    for i in 1 .. n do
      let! r = Task.timeout 0 (Ch.receive c)
      if Option.isNone r then missed <- missed + 1
    return (n, missed)
  }

// baselines without Alt: ping-pong over promises (one made, fulfilled and waited for per
// message each way), and turns of the loop
let promises (n: int) =
  let request = ref (Task.promise ())
  let reply = ref (Task.promise ())
  Task.scope (fun s ->
    task {
      Task.start s (task {
          for i in 1 .. n do
            let! x = Task.wait request.Value
            request.Value <- Task.promise ()
            Task.fulfill reply.Value (x + 1)
          return ()
        }) |> ignore
      let mutable sum = 0
      for i in 1 .. n do
        let r = Task.promise ()
        reply.Value <- r
        Task.fulfill request.Value i
        let! y = Task.wait r
        sum <- sum + y
      return (n, sum)
    })

let yields (n: int) =
  task {
    for i in 1 .. n do
      do! Task.yield ()
    return (n, n)
  }

let bench (name: string) : Task<int * int> =
  match name with
  | "pingpong-ch" -> pingpong false 1000000
  | "pingpong-alt" -> pingpong true 1000000
  | "fanin-ch" -> fanin 100000
  | "fanin-mailbox" -> faninMailbox 100000
  | "choose-2" -> choose 2 1000000
  | "choose-8" -> choose 8 1000000
  | "choose-64" -> choose 64 1000000
  | "sieve" -> sieve 2000
  | "ring" -> ring 503 10000000
  | "timeout" -> timeout 1000000
  | "losers" -> losers 1000000
  | "cancel" -> cancel 1000000
  | "promise" -> promises 1000000
  | "yield" -> yields 1000000
  | _ -> panic $"no bench {name}"

let main () =
  let name =
    match Environment.args () with
    | a :: _ -> a
    | [] -> "pingpong-ch"
  let a0 = Runtime.allocations ()
  let t0 = Runtime.ticks ()
  let (ops, sum) = Task.run (bench name)
  let t1 = Runtime.ticks ()
  let tenths = (Runtime.allocations () - a0) * 10 / ops
  println $"{name} {int (t1 - t0) / 1000000} {tenths / 10}.{tenths % 10} {sum}"
  0
