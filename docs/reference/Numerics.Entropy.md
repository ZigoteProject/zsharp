# Numerics.Entropy

A generator seeded from the operating system, which needs one.

## Types

#### `Random#shared`

```zsharp
static member shared () : Random
```

A new generator seeded from the operating system's randomness, so each run's numbers
differ: `Random.shared ()`. A function, since a value threads share can't hold a `Random`.

