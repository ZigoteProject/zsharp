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

### `Result.Builder.bind`

```zsharp
Result.Builder.bind : result<'a, 'b> -> ('a -> result<'c, 'b>) -> result<'c, 'b>
```

`let!`: the rest with the value of `Ok`, or the `Error`.

### `Result.Builder.ret`

```zsharp
Result.Builder.ret : 'a -> result<'a, 'b>
```

`return x`: `Ok x`.

### `Result.Builder.zero`

```zsharp
Result.Builder.zero : unit -> result<unit, 'a>
```

An `if` without `else`, or a body that ends in a statement: `Ok ()`.

### `Result.Builder.delay`

```zsharp
Result.Builder.delay : (unit -> 'a) -> 'a
```

The body, run now.

### `Result.Builder.using`

```zsharp
Result.Builder.using : 'a -> ('a -> 'b) -> 'b when 'a : Dispose
```

`use x = e`: the rest with `x`, which is disposed after it.

### `Result.Builder.forEach`

```zsharp
Result.Builder.forEach : list<'a> -> ('a -> result<unit, 'b>) -> result<unit, 'b>
```

`for x in xs do`: the body for each element, until one gives an `Error`.

