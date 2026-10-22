// Generic constants: a top-level constant whose type has type variables is generic, as F#'s
// values are, so the empty collections are values (no `()`), at any type, twice in a function too
type Pair<'a, 'b> = { first: option<'a>; second: list<'b> }

// a generic constant of the program's own
let nothing : Pair<'a, 'b> = { first = None; second = [] }

let main () =
  let ages = Map.empty |> Map.add "ada" 36
  let names = Map.empty |> Map.add 1 "one" |> Map.add 2 "two"
  println $"{ages} {names}"
  let small = Set.empty |> Set.add 3 |> Set.add 1
  let words = Set.empty |> Set.add "b" |> Set.add "a"
  println $"{small} {words}"
  let counts = HashMap.empty |> HashMap.add "x" 1 |> HashMap.add "y" 2 |> HashMap.add "x" 3
  let flags = HashMap.empty |> HashMap.add 7 true
  println $"{HashMap.tryFind "x" counts} {HashMap.tryFind 7 flags} {HashMap.count counts} {HashMap.tryFind "z" (HashMap.empty: HashMap<string, int>)}"
  let p: Pair<int, string> = nothing
  let q: Pair<string, bool> = { nothing with second = [ true ] }
  println $"{p.first} {p.second} {q.first} {q.second}"
  0
