// for loops over a collection take a pattern, such as a tuple
let main () =
  for (k, v) in [ ("a", 1); ("b", 2) ] do
    print $"{k}={v} "
  println ""
  let mutable total = 0
  for (name, qty) in [| ("pen", 3); ("ink", 2) |] do
    total <- total + qty
    print $"{name} "
  println $"{total}"
  for (i, (a, b)) in List.indexed [ (1, 2); (3, 4) ] do
    print $"{i}:{a + b} "
  println ""
  0
