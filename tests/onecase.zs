// a one-case union with fields has no tag (decision 66): a newtype over an int is the int (its
// size, in arrays and records too), several fields a struct of them; matching, equality, show
// and hash are the field's. One over a heap value stays boxed (its count is in the object).
open Numerics
type UserId = UserId of int
type Pair = Pair of i16 * i8
type Wrap = Wrap of string
let bump (UserId n) = UserId(n + 1)
let main () =
  let xs = [| Q15.ofFloat 0.5; Q15.ofFloat 0.25 |]
  let (Pair(a, b)) = Pair(i16 7, i8 3)
  let (UserId n) = bump (UserId 41)
  println $"{sizeof<q7>} {sizeof<q15>} {sizeof<q31>} {sizeof<UserId>} {sizeof<Pair>} {sizeof<Wrap>} {n} {a} {b} {xs.[1]} {Q15.raw xs.[0]}"
  match Pair(i16 1, i8 2) with
  | Pair(p, x) when p = i16 1 -> println $"one {x}"
  | Pair(_, x) -> println $"other {x}"
  println $"{UserId 3 = UserId 3} {UserId 3 = UserId 4} {UserId 5} {Pair(i16 1, i8 2)} {Wrap "s"} {Wrap "s" = Wrap "s"} {Hash.hash (UserId 5) = Hash.hash (UserId 5)}"
  0
