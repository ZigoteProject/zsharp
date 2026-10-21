// Phase 3: modules (files next to the main file), open, qualified names, private
open Geometry

let main () =
  let s = Circle 2.0
  println (describe s)
  println $"{Geometry.area (Geometry.Square 3.0)} {s.Area} {Units.label ()}"
  0
