// A small header for `module Shapes = import c "shapes.h"` (0001): a struct, an enum-like
// constant set, a function and a macro, each with a comment that becomes the module's doc
#include <stdint.h>

/* A point in the plane. */
typedef struct { double x; double y; } Point;

/** The number of corners a shape may have at most. */
#define MAX_CORNERS 8

/** The unit square's area. */
#define UNIT_AREA 1.0

/* The area of the rectangle with corners a and b. */
double rect_area(Point a, Point b);

/* The distance from the origin, as an integer. */
int32_t manhattan(int32_t x, int32_t y);
