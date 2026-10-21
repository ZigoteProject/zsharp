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
