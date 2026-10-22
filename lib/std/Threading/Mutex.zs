/// Mutexes: a `Mutex<T>` holds a value that threads take turns with, under a lock. The value
/// must be Share (immutable, or another Atomic, Mutex or Channel), since every thread may read
/// it: `Mutex.update m f` replaces it with `f` of it while holding the lock, so updates from
/// several threads don't lose one another. Its functions are built into the compiler.
namespace Threading

/// Functions on mutexes: `make`, `get` (the value now), `set` and `update` (the value `f` makes
/// of it, under the lock; `f` mustn't use the same mutex). `update` gives the new value.
module Mutex
