// [<NoAlloc>] functions that pass (0012): numbers, a borrowed string, a record, a loop over an
// array it borrows
type Point = { x: int; y: int }

[<NoAlloc>]
let step (p: Point) (s: string) : Point = { x = p.x + String.length s; y = p.y * 2 }

[<NoAlloc>]
let total (xs: array<int>) : int = Array.fold (fun acc x -> acc + x) 0 xs

let main () =
  let p = step { x = 1; y = 2 } "abc"
  println $"{p.x} {p.y} {total [| 1; 2; 3 |]}"
  0
