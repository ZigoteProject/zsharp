# Result

Functions on results, the outcome of something that can fail: `Ok value` or `Error err` (the
type is in the prelude).

## Functions

### `Result.map`

```zsharp
Result.map : ('a -> 'b) -> result<'a, 'c> -> result<'b, 'c>
```

Applies `f` to the value of `Ok`; an `Error` passes through.

### `Result.bind`

```zsharp
Result.bind : ('a -> result<'b, 'c>) -> result<'a, 'c> -> result<'b, 'c>
```

Applies `f`, which itself returns a result, to the value of `Ok`.

### `Result.mapError`

```zsharp
Result.mapError : ('a -> 'b) -> result<'c, 'a> -> result<'c, 'b>
```

Applies `f` to the error of `Error`; an `Ok` passes through.

### `Result.defaultValue`

```zsharp
Result.defaultValue : 'a -> result<'a, 'b> -> 'a
```

The value of `Ok`, or `d` for an `Error`.

### `Result.isOk`

```zsharp
Result.isOk : result<'a, 'b> -> bool
```

Whether the result is `Ok`.

### `Result.isError`

```zsharp
Result.isError : result<'a, 'b> -> bool
```

Whether the result is `Error`.

### `Result.toOption`

```zsharp
Result.toOption : result<'a, 'b> -> option<'a>
```

`Some x` for `Ok x`, `None` for an `Error`.

