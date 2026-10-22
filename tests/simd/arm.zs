// aarch64's intrinsics (Simd.Arm), the NEON ones: test.sh builds it for aarch64 and runs it
// under qemu.
let main () =
  let v = F32x4.init (fun i -> f32 (i + 1) * f32 (i + 1))
  let r = Simd.Arm.rsqrtEstimate4 v
  let close = F32x4.lessThan (F32x4.abs (r * F32x4.sqrt v - F32x4.splat (f32 1.0))) (F32x4.splat (f32 0.01))
  println $"rsqrt close: {Mask4.all close}"
  println $"pairwise {Simd.Arm.pairwiseAdd4 v v}"
  let bytes = I8x16.init (fun i -> i8 (i * 3))
  println $"tbl {Simd.Arm.tableLookup16 bytes (I8x16.init (fun i -> i8 (15 - i)))}"
