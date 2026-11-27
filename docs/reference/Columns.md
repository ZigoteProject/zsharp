# Collections.Columns

Columns (0037): an array of records stored field by field, a value (`columns<'r>`) or a
shared, growing buffer (`ColumnBuffer<'r>`). In Collections, as Buffer is, so a program's own
`Columns` or `ColumnBuffer` is its own.

## Modules

### `Columns`

```zsharp
module Columns
```

Columns (0037): an array of records stored field by field. `[<Derive(Columns)>]` on a record
gives it `columns<'r>`, a value as an array is (a write through one name is never seen through
another), with a column per field:

- `c.[i]` is row `i`, and `c.[i].f` reads column `f` alone; `c.f` is the column, an `array`.
- `c.[i] <- row` and `c.[i].f <- v` write in place where `c` is a `let mutable`.
- `for row in c do` gives each row.

A loop over one or two fields of many records reads only those fields' memory, and a column
is what `Array.sum`, `F32x8.load` and the other functions over arrays take.

### `ColumnBuffer`

```zsharp
module ColumnBuffer
```

ColumnBuffer (0037): the shared, growing form of `columns<'r>`, as `Buffer<'a>` is `array<'a>`'s.
`[<Derive(Columns)>]` on a record gives it `ColumnBuffer<'r>` beside its columns: a `Buffer`
per field, every one of one length.

- `b.[i]` is row `i` and `b.[i].f` reads column `f` alone; `b.f` is the column, a `Buffer`.
- `b.[i] <- row` and `b.[i].f <- v` write through any binding, as a Buffer's elements are
  written, and are seen through every reference.
- `ColumnBuffer.push row b` adds a row at the end of each column; `for row in b do` gives each.
- A column's length is every column's: push, pop and truncate the ColumnBuffer, not a column
  through `b.f`. One changed alone is a panic at the next `length`, `set`, `push`,
  `truncate` or `b.[i] <- row` (and `pop`, `clear`, `toArray` and `for`, which use them), not
  rows that mix two; `b.[i]`, `b.[i].f` and `b.[i].f <- v` reach their own columns only.

## Traits

### `Columns.Columnar`

```zsharp
trait Columnar<'c, 'r>
```

What `columns<'r>` does, for the columns `'c` of a row type `'r`: `[<Derive(Columns)>]`
writes the impl. A function over any columns needs no annotation.

#### `Columns.Columnar.length`

```zsharp
abstract length : 'c -> int
```

The number of rows.

#### `Columns.Columnar.get`

```zsharp
abstract get : 'c -> int -> 'r
```

Row `i`, built from each column: `c.[i]`. A panic when `i` isn't a row's index.

#### `Columns.Columnar.set`

```zsharp
abstract set : 'c -> int -> 'r -> 'c
```

The columns with row `i` replaced, as `Array.set`: `c` is left alone.

### `Columns.Row`

```zsharp
trait Row<'r, 'c>
```

A row type `'r` that has columns `'c`: `[<Derive(Columns)>]` writes the impl.

#### `Columns.Row.ofArray`

```zsharp
abstract ofArray : span<'r> -> 'c
```

The rows' fields, a column each.

### `ColumnBuffer.Buffered`

```zsharp
trait Buffered<'b, 'r>
```

What `ColumnBuffer<'r>` does, for the buffer `'b` of a row type `'r`:
`[<Derive(Columns)>]` writes the impl. A function over any ColumnBuffer needs no annotation.

#### `ColumnBuffer.Buffered.empty`

```zsharp
abstract empty : unit -> 'b
```

A new one with no rows. Its type comes from where it's used:
`let b : ColumnBuffer<Particle> = ColumnBuffer.empty ()`.

#### `ColumnBuffer.Buffered.length`

```zsharp
abstract length : 'b -> int
```

The number of rows.

#### `ColumnBuffer.Buffered.get`

```zsharp
abstract get : 'b -> int -> 'r
```

Row `i`, built from each column: `b.[i]`. A panic when `i` isn't a row's index.

#### `ColumnBuffer.Buffered.set`

```zsharp
abstract set : 'b -> int -> 'r -> unit
```

Replaces row `i`, seen through every reference: `b.[i] <- row`.

#### `ColumnBuffer.Buffered.push`

