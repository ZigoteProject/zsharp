// import c of a header for the chip, and its C linked into the image (size_t is usize; on a chip
// it and pointers are 32 bits, so Port is 16 bytes)
[<Link "chip.c">]
import c "chip.h"

assert (sizeof<Port> = 16)

let main () =
  println $"{port_sum { moder = u32 1; otyper = u32 2; len = usize 3; buf = Ptr.toCPtr (Ptr.null ()) }}"
  0
