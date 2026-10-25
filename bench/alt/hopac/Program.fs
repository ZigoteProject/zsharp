// The Hopac twins of bench/alt/bench.zs: `HBench <name> [workers]` runs one once to warm up,
// then again, and prints `name ms checksum`.
open Hopac
open Hopac.Infixes
open System.Diagnostics

// sends from + 1 .. from + n on c
let producer (c: Ch<int>) from n =
  let rec go i = if i <= from + n then Ch.give c i >>= fun () -> go (i + 1) else Job.unit ()
  go (from + 1)

// sums n values of the event
let rec consume (e: Alt<int>) n (acc: int64) =
  if n = 0 then Job.result acc else e >>= fun x -> consume e (n - 1) (acc + int64 x)

let pingpong n =
  let ping = Ch ()
  let pong = Ch ()
  let rec ponger k = if k > 0 then Ch.take ping >>= fun x -> Ch.give pong (x + 1) >>= fun () -> ponger (k - 1) else Job.unit ()
  let rec pinger i acc =
    if i > n then Job.result acc
    else Ch.give ping i >>=. Ch.take pong >>= fun y -> pinger (i + 1) (acc + int64 y)
  Job.start (ponger n) >>=. pinger 1 0L

let fanin n =
  let c = Ch ()
  Job.forUpTo 0 9 (fun p -> Job.start (producer c (p * n) n)) >>=. consume (Ch.take c) (10 * n) 0L

let faninMailbox n =
  let m = Mailbox ()
  let post p =
    let rec go i = if i <= p * n + n then Mailbox.send m i >>= fun () -> go (i + 1) else Job.unit ()
    go (p * n + 1)
  Job.forUpTo 0 9 (fun p -> Job.start (post p)) >>=. consume (Mailbox.take m) (10 * n) 0L

let choose k total =
  let chs = Array.init k (fun _ -> Ch ())
  let each = total / k
  Job.forUpTo 0 (k - 1) (fun j -> Job.start (producer chs.[j] (j * each) each))
  >>=. consume (Alt.choose (Array.map Ch.take chs)) (k * each) 0L

let sieve primes =
  let first = Ch ()
  let rec numbers i = Ch.give first i >>= fun () -> numbers (i + 1)
  let filter p (input: Ch<int>) (output: Ch<int>) =
    let rec go () = Ch.take input >>= fun x -> (if x % p <> 0 then Ch.give output x :> Job<unit> else Job.unit ()) >>= go
    go ()
  let rec find n (c: Ch<int>) acc =
    if n = 0 then Job.result acc
    else
      Ch.take c >>= fun p ->
        let output = Ch ()
        Job.start (filter p c output) >>=. find (n - 1) output (acc + int64 p)
  Job.start (numbers 2) >>=. find primes first 0L

let ring size hops =
  let chs = Array.init size (fun _ -> Ch ())
  let winner = IVar ()
  let runner i =
    let next = chs.[(i + 1) % size]
    let rec go () = Ch.take chs.[i] >>= fun v -> if v = 0 then IVar.fill winner (int64 (i + 1)) else Ch.give next (v - 1) >>= go
    go ()
  Job.forUpTo 0 (size - 1) (fun i -> Job.start (runner i)) >>=. Ch.give chs.[0] hops >>=. IVar.read winner

let timeout n =
  let c = Ch ()
  let any = Ch.take c <|> (timeOutMillis 1000 ^->. 0)
  Job.start (producer c 0 n) >>=. consume any n 0L

let losers n =
  let a = Ch ()
  let b = Ch ()
  let wake = Ch ()
  Job.start (producer wake 0 n) >>=. consume (Ch.take a <|> Ch.take b <|> Ch.take wake) n 0L

let benches : Map<string, unit -> Job<int64>> =
  Map.ofList [
    "pingpong-ch", (fun () -> pingpong 1000000)
    "pingpong-alt", (fun () -> pingpong 1000000)
    "fanin-ch", (fun () -> fanin 100000)
    "fanin-mailbox", (fun () -> faninMailbox 100000)
    "choose-2", (fun () -> choose 2 1000000)
    "choose-8", (fun () -> choose 8 1000000)
    "choose-64", (fun () -> choose 64 1000000)
    "sieve", (fun () -> sieve 2000)
    "ring", (fun () -> ring 503 10000000)
    "timeout", (fun () -> timeout 1000000)
    "losers", (fun () -> losers 1000000) ]

[<EntryPoint>]
let main args =
  if args.Length > 1 then
    Scheduler.Global.setCreate { Scheduler.Create.Def with NumWorkers = Some (int args.[1]) }
  let name = if args.Length > 0 then args.[0] else "pingpong-ch"
  let make = benches.[name]
  run (make ()) |> ignore
  let sw = Stopwatch.StartNew ()
  let sum = run (make ())
  printfn "%s %d %d" name sw.ElapsedMilliseconds sum
  0