```zsharp
abstract push : 'r -> 'b -> unit
```

Adds a row at the end of each column.

#### `ColumnBuffer.Buffered.truncate`

```zsharp
abstract truncate : int -> 'b -> unit
```

Keeps the first `n` rows.

### `ColumnBuffer.BufferRow`

```zsharp
trait BufferRow<'r, 'b>
```

A row type `'r` that has a ColumnBuffer `'b`: `[<Derive(Columns)>]` writes the impl.

#### `ColumnBuffer.BufferRow.ofArray`

```zsharp
abstract ofArray : span<'r> -> 'b
```

A new one holding the rows.

## Derives and impls

### `derive ColumnsColumnar`

```zsharp
derive ColumnsColumnar
```

`Columnar` for a row type's columns: `'self` is the columns, `'other` the row.

### `derive ColumnsRow`

```zsharp
derive ColumnsRow
```

`Row` for a row type: `'self` is the row, `'other` its columns.

### `derive ColumnsRows`

```zsharp
derive ColumnsRows
```

`Iter` for a row type's columns: `for row in c do`.

### `derive ColumnsBuffered`

```zsharp
derive ColumnsBuffered
```

`Buffered` for a row type's ColumnBuffer: `'self` is the buffer, `'other` the row.

### `derive ColumnsBufferRow`

```zsharp
derive ColumnsBufferRow
```

`BufferRow` for a row type: `'self` is the row, `'other` its ColumnBuffer.

### `derive ColumnsBufferRows`

```zsharp
derive ColumnsBufferRows
```

`Iter` for a row type's ColumnBuffer: `for row in b do`. Its length is read each round, so
the body may push to it or pop from it.

### `derive Columns`

```zsharp
derive Columns
```

A record's columns: `[<Derive(Columns)>]` on a record declares `columns<'r>` and
`ColumnBuffer<'r>` for it.

## Functions

### `Columns.init`

```zsharp
Columns.init : int -> (int -> 'a) -> 'b when 'a : Columns.Row<'b>
```

`n` rows, row `i` given by `f i`.

### `Columns.create`

```zsharp
Columns.create : int -> 'a -> 'b when 'a : Columns.Row<'b>
```

`n` rows, each `row`.

### `Columns.toArray`

```zsharp
Columns.toArray : 'a -> array<'b> when 'a : Columns.Columnar<'b>
```

The rows as an array of records.

### `Columns.map`

```zsharp
Columns.map : ('a -> 'b) -> 'd -> 'c when 'b : Columns.Row<'c>, 'd : Columns.Columnar<'a>
```

The columns of `f row` for each row.

### `ColumnBuffer.create`

```zsharp
ColumnBuffer.create : int -> 'a -> 'b when 'a : ColumnBuffer.BufferRow<'b>
```

`n` rows, each `row`.

### `ColumnBuffer.pop`

```zsharp
ColumnBuffer.pop : 'a -> option<'b> when 'a : ColumnBuffer.Buffered<'b>
```

The last row, taken out, or `None` when there's none.

### `ColumnBuffer.clear`

```zsharp
ColumnBuffer.clear : 'a -> unit when 'a : ColumnBuffer.Buffered<'b>
```

Removes every row.

### `ColumnBuffer.toArray`

```zsharp
ColumnBuffer.toArray : 'a -> array<'b> when 'a : ColumnBuffer.Buffered<'b>
```

The rows as an array of records.

### `ColumnBuffer.ofColumns`

```zsharp
ColumnBuffer.ofColumns : 'a -> 'c when 'a : Columns.Columnar<'b>, 'b : ColumnBuffer.BufferRow<'c>
```

A new one holding the columns' rows.

### `ColumnBuffer.toColumns`

```zsharp
ColumnBuffer.toColumns : 'a -> 'c when 'a : ColumnBuffer.Buffered<'b>, 'b : Columns.Row<'c>
```

The rows as columns, a copy: a later write to the buffer isn't seen in them.

### `ColumnBuffer.differentLengths`

```zsharp
ColumnBuffer.differentLengths : unit -> 'a
```

The panic of a ColumnBuffer whose columns have different lengths, one pushed to or truncated
alone through `b.f`: what `length`, `set`, `push` and `truncate` give then. Here, not in the
derive's code, so a program's own `panic` isn't the one called.

