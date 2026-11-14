// Calls f(user, x) before it returns (tests/contained/c.zs).
#include <stdint.h>

void call_it(void (*f)(void *, int64_t), void *user, int64_t x);
