# Testing.Runner

The test binary's entry: `zs test` builds one from a file's `[<Tests>]` values, lists its
tests with `--list`, and runs each by its path in a process of its own; `zs bench` times a
benchmark with `--bench path runs`.

## Functions

### `Testing.Runner.main`

```zsharp
Testing.Runner.main : list<Testing.Test> -> int
```

Lists the tests (`--list`: path, focus, time limit, sequenced group and kind, a line each,
tabs between), runs the one a path names, or times a benchmark (`--bench path runs`: three
warm-up runs, then the nanoseconds of each of `runs` runs on one line); the exit code.

