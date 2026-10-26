/// UTF-8, the encoding of every string: bytes checked, decoded and encoded. A string's own bytes
/// are `String.bytes`.
module Text.Utf8

// the length of the well-formed sequence at `at` (RFC 3629: no overlong forms, surrogates or
// values past U+10FFFF), or 0
let private sequence (b: span<u8>) (at: int) : int =
  let n = Array.length b
  let lead = b.[at]
  let more (i: int) (lo: u8) (hi: u8) = at + i < n && b.[at + i] >= lo && b.[at + i] <= hi
  let rest (i: int) = more i (u8 0x80) (u8 0xBF)
  if lead < u8 0x80 then 1
  else if lead >= u8 0xC2 && lead <= u8 0xDF then (if rest 1 then 2 else 0)
  else if lead = u8 0xE0 then (if more 1 (u8 0xA0) (u8 0xBF) && rest 2 then 3 else 0)
  else if lead = u8 0xED then (if more 1 (u8 0x80) (u8 0x9F) && rest 2 then 3 else 0)
  else if lead >= u8 0xE1 && lead <= u8 0xEF then (if rest 1 && rest 2 then 3 else 0)
  else if lead = u8 0xF0 then (if more 1 (u8 0x90) (u8 0xBF) && rest 2 && rest 3 then 4 else 0)
  else if lead = u8 0xF4 then (if more 1 (u8 0x80) (u8 0x8F) && rest 2 && rest 3 then 4 else 0)
  else if lead >= u8 0xF1 && lead <= u8 0xF3 then (if rest 1 && rest 2 && rest 3 then 4 else 0)
  else 0

/// `Ok ()` when the bytes are well-formed UTF-8, else `Error` with the offset of the first byte
/// that isn't.
///
/// ```zsharp
/// println $"{Utf8.validate [| u8 0x68; u8 0xC3; u8 0xA9 |]}"
/// println $"{Utf8.validate [| u8 0x68; u8 0xC3; u8 0x28 |]}"
/// // => Ok ()
/// // => Error 1
/// ```
let validate (bytes: span<u8>) : result<unit, int> =
  let mutable at = 0
  let mutable bad = -1
  while bad < 0 && at < Array.length bytes do
    let k = sequence bytes at
    if k = 0 then
      bad <- at
    else
      at <- at + k
  if bad < 0 then Ok() else Error bad

/// The text the bytes encode, each malformed byte as U+FFFD (�), as `for c in s` reads one.
let decode (bytes: span<u8>) : string = String.ofBytes bytes

/// The text the bytes encode, or `None` when they aren't well-formed UTF-8.
let tryDecode (bytes: span<u8>) : option<string> =
  match validate bytes with
  | Ok() -> Some(String.ofBytes bytes)
  | Error _ -> None

/// Adds the character's UTF-8 bytes (one to four) to `out`.
let encodeChar (c: char) (out: Buffer<u8>) : unit =
  let n = u32 c
  if n < u32 0x80 then
    Buffer.push (u8 n) out
  else if n < u32 0x800 then
    Buffer.push (u8 (u32 0xC0 ||| (n >>> 6))) out
    Buffer.push (u8 (u32 0x80 ||| (n &&& u32 0x3F))) out
  else if n < u32 0x10000 then
    Buffer.push (u8 (u32 0xE0 ||| (n >>> 12))) out
    Buffer.push (u8 (u32 0x80 ||| ((n >>> 6) &&& u32 0x3F))) out
    Buffer.push (u8 (u32 0x80 ||| (n &&& u32 0x3F))) out
  else
    Buffer.push (u8 (u32 0xF0 ||| (n >>> 18))) out
    Buffer.push (u8 (u32 0x80 ||| ((n >>> 12) &&& u32 0x3F))) out
    Buffer.push (u8 (u32 0x80 ||| ((n >>> 6) &&& u32 0x3F))) out
    Buffer.push (u8 (u32 0x80 ||| (n &&& u32 0x3F))) out
