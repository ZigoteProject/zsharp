// [<NoAlloc>] and a Buffer chosen by a match: one arm takes it out of the union value the write
// frees (the other's a top-level Buffer, which would be fine), so the write may free it
type Shape =
  | Box of Buffer<int>
  | Empty

let frame = Buffer.create 2 0

[<NoAlloc>]
let w (s: Shape) = (match s with | Box b -> b | Empty -> frame).[0] <- 7

let main () =
  w (Box(Buffer.create 2 0))
  0
