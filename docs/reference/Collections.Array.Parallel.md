# Collections.Array.Parallel

Arrays built in parallel, on the thread pool (`Threading.Parallel`).

## Functions

### `Array.Parallel.init`

```zsharp
Array.Parallel.init : int -> share<int -> 'a> -> array<'a>
```

The array of `f 0`, …, `f (n - 1)`, its elements computed in parallel.

### `Array.Parallel.map`

```zsharp
Array.Parallel.map : share<'a -> 'b> -> array<'a> -> array<'b> when 'a : Share
```

The array of `f` applied to each element, computed in parallel. The array is cut into parts
and each moves into its job (decision 75): when the caller gives the array up, a job's
elements are its own and aren't marked shared.

