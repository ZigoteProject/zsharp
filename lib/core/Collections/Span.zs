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

type span<'a> with
  /// The number of elements.
  member s.Length = Span.length s
