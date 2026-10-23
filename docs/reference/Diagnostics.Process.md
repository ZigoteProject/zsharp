# Diagnostics.Process

Running other programs.

## Types

### `ProcessResult`

```zsharp
type ProcessResult
```

What a finished process left: its exit code and everything it wrote to standard output.

### `Pipe`

```zsharp
type Pipe
```

How a started process's standard stream is connected (`ProcessStart`'s `stdin`, `stdout` and
`stderr`).

#### `Inherit`

```zsharp
| Inherit
```

This program's own stream.

#### `Piped`

```zsharp
| Piped
```

A pipe: the `Process` record's `stdin`, `stdout` or `stderr`.

#### `Null`

```zsharp
| Null
```

Nothing: reading gets the end at once, and what's written is dropped.

### `ProcessStart`

```zsharp
type ProcessStart
```

What `Process.start` runs, naming only what it changes from the defaults:
`Process.start { program = "clang"; args = [ "-c"; f ]; stderr = Piped }`.

### `Process`

```zsharp
type Process
```

A process running: its id, and this end of each stream that was `Piped`. `use` closes the
pipes (it doesn't wait for the process: `Process.wait` does).

## Derives and impls

### `impl Dispose<Process>`

```zsharp
impl Dispose<Process>
```

`use` closes the process's pipes (it doesn't wait for it: `Process.wait` does).

## Functions

### `Process.run`

```zsharp
Process.run : string -> list<string> -> result<ProcessResult, string>
```

Runs `program` (looked up on PATH) with the arguments, without a shell, and waits for it.
An `Error` means it couldn't start; a failing program is an `Ok` with a nonzero code.

### `Process.start`

```zsharp
Process.start : ProcessStart -> result<Process, string>
```

Starts the program (looked up on PATH unless it has a `/`), without a shell; each stream
that is `Piped` is the `Process`'s to use. `Process.wait` gives its exit code.

### `Process.wait`

```zsharp
Process.wait : Process -> Task<int>
```

Waits for the process to end: its exit code (128 plus the signal's number when a signal
ended it), on `Task.blocking`'s thread so other tasks go on.

### `Process.kill`

```zsharp
Process.kill : Process -> result<unit, string>
```

Ends the process at once (SIGKILL).

