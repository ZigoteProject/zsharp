/// Parallelism: work spread over every core by the runtime's thread pool (a worker per core,
/// which take work from one another when they run out). A function another thread runs is a
/// `share<…>`: what it captures must be Share (immutable values; or an Atomic, Mutex or Channel
/// for what threads change), so no two threads change the same data at once.
namespace Threading

/// Functions that run work on the thread pool.
module Parallel =
  /// The number of threads that run the pool's work: the cores, or `ZS_WORKERS` if it's set.
  let workers () = Native.parWorkers ()

  /// Runs both functions at once (`g` on another thread when one is free), and gives both results.
  let both (f: share<unit -> 'a>) (g: share<unit -> 'b>) : 'a * 'b =
    let job = Native.parFork g
    let a = f ()
    (a, Native.parJoin job)

  /// How many indices a job takes: about 32 jobs per thread, so threads that finish early take
  /// work from the others.
  let grain (n: int) = max 1 (n / (Native.parWorkers () * 32))

  // f i for i from lo up to hi, halved until a part is at most g long; one half goes to the pool
  let rec private range (lo: int) (hi: int) (g: int) (f: share<int -> unit>) =
    if hi - lo <= g then
      for i in lo .. hi - 1 do
        f i
    else
      let mid = lo + (hi - lo) / 2
      let job = Native.parFork (fun () -> range mid hi g f)
      range lo mid g f
      Native.parJoin job

  /// Calls `f i` for each `i` from `lo` up to (not including) `hi`, spread over the pool, in no
  /// particular order. What the calls give back goes through an `Atomic`, a `Mutex` or a
  /// `Channel`; `Array.Parallel.init` builds an array instead.
  let ``for`` (lo: int) (hi: int) (f: share<int -> unit>) = range lo hi (grain (hi - lo)) f

  // the parts' results combined, halving as range does
  let rec private reduceRange (lo: int) (hi: int) (g: int) (f: share<int -> 'a>) (combine: share<'a -> 'a -> 'a>) : 'a =
    if hi - lo <= g then
      let mutable acc = f lo
      for i in lo + 1 .. hi - 1 do
        acc <- combine acc (f i)
      acc
    else
      let mid = lo + (hi - lo) / 2
      let job = Native.parFork (fun () -> reduceRange mid hi g f combine)
      let left = reduceRange lo mid g f combine
      combine left (Native.parJoin job)

  /// `f i` for each `i` from `lo` up to (not including) `hi`, combined with `combine`, spread
  /// over the pool: `zero` when the range is empty. `combine` must be associative (the parts
  /// are combined in order, but grouped any way).
  let reduce (lo: int) (hi: int) (zero: 'a) (f: share<int -> 'a>) (combine: share<'a -> 'a -> 'a>) : 'a =
    if hi <= lo then zero else reduceRange lo hi (grain (hi - lo)) f combine
