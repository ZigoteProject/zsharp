# Diagnostics.Stopwatch

Measuring elapsed time.

## Types

### `Stopwatch`

```zsharp
type Stopwatch
```

A started stopwatch: `let sw = Stopwatch.startNew ()`, then `sw.ElapsedMilliseconds`.

#### `Stopwatch#ElapsedNanoseconds`

```zsharp
member sw.ElapsedNanoseconds
```

The time since it started, in nanoseconds.

#### `Stopwatch#ElapsedMilliseconds`

```zsharp
member sw.ElapsedMilliseconds
```

The time since it started, in whole milliseconds.

## Functions

### `Stopwatch.startNew`

```zsharp
Stopwatch.startNew : unit -> Stopwatch
```

A stopwatch started now.

