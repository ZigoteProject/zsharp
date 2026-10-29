/// Binary formats and protocols: integers read from and written to bytes at an offset, in big-
/// or little-endian order (`Bytes.readU16BE data 4`, `Bytes.writeU32LE out 0 n`); a read or
/// write past the end panics, as indexing does. And a writer: the `append` functions add to a
/// growing `Buffer<u8>` and return it, so a response is a pipeline:
/// `out |> Bytes.append b"Content-Length: " |> Bytes.appendInt n |> Bytes.append b"\r\n"`.
module Bytes

// the `n` bytes from `at` as one integer, the first byte the most significant
let private be (b: span<u8>) (at: int) (n: int) : u64 =
  let mutable x = u64 0
  for i in 0 .. n - 1 do
    x <- (x <<< u64 8) ||| u64 b.[at + i]
  x

// the `n` bytes from `at` as one integer, the first byte the least significant
let private le (b: span<u8>) (at: int) (n: int) : u64 =
  let mutable x = u64 0
  for i in n - 1 .. -1 .. 0 do
    x <- (x <<< u64 8) ||| u64 b.[at + i]
  x

// `x`'s low `n` bytes written from `at`, the most significant first
let private putBE (b: Buffer<u8>) (at: int) (n: int) (x: u64) =
  for i in 0 .. n - 1 do
    b.[at + i] <- u8 (x >>> u64 (8 * (n - 1 - i)))

// `x`'s low `n` bytes written from `at`, the least significant first
let private putLE (b: Buffer<u8>) (at: int) (n: int) (x: u64) =
  for i in 0 .. n - 1 do
    b.[at + i] <- u8 (x >>> u64 (8 * i))

/// The `u16` at offset `at`, big-endian (network order).
///
/// ```zsharp
/// println $"{Bytes.readU16BE [| u8 1; u8 2 |] 0} {Bytes.readU16LE [| u8 1; u8 2 |] 0}"
/// // => 258 513
/// ```
let readU16BE (b: span<u8>) (at: int) : u16 = u16 (be b at 2)
/// The `u16` at offset `at`, little-endian.
let readU16LE (b: span<u8>) (at: int) : u16 = u16 (le b at 2)
/// The `u32` at offset `at`, big-endian (network order).
let readU32BE (b: span<u8>) (at: int) : u32 = u32 (be b at 4)
/// The `u32` at offset `at`, little-endian.
let readU32LE (b: span<u8>) (at: int) : u32 = u32 (le b at 4)
/// The `u64` at offset `at`, big-endian (network order).
let readU64BE (b: span<u8>) (at: int) : u64 = be b at 8
/// The `u64` at offset `at`, little-endian.
let readU64LE (b: span<u8>) (at: int) : u64 = le b at 8
/// The `i16` at offset `at`, big-endian (network order).
let readI16BE (b: span<u8>) (at: int) : i16 = i16 (be b at 2)
/// The `i16` at offset `at`, little-endian.
let readI16LE (b: span<u8>) (at: int) : i16 = i16 (le b at 2)
/// The `i32` at offset `at`, big-endian (network order).
let readI32BE (b: span<u8>) (at: int) : i32 = i32 (be b at 4)
/// The `i32` at offset `at`, little-endian.
let readI32LE (b: span<u8>) (at: int) : i32 = i32 (le b at 4)
/// The `i64` at offset `at`, big-endian (network order).
let readI64BE (b: span<u8>) (at: int) : i64 = i64 (be b at 8)
/// The `i64` at offset `at`, little-endian.
let readI64LE (b: span<u8>) (at: int) : i64 = i64 (le b at 8)

/// Writes the `u16` at offset `at`, big-endian (network order), over the bytes there.
let writeU16BE (b: Buffer<u8>) (at: int) (x: u16) = putBE b at 2 (u64 x)
/// Writes the `u16` at offset `at`, little-endian.
let writeU16LE (b: Buffer<u8>) (at: int) (x: u16) = putLE b at 2 (u64 x)
/// Writes the `u32` at offset `at`, big-endian (network order).
let writeU32BE (b: Buffer<u8>) (at: int) (x: u32) = putBE b at 4 (u64 x)
/// Writes the `u32` at offset `at`, little-endian.
let writeU32LE (b: Buffer<u8>) (at: int) (x: u32) = putLE b at 4 (u64 x)
/// Writes the `u64` at offset `at`, big-endian (network order).
let writeU64BE (b: Buffer<u8>) (at: int) (x: u64) = putBE b at 8 x
/// Writes the `u64` at offset `at`, little-endian.
let writeU64LE (b: Buffer<u8>) (at: int) (x: u64) = putLE b at 8 x
/// Writes the `i16` at offset `at`, big-endian (network order).
let writeI16BE (b: Buffer<u8>) (at: int) (x: i16) = putBE b at 2 (u64 x)
/// Writes the `i16` at offset `at`, little-endian.
let writeI16LE (b: Buffer<u8>) (at: int) (x: i16) = putLE b at 2 (u64 x)
/// Writes the `i32` at offset `at`, big-endian (network order).
let writeI32BE (b: Buffer<u8>) (at: int) (x: i32) = putBE b at 4 (u64 x)
/// Writes the `i32` at offset `at`, little-endian.
let writeI32LE (b: Buffer<u8>) (at: int) (x: i32) = putLE b at 4 (u64 x)
/// Writes the `i64` at offset `at`, big-endian (network order).
let writeI64BE (b: Buffer<u8>) (at: int) (x: i64) = putBE b at 8 (u64 x)
/// Writes the `i64` at offset `at`, little-endian.
let writeI64LE (b: Buffer<u8>) (at: int) (x: i64) = putLE b at 8 (u64 x)

