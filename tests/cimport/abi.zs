// C structs by value in every shape the calling conventions distinguish (run on x86-64 and,
// cross-compiled, on aarch64 under qemu)
[<Link "abi.c">]
import c "abi.h"

let main () =
  let c = c4_swap { r = u8 1; g = u8 2; b = u8 3; a = u8 4 }
  println $"c4 {c.r} {c.g} {c.b} {c.a}"
  let p = p3_shift { x = 1; y = 2; z = 3 } 10
  println $"p3 {p.x} {p.y} {p.z}"
  let f = f4_scale { a = f32 1.0; b = f32 2.0; c = f32 3.0; d = f32 4.0 } (f32 0.5)
  println $"f4 {f.a} {f.b} {f.c} {f.d}"
  let d = d2_swap { a = 1.5; b = 2.5 }
  println $"d2 {d.a} {d.b}"
  let m = mix_add { a = 1.0; b = f32 2.0 } 0.5
  println $"mix {m.a} {m.b}"
  let b = big_sum { a = 1; b = 2.0; c = 3.0 } { a = 10; b = 20.0; c = 30.0 }
  println $"big {b.a} {b.b} {b.c}"
  let all =
    many { a = f32 1.0; b = f32 0.0; c = f32 0.0; d = f32 2.0 } { a = 3.0; b = 4.0 } { a = 5.0; b = f32 6.0 } { a = 7; b = 0.0; c = 8.0 } { x = 9; y = 0; z = 10 } { r = u8 11; g = u8 0; b = u8 0; a = u8 12 }
  println $"many {all}"
  let six =
    d2_six { a = 1.0; b = 2.0 } { a = 3.0; b = 4.0 } { a = 5.0; b = 6.0 } { a = 7.0; b = 8.0 } { a = 9.0; b = 1.0 } { a = 2.0; b = 3.0 }
  println $"d2 six {six}"
  println $"p3 after {p3_after 1 2 3 4 5 { x = 6; y = 7; z = 8 } 9}"
  let ba = big_after 1 2 3 4 { x = 5; y = 6; z = 7 } 8
  println $"big after {ba.a} {ba.b} {ba.c}"
  0
