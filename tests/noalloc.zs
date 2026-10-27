// [<NoAlloc>] functions that pass (0012): numbers, a borrowed string, a record, a loop over an
// array it borrows; an option's None (a static cell) dropped and its Some's string kept, which
// frees nothing; a string interpolated into what's printed, which is its own text; an
// interpolation of one string, which is that string
type Point = { x: int; y: int }

[<NoAlloc>]
let step (p: Point) (s: string) : Point = { x = p.x + String.length s; y = p.y * 2 }

[<NoAlloc>]
let total (xs: array<int>) : int = Array.fold (fun acc x -> acc + x) 0 xs

[<NoAlloc>]
let orNone (o: option<string>) : string =
  match o with
  | None -> "none"
  | Some s -> s

[<NoAlloc>]
let shout (s: string) = println $"{s}!"

[<NoAlloc>]
let same (s: string) : string = $"{s}"

let main () =
  let p = step { x = 1; y = 2 } "abc"
  println $"{p.x} {p.y} {total [| 1; 2; 3 |]}"
  println (orNone None)
  shout "hey"
  println (same "as is")
  0
