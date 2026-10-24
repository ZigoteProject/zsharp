// A small property checker. Random inputs come from the Gen effect: a generator is plain code
// that calls Gen.below, and `check` answers from a seeded LCG, so a failure repeats every run.
// FsCheck's Gen, without the monad.

effect Gen =
  abstract below : int -> int          // a number from 0 up to n - 1

let pick xs = List.item (Gen.below (List.length xs)) xs

// a 64-bit LCG (Knuth's MMIX constants): overflow is the point, so it wraps
let private step (s: int) = Int.wrappingAdd (Int.wrappingMul s 6364136223846793005) 1442695040888963407

// runs prop `runs` times; each run gives what it generated and whether the property held.
// The first counterexample, or None: `assert (check … = None)` prints it when it fails.
let check (runs: int) (prop: unit -> 'a * bool) =
  let mutable s = 2025
  let mutable failed = None
  for _ in 1 .. runs do
    if Option.isNone failed then
      let (input, ok) =
        handle prop () with
        | Gen.below n, k ->
          s <- step s
          k (Math.abs (s / 4294967296) % n)
      if not ok then failed <- Some input
  failed
