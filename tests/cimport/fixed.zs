// import c of structs with array fields: fixed<T, N> inline, passed and returned by value
[<Link "fixed.c">]
import c "fixed.h"

// a span crosses as its data and its length
extern bytes_sum : span<u8> -> i32

let main () =
  let p = packet_fill (u8 3) 5
  println $"packet {p.data.[0]} {p.data.[15]} {p.len} {packet_sum p}"
  let mutable q = p
  q.data.[1] <- u8 100
  q.data.[2] += u8 1
  println $"sum {packet_sum q} {packet_sum p} {p = q} {p = p}"
  let c = cursor_make 7
  println $"cursor {cursor_kind c} {cursor_check c} {c.xdata}"
  let t = mat2_transpose { m = Fixed.init (fun i -> Fixed.init (fun j -> f32 (i * 2 + j))) }
  println $"mat2 {t.m.[0].[1]} {t.m.[1].[0]} {t.m}"
  let px = pixel_invert { rgb = Fixed.ofArray [| u8 1; u8 2; u8 3 |]; a = u8 4 }
  println $"pixel {px.rgb} {px.a}"
  let data = [| u8 1; u8 2; u8 3; u8 4; u8 5 |]
  println $"bytes {bytes_sum data} {bytes_sum data.[1..2]} {bytes_sum (String.bytes "AB")}"
  // a span over C memory, in unsafe: its lifetime is the code's to keep
  let fromC =
    unsafe
      let p: ptr<i32> = Ptr.alloc 4
      for i in 0 .. 3 do
        Ptr.write (Ptr.add p i) (i32 (i + 1))
      let r = Array.sum (Span.ofPtr p 4) + sum4 (Ptr.toCPtr p) * i32 10
      Ptr.free p
      r
  println $"from C memory {fromC}"
  0
