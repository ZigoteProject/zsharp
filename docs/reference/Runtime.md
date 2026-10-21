# Runtime

The runtime: a cycle counter for timing code, and allocation statistics. Its functions are
built into the compiler.

## Functions

### `Runtime.allocations`

```zsharp
Runtime.allocations : unit -> int
```

The number of heap objects allocated so far.

### `Runtime.ticks`

```zsharp
Runtime.ticks : unit -> u64
```

A cycle counter for timing code: on a Cortex-M the SysTick count, elsewhere nanoseconds.

