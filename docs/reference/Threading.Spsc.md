# Threading.Spsc

Queues with one producer and one consumer: an interrupt handler and the program (0012), or two
threads. A push and a pop each copy a value and claim a slot, neither waiting nor locking, so
a handler can push. More producers or consumers are safe too, as the type allows them: a pop
finds nothing while the value it would take is still being pushed, and a push finds the queue
full while the slot it would fill is still being popped. A fixed capacity, the storage
allocated once. Its functions are built into the compiler.

