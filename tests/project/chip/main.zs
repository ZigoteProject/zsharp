// built for the project's target (zs.toml), its C source linked, its heap 4K: a map of 50 entries
// fits, one of 500 doesn't
extern answer : unit -> c_int

let main () =
  println $"answer {answer ()}"
  let small = Map.ofList [ for i in 1 .. 50 -> (i, i) ]
  println $"{Map.count small} entries fit"
  let big = Map.ofList [ for i in 1 .. 500 -> (i, i) ]
  println $"{Map.count big} entries fit"
  0
