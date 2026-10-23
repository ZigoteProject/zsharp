# Testing.Runner

The test binary's entry: `zs test` builds one from a file's `[<Tests>]` values, lists its
tests with `--list`, and runs each by its path in a process of its own.

## Functions

### `Testing.Runner.main`

```zsharp
Testing.Runner.main : list<Testing.Test> -> int
```

Lists the tests (`--list`: path, focus, time limit and sequenced group, a line each, tabs
between) or runs the one a path names; the exit code.

