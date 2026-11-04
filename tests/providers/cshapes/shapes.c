#include "shapes.h"
double rect_area(Point a, Point b) {
  double w = b.x - a.x, h = b.y - a.y;
  return (w < 0 ? -w : w) * (h < 0 ? -h : h);
}
int32_t manhattan(int32_t x, int32_t y) { return (x < 0 ? -x : x) + (y < 0 ? -y : y); }
