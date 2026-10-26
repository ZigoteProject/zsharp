// A Z# library Rust calls (src/main.rs): build.rs builds it with zs build --lib, and main.rs
// declares what its header (stats.h, written beside the archive) declares
[<CLayout>]
type Summary = { count: int; mean: f64; low: f64; high: f64 }

/// How many numbers there are, their mean, the lowest and the highest, of `n` at `data` (Rust's
/// slice: C's memory, read as a span for the call, which is what `unsafe` promises).
[<Export "zs_summary">]
let summary (data: ptr<f64>) (n: int) : Summary =
  let xs = unsafe Span.ofPtr data n
  if Span.isEmpty xs then
    { count = 0; mean = 0.0; low = 0.0; high = 0.0 }
  else
    let low = Array.fold (fun m x -> if x < m then x else m) xs.[0] xs
    let high = Array.fold (fun m x -> if x > m then x else m) xs.[0] xs
    { count = n; mean = Array.sum xs / float n; low = low; high = high }

/// The middle one of `n` numbers at `data`, the mean of the two middle ones for an even count.
[<Export "zs_median">]
let median (data: ptr<f64>) (n: int) : f64 =
  let sorted = Array.sort (unsafe Span.ofPtr data n)
  if n = 0 then 0.0
  else if n % 2 = 1 then sorted.[n / 2]
  else (sorted.[n / 2 - 1] + sorted.[n / 2]) / 2.0

/// How many words a C string has (runs of characters between spaces).
[<Export "zs_words">]
let words (text: cstr) : int =
  String.ofCStr text |> String.split " " |> List.filter (fun w -> w <> "") |> List.length
