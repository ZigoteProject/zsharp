// x86-64's intrinsics (Simd.X86): the SSE2 ones every x86-64 has, and SSSE3's in a function
// marked for it.
[<Target "ssse3">]
let ssse3 (v: f32x4) =
  println $"hadd {Simd.X86.hadd4 v v}"
  let bytes = I8x16.init (fun i -> i8 (i * 3))
  println $"pshufb {Simd.X86.shuffleBytes16 bytes (I8x16.init (fun i -> i8 (15 - i)))}"

let main () =
  let v = F32x4.init (fun i -> f32 (i + 1) * f32 (i + 1))
  let r = Simd.X86.rsqrt4 v
  // an estimate: 1 / sqrt x to within 1.5 * 2^-12
  let close =
    F32x4.lessThan (F32x4.abs (r * F32x4.sqrt v - F32x4.splat (f32 1.0))) (F32x4.splat (f32 0.001))
  println $"rsqrt close: {Mask4.all close}"
  println $"movemask {Simd.X86.movemask4 (v - F32x4.splat (f32 5.0))}"
  let a = I16x8.init (fun i -> i16 (i + 1))
  println $"pmaddwd {Simd.X86.maddPairs8 a a}"
  println $"psadbw {Simd.X86.sadBytes16 (U8x16.splat (u8 10)) (U8x16.splat (u8 3))}"
  ssse3 v
