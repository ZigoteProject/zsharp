// dyn Trait: values of different types in one list, each used through its own type's impl
trait Shape<'a> =
  abstract area : 'a -> f64
  abstract name : 'a -> string
  abstract scaled : 'a -> f64 -> string

type Circle = { r: f64 }

type Rect = Rect of f64 * f64

// a value holding a string: the dyn owns it, and freeing the dyn frees it
type Label = Label of string * f64

impl Shape<Circle> =
  let area c = 3.0 * c.r * c.r
  let name _ = "circle"
  let scaled c k = $"circle of radius {c.r * k}"

impl Shape<Rect> =
  let area (Rect (w, h)) = w * h
  let name _ = "rect"
  let scaled (Rect (w, h)) k = $"rect {w * k} by {h * k}"

impl Shape<Label> =
  let area (Label (_, a)) = a
  let name (Label (s, _)) = s
  let scaled (Label (s, a)) k = $"{s} times {k}"

let describe (s: dyn Shape) = $"{name s}: {area s}"

// a generic function over Shape takes dyn values too
let twice (s: 'a) = 2.0 * area s

// different types on the two branches, each made a dyn Shape
let pick (i: int) : dyn Shape = if i = 0 then { r = 2.0 } else Rect (1.0, 5.0)

let main () =
  let shapes: list<dyn Shape> = [ { r = 1.0 }; Rect (2.0, 3.0); Label ("unit square", 1.0) ]

  for s in shapes do
    println (describe s)

  println $"total {List.sumBy area shapes}"
  println $"doubled {shapes |> List.map twice}"
  println (scaled (List.head shapes) 10.0)
  println $"{describe (pick 0)}, {describe (pick 1)}"
  // a dyn passed where the trait is required, and kept in another list
  let bigger = shapes |> List.filter (fun s -> area s > 2.0)
  println $"bigger {bigger |> List.map name}"
  // built-in and derived impls: numbers, strings, a record and a tuple shown through dyn Show
  let things: list<dyn Show> = [ 1; "two"; 3.5; { r = 4.0 }; (5, true) ]
  println (things |> List.map show |> String.join ", ")
  0
