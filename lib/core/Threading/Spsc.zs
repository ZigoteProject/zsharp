/// Queues with one producer and one consumer: an interrupt handler and the program (0012), or two
/// threads. A push and a pop each copy a value and move an index, neither waiting nor locking, so
/// a handler can push. A fixed capacity, the storage allocated once. Its functions are built into
/// the compiler.
namespace Threading

/// Functions on queues of one producer and one consumer: `create capacity`, `push q x` (`false`
/// when the queue is full, the value dropped), `pop q` (`None` when it's empty).
module Spsc
