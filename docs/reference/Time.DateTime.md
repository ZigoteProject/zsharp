# Time.DateTime

Time: `DateTime`, a moment in UTC, and `Duration`, a length of time in nanoseconds
(`i64<ns>`, so that a plain number isn't one). `DateTime.utcNow` reads the clock (Std).

## Types

### `ns`

```zsharp
type ns
```

Nanoseconds: the unit of a `Duration`.

### `Duration`

```zsharp
type Duration
```

A length of time in nanoseconds: an `i64` on every target, since an `int` of nanoseconds is
2.1 seconds on a microcontroller.

### `DateTime`

```zsharp
type DateTime
```

A moment: nanoseconds since 1970-01-01T00:00:00Z, in UTC (the years 1678 to 2262). Its
equality, ordering and hashing are its number's; `string` prints it in ISO 8601.

## Derives and impls

### `impl Show<DateTime>`

```zsharp
impl Show<DateTime>
```

A moment prints in ISO 8601 (`DateTime.toIso`).

## Functions

### `DateTime.unixEpoch`

```zsharp
let unixEpoch : DateTime
```

1970-01-01T00:00:00Z.

### `DateTime.toIso`

```zsharp
DateTime.toIso : DateTime -> string
```

The moment in ISO 8601: `2026-10-22T08:00:00Z`, with a fraction of a second only when it
has one (`08:00:00.25Z`).

