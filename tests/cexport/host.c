// A C shared library that links the Z# library's --lib archive whole (test.sh): the Z# functions
// are part of this library, and its own functions call them.
#include "lib.h"

double host_area_twice(Box r) { return 2 * geo_area(r); }
