# Threading.Spsc

Queues with one producer and one consumer: an interrupt handler and the program (0012), or two
threads. A push and a pop each copy a value and move an index, neither waiting nor locking, so
a handler can push. A fixed capacity, the storage allocated once. Its functions are built into
the compiler.

