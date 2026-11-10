// [<NoAlloc>] and a vector stored into an array: the array is copied first when anything else
// holds it, as a.[i] <- v's is
[<NoAlloc>]
let put (a: array<f32>) (v: f32x4) : array<f32> = F32x4.store a 0 v

let main () =
  let a = put (Array.create 4 (f32 0.0)) (F32x4.splat (f32 1.0))
  println $"{a.[0]}"
  0
