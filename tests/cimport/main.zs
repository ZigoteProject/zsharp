// import c: a header's structs, enums, #defines and functions, linked with its C source
[<Link "shapes.c">]
import c "shapes.h"

let main () =
  let p = point_add { x = 1; y = 2 } { x = 10; y = 20 }
  println $"point_add {p.x} {p.y}, ORIGIN {ORIGIN.x}"
  println $"size_area {size_area { w = f32 1.5; h = f32 4.0 }} scale {SHAPES_SCALE}"
  let r = rect_move { corner = p; size = { w = f32 2.0; h = f32 3.0 }; angle = 0.5 } 5 -5
  println $"rect_move {r.corner.x} {r.corner.y} {r.size.h} {r.angle}"
  println $"color_pack {color_pack WHITE} {color_pack { r = u8 1; g = u8 2; b = u8 3; a = u8 4 }}"
  println $"enum {SHAPE_CIRCLE} {SHAPE_SQUARE} {SHAPE_TRIANGLE} {String.ofCStr (shape_name SHAPE_TRIANGLE)} {is_square SHAPE_SQUARE}"
  println $"defines {SHAPES_VERSION} {SHAPES_MASK} {SHAPES_NAME} sum_to {sum_to 100}"
  let c = canvas_new 10 10
  canvas_paint c { x = 1; y = 1 } |> ignore
  canvas_paint c { x = 99; y = 1 } |> ignore
  println $"canvas painted {canvas_paint c ORIGIN}"
  canvas_free c
  0
