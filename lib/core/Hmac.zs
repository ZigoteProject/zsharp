/// HMAC (RFC 2104): a message's authentication code under a secret key, as a JWT's HS256
/// signature is.
module Hmac

/// The HMAC-SHA256 of the message under the key, 32 bytes.
///
/// ```zsharp
/// println (Hex.encode (Hmac.sha256 (String.bytes "key") (String.bytes "The quick brown fox jumps over the lazy dog")))
/// // => f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8
/// ```
let sha256 (key: span<u8>) (message: span<u8>) : array<u8> =
  let k = if Array.length key > 64 then Sha256.hash key else Array.ofSpan key
  // the key padded to 64 bytes, each byte xor x, then `n` bytes of `rest`
  let padded (x: u8) (rest: span<u8>) =
    let n = Array.length rest
    let b = Buffer.create (64 + n) x
    for i in 0 .. Array.length k - 1 do
      b.[i] <- k.[i] ^^^ x
    Buffer.blit rest 0 b 64 n
    b
  Sha256.hash (padded (u8 0x5c) (Sha256.hash (padded (u8 0x36) message)))
