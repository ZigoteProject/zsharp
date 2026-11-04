// Not Quite Lisp (2015, day 1): '(' goes up a floor and ')' down; the floor the instructions end
// on, and the position of the first instruction that enters the basement
let input = "()())(((((()))"

let main () =
  let floors =
    List.scan (fun floor c -> if c = '(' then floor + 1 else floor - 1) 0 (String.chars input)
  println $"part 1: {List.last floors}"
  match List.tryFindIndex (fun f -> f < 0) floors with
  | Some i -> println $"part 2: {i}"
  | None -> println "part 2: never in the basement"
  0
