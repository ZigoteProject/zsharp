// Format specifiers and widths in interpolation (0024): .NET's standard numeric formats, with the
// invariant culture's text; a width pads, a negative one on the right
let main () =
  let ratio = 0.9745
  let flags = u32 207
  let name = "clang"
  println $"[{name,-10}] [{name,8}] [{ratio,10:F3}] [{ratio:F2}] [{ratio:F0}]"
  println $"{flags:X8} {flags:x} {255:B10} {42:D5} {-42:D5} {-1:X} {u8 255:X} {i8 -1:X}"
  println $"{1234567:N0} {1234567.891:N2} {7:N} {12:F} {0.125:F2} {0.375:F2} {2.5:F0} {-2.5:F0}"
  println $"{1234.5:E2} {0.000123:E} {0.1:G3} {1.0e21:G} {1234.5678:G6}"
  0
