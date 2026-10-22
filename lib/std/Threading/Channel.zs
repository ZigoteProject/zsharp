/// Channels: a `Channel<T>` carries values from threads that send them to threads that receive
/// them, in order, holding up to the capacity it was made with (a sender waits while it's full).
/// Its values must be Share. Its functions are built into the compiler.
namespace Threading

/// Functions on channels: `make capacity`, `send ch x` (waits while it's full; panics once it's
/// closed), `receive ch` (waits for a value: `None` once it's closed and empty) and `close ch`.
module Channel
