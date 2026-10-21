// A C library for the import c test: structs by value, enums, #defines, pointers.
#include <stdbool.h>
#include <stdint.h>

#define SHAPES_VERSION 3
#define SHAPES_SCALE 2.5f
#define SHAPES_NAME "shapes"
#define SHAPES_MASK 0xFF
#define ORIGIN (Point){ 0, 0 }
#define WHITE (Color){ 255, 255, 255, 255 }

typedef struct Point { int x; int y; } Point;
typedef struct { float w; float h; } Size;
typedef struct Color { unsigned char r, g, b, a; } Color;
typedef struct Rect { Point corner; Size size; double angle; } Rect; // 32 bytes: in memory

typedef enum { SHAPE_CIRCLE, SHAPE_SQUARE = 5, SHAPE_TRIANGLE } ShapeKind;

typedef struct Canvas Canvas; // opaque

Point point_add(Point a, Point b);
float size_area(Size s);
Rect rect_move(Rect r, int dx, int dy);
unsigned int color_pack(Color c);
const char *shape_name(ShapeKind k);
bool is_square(ShapeKind k);
int64_t sum_to(int32_t n);

Canvas *canvas_new(int w, int h);
int canvas_paint(Canvas *c, Point p);
void canvas_free(Canvas *c);

// left out, with reasons
int sum_array(int xs[4]);
void apply(int (*f)(int), int x);
static inline int twice(int x) { return 2 * x; }
typedef union { int i; float f; } Number;
Number number_of(int i);
