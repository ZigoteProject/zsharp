#include "bench.h"
static int32_t a[512];
static void isort(int32_t *p, int n) {
    for (int i = 1; i < n; i++) {
        int32_t v = p[i];
        int j = i - 1;
        while (j >= 0 && p[j] > v) { p[j + 1] = p[j]; j--; }
        p[j + 1] = v;
    }
}
int main(void) {
    for (int i = 0; i < 512; i++) a[i] = (int32_t)((i * 7919) % 1009);
    int64_t t0 = zs_ticks();
    isort(a, 512);
    report("isort", a[0] + a[255] + a[511], zs_ticks() - t0);
    return 0;
}
