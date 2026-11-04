// import c on the providers' protocol (0001): the header's declarations as a module, named
// here, with the C signatures as docs; the C code is linked by the bare import's [<Link>] form or
// a package's [c], here zs.toml's
module Shapes = import c "shapes.h"

let main () =
  let a: Shapes.Point = { x = 1.0; y = 2.0 }
  let b: Shapes.Point = { x = 4.0; y = 6.0 }
  println $"{Shapes.rect_area a b} {Shapes.manhattan -3 4} {Shapes.MAX_CORNERS} {Shapes.UNIT_AREA}"
  0
