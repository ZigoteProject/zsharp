// A for over a Map is one loop with its body in place: the same IR as Map.iter's
// (map_for.same-ir names that program).
let main () =
  let m = Map.add 2 "two" (Map.add 1 "one" Map.empty)
  for (k, v) in m do
    println $"{k} {v}"
  0
