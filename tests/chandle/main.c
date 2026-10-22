// Holds Z# objects as handles: builds a tree through the library, keeps a closure, and gives
// every handle up with zs_release (valgrind and ZS_LEAKCHECK check that everything is freed).
#include <stdio.h>
#include "lib.h"

int main(void) {
    zs_handle t = tree_empty();
    for (int64_t i = 0; i < 10; i++) {
        zs_handle bigger = tree_insert(t, (i * 7) % 10);
        zs_release(t);
        t = bigger;
    }
    printf("count %lld sum %lld\n", (long long)tree_count(t), (long long)tree_sum(t));

    zs_handle f = tree_adder(t);
    zs_retain(t); // a second reference, given up below
    zs_release(t);
    zs_release(t); // the tree lives on in the closure
    printf("apply %lld\n", (long long)tree_apply(f, 100));
    zs_release(f);
    printf("done\n");
    return 0;
}
