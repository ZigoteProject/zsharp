#include "bench.h"
static const char text[] = "set 12 leds to 255 and wait 1000 ms then blink 3 times ";
static uint8_t data[2048];
enum kind { IDLE, NUMBER, WORD };
int main(void) {
    for (int i = 0; i < 2048; i++) data[i] = (uint8_t)text[i % (sizeof text - 1)];
    int64_t t0 = zs_ticks();
    enum kind st = IDLE;
    long value = 0, numbers = 0, words = 0;
    for (int i = 0; i < 2048; i++) {
        uint8_t b = data[i];
        int digit = b >= '0' && b <= '9', letter = b >= 'a' && b <= 'z';
        if (st == NUMBER && digit) { value = value * 10 + (b - '0'); continue; }
        if (st == WORD && letter) { value++; continue; }
        if (st == NUMBER) numbers++;
        if (st == WORD) words++;
        if (digit) { st = NUMBER; value = b - '0'; }
        else if (letter) { st = WORD; value = 1; }
        else st = IDLE;
    }
    report("tokens", numbers * 1000 + words, zs_ticks() - t0);
    return 0;
}
