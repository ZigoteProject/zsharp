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

#### `ToOutput`

```zsharp
| ToOutput
```

`stderr` only: where standard output goes (its pipe, when that's `Piped`), as a shell's
`2>&1`. One reader then sees both, in the order they were written, and neither can fill
while the other waits to be read.

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
An `Error` means it couldn't start (or be waited for); a failing program is an `Ok` with a
nonzero code. On Windows a batch file (`.bat`, `.cmd`) runs in `cmd.exe`, its arguments
quoted for it, and one with a line break (CR or LF), which `cmd.exe` can't be given, is an
`Error`.

### `Process.start`

```zsharp
Process.start : ProcessStart -> result<Process, string>
```

Starts the program (looked up on PATH unless it has a `/`; a relative path is from this
program's working directory, not `directory`), without a shell; each stream that is `Piped`
is the `Process`'s to use. `Process.wait` gives its exit code. A Windows batch file's
arguments are as `Process.run` passes them.

### `Process.wait`

```zsharp
Process.wait : Process -> Task<int>
```

Waits for the process to end: its exit code (128 plus the signal's number when a signal
ended it, -1 when it can't be had). Other tasks go on meanwhile, and a wait that's
cancelled (`Task.timeout`) is over at once, the process left running. Waiting again gives
the same code.

### `Process.kill`

```zsharp
Process.kill : Process -> result<unit, string>
```

Ends the process at once (SIGKILL). One that has been waited for has ended, and is left
alone.

