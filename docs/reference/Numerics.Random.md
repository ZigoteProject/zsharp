# Numerics.Random

Numbers beyond the built-in ones: `Random`, a seeded generator of pseudo-random numbers.

## Types

### `Random`

```zsharp
type Random
```

A generator of pseudo-random numbers: PCG32 (Melissa O'Neill's, pcg-random.org), 64 bits of
state, so a seed gives the same numbers on every target. Not for secrets. It changes as it's
used, so a `Random` isn't `Share`: each thread makes its own. `Random.shared ()` (Std) is one
seeded from the operating system.

## Functions

### `Random.create`

```zsharp
Random.create : u64 -> Random
```

A generator seeded with `seed`: the same seed gives the same numbers.

### `Random.nextU32`

```zsharp
Random.nextU32 : Random -> u32
```

The next 32 random bits.

### `Random.nextInt`

```zsharp
Random.nextInt : int -> int -> Random -> int
```

A number from `low` up to but not including `high`, each as likely as the others: a draw
that would favor some is drawn again.

### `Random.nextFloat`

```zsharp
Random.nextFloat : Random -> f64
```

A number from 0 up to but not including 1, with 53 random bits.

### `Random.nextBytes`

```zsharp
Random.nextBytes : Buffer<u8> -> Random -> unit
```

Fills `bytes` with random bytes.

### `Random.shuffle`

```zsharp
Random.shuffle : array<'a> -> Random -> array<'a>
```

The items in a random order, each order as likely (Fisher-Yates); in place when the array
isn't shared.

