# Threading.Signal

Signals: a doorbell an interrupt handler rings for a task, on a microcontroller. `Signal.set`
marks a signal set, from a handler or anywhere, and never waits or allocates; `Signal.wait` is
a task that goes on once it's set (at once, when it was already) and clears it. A set with no
task waiting stays set until one waits, so none is lost, and several sets before a wait are
one. One task waits on a signal at a time. A handler may reach a signal, as it may an `Atomic`
or an `Spsc`: the handler pushes what it read to an `Spsc` and sets the signal, and the task
pops it.

## Types

### `Signal`

```zsharp
type Signal
```

A doorbell between interrupt handlers and a task: the runtime's number for it.

## Functions

### `Signal.create`

```zsharp
Signal.create : unit -> Signal
```

A new signal, not set.

### `Signal.set`

```zsharp
Signal.set : Signal -> unit
```

Sets the signal: the task waiting on it goes on, or the next to wait does at once.

### `Signal.wait`

```zsharp
Signal.wait : Signal -> Task<unit>
```

Waits until the signal is set, and clears it.

