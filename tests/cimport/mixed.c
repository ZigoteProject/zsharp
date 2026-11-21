#include "mixed.h"
F1 f1_double(F1 v) { return (F1){ v.f * 2 }; }
FI fi_swap(FI v) { return (FI){ (float)v.i, (int)v.f }; }
ID id_add(ID v, int n) { return (ID){ v.i + n, v.d + n }; }
CF cf_next(CF v) { return (CF){ (signed char)(v.c - 1), v.f + 0.5f }; }
FA fa_swap(FA v) { return (FA){ { v.v[1], v.v[0] } }; }
Nest nest_bump(Nest v) { v.inner.f += 1; v.i += 10; return v; }
II ii_swap(II v) { return (II){ v.b, v.a }; }
FII fii_turn(FII v) { return (FII){ v.f + v.i, v.j, v.i }; }
static const int cells[3] = { 7, 8, 9 };
DP dp_make(double d) { return (DP){ d, cells }; }
int dp_read(DP v, int n) { return v.p[n] + (int)v.d; }

double fi_after_floats(double a, double b, double c, double d, double e, double f, double g, double h, FI v, F1 w) {
    return a + b + c + d + e + f + g + h + v.f * 100 + v.i * 1000 + w.f * 10000;
}

double fi_after_ints(long a, long b, long c, long d, long e, long f, long g, long h, FI v, ID w, double x) {
    return (double)(a + b + c + d + e + f + g + h) + v.f * 100 + v.i * 1000 + w.i * 10000 + w.d * 100000 + x * 1000000;
}

long narrow_sum(signed char a, unsigned char b, short c, unsigned short d, int e, unsigned f) {
    return (long)a + (long)b + (long)c + (long)d + (long)e + (long)f;
}
int int_negate(int v) { return -v; }
unsigned unsigned_half(unsigned v) { return v / 2; }
short short_negate(short v) { return (short)-v; }
