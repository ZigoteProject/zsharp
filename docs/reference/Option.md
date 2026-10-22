# Option

Functions on options, values that may be missing: `Some x` or `None` (the type is in the
prelude).

## Types

#### `option#IsSome`

```zsharp
member o.IsSome
```

Whether the option holds a value.

#### `option#IsNone`

```zsharp
member o.IsNone
```

Whether the option is `None`.

## Functions

### `Option.map`

```zsharp
Option.map : ('a -> 'b) -> option<'a> -> option<'b>
```

Applies `f` to the value of `Some`; `None` stays `None`.

### `Option.bind`

```zsharp
Option.bind : ('a -> option<'b>) -> option<'a> -> option<'b>
```

Applies `f`, which itself returns an option, to the value of `Some`.

### `Option.defaultValue`

```zsharp
Option.defaultValue : 'a -> option<'a> -> 'a
```

The value of `Some`, or `d` for `None`.

### `Option.isSome`

```zsharp
Option.isSome : option<'a> -> bool
```

Whether the option holds a value.

### `Option.isNone`

```zsharp
Option.isNone : option<'a> -> bool
```

Whether the option is `None`.

### `Option.get`

```zsharp
Option.get : option<'a> -> 'a
```

The value of `Some`. Panics on `None`; prefer a match or `Option.defaultValue`.

### `Option.toList`

```zsharp
Option.toList : option<'a> -> list<'a>
```

`[x]` for `Some x`, `[]` for `None`.

### `Option.orElse`

```zsharp
Option.orElse : option<'a> -> option<'a> -> option<'a>
```

The option itself if it is `Some`, otherwise `other`.

### `Option.iter`

```zsharp
Option.iter : ('a -> unit) -> option<'a> -> unit
```

Calls `f` on the value of `Some`; does nothing for `None`.

### `Option.toResult`

```zsharp
Option.toResult : 'a -> option<'b> -> result<'b, 'a>
```

`Ok x` for `Some x`, `Error err` for `None`.

### `Option.Builder.bind`

```zsharp
Option.Builder.bind : option<'a> -> ('a -> option<'b>) -> option<'b>
```

`let!`: the rest with the value of `Some`, or `None`.

### `Option.Builder.ret`

```zsharp
Option.Builder.ret : 'a -> option<'a>
```

`return x`: `Some x`.

### `Option.Builder.zero`

```zsharp
Option.Builder.zero : unit -> option<unit>
```

An `if` without `else`, or a body that ends in a statement: `Some ()`.

### `Option.Builder.delay`

```zsharp
Option.Builder.delay : (unit -> 'a) -> 'a
```

The body, run now.

### `Option.Builder.using`

```zsharp
Option.Builder.using : 'a -> ('a -> 'b) -> 'b when 'a : Dispose
```

`use x = e`: the rest with `x`, which is disposed after it.

### `Option.Builder.forEach`

```zsharp
Option.Builder.forEach : list<'a> -> ('a -> option<unit>) -> option<unit>
```

`for x in xs do`: the body for each element, until one gives `None`.

