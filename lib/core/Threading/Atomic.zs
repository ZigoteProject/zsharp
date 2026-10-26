/// Atomic values: an `Atomic<T>` holds a number, a `bool` or a `char` that threads read and
/// change at once, each operation whole (sequentially consistent), without a lock. For a counter
/// or a flag that parallel work shares, or that an interrupt handler shares with a program; a
/// `Mutex` holds any other value. On a Cortex-M0, which has no atomic instructions, each
/// operation masks interrupts around it. Its functions are built into the compiler.
namespace Threading

/// Functions on atomic values: `make`, `get`, `set`, `exchange` (sets, giving the old value),
/// `compareExchange a expected desired` (sets only if it holds `expected`, giving what it held,
/// as .NET's Interlocked does) and `add` (giving the new value, wrapping on overflow).
module Atomic
