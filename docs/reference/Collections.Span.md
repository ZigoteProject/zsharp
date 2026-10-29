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

### `Span.startsWith`

```zsharp
Span.startsWith : span<'a> -> span<'a> -> bool when 'a : Eq
```

Whether `s` begins with the elements of `p`.

### `Span.indexOf`

```zsharp
Span.indexOf : span<'a> -> span<'a> -> option<int> when 'a : Eq
```

The index of the first occurrence of `sub` in `s`, or `None` (`Some 0` for an empty `sub`).

```zsharp
let request = String.bytes "GET / HTTP/1.1\r\nHost: a\r\n\r\nbody"
println $"{Span.indexOf (String.bytes "\r\n\r\n") request}"
// => Some 23
```

### `Span.equalsIgnoreCase`

```zsharp
Span.equalsIgnoreCase : span<u8> -> span<u8> -> bool
```

Whether two spans of bytes are equal, ASCII letters in either case (`Content-Length` and
`content-length`); other bytes must match exactly.

### `Span.trim`

```zsharp
Span.trim : span<u8> -> span<u8>
```

The bytes without the ASCII spaces, tabs and line breaks at either end, without a copy.

### `Span.parseInt`

```zsharp
Span.parseInt : span<u8> -> option<int>
```

The decimal integer the bytes write: an optional `-` or `+`, then digits and nothing else;
`None` for anything else or a number outside the `int` range.

```zsharp
println $"{Span.parseInt (String.bytes "-42")} {Span.parseInt (String.bytes "4x")}"
// => Some -42 None
```

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

