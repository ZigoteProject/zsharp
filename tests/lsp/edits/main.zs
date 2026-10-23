open Shapes

type Shape =
  | Circle of int
  | Square of int

let area (s: Shape) =
  match s with
  | Circle r -> 3 * r * r

let numbers () = parse "1"

let main () =
  let p = { x = 1; y = 2 }
  let { x = a } = p
  let q = right p 3
  println $"{p.x} {a} {q.x} {area (Square 2)}"
  0
