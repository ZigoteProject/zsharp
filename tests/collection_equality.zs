// Two maps, sets or hash maps with the same entries are equal (and hash the same) whatever order
// their entries were added in: their trees and buckets differ, their contents don't.
let main () =
  let a = Set.add "Show" (Set.add "Eq" Set.empty)
  let b = Set.add "Eq" (Set.add "Show" Set.empty)
  let c = Set.ofList [ "Eq"; "Show"; "Hash"; "Num" ]
  let d = Set.add "Num" (Set.add "Hash" (Set.add "Show" (Set.add "Eq" Set.empty)))
  println $"{a = b} {c = d} {hash c = hash d} {compare a b} {a = c}"
  let m = Map.ofList [ (1, "a"); (2, "b"); (3, "c") ]
  let n = Map.add 1 "a" (Map.add 3 "c" (Map.add 2 "b" Map.empty))
  println $"{m = n} {hash m = hash n} {compare m n} {m = Map.add 3 "d" n}"
  let h = HashMap.ofList [ (1, 2); (3, 4); (5, 6) ]
  let k = HashMap.ofList [ (5, 6); (3, 4); (1, 2) ]
  println $"{h = k} {hash h = hash k} {h = HashMap.add 5 7 k}"
  0
