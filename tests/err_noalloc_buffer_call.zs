// [<NoAlloc>] and a Buffer a call gives, written: the write takes the call's reference and drops
// it after, which may free the Buffer (the caller's may be the only other one)
let rec pass (n: int) (b: Buffer<int>) : Buffer<int> = if n = 0 then b else pass (n - 1) b

[<NoAlloc>]
let put (n: int) (b: Buffer<int>) : unit = (pass n b).[0] <- 5

let main () =
  let b = Buffer.create 2 0
  put 1 b
  println $"{b.[0]}"
  0
