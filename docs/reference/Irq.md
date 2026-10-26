# Irq

A microcontroller's interrupt lines, by number, through its interrupt controller (the NVIC). A
line's handler is a function marked `[<Interrupt 38>]` or `[<Interrupt "USART2">]` (the
board's names, runtime/boards/<board>.irq); or a task waits for the line with `Irq.wait`.

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

### `Irq.wait`

```zsharp
Irq.wait : int -> Task<unit>
```

Waits for line `n` to fire once: a task that enables the line and goes on after its
interrupt. The runtime's handler disables the line again, so the task goes on with it quiet:
clear the device's flag before waiting again, or it fires at once. One task waits on a line
at a time, and a line with a handler of its own (`[<Interrupt>]`) wakes none: that handler
sets a `Signal` instead.

