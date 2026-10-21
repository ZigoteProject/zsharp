// Calls the Z# library built from lib.zs through its generated header.
#include <stdio.h>
#include "lib.h"

void each(int64_t n, void (*cb)(void *, int64_t), void *user) {
    for (int64_t i = 1; i <= n; i++) cb(user, i);
}

int main(void) {
    Vec2 c = geo_add((Vec2){1, 2}, (Vec2){3, 4});
    printf("add %g %g\n", c.x, c.y);
    Box r = {{0, 0}, {2, 3}, 7};
    printf("area %g\n", geo_area(r));
    Box g = geo_grow(r, 1.0);
    printf("grow %g %g %d\n", g.hi.x, g.hi.y, g.id);
    Pair p = geo_swap((Pair){1, 2});
    printf("swap %d %d\n", p.a, p.b);
    printf("sum of squares %lld\n", (long long)geo_sum_squares(4));
    printf("label %lld\n", (long long)geo_label_length("hello"));
    printf("square %d %d\n", geo_is_square(r), geo_is_square((Box){{0, 0}, {2, 2}, 0}));
    return 0;
}
