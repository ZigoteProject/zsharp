#!/usr/bin/env bash
# The embedded runtime's pow, atan2 and roundeven (runtime/rt-embedded.c: compiler-rt lacks them
# on a chip and on WebAssembly) against the host's libm: the special values, and the largest
# difference over random arguments in units in the last place. fdlibm's pow and atan2 are faithful
# (within 1 ulp of the true value), so they may be 1 ulp from a correctly rounded host's.
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo '#include <stdint.h>'; sed -n '/ZS_LIBM_BEGIN/,/ZS_LIBM_END/p' runtime/rt-embedded.c; } > "$tmp/libm.c"
cat > "$tmp/main.c" <<'C'
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
double zs_pow(double, double); double zs_atan2(double, double); double zs_roundeven(double);
float zs_roundevenf(float); float zs_powf(float, float);

static uint64_t state = 0x853c49e6748fea9bULL;
static uint64_t next(void) { state = state * 6364136223846793005ULL + 1442695040888963407ULL; return state ^ (state >> 29); }
static double any(void) { uint64_t u = next(); double d; memcpy(&d, &u, 8); return d; }
static double within(double lo, double hi) { return lo + (hi - lo) * (double)(next() >> 11) / 9007199254740992.0; }

// the error of `got` in units in the last place of `want`; 0 when both are the same NaN,
// infinity or zero, and huge when they differ in kind or in a zero's sign
static double ulps(double got, double want) {
    if (isnan(want)) return isnan(got) ? 0 : 1e9;
    if (isinf(want) || want == 0) return memcmp(&got, &want, 8) == 0 ? 0 : 1e9;
    double u = nextafter(fabs(want), INFINITY) - fabs(want);
    return fabs(got - want) / u;
}

static double worst_pow = 0, worst_atan2 = 0, worst_round = 0;
static void pow_at(double x, double y) {
    double e = ulps(zs_pow(x, y), pow(x, y));
    if (e > worst_pow) worst_pow = e;
}
static void atan2_at(double y, double x) {
    double e = ulps(zs_atan2(y, x), atan2(y, x));
    if (e > worst_atan2) worst_atan2 = e;
}

int main(void) {
    double special[] = {0.0, -0.0, 1.0, -1.0, 0.5, -0.5, 2.0, -2.0, 3.0, -3.0, 1e-310, -1e-310,
                        1e300, -1e300, INFINITY, -INFINITY, NAN, 0x1p-1074, 1.0000000001, 0.9999999999};
    int ns = sizeof special / sizeof special[0];
    for (int i = 0; i < ns; i++)
        for (int j = 0; j < ns; j++) { pow_at(special[i], special[j]); atan2_at(special[i], special[j]); }
    for (int i = 0; i < 2000000; i++) {
        pow_at(within(0, 4), within(-40, 40));
        pow_at(fabs(any()), within(-2, 2));
        pow_at(within(-10, 10), floor(within(-30, 30)));
        pow_at(within(0.999, 1.001), within(-1e6, 1e6));
        atan2_at(any(), any());
        atan2_at(within(-10, 10), within(-10, 10));
        double r = within(-1e6, 1e6), h = floor(r) + 0.5;
        worst_round = fmax(worst_round, fmax(ulps(zs_roundeven(r), nearbyint(r)), ulps(zs_roundeven(h), nearbyint(h))));
        worst_round = fmax(worst_round, ulps(zs_roundevenf((float)h), nearbyintf((float)h)));
    }
    printf("pow    %.0f ulp at most\n", worst_pow);
    printf("atan2  %.0f ulp at most\n", worst_atan2);
    printf("round  %.0f ulp at most\n", worst_round);
    printf("powf   %s\n", zs_powf(2.0f, 10.0f) == 1024.0f && zs_powf(9.0f, 0.5f) == 3.0f ? "ok" : "wrong");
    return worst_pow <= 1 && worst_atan2 <= 1 && worst_round == 0 ? 0 : 1;
}
C
renames="-Droundeven=zs_roundeven -Droundevenf=zs_roundevenf -Datan=zs_atan -Datan2=zs_atan2 -Dpow=zs_pow -Datanf=zs_atanf -Datan2f=zs_atan2f -Dpowf=zs_powf"
clang -O2 -ffp-contract=off $renames -c "$tmp/libm.c" -o "$tmp/libm.o" && clang -O2 "$tmp/main.c" "$tmp/libm.o" -lm -o "$tmp/check" && "$tmp/check"
