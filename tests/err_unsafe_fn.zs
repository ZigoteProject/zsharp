// [<Unsafe>] on a function: only unsafe code may call it, as Bytes.writer is
[<Unsafe>]
let poke (p: ptr<u8>) (x: u8) = unsafe (Ptr.write p x)

let main () =
  let p: ptr<u8> = unsafe (Ptr.alloc 1)
  poke p (u8 1)
  0
