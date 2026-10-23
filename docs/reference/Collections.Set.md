# Collections.Set

Persistent sorted sets, a `Map` to unit underneath.

## Types

### `Set`

```zsharp
type Set<'a>
```

A persistent sorted set (a `Map` to unit underneath).

## Derives and impls

### `impl Eq<Set<'a>>`

```zsharp
impl Eq<Set<'a>>
```

By their elements: two sets with the same elements are equal whatever order they were added in.

### `impl Ord<Set<'a>>`

```zsharp
impl Ord<Set<'a>>
```

By their elements in ascending order.

### `impl Hash<Set<'a>>`

```zsharp
impl Hash<Set<'a>>
```

Consistent with `Eq`.

### `impl Show<Set<'a>>`

```zsharp
impl Show<Set<'a>>
```

Sets print as `set [1; 2; 3]`.

### `impl Iter<Set<'a>, 'a>`

```zsharp
impl Iter<Set<'a>, 'a>
```

A set's elements in ascending order (its map's keys).

## Functions

### `Set.empty`

```zsharp
let empty : Set<'a>
```

The empty set.

### `Set.add`

```zsharp
Set.add : 'a -> Set<'a> -> Set<'a> when 'a : Ord
```

The set with `x` added.

### `Set.remove`

```zsharp
Set.remove : 'a -> Set<'a> -> Set<'a> when 'a : Ord
```

The set without `x`.

### `Set.contains`

```zsharp
Set.contains : 'a -> Set<'a> -> bool when 'a : Ord
```

Whether the set contains `x`.

### `Set.count`

```zsharp
Set.count : Set<'a> -> 'b when 'b : Add
```

The number of elements. O(n).

### `Set.isEmpty`

```zsharp
Set.isEmpty : Set<'a> -> bool
```

Whether the set has no elements.

### `Set.toList`

```zsharp
Set.toList : Set<'a> -> list<'a>
```

The elements in ascending order.

### `Set.ofIter`

```zsharp
Set.ofIter : 'a -> Set<'b> when 'a : Iter<'b>, 'b : Ord
```

A set of a collection's elements: a list, an array, a string's characters, …

### `Set.ofList`

```zsharp
Set.ofList : list<'a> -> Set<'a> when 'a : Ord
```

A set of the list's elements.

### `Set.union`

```zsharp
Set.union : Set<'a> -> Set<'a> -> Set<'a> when 'a : Ord
```

The elements in either set.

### `Set.intersect`

```zsharp
Set.intersect : Set<'a> -> Set<'a> -> Set<'a> when 'a : Ord
```

The elements in both sets.

### `Set.difference`

```zsharp
Set.difference : Set<'a> -> Set<'a> -> Set<'a> when 'a : Ord
```

The elements of `a` that aren't in `b`.

