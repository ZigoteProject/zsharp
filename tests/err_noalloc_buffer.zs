// [<NoAlloc>] and a Buffer's element written: the overwritten element is dropped (a string may be
// freed there); the Buffer, a parameter, is borrowed by the write and not dropped
[<NoAlloc>]
let put (b: Buffer<string>) (s: string) : unit = b.[0] <- s

let main () =
  let b : Buffer<string> = Buffer.empty
  Buffer.push "a" b
  put b "lit"
  println b.[0]
  0
