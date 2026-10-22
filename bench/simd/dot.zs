// The dot product of two arrays of f32, 8 lanes at a time (with a scalar tail), many times
// over: phase 8's exit test against dot.c, which uses AVX or NEON intrinsics.
let dot (a: array<f32>) (b: array<f32>) : f32 =
  let n = Array.length a
  let mutable acc0 = F32x8.splat (f32 0.0)
  let mutable acc1 = F32x8.splat (f32 0.0)
  let mutable i = 0
  // two accumulators, so consecutive multiply-adds don't wait for each other
  while i + 16 <= n do
    acc0 <- F32x8.mulAdd (F32x8.load a i) (F32x8.load b i) acc0
    acc1 <- F32x8.mulAdd (F32x8.load a (i + 8)) (F32x8.load b (i + 8)) acc1
    i <- i + 16
  let mutable total = F32x8.sum (acc0 + acc1)
  while i < n do
    total <- total + a.[i] * b.[i]
    i <- i + 1
  total

let main () =
  let n = 4096
  let a = Array.init n (fun i -> f32 (i % 7) * f32 0.25)
  let b = Array.init n (fun i -> f32 (i % 5) * f32 0.5)
  let mutable s = f32 0.0
  for _ in 1 .. 200000 do
    s <- s + dot a b
  println $"{s}"
