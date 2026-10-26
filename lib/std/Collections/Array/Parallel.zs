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

// a job per part, each part moved into its job: taken out of the list's cell, it's the job's
// only reference (decision 75)
let rec private forkEach (f: share<'a -> 'b>) (parts: list<array<'a>>) =
  match parts with
  | [] -> []
  | part :: rest ->
    let job = Native.parFork (fun () -> Array.map f part)
    job :: forkEach f rest

// the array in parts of g elements, the array given up for them (it's this function's, not
// borrowed): once it's gone, a part's elements are only the part's
let private cut (a: array<'a>) (g: int) : list<array<'a>> =
  let n = Array.length a
  if n <= g then
    [ a ]
  else
    [ for i in 0 .. g .. n - 1 -> Array.sub a i (if g < n - i then g else n - i) ]

/// The array of `f` applied to each element, computed in parallel. The array is cut into parts
/// and each moves into its job (decision 75): when the caller gives the array up, a job's
/// elements are its own and aren't marked shared.
let map (f: share<'a -> 'b>) (a: array<'a>) : array<'b> =
  let n = Array.length a

  if n = 0 then
    [||]
  else
    let parts = cut a (Threading.Parallel.grain n)
    Array.concat (List.map Native.parJoin (forkEach f parts))
