// used by types.sh
/// A point on the plane.
type Point = { x: int; y: int }

let shift (p: Point) (d: int) : Point = { p with x = p.x + d }

let main () =
  let q : option<Point> = Some(shift { x = 1; y = 2 } 3)
  0
