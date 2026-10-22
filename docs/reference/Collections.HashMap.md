# Collections.HashMap

Hash maps, for keys with `Hash` and `Eq`.

## Types

### `HashMap`

```zsharp
type HashMap<'k, 'v>
```

A hash map (keys with `Hash` and `Eq`). It is a value like an array: `HashMap.add` gives
the changed map, updated in place when nothing else refers to the old one.

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

