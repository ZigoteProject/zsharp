/// Columns (0037): an array of records stored field by field, a value (`columns<'r>`) or a
/// shared, growing buffer (`ColumnBuffer<'r>`). In Collections, as Buffer is, so a program's own
/// `Columns` or `ColumnBuffer` is its own.
namespace Collections

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

/// ColumnBuffer (0037): the shared, growing form of `columns<'r>`, as `Buffer<'a>` is `array<'a>`'s.
/// `[<Derive(Columns)>]` on a record gives it `ColumnBuffer<'r>` beside its columns: a `Buffer`
/// per field, every one of one length.
///
/// - `b.[i]` is row `i` and `b.[i].f` reads column `f` alone; `b.f` is the column, a `Buffer`.
/// - `b.[i] <- row` and `b.[i].f <- v` write through any binding, as a Buffer's elements are
///   written, and are seen through every reference.
/// - `ColumnBuffer.push row b` adds a row at the end of each column; `for row in b do` gives each.
/// - A column's length is every column's: push, pop and truncate the ColumnBuffer, not a column
///   through `b.f`. One changed alone is a panic at the next `length`, `set`, `push`,
///   `truncate` or `b.[i] <- row` (and `pop`, `clear`, `toArray` and `for`, which use them), not
///   rows that mix two; `b.[i]`, `b.[i].f` and `b.[i].f <- v` reach their own columns only.
module ColumnBuffer =
  /// What `ColumnBuffer<'r>` does, for the buffer `'b` of a row type `'r`:
  /// `[<Derive(Columns)>]` writes the impl. A function over any ColumnBuffer needs no annotation.
  trait Buffered<'b, 'r> =
    /// A new one with no rows. Its type comes from where it's used:
    /// `let b : ColumnBuffer<Particle> = ColumnBuffer.empty ()`.
    abstract empty : unit -> 'b
    /// The number of rows.
    abstract length : 'b -> int
    /// Row `i`, built from each column: `b.[i]`. A panic when `i` isn't a row's index.
    abstract get : 'b -> int -> 'r
    /// Replaces row `i`, seen through every reference: `b.[i] <- row`.
    abstract set : 'b -> int -> 'r -> unit
    /// Adds a row at the end of each column.
    abstract push : 'r -> 'b -> unit
    /// Keeps the first `n` rows.
    abstract truncate : int -> 'b -> unit

  /// A row type `'r` that has a ColumnBuffer `'b`: `[<Derive(Columns)>]` writes the impl.
  trait BufferRow<'r, 'b> =
    /// A new one holding the rows.
    abstract ofArray : span<'r> -> 'b

  /// `n` rows, each `row`.
  let create (n: int) (row: 'r) = ofArray (Array.create n row)

  /// The last row, taken out, or `None` when there's none.
  let pop b =
    let n = length b
    if n = 0 then None
    else
      let row = get b (n - 1)
      truncate (n - 1) b
      Some row

  /// Removes every row.
  let clear b = truncate 0 b

  /// The rows as an array of records.
  let toArray b = Array.init (length b) (fun i -> get b i)

  // ponytail: through an array of rows, a pass per column each way; a copy column by column
  // when a profile shows this
  /// A new one holding the columns' rows.
  let ofColumns c = ofArray (Columns.toArray c)

  /// The rows as columns, a copy: a later write to the buffer isn't seen in them.
  let toColumns b = Columns.ofArray (toArray b)

  /// The panic of a ColumnBuffer whose columns have different lengths, one pushed to or truncated
  /// alone through `b.f`: what `length`, `set`, `push` and `truncate` give then. Here, not in the
  /// derive's code, so a program's own `panic` isn't the one called.
  let differentLengths () : 'a =
    panic "a ColumnBuffer's columns have different lengths: a column was pushed to or truncated alone (ColumnBuffer.push, pop and truncate change every column)"

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

/// `Buffered` for a row type's ColumnBuffer: `'self` is the buffer, `'other` the row.
derive ColumnsBuffered =
  let empty () : 'self = Shape.record (fun f -> Buffer.ofArray [||])
  // the first column's length, every column's: b.f is the column itself, so one pushed to or
  // truncated alone is found here (as length, set, push and truncate begin), not as rows that
  // mix two
  let length (b: 'self) : int =
    match Shape.of b with
    | Record r ->
      let mutable n = -1
      for f in r.fields do
        let k = Buffer.length f.value
        if n < 0 then
          n <- k
        else if k <> n then
          ColumnBuffer.differentLengths ()
      if n < 0 then 0 else n
    | Union _ -> 0
  let get (b: 'self) (i: int) : 'other = Shape.record (fun f -> (Shape.field f b).[i])
  let set (b: 'self) (i: int) (row: 'other) : unit =
    // every column is one length, so a bad index panics at the first, before any is written
    let _ = ColumnBuffer.length b
    match Shape.of b with
    | Record r ->
      for f in r.fields do
        f.value.[i] <- Shape.field f row
    | Union _ -> ()
  let push (row: 'other) (b: 'self) : unit =
    let _ = ColumnBuffer.length b
    match Shape.of b with
    | Record r ->
      for f in r.fields do
        Buffer.push (Shape.field f row) f.value
    | Union _ -> ()
  let truncate (n: int) (b: 'self) : unit =
    let _ = ColumnBuffer.length b
    match Shape.of b with
    | Record r ->
      for f in r.fields do
        Buffer.truncate n f.value
    | Union _ -> ()

/// `BufferRow` for a row type: `'self` is the row, `'other` its ColumnBuffer.
derive ColumnsBufferRow =
  let ofArray (rows: span<'self>) : 'other = Shape.record (fun f ->
    Buffer.ofArray (Array.map (fun (r: 'self) -> Shape.field f r) rows))

/// `Iter` for a row type's ColumnBuffer: `for row in b do`. Its length is read each round, so
/// the body may push to it or pop from it.
derive ColumnsBufferRows =
  let forEach (b: 'self) g =
    let mutable i = 0
    let mutable ok = true
    // every column's length checked once, then the first column's each round
    let mutable n = ColumnBuffer.length b
    while ok && i < n do
      ok <- g (ColumnBuffer.get b i)
      i <- i + 1
      match Shape.of b with
      | Record r ->
        for f in r.fields do
          if f.index = 0 then
            n <- Buffer.length f.value
      | Union _ -> ()
    ok

/// A record's columns: `[<Derive(Columns)>]` on a record declares `columns<'r>` and
/// `ColumnBuffer<'r>` for it.
derive Columns = ColumnsColumnar, ColumnsRow, ColumnsRows, ColumnsBuffered, ColumnsBufferRow, ColumnsBufferRows
