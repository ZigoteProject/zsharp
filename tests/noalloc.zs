// [<NoAlloc>] functions that pass (0012): numbers, a borrowed string, a record, a loop over an
// array it borrows; an option's None (a static cell) dropped and its Some's string kept, which
// frees nothing; a string interpolated into what's printed, which is its own text; an
// interpolation of one string, which is that string; a Buffer's numbers written in place, the
// Buffer a parameter's or a top-level value's (directly, and through a name for it), a record's
// field, an element of a Buffer of Buffers, the value written read from the same Buffer: each
// write frees nothing
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

let frame = Buffer.create 4 (u8 0)

[<NoAlloc>]
let mark (b: Buffer<u8>) (i: int) = b.[i] <- u8 7

[<NoAlloc>]
let markFrame () =
  frame.[1] <- u8 9
  let f = frame
  f.[2] <- u8 5

type Ring = { data: Buffer<u8>; head: ref<int> }

[<NoAlloc>]
let push (r: Ring) (x: u8) =
  r.data.[r.head.Value] <- x
  r.head.Value <- (r.head.Value + 1) % Buffer.length r.data

[<NoAlloc>]
let bump (counts: Buffer<int>) (k: int) = counts.[k] <- counts.[k] + 1

[<NoAlloc>]
let setCell (grid: Buffer<Buffer<u8>>) (r: int) (c: int) = grid.[r].[c] <- u8 1

let main () =
  let ring = { data = Buffer.create 2 (u8 0); head = ref 0 }
  push ring (u8 4)
  push ring (u8 5)
  push ring (u8 6)
  let counts = Buffer.create 2 0
  bump counts 1
  bump counts 1
  let grid = Buffer.ofArray [| Buffer.create 2 (u8 0); Buffer.create 2 (u8 0) |]
  setCell grid 1 0
  println $"{ring.data.[0]} {ring.data.[1]} {counts.[1]} {grid.[1].[0]}"
  let b = Buffer.create 2 (u8 0)
  mark b 0
  markFrame ()
  println $"{b.[0]} {frame.[1]} {frame.[2]}"
  let p = step { x = 1; y = 2 } "abc"
  println $"{p.x} {p.y} {total [| 1; 2; 3 |]}"
  println (orNone None)
  shout "hey"
  println (same "as is")
  0
