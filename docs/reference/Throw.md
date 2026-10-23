# Throw

Functions for the `Throw` effect (typed exceptions): turning a failure into a `result`, or
a `result` into a failure.

## Functions

### `Throw.catch`

```zsharp
Throw.catch : (unit -> 'a / Throw<'b>) -> result<'a, 'b>
  handles Throw<'b> from f
```

Runs `f`, giving `Ok` of its result, or `Error e` when it throws `e`:
`Throw.catch (fun () -> digit c)`.

### `Throw.recover`

```zsharp
Throw.recover : ('a -> 'b) -> (unit -> 'b / Throw<'a>) -> 'b
  handles Throw<'a> from f
```

Runs `f`, giving its result, or `onError e` when it throws `e`.

### `Throw.ofResult`

```zsharp
Throw.ofResult : result<'a, 'b> -> 'a / Throw<'b>
```

The value of an `Ok`, or the error of an `Error` thrown: `Throw.ofResult (Int.parse s)`.

### `Throw.ofOption`

```zsharp
Throw.ofOption : 'a -> option<'b> -> 'b / Throw<'a>
```

The value of a `Some`, or `e` thrown for `None`.

