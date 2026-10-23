// Phase 10: a generator pipeline (seq { } through Seq.filter, Seq.map and Seq.sum, each a
// handler of Yield whose clause resumes last) against the same over a list (fused by Mono into
// one loop) and a loop written by hand. The clauses run where the generator yields: no
// continuation is captured, so the pipeline allocates nothing per element.

let squares (n: int) = seq { for i in 1 .. n do yield i }

let viaSeq (n: int) = squares n |> Seq.filter (fun x -> x % 3 = 0) |> Seq.map (fun x -> x * x) |> Seq.sum

let viaList (n: int) = List.init n (fun i -> i + 1) |> List.filter (fun x -> x % 3 = 0) |> List.map (fun x -> x * x) |> List.sum

let byHand (n: int) =
  let mutable total = 0
  for i in 1 .. n do
    if i % 3 = 0 then total <- total + i * i
  total

// a consumer that stops early: Seq.take's clause stops the generator after n elements
let firstTen (n: int) = squares n |> Seq.map (fun x -> x * 2) |> Seq.take 10 |> Seq.toList

// the best of 5 runs
let measure (name: string) (f: int -> int) (n: int) =
  let before = Runtime.allocations ()
  let r = f n
  let allocations = Runtime.allocations () - before
  let mutable best = u64 0
  for i in 1 .. 5 do
    let watch = Stopwatch.startNew ()
    f n |> ignore
    let ns = watch.ElapsedNanoseconds
    if i = 1 || ns < best then best <- ns
  println $"{name}: {r}, {allocations} allocations, {int (best / u64 1000)} us"

let main () =
  let n = 1000000
  measure "seq { } pipeline" viaSeq n
  measure "list pipeline (fused)" viaList n
  measure "loop by hand" byHand n
  let before = Runtime.allocations ()
  let ten = firstTen n
  println $"take 10 of {n}: {ten}, {Runtime.allocations () - before} allocations"
  0
