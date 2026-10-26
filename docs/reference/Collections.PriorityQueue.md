# Collections.PriorityQueue

Lowest priority first.

## Types

### `PriorityQueue`

```zsharp
type PriorityQueue<'a, 'p>
```

A priority queue: `PriorityQueue.dequeue` gives the item of the lowest priority (`'p` with
`Ord`), as .NET's; items of equal priority come in no set order. A leftist heap: `enqueue` and
`dequeue` take a logarithmic number of steps, reusing the old queue's cells when nothing else
refers to it, and an older queue kept alive (`match dequeue q with Some(x, rest) -> q <- rest`)
costs no copy.

#### `Empty`

```zsharp
| Empty
```

no items

#### `Node`

```zsharp
| Node of rank: int * item: 'a * priority: 'p * left: PriorityQueue<'a, 'p> * right: PriorityQueue<'a, 'p> * size: int
```

a node: the length of its rightmost path, its item and priority, and the two below it, the
left one's rightmost path no shorter; no priority below a node's is lower than its own

## Functions

### `PriorityQueue.empty`

```zsharp
let empty : PriorityQueue<'a, 'p>
```

An empty priority queue.

### `PriorityQueue.count`

```zsharp
PriorityQueue.count : PriorityQueue<'a, 'b> -> int
```

The number of items.

### `PriorityQueue.enqueue`

```zsharp
PriorityQueue.enqueue : 'a -> 'b -> PriorityQueue<'a, 'b> -> PriorityQueue<'a, 'b> when 'b : Ord
```

The queue with `x` added at priority `p`.

### `PriorityQueue.dequeue`

```zsharp
PriorityQueue.dequeue : PriorityQueue<'a, 'b> -> option<('a * 'b) * PriorityQueue<'a, 'b>> when 'b : Ord
```

The item of the lowest priority, with its priority, and the queue without it; `None` when
it's empty.

### `PriorityQueue.peek`

```zsharp
PriorityQueue.peek : PriorityQueue<'a, 'b> -> option<'a * 'b>
```

The item of the lowest priority, with its priority, or `None`.

