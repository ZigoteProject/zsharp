# Bytes

Binary formats and protocols: numbers read from and written to bytes at an offset, in big-
or little-endian order (`Bytes.readU16BE data 4`, `Bytes.writeF64LE out 0 x`); a read or
write past the end panics, as indexing does. And a `Writer`, over a growing `Buffer<u8>` or
fixed C memory: the `append` functions add to it and return it, so a response is a pipeline:
`out |> Bytes.append b"Content-Length: " |> Bytes.appendInt n |> Bytes.append b"\r\n"`.

## Types

### `Bytes.Writer`

```zsharp
type Writer
```

Where the `append` functions write: a growing `Buffer<u8>` (`Bytes.writerOf`), or fixed
memory C owns, such as a socket's send buffer (`Bytes.writer`), where writing past the end
panics. A value: each write gives the Writer back, longer, so writes chain,
`w |> Bytes.append b"OK" |> Bytes.appendInt n`; `Bytes.written` is what they wrote.

#### `Bytes.Growing`

```zsharp
| Growing of Buffer<u8>
```

Bytes pushed onto a Buffer, which the Buffer's other references see.

#### `Bytes.Fixed`

```zsharp
| Fixed of Memory
```

Bytes written into fixed memory, from its start; only `Bytes.writer` makes one.

## Functions

### `Bytes.readU16BE`

```zsharp
Bytes.readU16BE : span<u8> -> int -> u16
```

The `u16` at offset `at`, big-endian (network order).

```zsharp
println $"{Bytes.readU16BE [| u8 1; u8 2 |] 0} {Bytes.readU16LE [| u8 1; u8 2 |] 0}"
// => 258 513
```

### `Bytes.readU16LE`

```zsharp
Bytes.readU16LE : span<u8> -> int -> u16
```

The `u16` at offset `at`, little-endian.

### `Bytes.readU32BE`

```zsharp
Bytes.readU32BE : span<u8> -> int -> u32
```

The `u32` at offset `at`, big-endian (network order).

### `Bytes.readU32LE`

```zsharp
Bytes.readU32LE : span<u8> -> int -> u32
```

The `u32` at offset `at`, little-endian.

### `Bytes.readU64BE`

```zsharp
Bytes.readU64BE : span<u8> -> int -> u64
```

The `u64` at offset `at`, big-endian (network order).

### `Bytes.readU64LE`

```zsharp
Bytes.readU64LE : span<u8> -> int -> u64
```

The `u64` at offset `at`, little-endian.

### `Bytes.readI16BE`

```zsharp
Bytes.readI16BE : span<u8> -> int -> i16
```

The `i16` at offset `at`, big-endian (network order).

### `Bytes.readI16LE`

```zsharp
Bytes.readI16LE : span<u8> -> int -> i16
```

The `i16` at offset `at`, little-endian.

### `Bytes.readI32BE`

```zsharp
Bytes.readI32BE : span<u8> -> int -> i32
```

The `i32` at offset `at`, big-endian (network order).

### `Bytes.readI32LE`

```zsharp
Bytes.readI32LE : span<u8> -> int -> i32
```

The `i32` at offset `at`, little-endian.

### `Bytes.readI64BE`

```zsharp
Bytes.readI64BE : span<u8> -> int -> i64
```

The `i64` at offset `at`, big-endian (network order).

### `Bytes.readI64LE`

```zsharp
Bytes.readI64LE : span<u8> -> int -> i64
```

The `i64` at offset `at`, little-endian.

### `Bytes.writeU16BE`

```zsharp
Bytes.writeU16BE : Buffer<u8> -> int -> u16 -> unit
```

Writes the `u16` at offset `at`, big-endian (network order), over the bytes there.

### `Bytes.writeU16LE`

```zsharp
Bytes.writeU16LE : Buffer<u8> -> int -> u16 -> unit
```

Writes the `u16` at offset `at`, little-endian.

### `Bytes.writeU32BE`

```zsharp
Bytes.writeU32BE : Buffer<u8> -> int -> u32 -> unit
```

Writes the `u32` at offset `at`, big-endian (network order).

### `Bytes.writeU32LE`

```zsharp
Bytes.writeU32LE : Buffer<u8> -> int -> u32 -> unit
```

Writes the `u32` at offset `at`, little-endian.

### `Bytes.writeU64BE`

```zsharp
Bytes.writeU64BE : Buffer<u8> -> int -> u64 -> unit
```

Writes the `u64` at offset `at`, big-endian (network order).

### `Bytes.writeU64LE`

```zsharp
Bytes.writeU64LE : Buffer<u8> -> int -> u64 -> unit
```

Writes the `u64` at offset `at`, little-endian.

### `Bytes.writeI16BE`

```zsharp
Bytes.writeI16BE : Buffer<u8> -> int -> i16 -> unit
```

Writes the `i16` at offset `at`, big-endian (network order).

### `Bytes.writeI16LE`

```zsharp
Bytes.writeI16LE : Buffer<u8> -> int -> i16 -> unit
```

Writes the `i16` at offset `at`, little-endian.

### `Bytes.writeI32BE`

