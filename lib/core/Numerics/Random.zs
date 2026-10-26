/// Numbers beyond the built-in ones: `Random`, a seeded generator of pseudo-random numbers.
namespace Numerics

/// A generator of pseudo-random numbers: PCG32 (Melissa O'Neill's, pcg-random.org), 64 bits of
/// state, so a seed gives the same numbers on every target. Not for secrets. It changes as it's
/// used, so a `Random` isn't `Share`: each thread makes its own. `Random.shared ()` (Std) is one
/// seeded from the operating system.
type Random = { state: ref<u64>; inc: u64 }

/// Functions on `Random`.
module Random =
  // the next 32 bits: a step of the state, then its high bits permuted
  let private step (r: Random) : u32 =
    let old = r.state.Value
    let mult: u64 = 6364136223846793005
    r.state.Value <- Int.wrappingAdd (Int.wrappingMul old mult) r.inc
    let mixed = u32 (((old >>> 18) ^^^ old) >>> 27)
    let rot = u32 (old >>> 59)
    (mixed >>> rot) ||| (mixed <<< ((u32 32 - rot) &&& u32 31))

  /// A generator seeded with `seed`: the same seed gives the same numbers.
  let create (seed: u64) : Random =
    // PCG's reference seeding, stream 54
    let r = { state = ref (u64 0); inc = u64 109 }
    step r |> ignore
    r.state.Value <- Int.wrappingAdd r.state.Value seed
    step r |> ignore
    r

  /// The next 32 random bits.
  let nextU32 (r: Random) : u32 = step r

  // the next 64 random bits
  let private next64 (r: Random) : u64 = (u64 (step r) <<< 32) ||| u64 (step r)

  /// A number from `low` up to but not including `high`, each as likely as the others: a draw
  /// that would favor some is drawn again.
  let nextInt (low: int) (high: int) (r: Random) : int =
    if high <= low then
      panic $"Random.nextInt: high ({high}) must be above low ({low})"
    let range = u64 (Int.wrappingSub (i64 high) (i64 low))
    if range <= u64 4294967295 then
      let n = u32 range
      // below this, some remainders would come once more than others
      let limit = Int.wrappingSub (u32 0) n % n
      let mutable x = step r
      while x < limit do
        x <- step r
      Int.wrappingAdd low (int (x % n))
    else
      let limit = Int.wrappingSub (u64 0) range % range
      let mutable x = next64 r
      while x < limit do
        x <- next64 r
      Int.wrappingAdd low (int (x % range))

  /// A number from 0 up to but not including 1, with 53 random bits.
  let nextFloat (r: Random) : f64 = f64 (next64 r >>> 11) * 1.1102230246251565e-16

  /// Fills `bytes` with random bytes.
  let nextBytes (bytes: Buffer<u8>) (r: Random) : unit =
    for i in 0 .. Buffer.length bytes - 1 do
      bytes.[i] <- u8 (step r)

  /// The items in a random order, each order as likely (Fisher-Yates); in place when the array
  /// isn't shared.
  let shuffle (items: array<'a>) (r: Random) : array<'a> =
    let mutable a = items
    for k in 0 .. Array.length a - 2 do
      let i = Array.length a - 1 - k
      let j = nextInt 0 (i + 1) r
      let t = a.[i]
      a.[i] <- a.[j]
      a.[j] <- t
    a
