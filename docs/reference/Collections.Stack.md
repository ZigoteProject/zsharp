# Collections.Stack

Last in, first out.

## Types

### `Stack`

```zsharp
type Stack<'a>
```

A stack: `Stack.pop` gives the newest item. A value, as a list is.

## Functions

### `Stack.empty`

```zsharp
let empty : Stack<'a>
```

An empty stack.

### `Stack.push`

```zsharp
Stack.push : 'a -> Stack<'a> -> Stack<'a>
```

The stack with `x` on top.

### `Stack.pop`

```zsharp
Stack.pop : Stack<'a> -> option<'a * Stack<'a>>
```

The top item and the stack without it, or `None` when it's empty.

### `Stack.peek`

```zsharp
Stack.peek : Stack<'a> -> option<'a>
```

The top item, or `None`.

### `Stack.count`

```zsharp
Stack.count : Stack<'a> -> int
```

The number of items.

