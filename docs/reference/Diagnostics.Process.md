# Diagnostics.Process

Running other programs.

## Types

### `ProcessResult`

```zsharp
type ProcessResult
```

What a finished process left: its exit code and everything it wrote to standard output.

## Functions

### `Process.run`

```zsharp
Process.run : string -> list<string> -> result<ProcessResult, string>
```

Runs `program` (looked up on PATH) with the arguments, without a shell, and waits for it.
An `Error` means it couldn't start; a failing program is an `Ok` with a nonzero code.

