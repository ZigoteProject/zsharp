// Perfectly Spherical Houses in a Vacuum (2015, day 3): Santa follows the arrows on a grid,
// delivering to each house; then Santa and a robot take turns on the same arrows; the houses
// visited at least once
let input = "^v^v^v^v^v>>vv<<^^"

let step (pos: int * int) (c: char) =
  let (x, y) = pos
  match c with
  | '^' -> (x, y + 1)
  | 'v' -> (x, y - 1)
  | '>' -> (x + 1, y)
  | '<' -> (x - 1, y)
  | _ -> pos

let visited (moves: list<char>) : Set<int * int> = Set.ofList (List.scan step (0, 0) moves)

let main () =
  let moves = String.chars input
  println $"part 1: {Set.count (visited moves)}"
  let (santa, robot) = List.partition (fun (i, _) -> i % 2 = 0) (List.indexed moves)
  let both = Set.union (visited (List.map snd santa)) (visited (List.map snd robot))
  println $"part 2: {Set.count both}"
  0
