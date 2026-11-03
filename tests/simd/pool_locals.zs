// Vectors in a record passed and returned by value, a tuple local and a loop's locals: none in
// a heap object, so the program keeps the pool (tests/simd/pool.zs: Bytes.appendJsonString)
type Pair = { lo: u8x16; hi: u8x16 }

let swap (p: Pair) : Pair = { lo = p.hi; hi = p.lo }

let quotes (b: array<u8>) : int =
  let mutable n = 0
  let mutable j = 0
  while j + 16 <= Array.length b do
    n <- n + Mask16.count (U8x16.equal (U8x16.load b j) (U8x16.splat (u8 34)))
    j <- j + 16
  n

let main () =
  let b = Array.init 64 (fun i -> u8 (if i % 5 = 0 then 34 else 65))
  let p = swap { lo = U8x16.splat (u8 1); hi = U8x16.load b 0 }
  let t = (U8x16.splat (u8 2), 3)
  let before = Runtime.mallocs ()
  let cells = List.init 1000 (fun i -> (i, "x"))
  println $"{quotes b} {U8x16.get p.lo 0} {snd t} {List.length cells}, from the pool: {Runtime.mallocs () - before < 10}"
  0
