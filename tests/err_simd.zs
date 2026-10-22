// An intrinsic needs its CPU feature: SSE3's haddps isn't in every x86-64.
let main () =
  let v = F32x4.splat (f32 1.0)
  println $"{Simd.X86.hadd4 v v}"
