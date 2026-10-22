#include <stddef.h>

#include "fixed.h"

static int a, b, c;

Packet packet_fill(uint8_t v, int32_t len) {
    Packet p;
    for (int i = 0; i < 16; i++) p.data[i] = v;
    p.len = len;
    return p;
}

int32_t packet_sum(Packet p) {
    int32_t s = p.len;
    for (int i = 0; i < 16; i++) s += p.data[i];
    return s;
}

Cursor cursor_make(int kind) { return (Cursor){ kind, 42, { &a, &b, &c } }; }
int cursor_kind(Cursor c) { return c.kind; }
int cursor_check(Cursor x) { return x.xdata == 42 && x.data[0] == &a && x.data[1] == &b && x.data[2] == &c; }

Mat2 mat2_transpose(Mat2 m) {
    Mat2 t;
    for (int i = 0; i < 2; i++)
        for (int j = 0; j < 2; j++) t.m[i][j] = m.m[j][i];
    return t;
}

Pixel pixel_invert(Pixel p) {
    for (int i = 0; i < 3; i++) p.rgb[i] = (uint8_t)(255 - p.rgb[i]);
    return p;
}

int32_t sum4(const int32_t xs[4]) { return xs[0] + xs[1] + xs[2] + xs[3]; }

// declared in fixed.zs, taking a span: its data and its length
int32_t bytes_sum(const uint8_t *p, size_t n) {
    int32_t s = 0;
    for (size_t i = 0; i < n; i++) s += p[i];
    return s;
}
