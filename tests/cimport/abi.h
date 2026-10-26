// Struct shapes that the x86-64 and AAPCS64 calling conventions treat differently
typedef struct { unsigned char r, g, b, a; } C4;   // 4 bytes: one integer register
typedef struct { int x, y, z; } P3;                // 12 bytes: two integer registers
typedef struct { float a, b, c, d; } F4;           // HFA: four float registers (AAPCS64)
typedef struct { double a, b; } D2;                // HFA: two double registers
typedef struct { double a; float b; } Mix;         // 16 bytes, mixed
typedef struct { int a; double b; double c; } Big; // 24 bytes: memory / by reference

C4 c4_swap(C4 v);
P3 p3_shift(P3 v, int d);
F4 f4_scale(F4 v, float k);
D2 d2_swap(D2 v);
Mix mix_add(Mix v, double d);
Big big_sum(Big v, Big w);
double many(F4 a, D2 b, Mix c, Big d, P3 e, C4 f);
// out of argument registers (x86-64: 6 integer, 8 SSE): a struct that doesn't fit whole in
// the ones left goes on the stack whole, and later scalars still take the registers left
double d2_six(D2 a, D2 b, D2 c, D2 d, D2 e, D2 f);
long p3_after(long a, long b, long c, long d, long e, P3 p, long f);
Big big_after(long a, long b, long c, long d, P3 p, long e);

// unions (0004), passed as a struct of their size and class is
typedef union { int i; float f; } IntOrFloat;               // 4 bytes, an integer or a float
typedef union { float one; float two[2]; } Floats;          // floats only: an HFA of two (Arm)
typedef union { double d; unsigned char bytes[12]; } Wide;  // 16 bytes, 8-aligned, mixed
typedef union big3 { long long words[3]; double d; } Big3;  // 24 bytes: memory / by reference
typedef struct { int kind; IntOrFloat value; } Tagged;      // a union in a struct
typedef struct { int kind; union { int code; float ratio; } body; } Msg; // one without a name

IntOrFloat iof_next(IntOrFloat v);
Floats floats_swap(Floats v);
Wide wide_flip(Wide w);
long long big3_sum(Big3 b);
Tagged tagged_bump(Tagged t);
Msg msg_reply(Msg m);
