/// Binary formats and protocols: numbers read from and written to bytes at an offset, in big-
/// or little-endian order (`Bytes.readU16BE data 4`, `Bytes.writeF64LE out 0 x`); a read or
/// write past the end panics, as indexing does. And a `Writer`, over a growing `Buffer<u8>` or
/// fixed C memory: the `append` functions add to it and return it, so a response is a pipeline:
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

/// The `f32` at offset `at`, big-endian (its IEEE 754 bits).
let readF32BE (b: span<u8>) (at: int) : f32 = Float.ofBits32 (u32 (be b at 4))
/// The `f32` at offset `at`, little-endian.
let readF32LE (b: span<u8>) (at: int) : f32 = Float.ofBits32 (u32 (le b at 4))
/// The `f64` at offset `at`, big-endian (its IEEE 754 bits).
let readF64BE (b: span<u8>) (at: int) : f64 = Float.ofBits (be b at 8)
/// The `f64` at offset `at`, little-endian.
let readF64LE (b: span<u8>) (at: int) : f64 = Float.ofBits (le b at 8)
/// Writes the `f32` at offset `at`, big-endian (its IEEE 754 bits).
let writeF32BE (b: Buffer<u8>) (at: int) (x: f32) = putBE b at 4 (u64 (Float.toBits32 x))
/// Writes the `f32` at offset `at`, little-endian.
let writeF32LE (b: Buffer<u8>) (at: int) (x: f32) = putLE b at 4 (u64 (Float.toBits32 x))
/// Writes the `f64` at offset `at`, big-endian (its IEEE 754 bits).
let writeF64BE (b: Buffer<u8>) (at: int) (x: f64) = putBE b at 8 (Float.toBits x)
/// Writes the `f64` at offset `at`, little-endian.
let writeF64LE (b: Buffer<u8>) (at: int) (x: f64) = putLE b at 8 (Float.toBits x)

// a Writer's fixed memory and how much of it is written
type private Memory = { at: ptr<u8>; capacity: int; length: int }

/// Where the `append` functions write: a growing `Buffer<u8>` (`Bytes.writerOf`), or fixed
/// memory C owns, such as a socket's send buffer (`Bytes.writer`), where writing past the end
/// panics. A value: each write gives the Writer back, longer, so writes chain,
/// `w |> Bytes.append b"OK" |> Bytes.appendInt n`; `Bytes.written` is what they wrote.
type Writer =
  /// Bytes pushed onto a Buffer, which the Buffer's other references see.
  | Growing of Buffer<u8>
  /// Bytes written into fixed memory, from its start; only `Bytes.writer` makes one.
  | Fixed of Memory

/// A Writer that pushes onto the Buffer.
///
/// ```zsharp
/// let w = Bytes.writerOf Buffer.empty |> Bytes.append b"n=" |> Bytes.appendInt -1205
/// println (String.ofBytes (Bytes.written w))
/// // => n=-1205
/// ```
let writerOf (b: Buffer<u8>) : Writer = Growing b

/// A Writer over the `capacity` bytes at `p`, empty. Unsafe: the memory must stay valid, and
/// written by nothing else, while the Writer and the spans `Bytes.written` gives are used.
[<Unsafe>]
let writer (p: ptr<u8>) (capacity: int) : Writer =
  if Ptr.isNull p || capacity < 0 then
    panic "Bytes.writer: a null pointer or a negative capacity"
  Fixed { at = p; capacity = capacity; length = 0 }

/// The bytes written so far, without a copy: a growing Writer's whole Buffer, a fixed one's
/// memory up to its length.
let written (w: Writer) : span<u8> =
  match w with
  | Growing b -> b
  | Fixed m -> unsafe (Span.ofPtr m.at m.length)

/// How many more bytes fit: the most an `int` holds for a growing Writer.
let remaining (w: Writer) : int =
  match w with
  | Growing _ -> (1 <<< (8 * sizeof<int> -1)) - 1
  | Fixed m -> m.capacity - m.length

