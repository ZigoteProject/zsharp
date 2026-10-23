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

  /// A set of the list's elements.
  let ofList (xs: list<'a>) = List.fold (fun s x -> Set.add x s) Set.empty xs

  /// The elements in either set.
  let union (a: Set<'a>) (b: Set<'a>) = List.fold (fun s x -> Set.add x s) a (Set.toList b)

  /// The elements in both sets.
  let intersect (a: Set<'a>) (b: Set<'a>) =
    Set.ofList (List.filter (fun x -> Set.contains x b) (Set.toList a))

  /// The elements of `a` that aren't in `b`.
  let difference (a: Set<'a>) (b: Set<'a>) =
    Set.ofList (List.filter (fun x -> not (Set.contains x b)) (Set.toList a))

/// Sets print as `set [1; 2; 3]`.
impl Show<Set<'a>> =
  let show s = "set " + show (Set.toList s)
