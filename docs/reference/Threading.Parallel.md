# Threading.Parallel

Parallelism: work spread over every core by the runtime's thread pool (a worker per core,
which take work from one another when they run out). A function another thread runs is a
`share<…>`: what it captures must be Share (immutable values; or an Atomic, Mutex or Channel
for what threads change), so no two threads change the same data at once.

## Functions

### `Parallel.workers`

```zsharp
Parallel.workers : unit -> int
```

The number of threads that run the pool's work: the cores, or `ZS_WORKERS` if it's set.

### `Parallel.both`

```zsharp
Parallel.both : share<unit -> 'a> -> share<unit -> 'b> -> 'a * 'b
```

Runs both functions at once (`g` on another thread when one is free), and gives both results.

### `Parallel.grain`

```zsharp
Parallel.grain : int -> int
```

How many indices a job takes: about 32 jobs per thread, so threads that finish early take
work from the others.

### `Parallel.for`

```zsharp
Parallel.for : int -> int -> share<int -> unit> -> unit
```

Calls `f i` for each `i` from `lo` up to (not including) `hi`, spread over the pool, in no
particular order. What the calls give back goes through an `Atomic`, a `Mutex` or a
`Channel`; `Array.Parallel.init` builds an array instead.

### `Parallel.reduce`

```zsharp
Parallel.reduce : int -> int -> 'a -> share<int -> 'a> -> share<'a -> 'a -> 'a> -> 'a
```

`f i` for each `i` from `lo` up to (not including) `hi`, combined with `combine`, spread
over the pool: `zero` when the range is empty. `combine` must be associative (the parts
are combined in order, but grouped any way).

