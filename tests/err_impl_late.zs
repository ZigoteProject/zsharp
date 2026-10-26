// An impl written by hand is used from where it's declared on (K9): a use before it would need
// the automatic derive, a second impl, so it's an error saying where the impl must go
type Point = { x: int; y: int }

let describe (p: Point) = $"point {p}"

impl Show<Point> =
  let show p = $"<{p.x},{p.y}>"

let main () =
  println (describe { x = 1; y = 2 })
  0
