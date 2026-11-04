// [<NoAlloc>] and a Buffer a call gave, named twice before it's written: still the call's, so the
// write's drop may free it
let rec pass (n: int) (b: Buffer<int>) : Buffer<int> = if n = 0 then b else pass (n - 1) b

[<NoAlloc>]
let w (b: Buffer<int>) = (let c = pass 1 b in let d = c in d).[0] <- 7

let main () =
  w (Buffer.create 2 0)
  0
