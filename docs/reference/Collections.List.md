# Collections.List

Functions on lists, immutable singly linked lists: `[ 1; 2; 3 ]`, `x :: rest`. They are
tail-recursive (loops after compilation), so long lists don't exhaust the stack.

## Types

#### `list#Length`

```zsharp
member xs.Length
```

The number of elements. O(n).

#### `list#Head`

```zsharp
member xs.Head
```

The first element. Panics on an empty list.

#### `list#Tail`

```zsharp
member xs.Tail
```

Everything after the first element. Panics on an empty list.

#### `list#IsEmpty`

```zsharp
member xs.IsEmpty
```

Whether the list has no elements.

## Derives and impls

### `impl Iter<list<'a>, 'a>`

```zsharp
impl Iter<list<'a>, 'a>
```

A list's elements, front to back.

### `impl Diff<list<'a>>`

```zsharp
impl Diff<list<'a>>
```

The first element where two lists differ (`.[2]: 3 vs 4`), or where one of them ends.

## Functions

### `List.rev`

```zsharp
List.rev : list<'a> -> list<'a>
```

The list in reverse order. Reuses the cells when the list is unique.

### `List.length`

```zsharp
List.length : list<'a> -> 'b when 'b : Add
```

The number of elements. O(n).

### `List.isEmpty`

```zsharp
List.isEmpty : list<'a> -> bool
```

Whether the list has no elements.

### `List.head`

```zsharp
List.head : list<'a> -> 'a
```

The first element. Panics on an empty list; see `List.tryHead`.

### `List.tail`

```zsharp
List.tail : list<'a> -> list<'a>
```

Everything after the first element. Panics on an empty list.

### `List.map`

```zsharp
List.map : ('a -> 'b) -> list<'a> -> list<'b>
```

Applies `f` to every element: `List.map f [a; b] = [f a; f b]`.

### `List.filter`

```zsharp
List.filter : ('a -> bool) -> list<'a> -> list<'a>
```

The elements for which `f` returns true, in order.

### `List.fold`

```zsharp
List.fold : ('a -> 'b -> 'a) -> 'a -> list<'b> -> 'a
```

Combines the elements from the left: `List.fold f s [a; b] = f (f s a) b`.

### `List.iter`

```zsharp
List.iter : ('a -> unit) -> list<'a> -> unit
```

Calls `f` on every element, in order.

### `List.append`

```zsharp
List.append : list<'a> -> list<'a> -> list<'a>
```

The elements of `xs` followed by those of `ys` (also written `xs @ ys`).

### `List.exists`

```zsharp
List.exists : ('a -> bool) -> list<'a> -> bool
```

Whether `f` is true for some element. Stops at the first.

### `List.forall`

```zsharp
List.forall : ('a -> bool) -> list<'a> -> bool
```

Whether `f` is true for every element. Stops at the first false.

### `List.contains`

```zsharp
List.contains : 'a -> list<'a> -> bool when 'a : Eq
```

Whether the list contains `x` (compared with `=`).

### `List.tryFind`

```zsharp
List.tryFind : ('a -> bool) -> list<'a> -> option<'a>
```

The first element for which `f` is true, or `None`.

### `List.tryFindIndex`

```zsharp
List.tryFindIndex : ('a -> bool) -> list<'a> -> option<'b> when 'b : Add
```

The index of the first element for which `f` is true, or `None`.

### `List.findIndex`

```zsharp
List.findIndex : ('a -> bool) -> list<'a> -> 'b when 'b : Add
```

The index of the first element for which `f` is true. Panics if there is none; see
`List.tryFindIndex`.

### `List.find`

```zsharp
List.find : ('a -> bool) -> list<'a> -> 'a
```

The first element for which `f` is true. Panics if there is none; see `List.tryFind`.

### `List.tryPick`

```zsharp
List.tryPick : ('a -> option<'b>) -> list<'a> -> option<'b>
```

The first `Some` result of `f` on the elements, in order, or `None`.

### `List.sum`

```zsharp
List.sum : list<'a> -> 'a when 'a : Add
```

The sum of the elements (`Add.zero` for an empty list).

### `List.init`

```zsharp
List.init : 'a -> ('a -> 'b) -> list<'b> when 'a : Num, 'a : Ord
```

A list of `n` elements: `[f 0; f 1; …; f (n - 1)]`.

### `List.replicate`

```zsharp
List.replicate : 'a -> 'b -> list<'b> when 'a : Num, 'a : Ord
```

A list of `n` copies of `x`.

### `List.mapi`

```zsharp
List.mapi : ('a -> 'b -> 'c) -> list<'b> -> list<'c> when 'a : Add
```

Like `List.map`, with each element's index: `f i x`.

### `List.iteri`

```zsharp
List.iteri : ('a -> 'b -> unit) -> list<'b> -> unit when 'a : Add
```

