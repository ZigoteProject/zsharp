#include <stdio.h>
#include "ops.h"

static double area(double w, double h) { return w * h; }
static int twice(int x) { return 2 * x; }
static void hello(void) { printf("hello from C\n"); fflush(stdout); }
static const char *name(void) { return "rectangle"; }

ShapeOps shape_ops(void) { return (ShapeOps){area, twice, hello, name}; }

void fill_squares(int *out, int n) {
    for (int i = 0; i < n; i++) out[i] = i * i;
}

int sum_ints(const int *xs, int n) {
    int s = 0;
    for (int i = 0; i < n; i++) s += xs[i];
    return s;
}