/// Adds the bytes at the end of `out`, and returns `out`.
let append (bytes: span<u8>) (out: Buffer<u8>) : Buffer<u8> =
  for i in 0 .. Span.length bytes - 1 do
    Buffer.push bytes.[i] out
  out

/// Adds the string's UTF-8 bytes at the end of `out`, and returns `out`.
let appendUtf8 (s: string) (out: Buffer<u8>) : Buffer<u8> = Bytes.append (String.bytes s) out

/// Adds the integer in decimal (`-` before a negative one) at the end of `out`, and returns
/// `out`; nothing is allocated but the Buffer's growth.
///
/// ```zsharp
/// let out = Buffer.empty |> Bytes.append b"n=" |> Bytes.appendInt -1205 |> Bytes.appendInt 0
/// println (String.ofBytes out)
/// // => n=-12050
/// ```
let appendInt (n: int) (out: Buffer<u8>) : Buffer<u8> =
  if n < 0 then
    Buffer.push (u8 45) out
  let start = Buffer.length out
  // the digits from the last, each from a negative remainder, so the most negative int works
  let mutable x = if n < 0 then n else -n
  Buffer.push (u8 (48 - x % 10)) out
  x <- x / 10
  while x <> 0 do
    Buffer.push (u8 (48 - x % 10)) out
    x <- x / 10
  let mutable i = start
  let mutable j = Buffer.length out - 1
  while i < j do
    let t = out.[i]
    out.[i] <- out.[j]
    out.[j] <- t
    i <- i + 1
    j <- j - 1
  out

// whether JSON needs a byte escaped: a control character, `"` or `\`
let private needsEscape (b: u8) = b < u8 32 || b = u8 34 || b = u8 92

let private hex = "0123456789abcdef"

/// Adds the string as a JSON string, quoted and escaped (`"`, `\` and the control characters;
/// every other character as its UTF-8, as `Json.print` writes one), and returns `out`. The
/// string is scanned 16 bytes at a time.
///
/// ```zsharp
/// println (String.ofBytes (Bytes.appendJsonString "say \"hi\"\n" Buffer.empty))
/// // => "say \"hi\"\n"
/// ```
let appendJsonString (s: string) (out: Buffer<u8>) : Buffer<u8> =
  let b = String.bytes s
  let n = Span.length b
  Buffer.push (u8 34) out
  let mutable i = 0
  while i < n do
    // a run of bytes that need no escape, 16 at a time while they last
    let mutable j = i
    let mutable wide = true
    while wide && j + 16 <= n do
      let v = U8x16.load b j
      if Mask16.any (U8x16.lessThan v (U8x16.splat (u8 32))) || Mask16.any (U8x16.equal v (U8x16.splat (u8 34))) || Mask16.any (U8x16.equal v (U8x16.splat (u8 92))) then
        wide <- false
      else
        j <- j + 16
    while j < n && not (needsEscape b.[j]) do
      j <- j + 1
    Bytes.append b.[i .. j - 1] out |> ignore
    if j < n then
      let c = b.[j]
      Buffer.push (u8 92) out
      if c = u8 34 || c = u8 92 then Buffer.push c out
      else if c = u8 10 then Buffer.push (u8 110) out
      else if c = u8 13 then Buffer.push (u8 114) out
      else if c = u8 9 then Buffer.push (u8 116) out
      else if c = u8 8 then Buffer.push (u8 98) out
      else if c = u8 12 then Buffer.push (u8 102) out
      else
        Bytes.append b"u00" out |> ignore
        Buffer.push (String.byte hex (int (c >>> u8 4))) out
        Buffer.push (String.byte hex (int (c &&& u8 15))) out
    i <- j + 1
  Buffer.push (u8 34) out
  out
