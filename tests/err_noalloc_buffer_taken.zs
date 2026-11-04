// [<NoAlloc>] and a Buffer taken out of a value the write frees (Option.get, inlined): the write
// drops the Buffer's last reference after it
[<NoAlloc>]
let w (o: option<Buffer<int>>) : unit = (Option.get o).[0] <- 7

let main () =
  w (Some(Buffer.create 2 0))
  0
