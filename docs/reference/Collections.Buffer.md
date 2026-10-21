# Collections.Buffer

Buffers: an array's storage as a shared, mutable reference, so a write is seen through every
reference (an `array` is a value instead). Its functions are built into the compiler.

## Functions

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

### `Buffer.toArray`

```zsharp
Buffer.toArray : Buffer<'a> -> array<'a>
```

An array copy of the Buffer's current elements.

