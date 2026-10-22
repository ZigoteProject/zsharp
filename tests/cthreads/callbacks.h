// Calls f(user, x) on a thread of its own, and waits for it (tests/cthreads/callbacks.zs).
#include <stdint.h>

void on_thread(void (*f)(void *, int64_t), void *user, int64_t x);
