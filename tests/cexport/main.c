// Calls the Z# library built from lib.zs through its generated header.
#include <stdio.h>
#include <stdlib.h>
#include "lib.h"

// a host's panic hook: it can log and end the process its own way
static void on_panic(const char *message) {
    printf("hook: %s\n", message);
    exit(3);
}

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
    printf("ratio %lld\n", (long long)geo_ratio(r));
    printf("union %d\n", geo_next((Num){.Float = 1.0f}).Int);
    zs_set_panic_hook(on_panic);
    geo_ratio((Box){{1, 0}, {1, 2}, 0}); // zero width: division by zero
    printf("not reached\n");
    return 0;
}
