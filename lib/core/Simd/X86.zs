/// x86-64's SIMD intrinsics: instructions the portable vectors don't name. Each needs its CPU
/// feature (SSE2's every x86-64 has): build with `--cpu`, or mark the function `[<Target>]` or
/// `[<Multiversion>]`. Its functions are built into the compiler.
module Simd.X86
