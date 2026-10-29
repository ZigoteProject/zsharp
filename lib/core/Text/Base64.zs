/// Base64 (RFC 4648): bytes as text of 64 characters, three bytes to four, and back. `encode`
/// and `decode` use `+` and `/` with `=` padding; `encodeUrl` and `decodeUrl` use the URL-safe
/// `-` and `_` without padding, as JWTs and URLs do.
module Text.Base64

let private standard = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
let private url = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

let private encodeWith (alphabet: string) (pad: bool) (b: span<u8>) : string =
  let n = Array.length b
  let out = Buffer.empty
  let digit (x: u32) = Buffer.push (String.byte alphabet (int (x &&& u32 63))) out
  let mutable i = 0
  while i + 2 < n do
    let x = (u32 b.[i] <<< u32 16) ||| (u32 b.[i + 1] <<< u32 8) ||| u32 b.[i + 2]
    digit (x >>> u32 18)
    digit (x >>> u32 12)
    digit (x >>> u32 6)
    digit x
    i <- i + 3
  if n - i = 1 then
    let x = u32 b.[i] <<< u32 16
    digit (x >>> u32 18)
    digit (x >>> u32 12)
    if pad then
      Buffer.push (u8 61) out
      Buffer.push (u8 61) out
  else if n - i = 2 then
    let x = (u32 b.[i] <<< u32 16) ||| (u32 b.[i + 1] <<< u32 8)
    digit (x >>> u32 18)
    digit (x >>> u32 12)
    digit (x >>> u32 6)
    if pad then
      Buffer.push (u8 61) out
  String.ofBytes out

// a character's value in the alphabet whose last two are `c62` and `c63`, or -1
let private value (c62: u8) (c63: u8) (c: u8) : int =
  if c >= u8 65 && c <= u8 90 then int c - 65
  else if c >= u8 97 && c <= u8 122 then int c - 71
  else if c >= u8 48 && c <= u8 57 then int c + 4
  else if c = c62 then 62
  else if c = c63 then 63
  else -1

// padding is required when `pad`, else not allowed; bits left over in the last character must be
// zero, so each text decodes from one encoding only
let private decodeWith (c62: u8) (c63: u8) (pad: bool) (s: string) : option<array<u8>> =
  let total = String.length s
  let mutable n = total
  if pad && n % 4 = 0 && n > 0 && String.byte s (n - 1) = u8 61 then
    n <- n - 1
    if String.byte s (n - 1) = u8 61 then
      n <- n - 1
  let tail = n % 4
  if tail = 1 || (pad && total % 4 <> 0) then
    None
  else
    let out = Buffer.empty
    let mutable ok = true
    let mutable acc = u32 0
    let mutable bits = 0
    let mutable i = 0
    while ok && i < n do
      let v = value c62 c63 (String.byte s i)
      if v < 0 then
        ok <- false
      else
        acc <- ((acc <<< u32 6) ||| u32 v) &&& u32 0xFFFFFF
        bits <- bits + 6
        if bits >= 8 then
          bits <- bits - 8
          Buffer.push (u8 (acc >>> u32 bits)) out
      i <- i + 1
    if ok && (acc &&& ((u32 1 <<< u32 bits) - u32 1)) = u32 0 then
      Some(Buffer.toArray out)
    else
      None

/// The bytes in standard base64, padded with `=`.
///
/// ```zsharp
/// println (Base64.encode (String.bytes "hello"))
/// println (Base64.encodeUrl [| u8 0xFB; u8 0xFF |])
/// // => aGVsbG8=
/// // => -_8
/// ```
let encode (b: span<u8>) : string = encodeWith standard true b

/// The bytes in URL-safe base64 (`-` and `_`), without padding.
let encodeUrl (b: span<u8>) : string = encodeWith url false b

/// The bytes standard, padded base64 gives, or `None` when it isn't that.
let decode (s: string) : option<array<u8>> = decodeWith (u8 43) (u8 47) true s

/// The bytes URL-safe, unpadded base64 gives, or `None` when it isn't that.
let decodeUrl (s: string) : option<array<u8>> = decodeWith (u8 45) (u8 95) false s
