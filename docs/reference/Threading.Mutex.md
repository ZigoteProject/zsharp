# Threading.Mutex

Mutexes: a `Mutex<T>` holds a value that threads take turns with, under a lock. The value
must be Share (immutable, or another Atomic, Mutex or Channel), since every thread may read
it: `Mutex.update m f` replaces it with `f` of it while holding the lock, so updates from
several threads don't lose one another. Its functions are built into the compiler.

## Functions

### `Mutex.get`

```zsharp
Mutex.get : Mutex<'a> -> 'a
```

The value now (with a reference of its own, taken under the lock).

### `Mutex.make`

```zsharp
Mutex.make : 'a -> Mutex<'a>
```

A mutex holding `x` (which is then shared between threads).

### `Mutex.set`

```zsharp
Mutex.set : Mutex<'a> -> 'a -> unit
```

Replaces the value.

### `Mutex.update`

```zsharp
Mutex.update : Mutex<'a> -> ('a -> 'a) -> 'a
```

Replaces the value with `f` of it, holding the lock meanwhile (so updates from several threads don't lose one another), and gives the new value. `f` mustn't use the same mutex.

