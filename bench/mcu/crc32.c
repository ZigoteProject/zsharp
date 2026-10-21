#include "bench.h"
static uint8_t data[4096];
static uint32_t crc32(const uint8_t *p, int n) {
    uint32_t crc = 0xFFFFFFFF;
    for (int i = 0; i < n; i++) {
        crc ^= p[i];
        for (int k = 0; k < 8; k++) crc = crc & 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
    return crc ^ 0xFFFFFFFF;
}
int main(void) {
    for (int i = 0; i < 4096; i++) data[i] = (uint8_t)(i * 7 % 251);
    int64_t t0 = zs_ticks();
    uint32_t crc = 0;
    for (int r = 0; r < 10; r++) crc = crc32(data, 4096);
    report("crc32", crc, zs_ticks() - t0);
    return 0;
}
