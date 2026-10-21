# Int

Integer arithmetic that wraps around on overflow, for hashes and checksums (the operators
panic on overflow instead, except in a `[<Wrapping>]` function). Its functions are built
into the compiler.

## Functions

### `Int.wrappingAdd`

```zsharp
Int.wrappingAdd : 'a -> 'a -> 'a
```

`a + b`, wrapping around on overflow instead of panicking.

### `Int.wrappingMul`

```zsharp
Int.wrappingMul : 'a -> 'a -> 'a
```

`a * b`, wrapping around on overflow instead of panicking.

### `Int.wrappingSub`

```zsharp
Int.wrappingSub : 'a -> 'a -> 'a
```

`a - b`, wrapping around on overflow instead of panicking.

