# Text.Utf8

UTF-8, the encoding of every string: bytes checked, decoded and encoded. A string's own bytes
are `String.bytes`.

## Functions

### `Utf8.validate`

```zsharp
Utf8.validate : span<u8> -> result<unit, int>
```

`Ok ()` when the bytes are well-formed UTF-8, else `Error` with the offset of the first byte
that isn't.

### `Utf8.decode`

```zsharp
Utf8.decode : span<u8> -> string
```

The text the bytes encode, each malformed byte as U+FFFD (�), as `for c in s` reads one.

### `Utf8.tryDecode`

```zsharp
Utf8.tryDecode : span<u8> -> option<string>
```

The text the bytes encode, or `None` when they aren't well-formed UTF-8.

### `Utf8.encodeChar`

```zsharp
Utf8.encodeChar : char -> Buffer<u8> -> unit
```

Adds the character's UTF-8 bytes (one to four) to `out`.

