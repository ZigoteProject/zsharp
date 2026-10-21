type Shape =
  | Circle of int
  | Rect of int * int
  | Dot

let area s =
  match s with
  | Circle r -> r
  | Rect (0, h) -> h
  | Dot -> 0

let main () = area Dot
