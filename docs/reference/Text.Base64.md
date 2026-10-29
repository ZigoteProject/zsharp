# Text.Base64

Base64 (RFC 4648): bytes as text of 64 characters, three bytes to four, and back. `encode`
and `decode` use `+` and `/` with `=` padding; `encodeUrl` and `decodeUrl` use the URL-safe
`-` and `_` without padding, as JWTs and URLs do.

## Functions

### `Base64.encode`

```zsharp
Base64.encode : span<u8> -> string
```

The bytes in standard base64, padded with `=`.

```zsharp
println (Base64.encode (String.bytes "hello"))
println (Base64.encodeUrl [| u8 0xFB; u8 0xFF |])
// => aGVsbG8=
// => -_8
```

### `Base64.encodeUrl`

```zsharp
Base64.encodeUrl : span<u8> -> string
```

The bytes in URL-safe base64 (`-` and `_`), without padding.

### `Base64.decode`

```zsharp
Base64.decode : string -> option<array<u8>>
```

The bytes standard, padded base64 gives, or `None` when it isn't that.

### `Base64.decodeUrl`

```zsharp
Base64.decodeUrl : string -> option<array<u8>>
```

The bytes URL-safe, unpadded base64 gives, or `None` when it isn't that.

