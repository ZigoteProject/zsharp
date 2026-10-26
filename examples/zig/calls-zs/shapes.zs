// A Z# library Zig calls (main.zig on an OS, firmware.zig on a Cortex-M4): built with
// zs build --lib, Zig reads its header (libshapes.h) with @cImport
[<CLayout>]
type Point = { x: f64; y: f64 }

/// The area of the polygon whose corners are the `n` points at `corners` (C's memory, read as a
/// span for the call), by the shoelace formula: positive when they go counter-clockwise.
[<Export "zs_area">]
let area (corners: ptr<Point>) (n: int) : f64 =
  let ps = unsafe Span.ofPtr corners n
  let mutable twice = 0.0
  for i in 0 .. n - 1 do
    let a = ps.[i]
    let b = ps.[(i + 1) % n]
    twice <- twice + a.x * b.y - b.x * a.y
  twice / 2.0

/// The point halfway between two points.
[<Export "zs_middle">]
let middle (a: Point) (b: Point) : Point = { x = (a.x + b.x) / 2.0; y = (a.y + b.y) / 2.0 }

/// Calls `visit` with each prime up to `limit`, and gives how many there were: a C function
/// pointer called from Z#, in unsafe as calls through one are.
[<Export "zs_primes">]
let primes (limit: int) (visit: fnptr<int -> unit>) : int =
  let rec prime (n: int) (d: int) = d * d > n || (n % d <> 0 && prime n (d + 1))
  let mutable count = 0
  for n in 2 .. limit do
    if prime n 2 then
      unsafe visit n
      count <- count + 1
  count
