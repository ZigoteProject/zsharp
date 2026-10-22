// F#: a match that forgets a case is an error in Z#, not a warning
type Shape =
  | Circle of int
  | Rect of int * int
  | Dot

let area s =
  match s with
  | Circle r -> 3 * r * r
  | Rect (w, h) -> w * h

let main () = area Dot
