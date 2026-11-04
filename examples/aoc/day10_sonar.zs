// Sonar Sweep (2021, day 1): how many depths are deeper than the one before; then the same over
// sums of three in a row
let input = "199\n200\n208\n210\n200\n207\n240\n269\n260\n263"

let depths = List.choose Int.parse (String.splitLines input)

let increases (xs: list<int>) =
  List.length (List.filter (fun (a, b) -> b > a) (List.zip xs (List.tail xs)))

let windows (xs: list<int>) =
  let arr = Array.ofList xs
  List.init (Array.length arr - 2) (fun i -> arr.[i] + arr.[i + 1] + arr.[i + 2])

let main () =
  println $"part 1: {increases depths}"
  println $"part 2: {increases (windows depths)}"
  0
