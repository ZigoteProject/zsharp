#include "shapes.h"
#include <stdlib.h>

struct Canvas { int w, h, painted; };

Point point_add(Point a, Point b) { return (Point){ a.x + b.x, a.y + b.y }; }
float size_area(Size s) { return s.w * s.h; }
Rect rect_move(Rect r, int dx, int dy) { r.corner.x += dx; r.corner.y += dy; return r; }
unsigned int color_pack(Color c) { return (unsigned)c.r << 24 | (unsigned)c.g << 16 | (unsigned)c.b << 8 | c.a; }
const char *shape_name(ShapeKind k) { return k == SHAPE_CIRCLE ? "circle" : k == SHAPE_SQUARE ? "square" : "triangle"; }
bool is_square(ShapeKind k) { return k == SHAPE_SQUARE; }
int64_t sum_to(int32_t n) { int64_t s = 0; for (int i = 1; i <= n; i++) s += i; return s; }
Canvas *canvas_new(int w, int h) { Canvas *c = malloc(sizeof *c); c->w = w; c->h = h; c->painted = 0; return c; }
int canvas_paint(Canvas *c, Point p) { if (p.x >= 0 && p.x < c->w && p.y >= 0 && p.y < c->h) c->painted++; return c->painted; }
void canvas_free(Canvas *c) { free(c); }
int sum_array(int xs[4]) { return xs[0] + xs[1] + xs[2] + xs[3]; }
void apply(int (*f)(int), int x) { f(x); }
Flags flags_of(int i) { Flags f = {0}; f.kind = i; return f; }
