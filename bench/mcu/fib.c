#include "bench.h"
static int32_t fib(int32_t n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
int main(void) {
    int64_t t0 = zs_ticks();
    int32_t r = fib(24);
    report("fib", r, zs_ticks() - t0);
    return 0;
}