/// The Writer emptied (its Buffer cleared, or its memory to be written again from the start).
let reset (w: Writer) : Writer =
  match w with
  | Growing b ->
    Buffer.truncate 0 b
    w
  | Fixed m -> Fixed { m with length = 0 }

/// Adds the byte at the end of `out`, and returns it.
let put (b: u8) (out: Writer) : Writer =
  match out with
  | Growing buf ->
    Buffer.push b buf
    out
  | Fixed m ->
    if m.length >= m.capacity then
      panic "Bytes.Writer is full"
    unsafe (Ptr.write (Ptr.add m.at m.length) b)
    Fixed { m with length = m.length + 1 }

/// Adds the bytes at the end of `out`, and returns it.
let append (bytes: span<u8>) (out: Writer) : Writer =
  let n = Span.length bytes
  match out with
  | Growing buf ->
    for i in 0 .. n - 1 do
      Buffer.push bytes.[i] buf
    out
  | Fixed m ->
    if n > m.capacity - m.length then
      panic "Bytes.Writer is full"
    unsafe
      for i in 0 .. n - 1 do
        Ptr.write (Ptr.add m.at (m.length + i)) bytes.[i]
    Fixed { m with length = m.length + n }

/// Adds the string's UTF-8 bytes at the end of `out`, and returns it.
let appendUtf8 (s: string) (out: Writer) : Writer = Bytes.append (String.bytes s) out

/// Adds the integer in decimal (`-` before a negative one) at the end of `out`, and returns it;
/// nothing is allocated (but a Buffer's growth).
///
/// ```zsharp
/// let w = Bytes.writerOf Buffer.empty |> Bytes.appendInt -1205 |> Bytes.appendInt 0
/// println (String.ofBytes (Bytes.written w))
/// // => -12050
/// ```
let appendInt (n: int) (out: Writer) : Writer =
  let mutable o = if n < 0 then Bytes.put (u8 45) out else out
  // from the most significant digit, each from a negative remainder, so the most negative int
  // works too
  let x = if n < 0 then n else -n
  let mutable p = 1
  while x / p <= -10 do
    p <- p * 10
  while p > 0 do
    o <- Bytes.put (u8 (48 - x / p % 10)) o
    p <- p / 10
  o

// whether JSON needs a byte escaped: a control character, `"` or `\`
let private needsEscape (b: u8) = b < u8 32 || b = u8 34 || b = u8 92

let private hex = "0123456789abcdef"

/// Adds the string as a JSON string, quoted and escaped (`"`, `\` and the control characters;
/// every other character as its UTF-8, as `Json.print` writes one), and returns `out`. The
/// string is scanned 16 bytes at a time.
///
/// ```zsharp
/// println (String.ofBytes (Bytes.written (Bytes.appendJsonString "say \"hi\"\n" (Bytes.writerOf Buffer.empty))))
/// // => "say \"hi\"\n"
/// ```
let appendJsonString (s: string) (out: Writer) : Writer =
  let b = String.bytes s
  let n = Span.length b
  let mutable o = Bytes.put (u8 34) out
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
    o <- Bytes.append b.[i .. j - 1] o
    if j < n then
      let c = b.[j]
      o <- Bytes.put (u8 92) o
      if c = u8 34 || c = u8 92 then o <- Bytes.put c o
      else if c = u8 10 then o <- Bytes.put (u8 110) o
      else if c = u8 13 then o <- Bytes.put (u8 114) o
      else if c = u8 9 then o <- Bytes.put (u8 116) o
      else if c = u8 8 then o <- Bytes.put (u8 98) o
      else if c = u8 12 then o <- Bytes.put (u8 102) o
      else
        o <- Bytes.append b"u00" o
        o <- Bytes.put (String.byte hex (int (c >>> u8 4))) o
        o <- Bytes.put (String.byte hex (int (c &&& u8 15))) o
    i <- j + 1
  Bytes.put (u8 34) o
