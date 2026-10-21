# Collections.Set

Persistent sorted sets, a `Map` to unit underneath.

## Types

### `Set`

```zsharp
type Set<'a>
```

A persistent sorted set (a `Map` to unit underneath).

## Derives and impls

### `impl Show<Set<'a>>`

```zsharp
impl Show<Set<'a>>
```

Sets print as `set [1; 2; 3]`.

## Functions

### `Set.empty`

```zsharp
Set.empty : unit -> Set<'a>
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

