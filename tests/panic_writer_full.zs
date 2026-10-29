// writing past a fixed Writer's capacity panics, and writes nothing
let main () =
  let p: ptr<u8> = unsafe (Ptr.alloc 2)
  let w = unsafe (Bytes.writer p 2) |> Bytes.append b"ab"
  println (String.ofBytes (Bytes.written w))
  Bytes.put (u8 99) w |> ignore
  0
