// A program's own names come first (0037), beside a derived row's columns: a module's own type
// named ColumnBuffer, used after `open`; an alias named columns; and modules of the program named
// ColumnBuffer and Columns, whose functions are the program's, while the derive's code still calls
// the library's (its `for` counts every row)
module Grid =
  type ColumnBuffer<'a> = { items: list<'a>; width: int }

  let make (w: int) : ColumnBuffer<int> = { items = [ 1; 2 ]; width = w }

type columns<'a> = Buffer<'a>

module ColumnBuffer =
  let push (x: int) (b: Buffer<int>) = Buffer.push (x * 2) b

module Columns =
  let length (x: int) = x + 100

[<Derive(Columns)>]
type P = { a: int; s: string }

open Grid

let main () =
  let g : ColumnBuffer<int> = make 3
  let alias : columns<int> = Buffer.ofArray [| 1; 2 |]
  let b = Buffer.ofArray [| 1 |]
  ColumnBuffer.push 5 b
  let c = Collections.Columns.create 5 { a = 1; s = "x" }
  let mutable n = 0
  for p in c do
    n <- n + p.a
  println $"{g.width} {List.length g.items} {Buffer.length alias} {Buffer.toArray b |> Array.toList} {Columns.length 1} {n}"
