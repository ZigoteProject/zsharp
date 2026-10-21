// C side of the MCU benchmarks: the same runtime as Z# (rt-embedded.c), for printing and ticks.
#include <stdint.h>
typedef struct zs_str zs_str;
zs_str *zs_str_of_i64(int64_t v);
zs_str *zs_str_from_c(const char *c);
void zs_print(zs_str *s);
void zs_println(zs_str *s);
int64_t zs_ticks(void);
static void report(const char *name, int64_t result, int64_t ticks) {
    zs_print(zs_str_from_c(name));
    zs_print(zs_str_from_c(" result="));
    zs_print(zs_str_of_i64(result));
    zs_print(zs_str_from_c(" ticks="));
    zs_println(zs_str_of_i64(ticks));
}
