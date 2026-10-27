/// Persistent sorted sets, a `Map` to unit underneath.
namespace Collections

/// A persistent sorted set (a `Map` to unit underneath).
type Set<'a> =
  { /// The elements, as the keys of a map.
    items: Map<'a, unit> }

/// Functions on `Set`.
module Set =
  /// The empty set.
  let empty : Set<'a> = { items = MapLeaf }

  /// The set with `x` added.
  let add x (s: Set<'a>) = { items = Map.add x () s.items }

  /// The set without `x`.
  let remove x (s: Set<'a>) = { items = Map.remove x s.items }

  /// Whether the set contains `x`.
  let contains x (s: Set<'a>) = Map.containsKey x s.items

  /// The number of elements. O(n).
  let count (s: Set<'a>) = Map.count s.items

  /// Whether the set has no elements.
  let isEmpty (s: Set<'a>) = Map.isEmpty s.items

  /// The elements in ascending order.
  let toList (s: Set<'a>) = Map.keys s.items

  /// A set of a collection's elements: a list, an array, a string's characters, …
  let ofIter (xs: 'c) : Set<'a> =
    let mutable s = Set.empty
    for x in xs do
      s <- Set.add x s
    s

  /// A set of the list's elements.
  let ofList (xs: list<'a>) = List.fold (fun s x -> Set.add x s) Set.empty xs

  // a tree's height: how deep it is, known at its root
  let private height (s: Set<'a>) =
    match s.items with
    | MapLeaf -> 0
    | MapNode (_, _, _, _, h) -> h

  // the set of elements in ascending order, without repeats: a balanced tree built from the middle
  // out, with no comparisons
  let private ofAscending (xs: list<'a>) : Set<'a> =
    let a = Array.ofList xs
    let rec build (lo: int) (hi: int) : Map<'a, unit> =
      if lo >= hi then
        MapLeaf
      else
        let mid = lo + (hi - lo) / 2
        let l = build lo mid
        let r = build (mid + 1) hi
        let hl =
          match l with
          | MapLeaf -> 0
          | MapNode (_, _, _, _, h) -> h
        let hr =
          match r with
          | MapLeaf -> 0
          | MapNode (_, _, _, _, h) -> h
        MapNode (l, a.[mid], (), r, max hl hr + 1)
    { items = build 0 (Array.length a) }

  /// The elements in either set: the smaller one's added to the larger one.
  let union (a: Set<'a>) (b: Set<'a>) =
    if Set.isEmpty b then a
    else if Set.isEmpty a then b
    else if height a >= height b then List.fold (fun s x -> Set.add x s) a (Set.toList b)
    else List.fold (fun s x -> Set.add x s) b (Set.toList a)

  /// The elements in both sets: the smaller one's that the larger one has.
  let intersect (a: Set<'a>) (b: Set<'a>) =
    if Set.isEmpty a || Set.isEmpty b then Set.empty
    else if height a <= height b then
      ofAscending (List.filter (fun x -> Set.contains x b) (Set.toList a))
    else ofAscending (List.filter (fun x -> Set.contains x a) (Set.toList b))

  /// The elements of `a` that aren't in `b` (`a` itself when `b` has none of them).
  let difference (a: Set<'a>) (b: Set<'a>) =
    if Set.isEmpty a || Set.isEmpty b then a
    else
      let all = Set.toList a
      let kept = List.filter (fun x -> not (Set.contains x b)) all
      if List.length kept = List.length all then a else ofAscending kept

  /// Whether every element of `a` is in `b`.
  let isSubset (a: Set<'a>) (b: Set<'a>) =
    Set.count a <= Set.count b && List.forall (fun x -> Set.contains x b) (Set.toList a)

  /// Whether every element of `b` is in `a`.
  let isSuperset (a: Set<'a>) (b: Set<'a>) = Set.isSubset b a

/// By their elements: two sets with the same elements are equal whatever order they were added in.
impl Eq<Set<'a>> =
  let equal (a: Set<'a>) (b: Set<'a>) = Set.toList a = Set.toList b

/// By their elements in ascending order.
impl Ord<Set<'a>> =
  let compare (a: Set<'a>) (b: Set<'a>) = compare (Set.toList a) (Set.toList b)

/// Consistent with `Eq`.
impl Hash<Set<'a>> =
  let hash (s: Set<'a>) = hash (Set.toList s)

/// Sets print as `set [1; 2; 3]`.
impl Show<Set<'a>> =
  let show s = "set " + show (Set.toList s)

/// A set's elements in ascending order (its map's keys).
impl Iter<Set<'a>, 'a> =
  let forEach (s: Set<'a>) f = Iter.forEach s.items (fun (x, _) -> f x)
