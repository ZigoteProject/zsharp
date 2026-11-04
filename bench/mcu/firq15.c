#include "bench.h"
// the same q15 filter in C, CMSIS-DSP's style: a 32-bit product, the accumulator added at the
// product's scale, rounded and saturated to 16 bits
static int16_t taps[32], x[1024];
static inline int16_t mul_add_q15(int16_t a, int16_t b, int16_t c) {
    int32_t s = ((int32_t)a * b + ((int32_t)c << 15) + 0x4000) >> 15;
    return s > 32767 ? 32767 : s < -32768 ? -32768 : (int16_t)s;
}
static int32_t fir(void) {
    int32_t sum = 0;
    for (int i = 31; i < 1024; i++) {
        int16_t acc = 0;
        for (int k = 0; k < 32; k++) acc = mul_add_q15(taps[k], x[i - k], acc);
        sum += acc;
    }
    return sum;
}
int main(void) {
    for (int k = 0; k < 32; k++) taps[k] = (int16_t)((k + 1) * 62);
    for (int i = 0; i < 1024; i++) x[i] = (int16_t)((i % 17 - 8) * 4096);
    int64_t t0 = zs_ticks();
    int32_t s = fir();
    report("firq15", s, zs_ticks() - t0);
    return 0;
}
