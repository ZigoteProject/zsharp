// [<NoAlloc>] and a Buffer's element written: the overwritten element is dropped (a string may be
// freed there), and so is the Buffer passed (it may be the last reference)
[<NoAlloc>]
let put (b: Buffer<string>) (s: string) : unit = b.[0] <- s

let main () =
  let b : Buffer<string> = Buffer.empty
  Buffer.push "a" b
  put b "lit"
  println b.[0]
  0
