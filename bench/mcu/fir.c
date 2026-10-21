#include "bench.h"
static float taps[32], x[1024];
static float fir(void) {
    float sum = 0;
    for (int i = 31; i < 1024; i++) {
        float acc = 0;
        for (int k = 0; k < 32; k++) acc += taps[k] * x[i - k];
        sum += acc;
    }
    return sum;
}
int main(void) {
    for (int k = 0; k < 32; k++) taps[k] = (float)(k + 1) / 528.0f;
    for (int i = 0; i < 1024; i++) x[i] = (float)(i % 17) - 8.0f;
    int64_t t0 = zs_ticks();
    float s = fir();
    report("fir", (int64_t)(s * 1000.0f), zs_ticks() - t0);
    return 0;
}
