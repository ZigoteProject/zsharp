// Structs with array fields (C's T[N], Z#'s fixed<T, N>) by value, in each calling convention
#include <stdint.h>

typedef struct { uint8_t data[16]; int32_t len; } Packet;           // 20 bytes: in memory
typedef struct { int kind; int xdata; const void *data[3]; } Cursor; // libclang's CXCursor: 32 bytes
typedef struct { float m[2][2]; } Mat2;                              // nested arrays; four floats
typedef struct { uint8_t rgb[3]; uint8_t a; } Pixel;                 // 4 bytes: one register

Packet packet_fill(uint8_t v, int32_t len);
int32_t packet_sum(Packet p);
Cursor cursor_make(int kind);
int cursor_kind(Cursor c); // by value, as clang_getCursorKind takes it
int cursor_check(Cursor c);
Mat2 mat2_transpose(Mat2 m);
Pixel pixel_invert(Pixel p);
int32_t sum4(const int32_t xs[4]); // an array parameter: a pointer to the first element
