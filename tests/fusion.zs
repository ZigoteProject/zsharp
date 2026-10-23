// Pipelines of maps and filters (from List.init, a list, Array.init or an array) are fused into
// one loop, building no intermediate lists or arrays, when their functions are pure; the
// results must be exactly those of the unfused pipeline.
let noisy x =
  print $"{x} "
  x

let basics () =
  let r = 3
  let before = Runtime.allocations ()
  let total =
    List.init 200 (fun i -> i + r)
    |> List.map (fun x -> x * 3)
    |> List.filter (fun x -> x % 2 = 0)
    |> List.sum
  let count = List.init 50 (fun i -> i * i) |> List.filter (fun x -> x % 3 = 1) |> List.length
  let folded = List.init 10 (fun i -> i) |> List.fold (fun acc x -> acc * 2 + x) 0
  let floats = List.init 4 (fun i -> float i * 0.5) |> List.sumBy (fun x -> x * x)
  let empty = List.init 0 (fun i -> i) |> List.sum
  let allocated = Runtime.allocations () - before
  println $"{total} {count} {folded} {floats} {empty} allocations {allocated}"
  // not fused (the lambda prints): order of effects is kept
  let printed = List.init 3 (fun i -> i) |> List.map (fun x -> noisy x) |> List.sum
  println $"| {printed}"

// A list or an array as the source, iter as the consumer, and pipelines that build one list or
// array: the same results as unfused, with fewer (or no) intermediate lists and arrays.
let more () =
  let xs = [ 1; 2; 3; 4; 5; 6 ]
  let a = [| 1.5; 2.5; 3.5 |]
  let before = Runtime.allocations ()
  let fromList = xs |> List.map (fun x -> x * x) |> List.filter (fun x -> x % 2 = 0) |> List.sum
  let counted = xs |> List.filter (fun x -> x > 2) |> List.length
  let fromArray = a |> Array.map (fun x -> x * 2.0) |> Array.sum
  let folded =
    a |> Array.toList |> List.map (fun x -> x + 1.0) |> List.fold (fun acc x -> acc * x) 1.0
  let allocated = Runtime.allocations () - before
  println $"{fromList} {counted} {fromArray} {folded} allocations {allocated}"
  // iter: a consumer that prints; stages that can't panic run in the same loop
  let before = Runtime.allocations ()
  xs
  |> List.filter (fun x -> x % 2 = 1)
  |> List.map (fun x -> float x * 0.5)
  |> List.iter (fun h -> print $"{h} ")
  a |> Array.map (fun x -> x - 1.0) |> Array.iter (fun x -> print $"{x} ")
  println $"allocations {Runtime.allocations () - before}"
  // a stage that could panic (overflow) isn't fused with a consumer that prints: all of it runs
  // first, as written
  let before = Runtime.allocations ()
  xs |> List.map (fun x -> x * 10) |> List.iter (fun x -> print $"{x} ")
  println $"allocations {Runtime.allocations () - before > 0}"
  // pipelines building one list or array: only the result is allocated
  let before = Runtime.allocations ()
  let squares = List.init 5 (fun i -> i * i) |> List.map (fun x -> x + 1)
  let evens = xs |> List.map (fun x -> x * 3) |> List.filter (fun x -> x % 2 = 0)
  let scaled = a |> Array.map (fun x -> x * 10.0) |> Array.map (fun x -> x + 0.5)
  let empty = [||] |> Array.map (fun (x: f64) -> x + 1.0) |> Array.map (fun x -> x * 2.0)
  let allocated = Runtime.allocations () - before
  println $"{squares} {evens} {Array.toList scaled} {Array.length empty} allocations {allocated}"

let main () =
  basics ()
  more ()
  0
