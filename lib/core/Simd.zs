/// SIMD vectors: a few numbers worked on at once, in one instruction where the CPU has it.
/// `f32x8` is 8 f32s, `u8x16` 16 bytes, and so on: every number type at 128, 256 and 512 bits
/// (`f32x4 f32x8 f32x16`, `f64x2 f64x4 f64x8`, `i8x16 i8x32 i8x64`, `i16x8`, `i32x4`, `i64x2`
/// and the unsigned ones at each width), as LLVM's vectors, which a target without them does
/// lane by lane. `+ - * / %` work lane by lane (integers wrap around, as SIMD instructions do;
/// integer division still panics on a zero), as do `&&& ||| ^^^` and a shift by an int on
/// integer vectors; `=` compares whole vectors. Comparing lane by lane gives a mask (`mask4`,
/// `mask8`, …).
///
/// Each type's functions are in a module named after it (`F32x8`, `U8x16`, `Mask8`), built
/// into the compiler: `splat`, `init`, `load` and `store` (from and into an array of its
/// numbers), `get` and `set` (a lane), `sum`, `min`, `max`, `reduceMin`, `reduceMax`, `abs`,
/// `equal`, `notEqual`, `lessThan`, `lessOrEqual`, `greaterThan`, `greaterOrEqual`, `select`,
/// `shuffle`, a conversion from each vector with as many lanes (`F32x8.ofI32x8`), and for
/// floats `sqrt`, `floor`, `ceil`, `round` and `mulAdd`. A mask's: `any`, `all`, `count`, `not`
/// and `get`. Target intrinsics are in `Simd.X86` and `Simd.Arm`.
module Simd
