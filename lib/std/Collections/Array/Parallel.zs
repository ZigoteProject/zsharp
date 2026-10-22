/// Arrays built in parallel, on the thread pool (`Threading.Parallel`).
module Collections.Array.Parallel

// the arrays of f i for parts of lo up to hi, in order, built as Parallel.for does its calls
let rec private parts (lo: int) (hi: int) (g: int) (f: share<int -> 'a>) : list<array<'a>> =
  if hi - lo <= g then
    [ Array.init (hi - lo) (fun j -> f (lo + j)) ]
  else
    let mid = lo + (hi - lo) / 2
    let job = Native.parFork (fun () -> parts mid hi g f)
    let left = parts lo mid g f
    left @ Native.parJoin job

/// The array of `f 0`, …, `f (n - 1)`, its elements computed in parallel.
let init (n: int) (f: share<int -> 'a>) : array<'a> =
  // ponytail: each part is its own array, joined at the end (a copy of the elements); writing
  // into one array would need unsafe code
  if n <= 0 then [||] else Array.concat (parts 0 n (Threading.Parallel.grain n) f)

/// The array of `f` applied to each element, computed in parallel.
let map (f: share<'a -> 'b>) (a: array<'a>) : array<'b> =
  init (Array.length a) (fun i -> f a.[i])
