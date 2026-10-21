#include "bench.h"
static int64_t fib(int64_t n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
int main(void) {
    int64_t t0 = zs_ticks();
    int64_t r = fib(24);
    report("fib64", r, zs_ticks() - t0);
    return 0;
}
