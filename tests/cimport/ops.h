// A C library's table of function pointers, called from Z# (tests/cimport/ops.zs), and
// functions that take pointers to C memory
typedef double (*area_fn)(double w, double h);

typedef struct {
    area_fn area;
    int (*twice)(int x);
    void (*hello)(void);
    const char *(*name)(void);
} ShapeOps;

ShapeOps shape_ops(void);

// writes the squares of 0 .. n-1 to out
void fill_squares(int *out, int n);

int sum_ints(const int *xs, int n);
