// module Inner = …: nested modules, qualified names, open, privacy and enclosing scope
let scale = 10

module Geometry =
  type Shape =
    | Circle of radius: int
    | Square of side: int

  let private pi3 = 3

  /// Area, roughly (pi is 3 here).
  let area s =
    match s with
    | Circle r -> pi3 * r * r
    | Square a -> a * a

  module Units =
    // sees the enclosing modules' names (scale, and Geometry's private pi3)
    let toBig x = x * scale * pi3

  let biggest shapes = shapes |> List.map area |> List.fold max 0

module Text =
  open Geometry

  let describe s = $"area {area s}"

let main () =
  let shapes = [ Geometry.Circle 2; Geometry.Square 5 ]
  println $"{Geometry.area (Geometry.Circle 1)} {Geometry.biggest shapes} {Geometry.Units.toBig 2}"
  println (Text.describe (Geometry.Square 3))
  0
