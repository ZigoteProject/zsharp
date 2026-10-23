# Collections.Span

Spans: read-only windows into an array, a string's bytes or a Buffer, without a copy:
`a.[1..3]`, `a.[..n]`, `a.[i..]`, `String.bytes s`. A span holds a reference to what it
windows, which lives as long as the span does. An array or a Buffer becomes a span where
one is expected, so the functions that read arrays (`Array.sum`, `Array.fold`, …) read
all three.

## Types

#### `span#Length`

```zsharp
member s.Length
```

The number of elements.

## Derives and impls

### `impl Iter<span<'a>, 'a>`

```zsharp
impl Iter<span<'a>, 'a>
```

A span's elements, by index.

## Functions

### `Span.isEmpty`

```zsharp
Span.isEmpty : span<'a> -> bool
```

Whether the span has no elements.

### `Span.slice`

```zsharp
Span.slice : span<'a> -> int -> int -> span<'a>
```

The `n` elements from index `i`, without a copy: `s.[i .. i + n - 1]`.

### `Span.length`

```zsharp
Span.length : span<'a> -> int
```

The number of elements.

### `Span.ofPtr`

```zsharp
Span.ofPtr : ptr<'a> -> int -> span<'a>
```

A span over `n` elements of C memory at `p`, in `unsafe`: its lifetime isn't checked, so the span mustn't outlive the memory.

