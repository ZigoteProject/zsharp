# Binary

## Traits

### `Binary`

```zsharp
trait Binary<'a>
```

A value that can be written as bytes and read back.

#### `Binary.write`

```zsharp
abstract write : BinaryWriter -> 'a -> unit
```

Writes the value.

#### `Binary.read`

```zsharp
abstract read : BinaryReader -> result<'a, string>
```

Reads a value, or says why the bytes aren't one.

## Types

### `BinaryWriter`

```zsharp
type BinaryWriter
```

Where values are written: bytes collect in a Buffer, and a string written again is the
number of its first time.

### `BinaryReader`

```zsharp
type BinaryReader
```

Where values are read from.

## Derives and impls

### `impl Binary<int>`

```zsharp
impl Binary<int>
```

As a zigzag varint (BinaryWriter.varint).

### `impl Binary<i8>`

```zsharp
impl Binary<i8>
```

As a zigzag varint.

### `impl Binary<i16>`

```zsharp
impl Binary<i16>
```

As a zigzag varint.

### `impl Binary<i32>`

```zsharp
impl Binary<i32>
```

As a zigzag varint.

### `impl Binary<i64>`

```zsharp
impl Binary<i64>
```

As a zigzag varint (BinaryWriter.varint64).

### `impl Binary<u8>`

```zsharp
impl Binary<u8>
```

As one byte.

### `impl Binary<u16>`

```zsharp
impl Binary<u16>
```

As a varint (BinaryWriter.uvarint).

### `impl Binary<u32>`

```zsharp
impl Binary<u32>
```

As a varint.

### `impl Binary<u64>`

```zsharp
impl Binary<u64>
```

As a varint.

### `impl Binary<usize>`

```zsharp
impl Binary<usize>
```

As a varint.

### `impl Binary<f64>`

```zsharp
impl Binary<f64>
```

Its 64 bits, low byte first.

### `impl Binary<f32>`

```zsharp
impl Binary<f32>
```

As an f64 (which holds every f32 exactly).

### `impl Binary<bool>`

```zsharp
impl Binary<bool>
```

As one byte, 0 or 1.

### `impl Binary<char>`

```zsharp
impl Binary<char>
```

Its code point, as a varint.

### `impl Binary<string>`

```zsharp
impl Binary<string>
```

Its length and bytes the first time, its number after.

### `impl Binary<unit>`

```zsharp
impl Binary<unit>
```

Nothing.

### `impl Binary<list<'a>>`

```zsharp
impl Binary<list<'a>>
```

Its length, then its elements. A length the bytes left can't hold is an `Error` (elements
that take no bytes, `unit`'s, at most 65,536 of them).

### `impl Binary<array<'a>>`

```zsharp
impl Binary<array<'a>>
```

Its length, then its elements.

### `impl Binary<option<'a>>`

```zsharp
impl Binary<option<'a>>
```

0 for None, 1 and the value for Some.

### `impl Binary<result<'a, 'e>>`

```zsharp
impl Binary<result<'a, 'e>>
```

0 and the value for Ok, 1 and the error for Error.

### `impl Binary<'a * 'b>`

```zsharp
impl Binary<'a * 'b>
```

Its elements in order.

### `impl Binary<'a * 'b * 'c>`

```zsharp
impl Binary<'a * 'b * 'c>
```

Its elements in order.

### `impl Binary<'a * 'b * 'c * 'd>`

```zsharp
impl Binary<'a * 'b * 'c * 'd>
```

Its elements in order.

### `impl Binary<Map<'k, 'v>>`

```zsharp
impl Binary<Map<'k, 'v>>
```

Its entries, as a list of pairs in key order.

### `impl Binary<Set<'a>>`

```zsharp
impl Binary<Set<'a>>
```

Its elements, as a list in order.

### `impl Binary<HashMap<'k, 'v>>`

```zsharp
impl Binary<HashMap<'k, 'v>>
```

Its entries, as a list of pairs.

### `derive Binary`

```zsharp
derive Binary
```

A record's fields in order; a union's case (by name, written once) and then its fields.

## Functions

### `BinaryWriter.create`

```zsharp
BinaryWriter.create : unit -> BinaryWriter
```

A writer with nothing written.

### `BinaryWriter.byte`

```zsharp
BinaryWriter.byte : BinaryWriter -> u8 -> unit
```

One byte.

### `BinaryWriter.uvarint`

```zsharp
BinaryWriter.uvarint : BinaryWriter -> u64 -> unit
```

An unsigned number in 7-bit groups, low first, the high bit set on all but the last.

### `BinaryWriter.varint64`

```zsharp
BinaryWriter.varint64 : BinaryWriter -> i64 -> unit
```

A signed 64-bit number: zigzag (0, -1, 1, -2, … as 0, 1, 2, 3, …), then as `uvarint`.

### `BinaryWriter.varint`

```zsharp
BinaryWriter.varint : BinaryWriter -> int -> unit
```

A signed number, as `varint64`: the same bytes whether `int` is 32 or 64 bits.

### `BinaryWriter.float`

```zsharp
BinaryWriter.float : BinaryWriter -> f64 -> unit
```

A float's 64 bits, low byte first.

### `BinaryWriter.string`

```zsharp
BinaryWriter.string : BinaryWriter -> string -> unit
```

A string: 0, its length and its bytes the first time; then the number it had, plus 1.

### `BinaryReader.create`

```zsharp
BinaryReader.create : span<u8> -> BinaryReader
```

A reader of the bytes from the start.

### `BinaryReader.byte`

```zsharp
BinaryReader.byte : BinaryReader -> result<u8, string>
```

One byte.

### `BinaryReader.uvarint`

```zsharp
BinaryReader.uvarint : BinaryReader -> result<u64, string>
```

An unsigned number as `BinaryWriter.uvarint` writes it.

### `BinaryReader.varint64`

```zsharp
BinaryReader.varint64 : BinaryReader -> result<i64, string>
```

A signed 64-bit number as `BinaryWriter.varint64` writes it.

### `BinaryReader.varint`

```zsharp
BinaryReader.varint : BinaryReader -> result<int, string>
```

A signed number as `BinaryWriter.varint` writes it; an `Error` for one that doesn't fit an
`int` (a 64-bit machine's, read where `int` is 32 bits).

### `BinaryReader.float`

```zsharp
BinaryReader.float : BinaryReader -> result<f64, string>
```

A float as `BinaryWriter.float` writes it.

### `BinaryReader.string`

```zsharp
BinaryReader.string : BinaryReader -> result<string, string>
```

A string as `BinaryWriter.string` writes it.

### `Binary.toBytes`

```zsharp
Binary.toBytes : 'a -> array<u8> when 'a : Binary
```

The value's bytes.

### `Binary.ofBytesWith`

```zsharp
Binary.ofBytesWith : Binary.Options -> span<u8> -> result<'a, string> when 'a : Binary
```

The value the bytes hold, its records and unions nested at most `options.depth` levels; an
`Error` when they don't hold one, or hold more than one.

### `Binary.ofBytes`

```zsharp
Binary.ofBytes : span<u8> -> result<'a, string> when 'a : Binary
```

The value the bytes hold; an `Error` when they don't hold one, or hold more than one.
Records and unions nest at most 1,000 levels, 32 where `int` is 32 bits (a microcontroller's
stack can be 4 KB, and a level is a call); `ofBytesWith` sets another limit.

