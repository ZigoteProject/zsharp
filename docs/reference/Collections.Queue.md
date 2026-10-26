# Collections.Queue

First in, first out.

## Types

### `Queue`

```zsharp
type Queue<'a>
```

A queue: `Queue.dequeue` gives the oldest item. A value: `enqueue` and `dequeue` give the
changed queue, reusing the old one's cells when nothing else refers to it.

## Functions

### `Queue.empty`

```zsharp
let empty : Queue<'a>
```

An empty queue.

### `Queue.enqueue`

```zsharp
Queue.enqueue : 'a -> Queue<'a> -> Queue<'a>
```

The queue with `x` added at the back.

### `Queue.dequeue`

```zsharp
Queue.dequeue : Queue<'a> -> option<'a * Queue<'a>>
```

The oldest item and the queue without it, or `None` when it's empty.

### `Queue.peek`

```zsharp
Queue.peek : Queue<'a> -> option<'a>
```

The oldest item, or `None`.

### `Queue.count`

```zsharp
Queue.count : Queue<'a> -> int
```

The number of items.

