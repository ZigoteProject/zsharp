# Columns

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

### `derive Columns`

```zsharp
derive Columns
```

A record's columns: `[<Derive(Columns)>]` on a record declares `columns<'r>` for it.

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

