// I Was Told There Would Be No Math (2015, day 2): each present's wrapping paper (its surface
// plus the smallest side) and ribbon (the smallest perimeter plus its volume), summed
let input = "2x3x4\n1x1x10\n4x5x6"

let dims (line: string) : list<int> = List.sort (List.choose Int.parse (String.split "x" line))

let paper (d: list<int>) =
  match d with
  | [ a; b; c ] -> 2 * (a * b + b * c + c * a) + a * b
  | _ -> 0

let ribbon (d: list<int>) =
  match d with
  | [ a; b; c ] -> 2 * (a + b) + a * b * c
  | _ -> 0

let main () =
  let presents = List.map dims (String.splitLines input)
  println $"part 1: {List.sumBy paper presents}"
  println $"part 2: {List.sumBy ribbon presents}"
  0
