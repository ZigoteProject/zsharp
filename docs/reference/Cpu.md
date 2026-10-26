# Cpu

The processor's instructions firmware needs, with nothing moved across them: `Cpu.nop`, `wfi`
(sleep until an interrupt), `wfe` and `sev` (events), `dmb` and `dsb` (memory barriers), `isb`,
`enableInterrupts` and `disableInterrupts`, and `Cpu.critical (fun () -> …)`, which runs its
body with interrupts masked and gives its value (one inside another is fine). On a computer the
barriers are fences and the rest do nothing, but masking interrupts is an error there. Its
functions are built into the compiler.

## Functions

### `Cpu.critical`

```zsharp
Cpu.critical : (unit -> 'a / <>) -> 'a
  the argument must perform nothing
```

Runs `body` with interrupts masked and gives its value, for a change that handlers mustn't see halfway; one inside another is fine (only on a microcontroller).

### `Cpu.disableInterrupts`

```zsharp
Cpu.disableInterrupts : unit -> unit
```

Keeps interrupts out until they're enabled again (only on a microcontroller).

### `Cpu.dmb`

```zsharp
Cpu.dmb : unit -> unit
```

A data memory barrier: the memory accesses before it complete, as others see them, before any after it.

### `Cpu.dsb`

```zsharp
Cpu.dsb : unit -> unit
```

A data synchronization barrier: nothing after it runs until the memory accesses before it complete.

### `Cpu.enableInterrupts`

```zsharp
Cpu.enableInterrupts : unit -> unit
```

Lets interrupts in (only on a microcontroller).

### `Cpu.isb`

```zsharp
Cpu.isb : unit -> unit
```

An instruction barrier: what follows is fetched again, seeing a change to the processor's state (on a computer, nothing).

### `Cpu.nop`

```zsharp
Cpu.nop : unit -> unit
```

Nothing, for one instruction's time.

### `Cpu.sev`

```zsharp
Cpu.sev : unit -> unit
```

Signals an event, waking a `wfe` (on a computer, nothing).

### `Cpu.wfe`

```zsharp
Cpu.wfe : unit -> unit
```

Sleeps until an event or an interrupt (on a computer, nothing).

### `Cpu.wfi`

```zsharp
Cpu.wfi : unit -> unit
```

Sleeps until an interrupt (on a computer, nothing).

