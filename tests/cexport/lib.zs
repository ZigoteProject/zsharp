// Phase 3 exit test: a Z# static library called from C (tests/cexport/main.c)
[<CLayout>]
type Vec2 = { x: f64; y: f64 }

[<CLayout>]
type Pair = { a: i32; b: i32 }

// 40 bytes: passed and returned in memory
[<CLayout>]
type Box = { lo: Vec2; hi: Vec2; id: i32 }

// a C function that calls back into Z#
extern each : int -> callback<int -> unit> -> unit

[<Export "geo_add">]
let add (a: Vec2) (b: Vec2) : Vec2 = { x = a.x + b.x; y = a.y + b.y }

[<Export "geo_area">]
let area (r: Box) : f64 = (r.hi.x - r.lo.x) * (r.hi.y - r.lo.y)

[<Export "geo_grow">]
let grow (r: Box) (by: f64) : Box = { lo = r.lo; hi = { x = r.hi.x + by; y = r.hi.y + by }; id = r.id + i32 1 }

[<Export "geo_swap">]
let swap (p: Pair) : Pair = { a = p.b; b = p.a }

// the callback closure captures `total`
[<Export "geo_sum_squares">]
let sumSquares (n: int) : int =
  let total = ref 0
  each n (fun i -> total.Value <- total.Value + i * i)
  total.Value

[<Export "geo_label_length">]
let labelLength (s: cstr) : int = (String.ofCStr s).Length

[<Export "geo_is_square">]
let isSquare (r: Box) : bool = r.hi.x - r.lo.x = r.hi.y - r.lo.y

// panics on a zero width: C's panic hook runs, then the process stops
[<Export "geo_ratio">]
let ratio (r: Box) : int = int (r.hi.y - r.lo.y) / int (r.hi.x - r.lo.x)
