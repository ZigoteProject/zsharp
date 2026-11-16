/// Columns (0037): an array of records stored field by field. `[<Derive(Columns)>]` on a record
/// gives it `columns<'r>`, a value as an array is (a write through one name is never seen through
/// another), with a column per field:
///
/// - `c.[i]` is row `i`, and `c.[i].f` reads column `f` alone; `c.f` is the column, an `array`.
/// - `c.[i] <- row` and `c.[i].f <- v` write in place where `c` is a `let mutable`.
/// - `for row in c do` gives each row.
///
/// A loop over one or two fields of many records reads only those fields' memory, and a column
/// is what `Array.sum`, `F32x8.load` and the other functions over arrays take.
module Columns =
  /// What `columns<'r>` does, for the columns `'c` of a row type `'r`: `[<Derive(Columns)>]`
  /// writes the impl. A function over any columns needs no annotation.
  trait Columnar<'c, 'r> =
    /// The number of rows.
    abstract length : 'c -> int
    /// Row `i`, built from each column: `c.[i]`. A panic when `i` isn't a row's index.
    abstract get : 'c -> int -> 'r
    /// The columns with row `i` replaced, as `Array.set`: `c` is left alone.
    abstract set : 'c -> int -> 'r -> 'c

  /// A row type `'r` that has columns `'c`: `[<Derive(Columns)>]` writes the impl.
  trait Row<'r, 'c> =
    /// The rows' fields, a column each.
    abstract ofArray : span<'r> -> 'c

  // ponytail: the rows are built as an array and then split, a pass per column; a fill of the
  // columns as the rows are made, when a profile shows this
  /// `n` rows, row `i` given by `f i`.
  let init (n: int) (f: int -> 'r) = ofArray (Array.init n f)

  /// `n` rows, each `row`.
  let create (n: int) (row: 'r) = ofArray (Array.create n row)

  /// The rows as an array of records.
  let toArray c = Array.init (length c) (fun i -> get c i)

  /// The columns of `f row` for each row.
  let map f c = ofArray (Array.map f (toArray c))

/// `Columnar` for a row type's columns: `'self` is the columns, `'other` the row.
derive ColumnsColumnar =
  let length (c: 'self) : int =
    match Shape.of c with
    | Record r ->
      let mutable n = 0
      for f in r.fields do
        if f.index = 0 then
          n <- Array.length f.value
      n
    | Union _ -> 0
  let get (c: 'self) (i: int) : 'other = Shape.record (fun f -> (Shape.field f c).[i])
  let set (c: 'self) (i: int) (row: 'other) : 'self = Shape.record (fun f ->
    Array.set (Shape.field f c) i (Shape.field f row))

/// `Row` for a row type: `'self` is the row, `'other` its columns.
derive ColumnsRow =
  let ofArray (rows: span<'self>) : 'other = Shape.record (fun f ->
    Array.map (fun (r: 'self) -> Shape.field f r) rows)

/// `Iter` for a row type's columns: `for row in c do`.
derive ColumnsRows =
  let forEach (c: 'self) g =
    let n = Columns.length c
    let mutable i = 0
    let mutable ok = true
    while ok && i < n do
      ok <- g (Columns.get c i)
      i <- i + 1
    ok

/// A record's columns: `[<Derive(Columns)>]` on a record declares `columns<'r>` for it.
derive Columns = ColumnsColumnar, ColumnsRow, ColumnsRows
