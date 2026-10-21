type Point = { x: int; y: int }

let f (p: Point) =
  match p with
  | { z = 1 } -> 1
  | _ -> 0

let main () = f { x = 1; y = 2 }
