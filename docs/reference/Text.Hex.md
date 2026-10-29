# Text.Hex

Hexadecimal: bytes as two digits each, and back.

## Functions

### `Hex.encode`

```zsharp
Hex.encode : span<u8> -> string
```

The bytes as lower-case hex digits, two a byte.

```zsharp
println (Hex.encode [| u8 0; u8 0xAB; u8 255 |])
// => 00abff
```

### `Hex.decode`

```zsharp
Hex.decode : string -> option<array<u8>>
```

The bytes the hex digits (either case, two a byte) give, or `None` for an odd count or
anything that isn't a digit.

