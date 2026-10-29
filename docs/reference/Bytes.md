# Bytes

Binary formats and protocols: integers read from and written to bytes at an offset, in big-
or little-endian order (`Bytes.readU16BE data 4`, `Bytes.writeU32LE out 0 n`); a read or
write past the end panics, as indexing does. And a writer: the `append` functions add to a
growing `Buffer<u8>` and return it, so a response is a pipeline:
`out |> Bytes.append b"Content-Length: " |> Bytes.appendInt n |> Bytes.append b"\r\n"`.

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

### `Bytes.append`

```zsharp
Bytes.append : span<u8> -> Buffer<u8> -> Buffer<u8>
```

Adds the bytes at the end of `out`, and returns `out`.

### `Bytes.appendUtf8`

```zsharp
Bytes.appendUtf8 : string -> Buffer<u8> -> Buffer<u8>
```

Adds the string's UTF-8 bytes at the end of `out`, and returns `out`.

### `Bytes.appendInt`

```zsharp
Bytes.appendInt : int -> Buffer<u8> -> Buffer<u8>
```

Adds the integer in decimal (`-` before a negative one) at the end of `out`, and returns
`out`; nothing is allocated but the Buffer's growth.

```zsharp
let out = Buffer.empty |> Bytes.append b"n=" |> Bytes.appendInt -1205 |> Bytes.appendInt 0
println (String.ofBytes out)
// => n=-12050
```

### `Bytes.appendJsonString`

```zsharp
Bytes.appendJsonString : string -> Buffer<u8> -> Buffer<u8>
```

Adds the string as a JSON string, quoted and escaped (`"`, `\` and the control characters;
every other character as its UTF-8, as `Json.print` writes one), and returns `out`. The
string is scanned 16 bytes at a time.

```zsharp
println (String.ofBytes (Bytes.appendJsonString "say \"hi\"\n" Buffer.empty))
// => "say \"hi\"\n"
```

