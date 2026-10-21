#include "bench.h"
// a loop of exactly 2 * 1,000,000 instructions (subs + bne), to turn ticks into instructions
int main(void) {
    int64_t t0 = zs_ticks();
    __asm__ volatile("ldr r0, =1000000\n1: subs r0, #1\n bne 1b" ::: "r0", "cc");
    report("calib", 2000000, zs_ticks() - t0);
    return 0;
}
