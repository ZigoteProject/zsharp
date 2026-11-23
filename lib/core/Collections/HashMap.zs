/// Hash maps, for keys with `Hash` and `Eq`.
namespace Collections

/// A hash map (keys with `Hash` and `Eq`). It is a value like an array: `HashMap.add` gives
/// the changed map, updated in place when nothing else refers to the old one.
type HashMap<'k, 'v> =
  { /// Chains of entries; the bucket of a key is its hash modulo the bucket count.
    buckets: array<list<'k * 'v>>
    /// The number of entries.
    size: int }

/// Functions on `HashMap`.
module HashMap =
  let private bucketOf key (n: int) =
    let h = hash key % n
    if h < 0 then h + n else h

  /// An empty hash map (with no buckets yet: the first `add` makes them).
  let empty : HashMap<'k, 'v> = { buckets = [||]; size = 0 }

  // A bucket's walks are loops of their own, with the key a parameter: no closure is made for one.

  // the value of key's entry in a bucket
  let rec private findIn key (b: list<'k * 'v>) =
    match b with
    | [] -> None
    | (k, v) :: rest -> if k = key then Some v else findIn key rest

  // whether a bucket has key's entry
  let rec private hasIn key (b: list<'k * 'v>) =
    match b with
    | [] -> false
    | (k, _) :: rest -> if k = key then true else hasIn key rest

  // the bucket without key's entry, the others in their order (acc: those passed, reversed); a
  // unique bucket is rebuilt in its own cells
  let rec private withoutIn key (acc: list<'k * 'v>) (b: list<'k * 'v>) =
    match b with
    | [] -> List.rev acc
    | (k, v) :: rest ->
      if k = key then withoutIn key acc rest else withoutIn key ((k, v) :: acc) rest

  /// The value bound to `key`, or `None`.
  let tryFind key (m: HashMap<'k, 'v>) =
    if Array.length m.buckets = 0 then
      None
    else
      findIn key m.buckets.[bucketOf key (Array.length m.buckets)]

  /// Whether the map binds `key`.
  let containsKey key (m: HashMap<'k, 'v>) = Option.isSome (HashMap.tryFind key m)

  /// The number of entries.
  let count (m: HashMap<'k, 'v>) = m.size

  /// The entries as (key, value) pairs, in no particular order.
  let toList (m: HashMap<'k, 'v>) = Array.fold (fun acc b -> List.append b acc) [] m.buckets

  // moves every entry into twice as many buckets (8 for the first)
  let private hashGrow (m: HashMap<'k, 'v>) =
    let n = max 8 (2 * Array.length m.buckets)
    let mutable buckets = Array.create n []
    for b in m.buckets do
      for kv in b do
        let i = bucketOf (fst kv) n
        buckets.[i] <- kv :: buckets.[i]
    { buckets = buckets; size = m.size }

  /// The map with `key` bound to `value` (replacing an existing binding).
  let add key value (m: HashMap<'k, 'v>) =
    let m = if m.size >= 2 * Array.length m.buckets then hashGrow m else m
    let size = m.size
    let mutable buckets = m.buckets // m's last use, so a unique map's array stays unique
    let i = bucketOf key (Array.length buckets)
    let old = buckets.[i]
    if hasIn key old then
      // taken out of the array first, so a unique map's bucket is unique too
      buckets.[i] <- []
      buckets.[i] <- (key, value) :: withoutIn key [] old
      { buckets = buckets; size = size }
    else
      buckets.[i] <- (key, value) :: old
      { buckets = buckets; size = size + 1 }

  // the map without `key`, which has buckets
  let private removeFrom key (m: HashMap<'k, 'v>) =
    let size = m.size
    let mutable buckets = m.buckets // m's last use, so a unique map's array stays unique
    let i = bucketOf key (Array.length buckets)
    let old = buckets.[i]
    if hasIn key old then
      buckets.[i] <- [] // as in add
      buckets.[i] <- withoutIn key [] old
      { buckets = buckets; size = size - 1 }
    else
      // nothing to take out: the map as it was, its array not copied
      { buckets = buckets; size = size }

  /// The map without `key`.
  let remove key (m: HashMap<'k, 'v>) =
    if Array.length m.buckets = 0 then m else HashMap.removeFrom key m

  /// A hash map with the pairs' bindings.
  let ofList (pairs: list<'k * 'v>) =
    List.fold (fun m (k, v) -> HashMap.add k v m) HashMap.empty pairs

/// By their entries: the same keys with equal values, whatever order they were added in.
impl Eq<HashMap<'k, 'v>> =
  let equal (a: HashMap<'k, 'v>) (b: HashMap<'k, 'v>) =
    a.size = b.size && List.forall (fun (k, v) -> HashMap.tryFind k b = Some v) (HashMap.toList a)

/// Consistent with `Eq`: the entries' hashes added, in no order.
impl Hash<HashMap<'k, 'v>> =
  let hash (m: HashMap<'k, 'v>) = List.fold (fun acc e -> Int.wrappingAdd acc (hash e)) m.size (HashMap.toList m)

/// A hash map's entries in bucket order, which is unspecified: a program that needs an order sorts
/// them (`List.sort (HashMap.toList m)`).
impl Iter<HashMap<'k, 'v>, 'k * 'v> =
  let forEach (m: HashMap<'k, 'v>) f =
    let mutable i = 0
    let mutable ok = true
    while ok && i < Array.length m.buckets do
      ok <- Iter.forEach m.buckets.[i] f
      i <- i + 1
    ok
