#include "bench.h"
// the same computation as C would write it: a loop, no allocation
int main(void) {
    int64_t t0 = zs_ticks();
    long total = 0;
    for (int r = 1; r <= 20; r++)
        for (int i = 0; i < 200; i++) {
            long x = (long)(i + r) * 3;
            if (x % 2 == 0) total += x;
        }
    report("pipeline", total, zs_ticks() - t0);
    return 0;
}
