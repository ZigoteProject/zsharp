// Map / Set (persistent AVL trees) and HashMap (a copy-on-write value)
let rec height (m: Map<'k, 'v>) =
  match m with
  | MapLeaf -> 0
  | MapNode (l, _, _, r, _) -> 1 + max (height l) (height r)

let main () =
  let m = Map.ofList [ ("b", 2); ("a", 1); ("c", 3) ]
  let m2 = Map.add "a" 10 m |> Map.remove "c"
  println $"map {Map.toList m} -> {Map.toList m2}"
  println $"find {Map.tryFind "b" m} {Map.tryFind "z" m} {Map.find "a" m2} count {Map.count m}"
  println $"keys {Map.keys m} values {Map.values m} map {Map.toList (Map.map (fun _ v -> v * 100) m)}"
  // 100k keys inserted in order stay balanced; removing half keeps the rest
  let mutable big = Map.empty
  for i in 1 .. 100000 do
    big <- Map.add i (i * 2) big
  println $"big: count {Map.count big} height {height big} find {Map.tryFind 77777 big}"
  let mutable half = big
  for i in 1 .. 50000 do
    half <- Map.remove (2 * i) half
  println $"removed evens: count {Map.count half} height {height half} {Map.containsKey 2 half} {Map.containsKey 3 half} original {Map.count big}"
  let s = Set.ofList [ 3; 1; 2; 3 ]
  let t = Set.ofList [ 2; 3; 4 ]
  println $"set {Set.toList s} union {Set.toList (Set.union s t)} intersect {Set.toList (Set.intersect s t)} diff {Set.toList (Set.difference s t)}"
  println $"contains {Set.contains 2 s} {Set.contains 9 s} remove {Set.toList (Set.remove 1 s)}"
  // HashMap: a value, so the old map is unchanged after an add
  let h = HashMap.ofList [ ("x", 1); ("y", 2) ]
  let h2 = HashMap.add "x" 5 h
  println $"hash {HashMap.tryFind "x" h} {HashMap.tryFind "x" h2} {HashMap.count h2} {HashMap.tryFind "q" h}"
  let mutable counts = HashMap.empty
  for w in String.split " " "the cat and the hat and the bat" do
    counts <- HashMap.add w (1 + Option.defaultValue 0 (HashMap.tryFind w counts)) counts
  println $"words {List.sort (HashMap.toList counts)}"
  let mutable many = HashMap.empty
  for i in 1 .. 100000 do
    many <- HashMap.add i i many
  let before = Runtime.allocations ()
  many <- HashMap.add 5 0 many
  println $"many: {HashMap.count many} {HashMap.tryFind 5 many} {HashMap.tryFind 99999 many} {HashMap.containsKey 100001 many}"
  println $"unique add copies no bucket array: {Runtime.allocations () - before < 100}"
  println $"removed {HashMap.count (HashMap.remove 7 many)} {HashMap.count many}"
  0