```zsharp
Bytes.writeI32BE : Buffer<u8> -> int -> i32 -> unit
```

Writes the `i32` at offset `at`, big-endian (network order).

### `Bytes.writeI32LE`

```zsharp
Bytes.writeI32LE : Buffer<u8> -> int -> i32 -> unit
```

Writes the `i32` at offset `at`, little-endian.

### `Bytes.writeI64BE`

```zsharp
Bytes.writeI64BE : Buffer<u8> -> int -> i64 -> unit
```

Writes the `i64` at offset `at`, big-endian (network order).

### `Bytes.writeI64LE`

```zsharp
Bytes.writeI64LE : Buffer<u8> -> int -> i64 -> unit
```

Writes the `i64` at offset `at`, little-endian.

### `Bytes.readF32BE`

```zsharp
Bytes.readF32BE : span<u8> -> int -> f32
```

The `f32` at offset `at`, big-endian (its IEEE 754 bits).

### `Bytes.readF32LE`

```zsharp
Bytes.readF32LE : span<u8> -> int -> f32
```

The `f32` at offset `at`, little-endian.

### `Bytes.readF64BE`

```zsharp
Bytes.readF64BE : span<u8> -> int -> f64
```

The `f64` at offset `at`, big-endian (its IEEE 754 bits).

### `Bytes.readF64LE`

```zsharp
Bytes.readF64LE : span<u8> -> int -> f64
```

The `f64` at offset `at`, little-endian.

### `Bytes.writeF32BE`

```zsharp
Bytes.writeF32BE : Buffer<u8> -> int -> f32 -> unit
```

Writes the `f32` at offset `at`, big-endian (its IEEE 754 bits).

### `Bytes.writeF32LE`

```zsharp
Bytes.writeF32LE : Buffer<u8> -> int -> f32 -> unit
```

Writes the `f32` at offset `at`, little-endian.

### `Bytes.writeF64BE`

```zsharp
Bytes.writeF64BE : Buffer<u8> -> int -> f64 -> unit
```

Writes the `f64` at offset `at`, big-endian (its IEEE 754 bits).

### `Bytes.writeF64LE`

```zsharp
Bytes.writeF64LE : Buffer<u8> -> int -> f64 -> unit
```

Writes the `f64` at offset `at`, little-endian.

### `Bytes.writerOf`

```zsharp
Bytes.writerOf : Buffer<u8> -> Bytes.Writer
```

A Writer that pushes onto the Buffer.

```zsharp
let w = Bytes.writerOf Buffer.empty |> Bytes.append b"n=" |> Bytes.appendInt -1205
println (String.ofBytes (Bytes.written w))
// => n=-1205
```

### `Bytes.writer`

```zsharp
Bytes.writer : ptr<u8> -> int -> Bytes.Writer
```

A Writer over the `capacity` bytes at `p`, empty. Unsafe: the memory must stay valid, and
written by nothing else, while the Writer and the spans `Bytes.written` gives are used.

### `Bytes.written`

```zsharp
Bytes.written : Bytes.Writer -> span<u8>
```

The bytes written so far, without a copy: a growing Writer's whole Buffer, a fixed one's
memory up to its length.

### `Bytes.remaining`

```zsharp
Bytes.remaining : Bytes.Writer -> int
```

How many more bytes fit: the most an `int` holds for a growing Writer.

### `Bytes.reset`

```zsharp
Bytes.reset : Bytes.Writer -> Bytes.Writer
```

The Writer emptied (its Buffer cleared, or its memory to be written again from the start).

### `Bytes.put`

```zsharp
Bytes.put : u8 -> Bytes.Writer -> Bytes.Writer
```

Adds the byte at the end of `out`, and returns it.

### `Bytes.append`

```zsharp
Bytes.append : span<u8> -> Bytes.Writer -> Bytes.Writer
```

Adds the bytes at the end of `out`, and returns it.

### `Bytes.appendUtf8`

```zsharp
Bytes.appendUtf8 : string -> Bytes.Writer -> Bytes.Writer
```

Adds the string's UTF-8 bytes at the end of `out`, and returns it.

### `Bytes.appendInt`

```zsharp
Bytes.appendInt : int -> Bytes.Writer -> Bytes.Writer
```

Adds the integer in decimal (`-` before a negative one) at the end of `out`, and returns it;
nothing is allocated (but a Buffer's growth).

```zsharp
let w = Bytes.writerOf Buffer.empty |> Bytes.appendInt -1205 |> Bytes.appendInt 0
println (String.ofBytes (Bytes.written w))
// => -12050
```

### `Bytes.appendJsonString`

```zsharp
Bytes.appendJsonString : string -> Bytes.Writer -> Bytes.Writer
```

Adds the string as a JSON string, quoted and escaped (`"`, `\` and the control characters;
every other character as its UTF-8, as `Json.print` writes one), and returns `out`. The
string is scanned 16 bytes at a time.

```zsharp
println (String.ofBytes (Bytes.written (Bytes.appendJsonString "say \"hi\"\n" (Bytes.writerOf Buffer.empty))))
// => "say \"hi\"\n"
```

