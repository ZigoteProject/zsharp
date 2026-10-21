// idiomatic list processing: build, map, filter, sum 200 elements, 20 times (heap allocation)
let main () =
  let t0 = Runtime.ticks ()
  let mutable total = 0
  for r in 1 .. 20 do
    total <- total + (List.init 200 (fun i -> i + r) |> List.map (fun x -> x * 3) |> List.filter (fun x -> x % 2 = 0) |> List.sum)
  let t1 = Runtime.ticks ()
  println $"pipeline result={total} ticks={t1 - t0}"
  0
