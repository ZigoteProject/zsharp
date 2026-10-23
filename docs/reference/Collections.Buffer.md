# Collections.Buffer

Buffers: an array's storage as a shared, mutable reference, so a write is seen through every
reference (an `array` is a value instead), and one that grows: `Buffer.push` adds an element
at the end (in amortized constant time, the storage doubling when full), `Buffer.pop` takes
one. A slice of a Buffer (`b.[i..j]`) is a Buffer too, sharing the storage until either grows
past it. Its other functions are built into the compiler: `create`, `length`, `ofArray`,
`ofSpan`, `toArray`, `push`, `removeLast` (the last element, taken; a panic when there's
none), `truncate` (the first `n` elements kept) and `blit` (`n` elements of a span copied in).

## Derives and impls

### `impl Iter<Buffer<'a>, 'a>`

```zsharp
impl Iter<Buffer<'a>, 'a>
```

A Buffer's elements, by index; its length is read each round, so the body may push to it.

## Functions

### `Buffer.empty`

```zsharp
let empty : Buffer<'a>
```

An empty Buffer, a new one at each use: `let names = Buffer.empty` then `Buffer.push n names`.

### `Buffer.pop`

```zsharp
Buffer.pop : Buffer<'a> -> option<'a>
```

The last element, taken out of the Buffer, or `None` when it's empty.

### `Buffer.clear`

```zsharp
Buffer.clear : Buffer<'a> -> unit
```

Removes every element.

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

