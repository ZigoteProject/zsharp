// what columns (0037) refuse: a row type that doesn't derive them, one that isn't a record, a
// record literal or an update in place of Columns' functions, a column replaced whole, a slice of
// rows, equality, and a let mutable captured
type Plain = { a: int; b: int }

[<Derive(Columns)>]
type Shape =
  | Circle of f64
  | Square of f64

[<Derive(Columns)>]
type Point = { x: f32; y: f32 }

let plain (c: columns<Plain>) = 0

let numbers (c: columns<int>) = 0

let written () : columns<Point> = { x = [| f32 1.0 |]; y = [||] }

let updated (c: columns<Point>) : columns<Point> = { c with x = [||] }

let whole (c: columns<Point>) =
  let mutable m = c
  m.x <- [||]
  m

let slice (c: columns<Point>) = c.[0..1]

let same (c: columns<Point>) = c = c

let captured (c: columns<Point>) =
  let mutable m = c
  let f () = m.[0].x
  f ()

let missing (c: columns<Point>) = c.[0].z

let main () = 0
