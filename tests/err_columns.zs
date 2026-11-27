// what columns and ColumnBuffer (0037) refuse: a row that doesn't derive them or isn't a record,
// a record literal or update, a column replaced whole, a slice of rows, equality, a captured let
// mutable, a row of another type, a type nothing gives, and a private row's fields
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

let plainBuffer (b: ColumnBuffer<Plain>) = 0

let writtenBuffer () : ColumnBuffer<Point> = { x = Buffer.empty; y = Buffer.empty }

let wholeBuffer (b: ColumnBuffer<Point>) = { b with x = Buffer.empty }

let missingBuffer (b: ColumnBuffer<Point>) = b.[0].z

// a ColumnBuffer of what isn't a row: a union, a number, a variable, columns already, and a
// [<Bits>] record
[<Bits 8>]
type Control = { on: bool = false }

type Shade =
  | Light
  | Dark

let unionBuffer (b: ColumnBuffer<Shade>) = 0

let numberBuffer (b: ColumnBuffer<int>) = 0

let varBuffer (b: ColumnBuffer<'a>) = 0

let nestedBuffer (b: ColumnBuffer<columns<Point>>) = 0

let nestedColumns (c: columns<ColumnBuffer<Point>>) = 0

let bitsBuffer (b: ColumnBuffer<Control>) = 0

// a ColumnBuffer's column replaced whole, also through a call's result, a slice of its rows,
// equality, a field it hasn't written, and a member written
let wholeColumn (b: ColumnBuffer<Point>) = b.x <- Buffer.empty

let held () : ColumnBuffer<Point> = ColumnBuffer.create 1 { x = f32 0.0; y = f32 0.0 }

let wholeHeld () = (held ()).x <- Buffer.empty

let sliceBuffer (b: ColumnBuffer<Point>) = b.[0..1]

let sameBuffer (b: ColumnBuffer<Point>) = b = b

let missingWrite (b: ColumnBuffer<Point>) = b.[0].z <- f32 1.0

[<Derive(Columns)>]
type Sized =
  { w: int }
  member s.Twice = s.w * 2

let memberWrite (b: ColumnBuffer<Sized>) = b.[0].Twice <- 4

// a row or an element written to a captured let mutable: one error, naming it, not one per column
let capturedRow (c: columns<Point>) =
  let mutable m = c
  let f () = m.[0] <- { x = f32 1.0; y = f32 2.0 }
  f ()

let capturedElement (c: columns<Point>) =
  let mutable m = c
  let f () = m.[0].x <- f32 1.0
  f ()

// columns are values, written only in a let mutable: not a call's, nor a parameter's
let made () = Columns.create 1 { x = f32 0.0; y = f32 0.0 }

let madeWrite () = (made ()).[0] <- { x = f32 1.0; y = f32 2.0 }

let madeElement () = (made ()).[0].x <- f32 1.0

let paramWrite (c: columns<Point>) = c.[0] <- { x = f32 1.0; y = f32 2.0 }

// a row of another type pushed; a function of columns given a record
let wrongRow (b: ColumnBuffer<Point>) = ColumnBuffer.push 5 b

let notColumns () = Columns.length { a = 1; b = 2 }

// a record naming its own columns, a union its own, a record one of its group's, a type with no
// body, an earlier record of a group, and a union of one
[<Derive(Columns)>]
type Node = { id: int; kids: ColumnBuffer<Node> }

type Tree =
  | Leaf
  | Branch of ColumnBuffer<Tree>

[<Derive(Columns)>]
type Scene = { name: string; items: ColumnBuffer<Item> }
and Item = { id: int; owner: option<Scene> }

type Handle

let handles (b: ColumnBuffer<Handle>) = 0

[<Derive(Columns)>]
type First = { n: int }
and Second = { firsts: ColumnBuffer<First> }

type Holder = { kinds: ColumnBuffer<Kind> }
and Kind =
  | Big
  | Small

// a private row's fields are its module's, through its columns too: read, written (once, a row),
// a column pushed to, and columns in a let mutable
module Vault =
  [<Derive(Columns)>]
  type private Secret = { code: int }

  let make () = ColumnBuffer.create 1 { code = 1 }

  let makeColumns () = Columns.create 1 { code = 1 }

let peek () = (Vault.make ()).[0].code

let poke () =
  let s = Vault.make ()
  s.[0].code <- 5

let pokeRow () =
  let s = Vault.make ()
  s.[0] <- ColumnBuffer.get s 0

let pushColumn () = Buffer.push 5 (Vault.make ()).code

let columnsField () = (Vault.makeColumns ()).code

let splitRead () =
  let mutable c = Vault.makeColumns ()
  c.code

let splitWrite () =
  let mutable c = Vault.makeColumns ()
  c.[0].code <- 5

let main () = 0
