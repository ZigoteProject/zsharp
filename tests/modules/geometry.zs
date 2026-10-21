// a module: geometry.zs is module Geometry
type Shape =
  | Circle of radius: f64
  | Square of side: f64

let private pi () = 3.0

let area s =
  match s with
  | Circle r -> pi () * r * r
  | Square a -> a * a

type Shape with
  member s.Area = area s

let describe s = $"{Units.label ()} {area s}"
