# Collections.HashMap

Hash maps, for keys with `Hash` and `Eq`.

## Types

### `HashMap`

```zsharp
type HashMap<'k, 'v>
```

A hash map (keys with `Hash` and `Eq`). It is a value like an array: `HashMap.add` gives
the changed map, updated in place when nothing else refers to the old one.

## Derives and impls

### `impl Eq<HashMap<'k, 'v>>`

```zsharp
impl Eq<HashMap<'k, 'v>>
```

By their entries: the same keys with equal values, whatever order they were added in.

### `impl Hash<HashMap<'k, 'v>>`

```zsharp
impl Hash<HashMap<'k, 'v>>
```

Consistent with `Eq`: the entries' hashes added, in no order.

### `impl Iter<HashMap<'k, 'v>, 'k * 'v>`

```zsharp
impl Iter<HashMap<'k, 'v>, 'k * 'v>
```

A hash map's entries in bucket order, which is unspecified: a program that needs an order sorts
them (`List.sort (HashMap.toList m)`).

## Functions

### `HashMap.empty`

```zsharp
let empty : HashMap<'k, 'v>
```

An empty hash map (with no buckets yet: the first `add` makes them).

### `HashMap.tryFind`

```zsharp
HashMap.tryFind : 'a -> HashMap<'a, 'b> -> option<'b> when 'a : Eq, 'a : Hash
```

The value bound to `key`, or `None`.

### `HashMap.containsKey`

```zsharp
HashMap.containsKey : 'a -> HashMap<'a, 'b> -> bool when 'a : Eq, 'a : Hash
```

Whether the map binds `key`.

### `HashMap.count`

```zsharp
HashMap.count : HashMap<'a, 'b> -> int
```

The number of entries.

### `HashMap.toList`

```zsharp
HashMap.toList : HashMap<'a, 'b> -> list<'a * 'b>
```

The entries as (key, value) pairs, in no particular order.

### `HashMap.add`

```zsharp
HashMap.add : 'a -> 'b -> HashMap<'a, 'b> -> HashMap<'a, 'b> when 'a : Eq, 'a : Hash
```

The map with `key` bound to `value` (replacing an existing binding).

### `HashMap.remove`

```zsharp
HashMap.remove : 'a -> HashMap<'a, 'b> -> HashMap<'a, 'b> when 'a : Eq, 'a : Hash
```

The map without `key`.

### `HashMap.ofList`

```zsharp
HashMap.ofList : list<'a * 'b> -> HashMap<'a, 'b> when 'a : Eq, 'a : Hash
```

A hash map with the pairs' bindings.

