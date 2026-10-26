# Irq

A microcontroller's interrupt lines, by number, through its interrupt controller (the NVIC). A
line's handler is a function marked `[<Interrupt 38>]` or `[<Interrupt "USART2">]` (the
board's names, runtime/boards/<board>.irq).

## Functions

### `Irq.enable`

```zsharp
Irq.enable : int -> unit
```

Enables line `n`: its handler runs when the device raises it.

### `Irq.disable`

```zsharp
Irq.disable : int -> unit
```

Disables line `n`.

### `Irq.pend`

```zsharp
Irq.pend : int -> unit
```

Sets line `n` pending, as its device would: its handler runs once the line is enabled. A test
needs no device.

