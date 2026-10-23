# Iter

Functions over any collection with an `Iter` impl (0017): a list, an array, a Buffer, a span,
a string, an option, a `Seq`, a `Range`, or a type of the program's own. `for x in c do`
walks one too. Each calls the impl's `forEach`, so a function here is one loop.

## Types

### `Iter.Range`

```zsharp
type Range
```

The integers `start`, `start + step`, … up to `stop` (included when a step reaches it), or
down to it for a negative step: `{ start = 10; stop = 0; step = -2 }`.

## Derives and impls

### `impl Iter<Range, int>`

```zsharp
impl Iter<Range, int>
```

A range's integers, counted.

## Functions

### `Iter.iter`

```zsharp
Iter.iter : ('a -> unit) -> 'b -> unit when 'b : Iter<'a>
```

Calls `f` on each element, in order.

### `Iter.fold`

```zsharp
Iter.fold : ('a -> 'b -> 'a) -> 'a -> 'c -> 'a when 'c : Iter<'b>
```

Combines the elements from the left: `f (f (f s x0) x1) x2`.

### `Iter.exists`

```zsharp
Iter.exists : ('a -> bool) -> 'b -> bool when 'b : Iter<'a>
```

Whether `p` holds for some element; stops at the first.

### `Iter.forall`

```zsharp
Iter.forall : ('a -> bool) -> 'b -> bool when 'b : Iter<'a>
```

Whether `p` holds for every element; stops at the first that it doesn't.

### `Iter.tryFind`

```zsharp
Iter.tryFind : ('a -> bool) -> 'b -> option<'a> when 'b : Iter<'a>
```

The first element `p` holds for.

### `Iter.length`

```zsharp
Iter.length : 'a -> int when 'a : Iter<'b>
```

How many elements there are.

### `Iter.toList`

```zsharp
Iter.toList : 'a -> list<'b> when 'a : Iter<'b>
```

The elements in a list, in order.