Applies `f` to each element with its index, in order: `f i x`.

### `List.indexed`

```zsharp
List.indexed : list<'a> -> list<'b * 'a> when 'b : Add
```

Each element paired with its index: `[(0, a); (1, b)]`.

### `List.choose`

```zsharp
List.choose : ('a -> option<'b>) -> list<'a> -> list<'b>
```

Applies `f` to every element and keeps the values of the `Some` results.

### `List.collect`

```zsharp
List.collect : ('a -> list<'b>) -> list<'a> -> list<'b>
```

Applies `f` to every element and concatenates the resulting lists.

### `List.concat`

```zsharp
List.concat : list<list<'a>> -> list<'a>
```

The lists one after another, in one list.

### `List.zip`

```zsharp
List.zip : list<'a> -> list<'b> -> list<'a * 'b>
```

Pairs up the elements of two lists; stops at the end of the shorter one.

### `List.map2`

```zsharp
List.map2 : ('a -> 'b -> 'c) -> list<'a> -> list<'b> -> list<'c>
```

Applies `f` to the elements of two lists pairwise. Panics if their lengths differ.

### `List.iter2`

```zsharp
List.iter2 : ('a -> 'b -> unit) -> list<'a> -> list<'b> -> unit
```

Applies `f` to the elements of two lists pairwise, in order. Panics if their lengths differ.

### `List.unzip`

```zsharp
List.unzip : list<'a * 'b> -> list<'a> * list<'b>
```

Splits a list of pairs into a pair of lists.

### `List.tryHead`

```zsharp
List.tryHead : list<'a> -> option<'a>
```

The first element, or `None` for an empty list.

### `List.last`

```zsharp
List.last : list<'a> -> 'a
```

The last element. Panics on an empty list.

### `List.tryLast`

```zsharp
List.tryLast : list<'a> -> option<'a>
```

The last element, or `None` for an empty list.

### `List.item`

```zsharp
List.item : 'a -> list<'b> -> 'b when 'a : Eq, 'a : Num
```

The element at index `n` (from 0). Panics if the list is too short. O(n).

### `List.tryItem`

```zsharp
List.tryItem : 'a -> list<'b> -> option<'b> when 'a : Eq, 'a : Num, 'a : Ord
```

The element at index `n` (from 0), or `None` if the list is too short.

### `List.removeAt`

```zsharp
List.removeAt : 'a -> list<'b> -> list<'b> when 'a : Eq, 'a : Num
```

The list without the element at index `n` (from 0). Panics if the list is too short.

### `List.take`

```zsharp
List.take : 'a -> list<'b> -> list<'b> when 'a : Num, 'a : Ord
```

The first `n` elements (fewer if the list is shorter).

### `List.takeWhile`

```zsharp
List.takeWhile : ('a -> bool) -> list<'a> -> list<'a>
```

The elements before the first one for which `f` is false.

### `List.skip`

```zsharp
List.skip : 'a -> list<'b> -> list<'b> when 'a : Num, 'a : Ord
```

The list without its first `n` elements.

### `List.reduce`

```zsharp
List.reduce : ('a -> 'a -> 'a) -> list<'a> -> 'a
```

Combines the elements from the left, starting with the first. Panics on an empty list.

### `List.partition`

```zsharp
List.partition : ('a -> bool) -> list<'a> -> list<'a> * list<'a>
```

The elements for which `f` is true, and the others, both in order.

### `List.max`

```zsharp
List.max : list<'a> -> 'a when 'a : Ord
```

The largest element. Panics on an empty list.

### `List.min`

```zsharp
List.min : list<'a> -> 'a when 'a : Ord
```

The smallest element. Panics on an empty list.

### `List.sumBy`

```zsharp
List.sumBy : ('a -> 'b) -> list<'a> -> 'b when 'b : Add
```

The sum of `f x` over the elements.

### `List.distinct`

```zsharp
List.distinct : list<'a> -> list<'a> when 'a : Eq
```

The list without repeated elements, keeping first occurrences.

### `List.sortWith`

```zsharp
List.sortWith : ('a -> 'a -> 'b) -> list<'a> -> list<'a> when 'b : Ord
```

The list sorted with `cmp` (negative, zero or positive, like `compare`). Stable.

### `List.sort`

```zsharp
List.sort : list<'a> -> list<'a> when 'a : Ord
```

The list sorted in ascending order. Stable.

### `List.sortBy`

```zsharp
List.sortBy : ('a -> 'b) -> list<'a> -> list<'a> when 'b : Ord
```

The list sorted by the key `f x`. Stable.

### `List.ofIter`

```zsharp
List.ofIter : 'a -> list<'b> when 'a : Iter<'b>
```

The elements of a collection, in its order: an array, a string's characters, a map's
entries, …

