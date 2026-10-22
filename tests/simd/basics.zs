// SIMD vectors: lane-wise arithmetic, loads and stores, reductions, masks, shuffles and
// conversions, at 128, 256 and 512 bits.

let dot (a: array<f32>) (b: array<f32>) : f32 =
  let n = Array.length a
  let mutable acc = F32x8.splat (f32 0.0)
  let mutable i = 0
  while i + 8 <= n do
    acc <- F32x8.mulAdd (F32x8.load a i) (F32x8.load b i) acc
    i <- i + 8
  let mutable total = F32x8.sum acc
  while i < n do
    total <- total + a.[i] * b.[i]
    i <- i + 1
  total

let main () =
  let a = F32x4.init (fun i -> f32 (i + 1))
  let b = F32x4.splat (f32 10.0)
  println $"{a} {a + b} {a * b - a} {-a} {b / a}"
  println $"sum {F32x4.sum a} min {F32x4.reduceMin a} max {F32x4.reduceMax (a * a)}"
  println $"lanes {F32x4.get a 2} {F32x4.set a 0 (f32 9.0)} {a = a} {a = b}"

  let xs = Array.init 20 (fun i -> f32 i)
  let ys = Array.init 20 (fun i -> f32 2.0)
  println $"dot {dot xs ys}"

  let mutable out = Array.create 8 (f32 0.0)
  out <- F32x4.store out 2 (F32x4.splat (f32 7.0))
  println $"store {out.[1]} {out.[2]} {out.[5]} {out.[6]}"

  let ints = I32x8.init (fun i -> i32 (i * 3 - 7))
  let m = I32x8.greaterThan ints (I32x8.splat (i32 0))
  println $"{ints} {m} any {Mask8.any m} all {Mask8.all m} count {Mask8.count m}"
  println $"select {I32x8.select m ints (I32x8.splat (i32 0))} abs {I32x8.abs ints}"
  println $"bits {(ints &&& I32x8.splat (i32 6))} {ints <<< 2} {ints >>> 1}"
  println $"shuffle {I32x8.shuffle ints (I32x8.splat (i32 100)) [| 0; 8; 1; 9; 2; 10; 3; 11 |]}"
  println $"convert {F32x8.ofI32x8 ints} {I32x8.ofF32x8 (F32x8.splat (f32 2.7))}"
  println $"divide {I32x8.splat (i32 100) / I32x8.init (fun i -> i32 (i + 1))}"

  let bytes = U8x16.init (fun i -> u8 (i * 20))
  println $"u8 {bytes + bytes} {U8x16.reduceMax bytes}"
  let wide = F64x8.init (fun i -> float i * 0.5)
  println $"f64x8 {F64x8.sqrt wide} {F64x8.sum wide} {F64x8.round (F64x8.splat 2.5)}"
  let arr = Array.init 3 (fun i -> F32x8.splat (f32 i))
  println $"array of vectors {arr.[2]} {F32x8.sum (arr.[1] + arr.[2])}"
