// Spectral norm (the Benchmarks Game): floating-point loops over arrays.
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static double a(long i, long j) { return 1.0 / (double)((i + j) * (i + j + 1) / 2 + i + 1); }

static void multiplyAv(long n, const double *v, double *av) {
    for (long i = 0; i < n; i++) {
        double s = 0;
        for (long j = 0; j < n; j++) s += a(i, j) * v[j];
        av[i] = s;
    }
}

static void multiplyAtv(long n, const double *v, double *atv) {
    for (long i = 0; i < n; i++) {
        double s = 0;
        for (long j = 0; j < n; j++) s += a(j, i) * v[j];
        atv[i] = s;
    }
}

static void multiplyAtAv(long n, const double *v, double *atav, double *tmp) {
    multiplyAv(n, v, tmp);
    multiplyAtv(n, tmp, atav);
}

int main(int argc, char **argv) {
    long n = argc > 1 ? atol(argv[1]) : 1000;
    double *u = malloc(n * sizeof *u), *v = malloc(n * sizeof *v), *tmp = malloc(n * sizeof *tmp);
    for (long i = 0; i < n; i++) u[i] = 1;
    for (int k = 0; k < 10; k++) {
        multiplyAtAv(n, u, v, tmp);
        multiplyAtAv(n, v, u, tmp);
    }
    double vBv = 0, vv = 0;
    for (long i = 0; i < n; i++) { vBv += u[i] * v[i]; vv += v[i] * v[i]; }
    printf("%ld\n", (long)(sqrt(vBv / vv) * 1000000000.0));
    free(u); free(v); free(tmp);
    return 0;
}
