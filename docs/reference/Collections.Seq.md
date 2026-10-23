# Collections.Seq

Lazy sequences: generators. A `seq { }`'s body runs when the sequence is consumed, and each
`yield` gives the consumer one element (the `Yield` effect, handled by the consumer), so
nothing is built in between: `Seq.map`, `filter` and `take` over a generator, consumed by
`Seq.iter` or `for`, run inside the generator's loop, each stage handling an element where
it's yielded, with nothing allocated per element. A sequence is computed again each time it's
consumed.

## Types

### `Seq`

```zsharp
type Seq<'a>
```

A lazy sequence of `'a`: what `seq { }` makes. Its function yields the elements.

## Functions

### `Seq.yieldAll`

```zsharp
Seq.yieldAll : Seq<'a> -> unit / Yield<'a>
```

Yields the sequence's elements to the consumer of the sequence the caller is in:
`yield! s` in a `seq { }`.

### `Seq.empty`

```zsharp
Seq.empty : unit -> Seq<'a>
```

The sequence of no elements.

### `Seq.singleton`

```zsharp
Seq.singleton : 'a -> Seq<'a>
```

The sequence of the one element `x`.

### `Seq.ofList`

```zsharp
Seq.ofList : list<'a> -> Seq<'a>
```

The elements of a list, in order.

### `Seq.ofArray`

```zsharp
Seq.ofArray : array<'a> -> Seq<'a>
```

The elements of an array, in order.

### `Seq.init`

```zsharp
Seq.init : int -> (int -> 'a / <>) -> Seq<'a>
  f must perform nothing
```

`n` elements, `f 0` to `f (n - 1)`, each computed as it's consumed.

### `Seq.unfold`

```zsharp
Seq.unfold : ('a -> option<'b * 'a> / <>) -> 'a -> Seq<'b>
  f must perform nothing
```

The elements of `state` unfolded: `f s` gives `Some (x, next)` for the element `x` and the
next state, or `None` at the end. Infinite while `f` never gives `None`.

### `Seq.iter`

```zsharp
Seq.iter : ('a -> unit) -> Seq<'a> -> unit
```

Calls `f` on each element, in order.

### `Seq.iteri`

```zsharp
Seq.iteri : ('a -> 'b -> unit) -> Seq<'b> -> unit when 'a : Add
```

Like `Seq.iter`, with each element's index: `f i x`.

### `Seq.fold`

```zsharp
Seq.fold : ('a -> 'b -> 'a) -> 'a -> Seq<'b> -> 'a
```

Combines the elements from the left: `Seq.fold f s [a; b] = f (f s a) b`.

### `Seq.toList`

```zsharp
Seq.toList : Seq<'a> -> list<'a>
```

The elements as a list, in order.

### `Seq.toArray`

```zsharp
Seq.toArray : Seq<'a> -> array<'a>
```

The elements as an array, in order.

### `Seq.length`

```zsharp
Seq.length : Seq<'a> -> 'b when 'b : Add
```

The number of elements. Consumes the whole sequence.

### `Seq.sum`

```zsharp
Seq.sum : Seq<'a> -> 'a when 'a : Add
```

The sum of the elements (`0` for none), with `+` and `Add.zero`.

### `Seq.sumBy`

```zsharp
Seq.sumBy : ('a -> 'b) -> Seq<'a> -> 'b when 'b : Add
```

The sum of `f x` over the elements.

### `Seq.exists`

```zsharp
Seq.exists : ('a -> bool) -> Seq<'a> -> bool
```

Whether `f` holds for some element. Stops at the first.

### `Seq.forall`

```zsharp
Seq.forall : ('a -> bool) -> Seq<'a> -> bool
```

Whether `f` holds for every element. Stops at the first for which it doesn't.

### `Seq.tryFind`

```zsharp
Seq.tryFind : ('a -> bool) -> Seq<'a> -> option<'a>
```

The first element for which `f` holds, if any. Stops there.

### `Seq.tryHead`

```zsharp
Seq.tryHead : Seq<'a> -> option<'a>
```

The first element, if any; the rest isn't computed.

### `Seq.isEmpty`

```zsharp
Seq.isEmpty : Seq<'a> -> bool
```

Whether the sequence has no elements. Computes at most the first.

### `Seq.map`

```zsharp
Seq.map : ('a -> 'b / <>) -> Seq<'a> -> Seq<'b>
  f must perform nothing
```

The sequence of `f x` for each element `x`, computed as it's consumed.

### `Seq.mapi`

```zsharp
Seq.mapi : (int -> 'a -> 'b / <>) -> Seq<'a> -> Seq<'b>
  f must perform nothing
```

Like `Seq.map`, with each element's index: `f i x`.

### `Seq.filter`

```zsharp
Seq.filter : ('a -> bool / <>) -> Seq<'a> -> Seq<'a>
  f must perform nothing
```

The elements for which `f` holds, in order.

### `Seq.choose`

```zsharp
Seq.choose : ('a -> option<'b> / <>) -> Seq<'a> -> Seq<'b>
  f must perform nothing
```

The values of `f x` that are `Some`, in order.

### `Seq.collect`

```zsharp
Seq.collect : ('a -> Seq<'b> / <>) -> Seq<'a> -> Seq<'b>
  f must perform nothing
```

The elements of `f x` for each element `x`, one sequence after another.

### `Seq.append`

```zsharp
Seq.append : Seq<'a> -> Seq<'a> -> Seq<'a>
```

The elements of `a`, then those of `b`.

### `Seq.take`

```zsharp
Seq.take : 'a -> Seq<'b> -> Seq<'b> when 'a : Num, 'a : Ord
```

The first `n` elements (all of them when there are fewer); the rest aren't computed.

### `Seq.takeWhile`

```zsharp
Seq.takeWhile : ('a -> bool / <>) -> Seq<'a> -> Seq<'a>
  f must perform nothing
```

The elements while `f` holds; the rest aren't computed.

### `Seq.skip`

```zsharp
Seq.skip : 'a -> Seq<'b> -> Seq<'b> when 'a : Num, 'a : Ord
```

The elements after the first `n`.

### `Seq.indexed`

```zsharp
Seq.indexed : Seq<'a> -> Seq<int * 'a>
```

Pairs of each element with its index, from 0.

