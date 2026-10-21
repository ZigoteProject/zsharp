// A first Z# program: functions, lists, pattern matching and string interpolation.
// Run with: zs run examples/simple.zs

let greet name = $"Hello, {name}!"

let grade score =
  match score with
  | s when s >= 90 -> "A"
  | s when s >= 75 -> "B"
  | s when s >= 50 -> "C"
  | _ -> "F"

let average (xs: list<int>) = float (List.sum xs) / float (List.length xs)

let main () =
  println (greet "Z#")
  let scores = [ ("ada", 95); ("alan", 72); ("grace", 88); ("linus", 40) ]
  for (name, score) in scores do
    println $"{name}: {score} ({grade score})"
  let points = List.map snd scores
  println $"average {average points}, best {List.max points}"
  let passed = scores |> List.filter (fun (_, s) -> s >= 50) |> List.map fst
  println $"passed: {passed}"
  0
