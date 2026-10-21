extern printf : cstr -> ... -> c_int

type Point = { x: int; y: int }

type Shape =
  | Circle of center: Point * radius: int
  | Rect of Point * Point
  | Dot

let area s =
  match s with
  | Circle (_, r) -> 3 * r * r
  | Rect (a, b) -> (b.x - a.x) * (b.y - a.y)
  | Dot -> 0

let swap p = match p with (a, b) -> (b, a)

let classify n =
  match n with
  | 0 -> "zero"
  | 1 | 2 | 3 -> "small"
  | n when n < 0 -> "negative"
  | _ -> "big"

let both a b =
  match (a, b) with
  | (true, true) -> 3
  | (true, false) | (false, true) -> 1
  | (false, false) -> 0

let moved p = { p with x = p.x + 10 }

let main () =
  let p = { x = 1; y = 2 }
  let q = moved p
  printf "q = (%ld, %ld)\n" q.x q.y |> ignore
  printf "areas: %ld %ld %ld\n" (area (Circle (p, 2))) (area (Rect (p, { x = 4; y = 6 }))) (area Dot) |> ignore
  let (a, b) = swap (1, true)
  printf "swap: %d %ld\n" a b |> ignore
  printf "%s %s %s %s\n" (classify 0) (classify 2) (classify (-5)) (classify 99) |> ignore
  printf "both: %ld %ld %ld\n" (both true true) (both false true) (both false false) |> ignore
  let r = Rect (p, { x = 4; y = 6 })
  match r with
  | Rect (c, _) as whole when c.x = 1 -> printf "as-pattern ok, area %ld\n" (area whole) |> ignore
  | _ -> printf "bad\n" |> ignore
  0
