// C structs by value in the shapes RISC-V's hard-float convention distinguishes (a float and an
// integer in a register each), and integers narrower than a register (run on every host, and
// cross-compiled, on riscv64 under qemu)
[<Link "mixed.c">]
import c "mixed.h"

let main () =
  let one = f1_double { f = f32 1.25 }
  println $"f1 {one.f}"
  let fi = fi_swap { f = f32 7.0; i = 3 }
  println $"fi {fi.f} {fi.i}"
  let id = id_add { i = 1; d = 2.5 } 10
  println $"id {id.i} {id.d}"
  let cf = cf_next { c = i8 -1; f = f32 1.0 }
  println $"cf {cf.c} {cf.f}"
  let fa = fa_swap { v = Fixed.ofArray [| f32 1.5; f32 2.5 |] }
  println $"fa {fa.v}"
  let nest = nest_bump { inner = { f = f32 1.0 }; i = 2 }
  println $"nest {nest.inner.f} {nest.i}"
  let ii = ii_swap { a = 1; b = -2 }
  println $"ii {ii.a} {ii.b}"
  let fii = fii_turn { f = f32 0.5; i = 2; j = -3 }
  println $"fii {fii.f} {fii.i} {fii.j}"
  let dp = dp_make 1.5
  println $"dp {dp.d} {dp_read dp 2}"
  println $"after floats {fi_after_floats 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 { f = f32 1.0; i = 2 } { f = f32 3.0 }}"
  println $"after ints {fi_after_ints 1 2 3 4 5 6 7 8 { f = f32 1.0; i = 2 } { i = 3; d = 4.0 } 5.0}"
  // each at its type's edge: a register's other bits must be the value's sign or zero
  println $"narrow {narrow_sum (i8 -128) (u8 255) (i16 -32768) (u16 65535) -2147483648 (u32 4294967295)}"
  println $"int {int_negate -2147483647} {int_negate 5}"
  println $"unsigned {unsigned_half (u32 4294967294)}"
  println $"short {short_negate (i16 -300)} {short_negate (i16 32767)}"
  0
