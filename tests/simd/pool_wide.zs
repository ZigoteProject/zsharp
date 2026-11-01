// A vector stored in a list's cells: every object is 64-byte aligned by the system allocator, so
// the vector loads LLVM emits at their natural alignment are safe (tests/simd/pool.zs: the pool).
let main () =
  let before = Runtime.mallocs ()
  let vs = List.init 100 (fun i -> F32x4.splat (f32 i))
  println $"{List.sumBy F32x4.sum vs}, each its own malloc: {Runtime.mallocs () - before >= 100}"
  0
