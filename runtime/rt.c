// Z# runtime: allocation, panics, strings. Linked into every Z# program.
#include <execinfo.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Every heap object starts with an int64 reference count: 1+ = live, 0 = static (never freed).
typedef struct {
    int64_t rc;
    int64_t len;
    char data[]; // len bytes + NUL
} zs_str;

static int64_t live; // objects currently allocated, reported at exit when ZS_LEAKCHECK is set

_Noreturn void zs_panic_c(const char *msg) {
    fflush(stdout);
    fprintf(stderr, "panic: %s\n", msg);
    const char *bt = getenv("ZS_BACKTRACE");
    if (bt && strcmp(bt, "0") == 0) abort();
    void *frames[64];
    int n = backtrace(frames, 64);
    backtrace_symbols_fd(frames + 1, n - 1, 2);
    abort();
}

_Noreturn void zs_panic(zs_str *msg) { zs_panic_c(msg->data); }

void *zs_alloc(int64_t size) {
    void *p = malloc((size_t)size);
    if (!p) zs_panic_c("out of memory");
    live++;
    return p;
}

void zs_free(void *p) {
    live--;
    free(p);
}

static void leak_report(void) {
    if (getenv("ZS_LEAKCHECK") && live != 0)
        fprintf(stderr, "leak check: %" PRId64 " object(s) still allocated\n", live);
}

__attribute__((constructor)) static void zs_init(void) { atexit(leak_report); }

static zs_str *str_new(int64_t len) {
    zs_str *s = zs_alloc((int64_t)sizeof(zs_str) + len + 1);
    s->rc = 1;
    s->len = len;
    s->data[len] = 0;
    return s;
}

static zs_str *str_of(const char *buf, int64_t len) {
    zs_str *s = str_new(len);
    memcpy(s->data, buf, (size_t)len);
    return s;
}

// String operations borrow their arguments; the caller drops them.
zs_str *zs_str_concat(zs_str *a, zs_str *b) {
    zs_str *s = str_new(a->len + b->len);
    memcpy(s->data, a->data, (size_t)a->len);
    memcpy(s->data + a->len, b->data, (size_t)b->len);
    return s;
}

// -1, 0 or 1
int64_t zs_str_cmp(zs_str *a, zs_str *b) {
    int64_t n = a->len < b->len ? a->len : b->len;
    int c = memcmp(a->data, b->data, (size_t)n);
    if (c != 0) return c < 0 ? -1 : 1;
    return a->len < b->len ? -1 : a->len > b->len;
}

// FNV-1a
int64_t zs_str_hash(zs_str *s) {
    uint64_t h = 14695981039346656037ull;
    for (int64_t i = 0; i < s->len; i++) h = (h ^ (uint8_t)s->data[i]) * 1099511628211ull;
    return (int64_t)h;
}

zs_str *zs_str_of_i64(int64_t v) {
    char buf[32];
    return str_of(buf, snprintf(buf, sizeof buf, "%" PRId64, v));
}

zs_str *zs_str_of_u64(uint64_t v) {
    char buf[32];
    return str_of(buf, snprintf(buf, sizeof buf, "%" PRIu64, v));
}

// Shortest representation that reads back as the same double; whole numbers print like ints.
zs_str *zs_str_of_f64(double v) {
    char buf[40];
    int n = 0;
    for (int prec = 15; prec <= 17; prec++) {
        n = snprintf(buf, sizeof buf, "%.*g", prec, v);
        if (strtod(buf, NULL) == v) break;
    }
    return str_of(buf, n);
}

zs_str *zs_str_of_bool(bool v) { return v ? str_of("true", 4) : str_of("false", 5); }

void zs_print(zs_str *s) { fwrite(s->data, 1, (size_t)s->len, stdout); }

void zs_println(zs_str *s) {
    fwrite(s->data, 1, (size_t)s->len, stdout);
    fputc('\n', stdout);
}
