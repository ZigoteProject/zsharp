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

  /// The value bound to `key`, or `None`.
  let tryFind key (m: HashMap<'k, 'v>) =
    if Array.length m.buckets = 0 then
      None
    else
      let b = m.buckets.[bucketOf key (Array.length m.buckets)]
      List.tryFind (fun (k, _) -> k = key) b |> Option.map snd

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
    let present = List.exists (fun (k, _) -> k = key) old
    buckets.[i] <- (key, value) :: List.filter (fun (k, _) -> k <> key) old
    { buckets = buckets; size = if present then size else size + 1 }

  // the map without `key`, which has buckets
  let private removeFrom key (m: HashMap<'k, 'v>) =
    let size = m.size
    let mutable buckets = m.buckets // m's last use, so a unique map's array stays unique
    let i = bucketOf key (Array.length buckets)
    let old = buckets.[i]
    let present = List.exists (fun (k, _) -> k = key) old
    buckets.[i] <- List.filter (fun (k, _) -> k <> key) old
    { buckets = buckets; size = if present then size - 1 else size }

  /// The map without `key`.
  let remove key (m: HashMap<'k, 'v>) =
    if Array.length m.buckets = 0 then m else HashMap.removeFrom key m

  /// A hash map with the pairs' bindings.
  let ofList (pairs: list<'k * 'v>) =
    List.fold (fun m (k, v) -> HashMap.add k v m) HashMap.empty pairs
