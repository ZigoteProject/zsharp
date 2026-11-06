// [<NoAlloc>] and a Buffer sliced: the slice is a Buffer of its own over the same storage, a new
// object
[<NoAlloc>]
let head (b: Buffer<u8>) : Buffer<u8> = b.[0..1]

let main () =
  let b = Buffer.create 4 (u8 1)
  println $"{Buffer.length (head b)}"
  0
