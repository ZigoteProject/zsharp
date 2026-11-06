# Hmac

HMAC (RFC 2104): a message's authentication code under a secret key, as a JWT's HS256
signature is.

## Functions

### `Hmac.sha256`

```zsharp
Hmac.sha256 : span<u8> -> span<u8> -> array<u8>
```

The HMAC-SHA256 of the message under the key, 32 bytes.

```zsharp
println (Hex.encode (Hmac.sha256 (String.bytes "key") (String.bytes "The quick brown fox jumps over the lazy dog")))
// => f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8
```

### `Hmac.verify`

```zsharp
Hmac.verify : span<u8> -> span<u8> -> span<u8> -> bool
```

Whether `tag` is the message's HMAC-SHA256 under the key, compared in a time that doesn't
depend on where they differ (`Bytes.fixedTimeEquals`): check a JWT's signature with this, the
signature decoded from Base64, never with `=`, whose time tells a forger how much is right.

```zsharp
let key = String.bytes "key"
let message = String.bytes "The quick brown fox jumps over the lazy dog"
let tag = Hmac.sha256 key message
println $"{Hmac.verify key message tag} {Hmac.verify key message (Array.set tag 31 (u8 0))}"
// => true false
```

