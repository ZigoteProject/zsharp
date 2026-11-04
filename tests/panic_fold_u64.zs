// a u64 sum past the type's range isn't folded away: it overflows at run time, as written
let main () =
  println $"{0xFFFF_FFFF_FFFF_FFFF + u64 1}"
  0
