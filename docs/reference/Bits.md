# Bits

`[<Bits>]` records (0013): a record that is one unsigned integer, its fields ranges of its bits
(a `bool` one bit, an enum the bits its cases need, `u8` to `u64` their size or `[<Width n>]`),
laid out from bit 0 or at `[<Bit n>]`. `[<Bits 32>]` fixes the width; without one it's the
smallest of 8, 16, 32 and 64 that holds the fields. Its equality, ordering and hashing are the
integer's. These convert between a record and its integer; its functions are built into the
compiler.

## Functions

### `Bits.ofRaw`

```zsharp
Bits.ofRaw : u64 -> 'a
```

The [<Bits>] record whose integer this is; a bit set past its width panics.

### `Bits.ofU16`

```zsharp
Bits.ofU16 : u16 -> 'a
```

The 16-bit [<Bits>] record whose integer this is, gaps kept.

### `Bits.ofU32`

```zsharp
Bits.ofU32 : u32 -> 'a
```

The 32-bit [<Bits>] record whose integer this is, gaps kept: `Bits.ofU32 (Mmio.read32 address)`.

### `Bits.ofU64`

```zsharp
Bits.ofU64 : u64 -> 'a
```

The 64-bit [<Bits>] record whose integer this is, gaps kept.

### `Bits.ofU8`

```zsharp
Bits.ofU8 : u8 -> 'a
```

The 8-bit [<Bits>] record whose integer this is, gaps kept (the record's type from where it's used).

### `Bits.raw`

```zsharp
Bits.raw : 'a -> u64
```

A [<Bits>] record's integer as a u64, whatever its width.

### `Bits.toU16`

```zsharp
Bits.toU16 : 'a -> u16
```

A 16-bit [<Bits>] record's integer.

### `Bits.toU32`

```zsharp
Bits.toU32 : 'a -> u32
```

A 32-bit [<Bits>] record's integer: `Mmio.write32 address (Bits.toU32 r)`.

### `Bits.toU64`

```zsharp
Bits.toU64 : 'a -> u64
```

A 64-bit [<Bits>] record's integer.

### `Bits.toU8`

```zsharp
Bits.toU8 : 'a -> u8
```

An 8-bit [<Bits>] record's integer.

