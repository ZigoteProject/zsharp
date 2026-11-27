// A trait method at a type nothing gives is an error where it's called, not a build's with no
// place (0037): one a type, the method that makes it first. An unannotated ColumnBuffer.empty (),
// rows of no type (and their columns, whose type theirs gives), and a program's own trait whose
// default, int, has no impl
[<Derive(Columns)>]
type Point = { x: f32; y: f32 }

trait Zero<'a> =
  abstract zero : unit -> 'a

let unknown () =
  let b = ColumnBuffer.empty ()
  ColumnBuffer.length b

let noRows () : ColumnBuffer<Point> = ColumnBuffer.ofArray [||]

let noColumns () =
  let c = Columns.ofArray [||]
  Columns.length c

let zero () =
  let z = Zero.zero ()
  0

let main () = 0
