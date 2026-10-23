# Testing

Tests as values (0009): `test "name" (fun () -> …)` is a `Test`, `testList` groups them, and
a top-level value marked `[<Tests>]` is what `zs test` runs, each test in its own process.

## Traits

### `Testing.Outcome`

```zsharp
trait Outcome<'r>
```

What a test's body gives back: nothing (a panic fails it), a `result` (an `Error` fails it),
or a task (Std's impl runs it on the event loop).

#### `Testing.Outcome.finish`

```zsharp
abstract finish : 'r -> unit
```

Panics when the outcome is a failure.

## Types

### `Testing.Focus`

```zsharp
type Focus
```

Whether a test runs: as usual; only with the other focused ones while any are (`ftest`); or
not, and said so (`ptest`).

#### `Testing.Normal`

```zsharp
| Normal
```

Runs as usual.

#### `Testing.Focused`

```zsharp
| Focused
```

Runs, and while any test is focused only the focused ones do.

#### `Testing.Pending`

```zsharp
| Pending
```

Doesn't run, and is listed as skipped.

### `Testing.Test`

```zsharp
type Test
```

A test, or a group of them. A test's path is the names down to it: `parser/parses`.

#### `Testing.Case`

```zsharp
| Case of name: string * run: (unit -> unit) * focus: Focus * timeout: int
```

One test: its name, its body (a failure panics), its focus and its time limit (ms).

#### `Testing.Group`

```zsharp
| Group of name: string * tests: list<Test> * focus: Focus * sequenced: bool
```

A group: its name, its tests, its focus, and whether they run one at a time.

## Derives and impls

### `impl Outcome<unit>`

```zsharp
impl Outcome<unit>
```

A body that returns: it passed.

### `impl Outcome<result<'a, 'e>>`

```zsharp
impl Outcome<result<'a, 'e>>
```

An `Error` fails the test, shown.

## Functions

### `Testing.test`

```zsharp
Testing.test : string -> (unit -> 'a / <>) -> Testing.Test when 'a : Testing.Outcome
  body must perform nothing
```

A test: its name and its body (a panic or an `Error` fails it). It may take 60 s.

### `Testing.testWithTimeout`

```zsharp
Testing.testWithTimeout : int -> string -> (unit -> 'a / <>) -> Testing.Test when 'a : Testing.Outcome
  body must perform nothing
```

A test that may take `ms` milliseconds.

### `Testing.ftest`

```zsharp
Testing.ftest : string -> (unit -> 'a / <>) -> Testing.Test when 'a : Testing.Outcome
  body must perform nothing
```

A focused test: while any test is focused, only those run (`zs test --fail-on-focused` fails
a run that has one).

### `Testing.ptest`

```zsharp
Testing.ptest : string -> (unit -> 'a / <>) -> Testing.Test when 'a : Testing.Outcome
  body must perform nothing
```

A pending test: not run, and listed as skipped.

### `Testing.testList`

```zsharp
Testing.testList : string -> list<Testing.Test> -> Testing.Test
```

A group of tests, run at once (each in its own process).

### `Testing.testSequenced`

```zsharp
Testing.testSequenced : string -> list<Testing.Test> -> Testing.Test
```

A group of tests run one at a time: tests that share a file or a port.

### `Testing.ftestList`

```zsharp
Testing.ftestList : string -> list<Testing.Test> -> Testing.Test
```

A focused group.

### `Testing.ptestList`

```zsharp
Testing.ptestList : string -> list<Testing.Test> -> Testing.Test
```

A pending group.

### `Testing.expectAt`

```zsharp
Testing.expectAt : 'a -> string -> string -> int -> unit when 'a : Show
```

Compares the value's text (through Show) with the literal next to it, which
`zs test --update` rewrites when they differ (an expect test, 0009). The compiler gives it
its place: `expect` is `expectAt` with the file and line.

### `Testing.expect`

```zsharp
Testing.expect : 'a -> string -> unit when 'a : Show
```

An expect test: `expect (parse "1 + 2") """Add (Num 1, Num 2)"""`.

