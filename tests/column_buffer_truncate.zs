// ColumnBuffer.truncate below zero (0037): a panic at the first column, before any is changed, as
// Buffer.truncate's
[<Derive(Columns)>]
type P = { a: int; s: string }

let main () =
  let b = ColumnBuffer.create 3 { a = 1; s = "x" }
  ColumnBuffer.truncate -1 b
  println "not reached"
