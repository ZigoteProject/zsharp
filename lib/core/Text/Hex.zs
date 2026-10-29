/// Hexadecimal: bytes as two digits each, and back.
module Text.Hex

let private digits = "0123456789abcdef"

// a hex digit's value, either case, or -1
let private value (c: u8) : int =
  if c >= u8 48 && c <= u8 57 then int c - 48
  else if c >= u8 97 && c <= u8 102 then int c - 87
  else if c >= u8 65 && c <= u8 70 then int c - 55
  else -1

/// The bytes as lower-case hex digits, two a byte.
///
/// ```zsharp
/// println (Hex.encode [| u8 0; u8 0xAB; u8 255 |])
/// // => 00abff
/// ```
let encode (b: span<u8>) : string =
  let out = Buffer.create (2 * Array.length b) (u8 0)
  for i in 0 .. Array.length b - 1 do
    out.[2 * i] <- String.byte digits (int (b.[i] >>> u8 4))
    out.[2 * i + 1] <- String.byte digits (int (b.[i] &&& u8 15))
  String.ofBytes out

/// The bytes the hex digits (either case, two a byte) give, or `None` for an odd count or
/// anything that isn't a digit.
let decode (s: string) : option<array<u8>> =
  let n = String.length s
  if n % 2 <> 0 then
    None
  else
    let mutable out = Array.create (n / 2) (u8 0)
    let mutable ok = true
    let mutable i = 0
    while ok && i < n / 2 do
      let hi = value (String.byte s (2 * i))
      let lo = value (String.byte s (2 * i + 1))
      if hi < 0 || lo < 0 then ok <- false else out.[i] <- u8 (hi * 16 + lo)
      i <- i + 1
    if ok then Some out else None
