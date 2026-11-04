// No Time for a Taxicab (2016, day 1): turns and steps on a grid from facing north; the
// distance to where the instructions end, and to the first place visited twice
let input = "R8, R4, R4, R8"

type Walk = { x: int; y: int; dir: int; seen: Set<int * int>; twice: option<int * int> }

let move (w: Walk) (instruction: string) : Walk =
  let turn = if String.startsWith "R" instruction then 1 else 3
  let steps =
    Option.defaultValue 0 (Int.parse (String.sub instruction 1 (String.length instruction - 1)))
  let dir = (w.dir + turn) % 4
  let (dx, dy) = List.item dir [ (0, 1); (1, 0); (0, -1); (-1, 0) ]
  let rec go (i: int) (w: Walk) =
    if i = 0 then
      w
    else
      let p = (w.x + dx, w.y + dy)
      let twice = if w.twice.IsNone && Set.contains p w.seen then Some p else w.twice
      go (i - 1) { w with x = fst p; y = snd p; seen = Set.add p w.seen; twice = twice }
  go steps { w with dir = dir }

let distance (p: int * int) =
  let size (n: int) = if n < 0 then -n else n
  size (fst p) + size (snd p)

let main () =
  let start = { x = 0; y = 0; dir = 0; seen = Set.ofList [ (0, 0) ]; twice = None }
  let w = List.fold move start (List.map String.trim (String.split "," input))
  println $"part 1: {distance (w.x, w.y)}"
  match w.twice with
  | Some p -> println $"part 2: {distance p}"
  | None -> println "part 2: no place twice"
  0
