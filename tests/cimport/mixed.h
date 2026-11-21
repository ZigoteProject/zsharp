// Struct shapes RISC-V's hard-float convention (LP64D) passes its own way: a struct that is, laid
// flat, one float, two, or a float and an integer goes field by field in float and integer
// registers while they last; and integers narrower than a register, widened in theirs
typedef struct { float f; } F1;                   // one float register
typedef struct { float f; int i; } FI;            // a float register and an integer one
typedef struct { int i; double d; } ID;           // the same, the integer first
typedef struct { signed char c; float f; } CF;    // a narrow integer and a float
typedef struct { float v[2]; } FA;                // an array's elements are fields: two floats
typedef struct { F1 inner; int i; } Nest;         // a struct in a struct, laid flat
typedef struct { int a, b; } II;                  // two integers: one integer register
typedef struct { float f; int i, j; } FII;        // three fields: two integer registers
typedef struct { double d; const int *p; } DP;    // a pointer isn't an integer here: two integer registers

F1 f1_double(F1 v);
FI fi_swap(FI v);
ID id_add(ID v, int n);
CF cf_next(CF v);
FA fa_swap(FA v);
Nest nest_bump(Nest v);
II ii_swap(II v);
FII fii_turn(FII v);
DP dp_make(double d);
int dp_read(DP v, int n);
// out of float registers (eight): a struct's floats go as integers, or on the stack
double fi_after_floats(double a, double b, double c, double d, double e, double f, double g, double h, FI v, F1 w);
// out of integer registers (eight): the struct's integer has none, so all of it goes on the stack
double fi_after_ints(long a, long b, long c, long d, long e, long f, long g, long h, FI v, ID w, double x);
// integers narrower than a register: C reads the whole register
long narrow_sum(signed char a, unsigned char b, short c, unsigned short d, int e, unsigned f);
int int_negate(int v);
unsigned unsigned_half(unsigned v);
short short_negate(short v);
