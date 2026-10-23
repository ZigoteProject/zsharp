/// A point on the grid.
type Point = { x: int; y: int }

/// The point moved right by dx.
let right (p: Point) (dx: int) = { p with x = p.x + dx }
