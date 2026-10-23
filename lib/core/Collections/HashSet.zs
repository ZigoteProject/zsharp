/// Hash sets, for elements with `Hash` and `Eq`.
namespace Collections

/// A hash set (elements with `Hash` and `Eq`). It is a value like an array: `HashSet.add` gives
/// the changed set, updated in place when nothing else refers to the old one.
type HashSet<'a> =
  { /// Chains of elements; an element's bucket is its hash modulo the bucket count.
    buckets: array<list<'a>>
    /// The number of elements.
    size: int }

/// Functions on `HashSet`.
module HashSet =
  let private bucketOf x (n: int) =
    let h = hash x % n
    if h < 0 then h + n else h

  /// An empty hash set (with no buckets yet: the first `add` makes them).
  let empty : HashSet<'a> = { buckets = [||]; size = 0 }

  /// Whether the set has `x`.
  let contains x (s: HashSet<'a>) =
    if Array.length s.buckets = 0 then
      false
    else
      List.contains x s.buckets.[bucketOf x (Array.length s.buckets)]

  /// The number of elements.
  let count (s: HashSet<'a>) = s.size

  /// The elements, in no particular order.
  let toList (s: HashSet<'a>) = Array.fold (fun acc b -> List.append b acc) [] s.buckets

  // moves every element into twice as many buckets (8 for the first)
  let private hashGrow (s: HashSet<'a>) =
    let n = max 8 (2 * Array.length s.buckets)
    let mutable buckets = Array.create n []
    for b in s.buckets do
      for x in b do
        let i = bucketOf x n
        buckets.[i] <- x :: buckets.[i]
    { buckets = buckets; size = s.size }

  /// The set with `x` (the same set when it has `x` already).
  let add x (s: HashSet<'a>) =
    let s = if s.size >= 2 * Array.length s.buckets then hashGrow s else s
    let size = s.size
    let mutable buckets = s.buckets // s's last use, so a unique set's array stays unique
    let i = bucketOf x (Array.length buckets)
    if List.contains x buckets.[i] then
      { buckets = buckets; size = size }
    else
      buckets.[i] <- x :: buckets.[i]
      { buckets = buckets; size = size + 1 }

  // the set without `x`, which has buckets
  let private removeFrom x (s: HashSet<'a>) =
    let size = s.size
    let mutable buckets = s.buckets // s's last use, so a unique set's array stays unique
    let i = bucketOf x (Array.length buckets)
    let old = buckets.[i]
    let present = List.contains x old
    buckets.[i] <- List.filter (fun y -> y <> x) old
    { buckets = buckets; size = if present then size - 1 else size }

  /// The set without `x`.
  let remove x (s: HashSet<'a>) = if Array.length s.buckets = 0 then s else HashSet.removeFrom x s

  /// A hash set of the elements.
  let ofList (xs: list<'a>) = List.fold (fun s x -> HashSet.add x s) HashSet.empty xs

  /// The elements of either set.
  let union (a: HashSet<'a>) (b: HashSet<'a>) =
    List.fold (fun s x -> HashSet.add x s) a (HashSet.toList b)

  /// The elements of `a` that `b` has too.
  let intersect (a: HashSet<'a>) (b: HashSet<'a>) =
    HashSet.ofList (List.filter (fun x -> HashSet.contains x b) (HashSet.toList a))

  /// The elements of `a` that `b` doesn't have.
  let difference (a: HashSet<'a>) (b: HashSet<'a>) =
    HashSet.ofList (List.filter (fun x -> not (HashSet.contains x b)) (HashSet.toList a))

/// A hash set's elements in bucket order, which is unspecified: a program that needs an order sorts
/// them (`List.sort (HashMap.toList m)`).
impl Iter<HashSet<'a>, 'a> =
  let forEach (m: HashSet<'a>) f =
    let mutable i = 0
    let mutable ok = true
    while ok && i < Array.length m.buckets do
      ok <- Iter.forEach m.buckets.[i] f
      i <- i + 1
    ok
