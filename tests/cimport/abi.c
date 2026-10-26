#include "abi.h"
C4 c4_swap(C4 v) { return (C4){ v.a, v.b, v.g, v.r }; }
P3 p3_shift(P3 v, int d) { return (P3){ v.x + d, v.y + d, v.z + d }; }
F4 f4_scale(F4 v, float k) { return (F4){ v.a * k, v.b * k, v.c * k, v.d * k }; }
D2 d2_swap(D2 v) { return (D2){ v.b, v.a }; }
Mix mix_add(Mix v, double d) { return (Mix){ v.a + d, v.b + (float)d }; }
Big big_sum(Big v, Big w) { return (Big){ v.a + w.a, v.b + w.b, v.c + w.c }; }
double many(F4 a, D2 b, Mix c, Big d, P3 e, C4 f) {
  return a.a + a.d + b.a + b.b + c.a + c.b + d.a + d.c + e.x + e.z + f.r + f.a;
}

double d2_six(D2 a, D2 b, D2 c, D2 d, D2 e, D2 f) {
    D2 v[] = {a, b, c, d, e, f};
    double r = 0;
    for (int i = 0; i < 6; i++) r = r * 100 + v[i].a * 10 + v[i].b;
    return r;
}

long p3_after(long a, long b, long c, long d, long e, P3 p, long f) {
    return ((((((a * 10 + b) * 10 + c) * 10 + d) * 10 + e) * 10 + p.x) * 10 + p.y) * 10 + p.z + f * 100000000;
}

Big big_after(long a, long b, long c, long d, P3 p, long e) {
    Big r = {(int)(a + b + c + d + e), p.x * 1.0, p.y * 10.0 + p.z};
    return r;
}

IntOrFloat iof_next(IntOrFloat v) { v.i += 1; return v; }
Floats floats_swap(Floats v) { float t = v.two[0]; v.two[0] = v.two[1]; v.two[1] = t; return v; }
Wide wide_flip(Wide w) {
    for (int i = 0; i < 6; i++) { unsigned char t = w.bytes[i]; w.bytes[i] = w.bytes[11 - i]; w.bytes[11 - i] = t; }
    return w;
}
long long big3_sum(Big3 b) { return b.words[0] + b.words[1] + b.words[2]; }
Tagged tagged_bump(Tagged t) { t.kind += 1; t.value.f *= 2; return t; }
Msg msg_reply(Msg m) { m.body.ratio = m.body.code / 4.0f; m.kind = 2; return m; }
