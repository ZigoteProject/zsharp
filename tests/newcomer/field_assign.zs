// F#/C: assigning to a record field; a record is a value, so build a new one with { p with x = … }
type Point = { x: int; y: int }

let main () =
  let p = { x = 1; y = 2 }
  p.x <- 5
  p.x
