/// Spans: read-only windows into an array, a string's bytes or a Buffer, without a copy:
/// `a.[1..3]`, `a.[..n]`, `a.[i..]`, `String.bytes s`. A span holds a reference to what it
/// windows, which lives as long as the span does. An array or a Buffer becomes a span where
/// one is expected, so the functions that read arrays (`Array.sum`, `Array.fold`, …) read
/// all three.
module Collections.Span

/// Whether the span has no elements.
let isEmpty (s: span<'a>) = Span.length s = 0

/// The `n` elements from index `i`, without a copy: `s.[i .. i + n - 1]`.
let slice (s: span<'a>) i n = s.[i .. i + n - 1]

/// Whether `s` begins with the elements of `p`.
let startsWith (p: span<'a>) (s: span<'a>) =
  let n = Span.length p
  let mutable ok = n <= Span.length s
  let mutable i = 0
  while ok && i < n do
    ok <- s.[i] = p.[i]
    i <- i + 1
  ok

/// The index of the first occurrence of `sub` in `s`, or `None` (`Some 0` for an empty `sub`).
///
/// ```zsharp
/// let request = String.bytes "GET / HTTP/1.1\r\nHost: a\r\n\r\nbody"
/// println $"{Span.indexOf (String.bytes "\r\n\r\n") request}"
/// // => Some 23
/// ```
let indexOf (sub: span<'a>) (s: span<'a>) : option<int> =
  let n = Span.length sub
  let last = Span.length s - n
  let mutable i = 0
  let mutable found = -1
  while found < 0 && i <= last do
    if Span.startsWith sub s.[i..] then
      found <- i
    i <- i + 1
  if found < 0 then None else Some found

// an ASCII letter in lower case, any other byte as it is
let private lower (b: u8) = if b >= u8 65 && b <= u8 90 then b + u8 32 else b

/// Whether two spans of bytes are equal, ASCII letters in either case (`Content-Length` and
/// `content-length`); other bytes must match exactly.
let equalsIgnoreCase (a: span<u8>) (b: span<u8>) =
  let n = Span.length a
  let mutable ok = n = Span.length b
  let mutable i = 0
  while ok && i < n do
    ok <- lower a.[i] = lower b.[i]
    i <- i + 1
  ok

let private isSpace (b: u8) = b = u8 32 || b = u8 9 || b = u8 10 || b = u8 13

/// The bytes without the ASCII spaces, tabs and line breaks at either end, without a copy.
let trim (s: span<u8>) : span<u8> =
  let mutable i = 0
  let mutable n = Span.length s
  while i < n && isSpace s.[i] do
    i <- i + 1
  while n > i && isSpace s.[n - 1] do
    n <- n - 1
  s.[i .. n - 1]

/// The decimal integer the bytes write: an optional `-` or `+`, then digits and nothing else;
/// `None` for anything else or a number outside the `int` range.
///
/// ```zsharp
/// println $"{Span.parseInt (String.bytes "-42")} {Span.parseInt (String.bytes "4x")}"
/// // => Some -42 None
/// ```
let parseInt (s: span<u8>) : option<int> =
  let n = Span.length s
  let negative = n > 0 && s.[0] = u8 45
  let start = if n > 0 && (negative || s.[0] = u8 43) then 1 else 0
  let mutable ok = start < n
  let mutable x = 0
  let mutable i = start
  // accumulated negative, so the most negative int reads too (`int` is 32 bits on a chip)
  let limit = 1 <<< (8 * sizeof<int> -1)
  while ok && i < n do
    let d = int s.[i] - 48
    if d < 0 || d > 9 || x < (limit + d) / 10 then
      ok <- false
    else
      x <- x * 10 - d
    i <- i + 1
  if not ok then None
  else if negative then Some x
  else if x = limit then None
  else Some(-x)

type span<'a> with
  /// The number of elements.
  member s.Length = Span.length s

/// A span's elements, by index.
impl Iter<span<'a>, 'a> =
  let forEach (s: span<'a>) f =
    let n = Span.length s
    let mutable i = 0
    let mutable ok = true
    while ok && i < n do
      ok <- f s.[i]
      i <- i + 1
    ok
