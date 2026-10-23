// The program tests/iter/map_for.zs must compile to, IR for IR.
let main () =
  let m = Map.add 2 "two" (Map.add 1 "one" Map.empty)
  Map.iter (fun k v -> println $"{k} {v}") m
  0
