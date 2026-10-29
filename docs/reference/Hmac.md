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

