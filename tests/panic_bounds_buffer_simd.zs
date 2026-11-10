// A SIMD load from a Buffer in a for loop, its last lanes past the end: checked, as a read is
let ones (b: Buffer<u8>) (n: int) =
  let mutable s = 0
  for j in 0 .. n - 1 do
    s <- s + Mask16.count (U8x16.equal (U8x16.load b j) (U8x16.splat (u8 1)))
  s

let main () =
  let b = Buffer.create 16 (u8 1)
  println $"{ones b 1}"
  println $"{ones b 8}"
  0
