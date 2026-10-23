# Collections.Map

Persistent sorted maps: an AVL tree, as in OCaml's Map, so every operation is O(log n) and
leaves the old map intact.

## Types

### `Map`

```zsharp
type Map<'k, 'v>
```

A persistent map from keys (ordered with `Ord`) to values. Adding or removing gives a new
map and leaves the old one unchanged; both share most of their structure.

#### `MapLeaf`

```zsharp
| MapLeaf
```

The empty map.

#### `MapNode`

```zsharp
| MapNode of Map<'k, 'v> * 'k * 'v * Map<'k, 'v> * int
```

A node: left subtree, key, value, right subtree, height.

## Derives and impls

### `impl Iter<Map<'k, 'v>, 'k * 'v>`

```zsharp
impl Iter<Map<'k, 'v>, 'k * 'v>
```

A map's entries in ascending key order, walked in a loop with the path to the current node in
a list (not a recursion), so a `for` over a map is one loop with its body in place.

### `impl Show<Map<'k, 'v>>`

```zsharp
impl Show<Map<'k, 'v>>
```

Maps print as `map [(1, a); (2, b)]`.

### `impl Diff<Map<'k, 'v>>`

```zsharp
impl Diff<Map<'k, 'v>>
```

The first key whose value differs (`.[k]: 1 vs 2`), or the first key one map has and the
other doesn't.

## Functions

### `Map.empty`

```zsharp
let empty : Map<'k, 'v>
```

The empty map.

### `Map.isEmpty`

```zsharp
Map.isEmpty : Map<'a, 'b> -> bool
```

Whether the map has no entries.

### `Map.add`

```zsharp
Map.add : 'a -> 'b -> Map<'a, 'b> -> Map<'a, 'b> when 'a : Ord
```

The map with `key` bound to `value` (replacing an existing binding).

### `Map.tryFind`

```zsharp
Map.tryFind : 'a -> Map<'a, 'b> -> option<'b> when 'a : Ord
```

The value bound to `key`, or `None`.

### `Map.find`

```zsharp
Map.find : 'a -> Map<'a, 'b> -> 'b when 'a : Ord
```

The value bound to `key`. Panics when there is none; see `Map.tryFind`.

### `Map.containsKey`

```zsharp
Map.containsKey : 'a -> Map<'a, 'b> -> bool when 'a : Ord
```

Whether the map binds `key`.

### `Map.remove`

```zsharp
Map.remove : 'a -> Map<'a, 'b> -> Map<'a, 'b> when 'a : Ord
```

The map without `key` (the same map when `key` isn't bound).

### `Map.fold`

```zsharp
Map.fold : ('a -> 'b -> 'c -> 'a) -> 'a -> Map<'b, 'c> -> 'a
```

Combines the entries in ascending key order: `f state key value`.

### `Map.count`

```zsharp
Map.count : Map<'a, 'b> -> 'c when 'c : Add
```

The number of entries. O(n).

### `Map.toList`

```zsharp
Map.toList : Map<'a, 'b> -> list<'a * 'b>
```

The entries as (key, value) pairs in ascending key order.

### `Map.ofIter`

```zsharp
Map.ofIter : 'a -> Map<'b, 'c> when 'a : Iter<'b * 'c>, 'b : Ord
```

A map of the pairs a collection has (a later pair wins over an earlier one with the same
key): a list, an array, another map, …

### `Map.ofList`

```zsharp
Map.ofList : list<'a * 'b> -> Map<'a, 'b> when 'a : Ord
```

A map with the pairs' bindings (a later pair wins over an earlier one with the same key).

### `Map.keys`

```zsharp
Map.keys : Map<'a, 'b> -> list<'a>
```

The keys in ascending order.

### `Map.values`

```zsharp
Map.values : Map<'a, 'b> -> list<'b>
```

The values in ascending key order.

### `Map.iter`

```zsharp
Map.iter : ('a -> 'b -> unit) -> Map<'a, 'b> -> unit
```

Calls `f key value` on every entry in ascending key order.

### `Map.map`

```zsharp
Map.map : ('a -> 'b -> 'c) -> Map<'a, 'b> -> Map<'a, 'c>
```

The map with `f key value` as every value.

### `Map.filter`

```zsharp
Map.filter : ('a -> 'b -> bool) -> Map<'a, 'b> -> Map<'a, 'b> when 'a : Ord
```

The entries for which `f key value` is true.

