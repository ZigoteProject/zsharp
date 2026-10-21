# Mmio

Memory-mapped hardware registers, for drivers on microcontrollers: volatile loads and stores,
which the optimizer keeps exactly as written. Its functions are built into the compiler.

## Functions

### `Mmio.read32`

```zsharp
Mmio.read32 : usize -> u32
```

Reads the 32-bit hardware register at an address (a volatile load).

### `Mmio.read8`

```zsharp
Mmio.read8 : usize -> u8
```

Reads the 8-bit hardware register at an address (a volatile load).

### `Mmio.write32`

```zsharp
Mmio.write32 : usize -> u32 -> unit
```

Writes the 32-bit hardware register at an address (a volatile store).

### `Mmio.write8`

```zsharp
Mmio.write8 : usize -> u8 -> unit
```

Writes the 8-bit hardware register at an address (a volatile store).

