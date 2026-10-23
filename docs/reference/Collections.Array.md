# Collections.Array

Functions on arrays: fixed-size sequences with constant-time indexing (`a.[i]`), written
`[| 1; 2; 3 |]`. Arrays are values, copied when changed (in place when nothing else refers
to the original).

## Types

#### `array#Length`

```zsharp
member a.Length
```

The number of elements.

## Functions

### `Array.init`

```zsharp
Array.init : int -> (int -> 'a) -> array<'a>
```

An array of `n` elements: `[| f 0; …; f (n - 1) |]`.

### `Array.map`

```zsharp
Array.map : ('a -> 'b) -> span<'a> -> array<'b>
```

A new array with `f` applied to every element.

### `Array.iter`

```zsharp
Array.iter : ('a -> unit) -> span<'a> -> unit
```

Calls `f` on every element, in order.

### `Array.fold`

```zsharp
Array.fold : ('a -> 'b -> 'a) -> 'a -> span<'b> -> 'a
```

Combines the elements from the left, like `List.fold`.

### `Array.sum`

```zsharp
Array.sum : span<'a> -> 'a when 'a : Add
```

The sum of the elements (`Add.zero` for an empty array).

### `Array.ofList`

```zsharp
Array.ofList : list<'a> -> array<'a>
```

An array with the list's elements, in order.

### `Array.toList`

```zsharp
Array.toList : span<'a> -> list<'a>
```

A list with the array's elements, in order.

### `Array.mapi`

```zsharp
Array.mapi : (int -> 'a -> 'b) -> span<'a> -> array<'b>
```

Like `Array.map`, with each element's index: `f i x`.

### `Array.exists`

```zsharp
Array.exists : ('a -> bool) -> span<'a> -> bool
```

Whether `f` is true for some element.

### `Array.contains`

```zsharp
Array.contains : 'a -> span<'a> -> bool when 'a : Eq
```

Whether the array contains `x` (compared with `=`).

### `Array.filter`

```zsharp
Array.filter : ('a -> bool) -> span<'a> -> array<'a>
```

A new array with the elements for which `f` is true.

### `Array.append`

```zsharp
Array.append : span<'a> -> span<'a> -> array<'a>
```

A new array with the elements of `a` followed by those of `b`.

### `Array.concat`

```zsharp
Array.concat : list<array<'a>> -> array<'a>
```

One array with the elements of each array in the list, in order.

### `Array.sub`

```zsharp
Array.sub : array<'a> -> int -> int -> array<'a>
```

A new array of `len` elements starting at index `start`.

### `Array.rev`

```zsharp
Array.rev : span<'a> -> array<'a>
```

A new array in reverse order.

### `Array.sort`

```zsharp
Array.sort : span<'a> -> array<'a> when 'a : Ord
```

A new array sorted in ascending order. Stable.

### `Array.sortWith`

```zsharp
Array.sortWith : ('a -> 'a -> 'b) -> span<'a> -> array<'a> when 'b : Ord
```

A new array sorted with `f` (like `compare`). Stable.

### `Array.copy`

```zsharp
Array.copy : array<'a> -> array<'a>
```

A new array with the same elements (copied at once, as by `memcpy`).

### `Array.create`

```zsharp
Array.create : int -> 'a -> array<'a>
```

An array of `n` copies of `x`.

### `Array.length`

```zsharp
Array.length : span<'a> -> int
```

The number of elements (of an array, a Buffer or a span).

### `Array.ofSpan`

```zsharp
Array.ofSpan : span<'a> -> array<'a>
```

An array with a copy of the span's elements.

### `Array.set`

```zsharp
Array.set : array<'a> -> int -> 'a -> array<'a>
```

`a` with element `i` replaced by `x`. Arrays are values: `a` itself is unchanged (it is reused in place when nothing else refers to it).

