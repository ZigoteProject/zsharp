// List pipelines from List.init are fused into one loop (no lists built) when their functions
// are pure; the results must be exactly those of the unfused pipeline.
let noisy x =
  print $"{x} "
  x

let main () =
  let r = 3
  let before = Runtime.allocations ()
  let total = List.init 200 (fun i -> i + r) |> List.map (fun x -> x * 3) |> List.filter (fun x -> x % 2 = 0) |> List.sum
  let count = List.init 50 (fun i -> i * i) |> List.filter (fun x -> x % 3 = 1) |> List.length
  let folded = List.init 10 (fun i -> i) |> List.fold (fun acc x -> acc * 2 + x) 0
  let floats = List.init 4 (fun i -> float i * 0.5) |> List.sumBy (fun x -> x * x)
  let empty = List.init 0 (fun i -> i) |> List.sum
  let allocated = Runtime.allocations () - before
  println $"{total} {count} {folded} {floats} {empty} allocations {allocated}"
  // not fused (the lambda prints): order of effects is kept
  let printed = List.init 3 (fun i -> i) |> List.map (fun x -> noisy x) |> List.sum
  println $"| {printed}"
  0
