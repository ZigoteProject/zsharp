# Collections.Buffer

Buffers: an array's storage as a shared, mutable reference, so a write is seen through every
reference (an `array` is a value instead). A slice of a Buffer (`b.[i..j]`) is a Buffer
too, a window sharing its storage. Its other functions are built into the compiler.

## Functions

### `Buffer.slice`

```zsharp
Buffer.slice : Buffer<'a> -> int -> int -> Buffer<'a>
```

The `n` elements from index `i`, as a Buffer sharing this one's storage: a write to either
is seen through both. `b.[i .. i + n - 1]`.

### `Buffer.create`

```zsharp
Buffer.create : int -> 'a -> Buffer<'a>
```

A Buffer of `n` copies of `x`. A Buffer is shared and mutable: a write is seen through every reference.

### `Buffer.length`

```zsharp
Buffer.length : Buffer<'a> -> int
```

The number of elements.

### `Buffer.ofArray`

```zsharp
Buffer.ofArray : array<'a> -> Buffer<'a>
```

A new Buffer with the array's elements.

### `Buffer.ofSpan`

```zsharp
Buffer.ofSpan : span<'a> -> Buffer<'a>
```

A new Buffer with a copy of the span's elements.

### `Buffer.toArray`

```zsharp
Buffer.toArray : span<'a> -> array<'a>
```

An array copy of the elements (of a Buffer, or of any span).

