# Collections.HashSet

Hash sets, for elements with `Hash` and `Eq`.

## Types

### `HashSet`

```zsharp
type HashSet<'a>
```

A hash set (elements with `Hash` and `Eq`). It is a value like an array: `HashSet.add` gives
the changed set, updated in place when nothing else refers to the old one.

## Derives and impls

### `impl Iter<HashSet<'a>, 'a>`

```zsharp
impl Iter<HashSet<'a>, 'a>
```

A hash set's elements in bucket order, which is unspecified: a program that needs an order sorts
them (`List.sort (HashMap.toList m)`).

## Functions

### `HashSet.empty`

```zsharp
let empty : HashSet<'a>
```

An empty hash set (with no buckets yet: the first `add` makes them).

### `HashSet.contains`

```zsharp
HashSet.contains : 'a -> HashSet<'a> -> bool when 'a : Eq, 'a : Hash
```

Whether the set has `x`.

### `HashSet.count`

```zsharp
HashSet.count : HashSet<'a> -> int
```

The number of elements.

### `HashSet.toList`

```zsharp
HashSet.toList : HashSet<'a> -> list<'a>
```

The elements, in no particular order.

### `HashSet.add`

```zsharp
HashSet.add : 'a -> HashSet<'a> -> HashSet<'a> when 'a : Eq, 'a : Hash
```

The set with `x` (the same set when it has `x` already).

### `HashSet.remove`

```zsharp
HashSet.remove : 'a -> HashSet<'a> -> HashSet<'a> when 'a : Eq, 'a : Hash
```

The set without `x`.

### `HashSet.ofList`

```zsharp
HashSet.ofList : list<'a> -> HashSet<'a> when 'a : Eq, 'a : Hash
```

A hash set of the elements.

### `HashSet.union`

```zsharp
HashSet.union : HashSet<'a> -> HashSet<'a> -> HashSet<'a> when 'a : Eq, 'a : Hash
```

The elements of either set.

### `HashSet.intersect`

```zsharp
HashSet.intersect : HashSet<'a> -> HashSet<'a> -> HashSet<'a> when 'a : Eq, 'a : Hash
```

The elements of `a` that `b` has too.

### `HashSet.difference`

```zsharp
HashSet.difference : HashSet<'a> -> HashSet<'a> -> HashSet<'a> when 'a : Eq, 'a : Hash
```

The elements of `a` that `b` doesn't have.

