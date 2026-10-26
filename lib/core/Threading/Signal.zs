/// Signals: a doorbell an interrupt handler rings for a task, on a microcontroller. `Signal.set`
/// marks a signal set, from a handler or anywhere, and never waits or allocates; `Signal.wait` is
/// a task that goes on once it's set (at once, when it was already) and clears it. A set with no
/// task waiting stays set until one waits, so none is lost, and several sets before a wait are
/// one. One task waits on a signal at a time. A handler may reach a signal, as it may an `Atomic`
/// or an `Spsc`: the handler pushes what it read to an `Spsc` and sets the signal, and the task
/// pops it.
namespace Threading

/// A doorbell between interrupt handlers and a task: the runtime's number for it.
type Signal = { id: int }

/// Functions on signals: `create` (a program has at most 32), `set` and `wait`.
module Signal =
  /// A new signal, not set.
  let create () : Signal = { id = Native.signalNew () }

  /// Sets the signal: the task waiting on it goes on, or the next to wait does at once.
  let set (s: Signal) = Native.signalSet s.id

  /// Waits until the signal is set, and clears it.
  let wait (s: Signal) : Task<unit> =
    // set already: on at once; else the loop wakes it once a handler sets it
    let start (k: unit -> unit) = if Native.signalTake s.id then k () else Native.signalWait s.id k
    Task.fromCallback start (fun () -> Native.signalUnwait s.id)
