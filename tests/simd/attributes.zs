// [<FastMath>]: a float reduction LLVM may reorder; [<Target>]: a function compiled for CPU
// features; [<Multiversion>]: a version for each, picked when it's first called.
[<FastMath>]
let sum (a: array<f32>) =
  let mutable s = f32 0.0
  for i in 0 .. Array.length a - 1 do
    s <- s + a.[i]
  s

[<Target "avx2,fma">]
let axpy (a: f32) (x: array<f32>) (y: array<f32>) : array<f32> =
  Array.init (Array.length x) (fun i -> a * x.[i] + y.[i])

[<Multiversion("avx2,fma", "sse4.2")>]
let dot (x: array<f32>) (y: array<f32>) : f32 =
  let mutable s = F32x8.splat (f32 0.0)
  for i in 0 .. 8 .. Array.length x - 8 do
    s <- F32x8.mulAdd (F32x8.load x i) (F32x8.load y i) s
  F32x8.sum s

let main () =
  let a = Array.init 1000 (fun i -> f32 (i % 10))
  println $"{sum a}"
  println $"{(axpy (f32 2.0) a a).[7]}"
  println $"{dot a a} {dot a a}"
