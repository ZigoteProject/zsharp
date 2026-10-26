# Runtime

The runtime: a cycle counter for timing code, and allocation statistics. Its functions are
built into the compiler.

## Functions

### `Runtime.allocations`

```zsharp
Runtime.allocations : unit -> int
```

The number of heap objects allocated so far.

### `Runtime.mallocs`

```zsharp
Runtime.mallocs : unit -> int
```

The number of times memory was taken from the system allocator: for a chunk of the runtime's object pool, a large object, or an arena's block.

### `Runtime.marks`

```zsharp
Runtime.marks : unit -> int
```

The number of objects marked shared so far, at crossings to other threads: what a value moved to another thread holds alone stays unmarked (`ZS_STATS=1` prints it at exit).

### `Runtime.setClock`

```zsharp
Runtime.setClock : u32 -> unit
```

On a microcontroller, the core's clock in Hz, after firmware changes it (its PLL): `Task.sleep` counts SysTick's cycles at this rate (the board's clock at reset unless set).

### `Runtime.ticks`

```zsharp
Runtime.ticks : unit -> u64
```

A cycle counter for timing code: on a Cortex-M the SysTick count, elsewhere nanoseconds.

