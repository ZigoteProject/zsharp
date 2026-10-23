# Collections.Fixed

Fixed-size arrays: `fixed<u8, 16>` holds 16 elements inline, in a record as C's
`uint8_t data[16]` is in a struct. A value, copied like a record and indexed like an array:
`f.[i]`, and `f.[i] <- x` when `f` (or the record holding it) is `let mutable`. The length
is a number in the type.

## Derives and impls

### `impl Eq<fixed<'a, 'n>>`

```zsharp
impl Eq<fixed<'a, 'n>>
```

Element by element, as records' fields are.

### `impl Ord<fixed<'a, 'n>>`

```zsharp
impl Ord<fixed<'a, 'n>>
```

By the first element that differs.

### `impl Hash<fixed<'a, 'n>>`

```zsharp
impl Hash<fixed<'a, 'n>>
```

Consistent with `Eq`.

### `impl Show<fixed<'a, 'n>>`

```zsharp
impl Show<fixed<'a, 'n>>
```

As F# prints an array: `[|1; 2; 3|]`.

## Functions

### `Fixed.init`

```zsharp
Fixed.init : (int -> 'a) -> fixed<'a, 'b>
```

A fixed-size array with `f i` at index `i` (its length from the type expected of it).

### `Fixed.toArray`

```zsharp
Fixed.toArray : fixed<'a, 'b> -> array<'a>
```

The elements in an array of their own.

### `Fixed.iter`

```zsharp
Fixed.iter : ('a -> unit) -> fixed<'a, 'b> -> unit
```

Calls `f` on every element, in order.

### `Fixed.map`

```zsharp
Fixed.map : ('a -> 'b) -> fixed<'a, 'c> -> fixed<'b, 'c>
```

A fixed-size array with `f` applied to every element.

### `Fixed.fold`

```zsharp
Fixed.fold : ('a -> 'b -> 'a) -> 'a -> fixed<'b, 'c> -> 'a
```

Combines the elements from the left, like `Array.fold`.

### `Fixed.create`

```zsharp
Fixed.create : 'a -> fixed<'a, 'b>
```

N copies of `x`, N from the type expected of it.

### `Fixed.get`

```zsharp
Fixed.get : fixed<'a, 'b> -> int -> 'a
```

The element at index `i`. Panics if out of range.

### `Fixed.length`

```zsharp
Fixed.length : fixed<'a, 'b> -> int
```

The number of elements: the N of fixed<'a, N>.

### `Fixed.ofArray`

```zsharp
Fixed.ofArray : span<'a> -> fixed<'a, 'b>
```

A fixed-size array with the elements of `a`, which must have exactly N (a panic otherwise).

### `Fixed.set`

```zsharp
Fixed.set : fixed<'a, 'b> -> int -> 'a -> fixed<'a, 'b>
```

The fixed-size array with element `i` replaced by `x` (a value: the original is unchanged).

