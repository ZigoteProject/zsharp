// for over the library's maps and sets (0017), their functions over forEach, a builder's for over
// any collection, and the ofIter functions.
let wordCounts (words: list<string>) =
  let mutable counts = Map.empty
  for w in words do
    counts <- Map.add w (1 + Option.defaultValue 0 (Map.tryFind w counts)) counts
  counts

let main () =
  let counts = wordCounts [ "b"; "a"; "c"; "a"; "b"; "a" ]
  for (w, n) in counts do
    print $"{w}={n} "
  println ""
  println $"{Map.keys counts} {Map.values counts} {Map.count counts} {Map.toList counts}"
  let total = ref 0
  Map.iter (fun _ n -> total.Value <- total.Value + n) counts
  let s = Set.ofIter "hello"
  let mutable letters = ""
  for c in s do
    letters <- letters + string c
  println $"{total.Value} {letters} {Set.count s} {List.ofIter s}"
  let h = HashMap.add "x" 1 (HashMap.add "y" 2 HashMap.empty)
  let mutable sum = 0
  for (_, v) in h do
    sum <- sum + v
  println $"{sum} {Iter.length h} {List.sort (List.ofIter (HashSet.ofList [ 3; 1; 2 ]))}"
  let small = option {
    for (_, n) in counts do
      if n > 2 then return! None
  }
  let ok = result {
    for x in [| 1; 2 |] do
      if x > 5 then return! Error "too big"
  }
  println $"{Option.isSome small} {Result.isOk ok} {Map.ofIter [| (1, "one"); (2, "two") |]} {Array.toList (Array.ofIter (Some 4))}"
  0
