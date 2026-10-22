# Threading.Atomic

Atomic values: an `Atomic<T>` holds a number, a `bool` or a `char` that threads read and
change at once, each operation whole (sequentially consistent), without a lock. For a counter
or a flag that parallel work shares; a `Mutex` holds any other value. Its functions are built
into the compiler.

## Functions

### `Atomic.add`

```zsharp
Atomic.add : Atomic<'a> -> 'a -> 'a
```

Adds `n` to the value, giving the new value (an integer wraps around on overflow).

### `Atomic.compareExchange`

```zsharp
Atomic.compareExchange : Atomic<'a> -> 'a -> 'a -> 'a
```

Sets the value to `desired` only if it is `expected`, giving the value it held (so it succeeded when that is `expected`), as .NET's `Interlocked.CompareExchange`.

### `Atomic.exchange`

```zsharp
Atomic.exchange : Atomic<'a> -> 'a -> 'a
```

Sets the value, giving the one it replaced.

### `Atomic.get`

```zsharp
Atomic.get : Atomic<'a> -> 'a
```

The value now.

### `Atomic.make`

```zsharp
Atomic.make : 'a -> Atomic<'a>
```

An atomic value holding `x`.

### `Atomic.set`

```zsharp
Atomic.set : Atomic<'a> -> 'a -> unit
```

Sets the value.

