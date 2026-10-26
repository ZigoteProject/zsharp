// import c of a header for the chip, and its C linked into the image (on a chip, size_t and
// pointers are 32 bits, so Port is 16 bytes)
[<Link "chip.c">]
import c "chip.h"

assert (sizeof<Port> = 16)

let main () =
  println $"{port_sum { moder = u32 1; otyper = u32 2; len = u32 3; buf = Ptr.toCPtr (Ptr.null ()) }}"
  0
