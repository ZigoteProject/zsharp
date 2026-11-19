// A program's own types named columns and ColumnBuffer are its own (a file's own names come
// first), beside a derived row's: each keeps its own layout, drop function and instances (0037)
type columns<'a> = { items: list<'a>; label: string }

type ColumnBuffer<'a> = { kept: list<'a>; name: string }

[<Derive(Columns)>]
type P = { x: int; y: string }

let mineColumns () : columns<P> =
  { items = [ { x = 1; y = String.concat [ "a"; "b" ] } ]; label = "mine" }

let mineBuffer () : ColumnBuffer<P> =
  { kept = [ { x = 2; y = String.concat [ "c"; "d" ] } ]; name = "own" }

let size (v: 'a) : int = sizeof<'a>

let main () =
  let a = mineColumns ()
  let b = mineBuffer ()
  let c = Columns.ofArray [| { x = 3; y = String.concat [ "e"; "f" ] } |]
  let d = ColumnBuffer.create 2 { x = 4; y = String.concat [ "g"; "h" ] }
  println $"{a.label} {List.length a.items} {b.name} {List.length b.kept}"
  println $"{c.[0].y} {d.[1].y} {Columns.length c} {ColumnBuffer.length d}"
  println $"{size a = size b} {size c > 0} {size d > 0}"
