/// Persistent sorted maps: an AVL tree, as in OCaml's Map, so every operation is O(log n) and
/// leaves the old map intact.
namespace Collections

/// A persistent map from keys (ordered with `Ord`) to values. Adding or removing gives a new
/// map and leaves the old one unchanged; both share most of their structure.
type Map<'k, 'v> =
  /// The empty map.
  | MapLeaf
  /// A node: left subtree, key, value, right subtree, height.
  | MapNode of Map<'k, 'v> * 'k * 'v * Map<'k, 'v> * int

/// A map's entries in ascending key order, walked in a loop with the path to the current node in
/// a list (not a recursion), so a `for` over a map is one loop with its body in place.
impl Iter<Map<'k, 'v>, 'k * 'v> =
  let forEach m f =
    let mutable path = []
    let mutable cur = m
    let mutable ok = true
    let mutable more = true
    while ok && more do
      match cur with
      | MapNode (l, _, _, _, _) ->
        path <- cur :: path
        cur <- l
      | MapLeaf ->
        match path with
        | MapNode (_, k, v, r, _) :: rest ->
          path <- rest
          cur <- r
          ok <- f (k, v)
        | _ -> more <- false
    ok

/// Functions on `Map`.
module Map =
  let private mapHeight m =
    match m with
    | MapLeaf -> 0
    | MapNode (_, _, _, _, h) -> h

  let private mapNode l k v r = MapNode (l, k, v, r, max (mapHeight l) (mapHeight r) + 1)

  // rebalances a node whose subtrees' heights differ by at most 2
  let private mapBalance l k v r =
    let hl = mapHeight l
    let hr = mapHeight r
    if hl > hr + 1 then
      match l with
      | MapNode (ll, lk, lv, lr, _) ->
        if mapHeight ll >= mapHeight lr then mapNode ll lk lv (mapNode lr k v r)
        else
          match lr with
          | MapNode (lrl, lrk, lrv, lrr, _) ->
            mapNode (mapNode ll lk lv lrl) lrk lrv (mapNode lrr k v r)
          | MapLeaf -> mapNode l k v r
      | MapLeaf -> mapNode l k v r
    else if hr > hl + 1 then
      match r with
      | MapNode (rl, rk, rv, rr, _) ->
        if mapHeight rr >= mapHeight rl then mapNode (mapNode l k v rl) rk rv rr
        else
          match rl with
          | MapNode (rll, rlk, rlv, rlr, _) ->
            mapNode (mapNode l k v rll) rlk rlv (mapNode rlr rk rv rr)
          | MapLeaf -> mapNode l k v r
      | MapLeaf -> mapNode l k v r
    else mapNode l k v r

  /// The empty map.
  let empty : Map<'k, 'v> = MapLeaf

  /// Whether the map has no entries.
  let isEmpty (m: Map<'k, 'v>) =
    match m with
    | MapLeaf -> true
    | MapNode _ -> false

  /// The map with `key` bound to `value` (replacing an existing binding).
  let rec add key value (m: Map<'k, 'v>) =
    match m with
    | MapLeaf -> MapNode (MapLeaf, key, value, MapLeaf, 1)
    | MapNode (l, k, v, r, h) ->
      let c = compare key k
      if c = 0 then MapNode (l, key, value, r, h)
      else if c < 0 then mapBalance (Map.add key value l) k v r
      else mapBalance l k v (Map.add key value r)

  /// The value bound to `key`, or `None`.
  let rec tryFind key (m: Map<'k, 'v>) =
    match m with
    | MapLeaf -> None
    | MapNode (l, k, v, r, _) ->
      let c = compare key k
      if c = 0 then Some v else if c < 0 then Map.tryFind key l else Map.tryFind key r

  /// The value bound to `key`. Panics when there is none; see `Map.tryFind`.
  let find key (m: Map<'k, 'v>) =
    match Map.tryFind key m with
    | Some v -> v
    | None -> panic "Map.find: key not found"

  /// Whether the map binds `key`.
  let containsKey key (m: Map<'k, 'v>) = Option.isSome (Map.tryFind key m)

  let rec private mapMinBinding (m: Map<'k, 'v>) =
    match m with
    | MapNode (MapLeaf, k, v, _, _) -> (k, v)
    | MapNode (l, _, _, _, _) -> mapMinBinding l
    | MapLeaf -> panic "Map: empty"

  let rec private mapRemoveMin (m: Map<'k, 'v>) =
    match m with
    | MapNode (MapLeaf, _, _, r, _) -> r
    | MapNode (l, k, v, r, _) -> mapBalance (mapRemoveMin l) k v r
    | MapLeaf -> MapLeaf

  /// The map without `key` (the same map when `key` isn't bound).
  let rec remove key (m: Map<'k, 'v>) =
    match m with
    | MapLeaf -> MapLeaf
    | MapNode (l, k, v, r, _) ->
      let c = compare key k
      if c = 0 then
        match (l, r) with
        | (MapLeaf, _) -> r
        | (_, MapLeaf) -> l
        | _ ->
          let (mk, mv) = mapMinBinding r
          mapBalance l mk mv (mapRemoveMin r)
      else if c < 0 then mapBalance (Map.remove key l) k v r
      else mapBalance l k v (Map.remove key r)

  /// Combines the entries in ascending key order: `f state key value`.
  let rec fold f state (m: Map<'k, 'v>) =
    match m with
    | MapLeaf -> state
    | MapNode (l, k, v, r, _) -> Map.fold f (f (Map.fold f state l) k v) r

  /// The number of entries. O(n).
  let count (m: Map<'k, 'v>) =
    let mutable n = 0
    for _ in m do
      n <- n + 1
    n

  /// The entries as (key, value) pairs in ascending key order.
  let toList (m: Map<'k, 'v>) =
    let mutable acc = []
    for kv in m do
      acc <- kv :: acc
    List.rev acc

  /// A map of the pairs a collection has (a later pair wins over an earlier one with the same
  /// key): a list, an array, another map, …
  let ofIter (pairs: 'c) : Map<'k, 'v> =
    let mutable m = MapLeaf
    for (k, v) in pairs do
      m <- Map.add k v m
    m

  /// A map with the pairs' bindings (a later pair wins over an earlier one with the same key).
  let ofList (pairs: list<'k * 'v>) = List.fold (fun m (k, v) -> Map.add k v m) Map.empty pairs

  /// The map with `key`'s binding changed by `f`, given the value or `None`: a value from it binds
  /// the key, `None` removes it.
  ///
  /// ```zsharp
  /// let count (word: string) (m: Map<string, int>) = Map.change word (fun n -> Some (Option.defaultValue 0 n + 1)) m
  /// let counts = List.fold (fun m w -> count w m) Map.empty [ "a"; "b"; "a" ]
  /// println $"{Map.toList counts}"
  /// println $"{Map.toList (Map.change "a" (fun _ -> None) counts)}"
  /// // => [(a, 2); (b, 1)]
  /// // => [(b, 1)]
  /// ```
  let change (key: 'k) (f: option<'v> -> option<'v>) (m: Map<'k, 'v>) : Map<'k, 'v> =
    match f (Map.tryFind key m) with
    | Some v -> Map.add key v m
    | None -> Map.remove key m

  /// The keys in ascending order.
  let keys (m: Map<'k, 'v>) =
    let mutable acc = []
    for (k, _) in m do
      acc <- k :: acc
    List.rev acc

  /// The values in ascending key order.
  let values (m: Map<'k, 'v>) =
    let mutable acc = []
    for (_, v) in m do
      acc <- v :: acc
    List.rev acc

  /// Calls `f key value` on every entry in ascending key order.
  let iter f (m: Map<'k, 'v>) =
    for (k, v) in m do
      f k v

  /// The map with `f key value` as every value.
  let rec map f (m: Map<'k, 'v>) =
    match m with
    | MapLeaf -> MapLeaf
    | MapNode (l, k, v, r, h) -> MapNode (Map.map f l, k, f k v, Map.map f r, h)

  /// The entries for which `f key value` is true.
  let filter f (m: Map<'k, 'v>) =
    Map.fold (fun acc k v -> if f k v then Map.add k v acc else acc) Map.empty m

/// By their entries in key order: two maps with the same entries are equal whatever order they
/// were added in (the tree's shape isn't compared).
impl Eq<Map<'k, 'v>> =
  let equal (a: Map<'k, 'v>) (b: Map<'k, 'v>) = Map.count a = Map.count b && Map.toList a = Map.toList b

/// By their entries in key order.
impl Ord<Map<'k, 'v>> =
  let compare (a: Map<'k, 'v>) (b: Map<'k, 'v>) = compare (Map.toList a) (Map.toList b)

/// Consistent with `Eq`.
impl Hash<Map<'k, 'v>> =
  let hash (m: Map<'k, 'v>) = hash (Map.toList m)

/// Maps print as `map [(1, a); (2, b)]`.
impl Show<Map<'k, 'v>> =
  let show m = "map " + show (Map.toList m)

/// The first key whose value differs (`.[k]: 1 vs 2`), or the first key one map has and the
/// other doesn't.
impl Diff<Map<'k, 'v>> =
  let diff a b =
    let rec go (xs: list<'k * 'v>) (ys: list<'k * 'v>) =
      match (xs, ys) with
      | [], [] -> None
      | (k, _) :: _, [] -> Some($": key {k} in the first only")
      | [], (k, _) :: _ -> Some($": key {k} in the second only")
      | (k, v) :: xs, (j, w) :: ys ->
        if k < j then Some($": key {k} in the first only")
        else if j < k then Some($": key {j} in the second only")
        else
          match diff v w with
          | Some rest -> Some($".[{k}]" + rest)
          | None -> go xs ys
    go (Map.toList a) (Map.toList b)
