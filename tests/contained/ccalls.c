#include "ccalls.h"

void call_it(void (*f)(void *, int64_t), void *user, int64_t x) { f(user, x); }

// declared callback<…> in Z#: called during the call, on its thread
void call_now(void (*f)(void *, int64_t), void *user, int64_t x) { call_it(f, user, x); }

// declared callback<share<…>> in Z#: C may call it on any thread, and later
void call_shared(void (*f)(void *, int64_t), void *user, int64_t x) { call_it(f, user, x); }
