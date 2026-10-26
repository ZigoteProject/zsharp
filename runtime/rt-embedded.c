// Z# runtime for bare-metal ARM Cortex-M (zs build --target cortex-m4 | cortex-m0plus) and
// freestanding WebAssembly (--target wasm32): no OS and no libc. The heap is a static array with
// size-class free lists. On a Cortex-M, output and the exit code go to the debugger or emulator
// through semihosting, and the vector table and reset handler are here too; on WebAssembly they
// are the host's imports. What needs an OS (files, processes, environment) isn't provided, so a
// program that uses it fails to link, naming the function.
//
// ZS_LIB (zs build --lib for a chip): a library a C firmware links. The firmware has the vector
// table, the reset handler, SysTick and maybe a C library, so none of those is here and the C
// library's functions are weak; output, stopping and Runtime.ticks go through zs_write, zs_stop
// and zs_ticks, weak defaults a firmware defines its own of (output is dropped, a stop traps into
// the firmware's HardFault handler, ticks are the DWT cycle counter where the core has one).
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifndef ZS_HEAP_SIZE
#define ZS_HEAP_SIZE (64 * 1024)
#endif

// zs_int: Z#'s int, the machine word (also the header fields of every heap object)
typedef intptr_t zs_int;

typedef struct {
    zs_int rc;
    zs_int len;
    char data[]; // len bytes + NUL
} zs_str;

// ---- C library pieces the compiler may call

__attribute__((weak)) void *memcpy(void *d, const void *s, size_t n) {
    uint8_t *dp = d;
    const uint8_t *sp = s;
    while (n--) *dp++ = *sp++;
    return d;
}

__attribute__((weak)) void *memmove(void *d, const void *s, size_t n) {
    uint8_t *dp = d;
    const uint8_t *sp = s;
    if (dp < sp)
        while (n--) *dp++ = *sp++;
    else
        while (n--) dp[n] = sp[n];
    return d;
}

__attribute__((weak)) void *memset(void *d, int c, size_t n) {
    uint8_t *dp = d;
    while (n--) *dp++ = (uint8_t)c;
    return d;
}

__attribute__((weak)) int memcmp(const void *a, const void *b, size_t n) {
    const uint8_t *x = a, *y = b;
    for (; n; n--, x++, y++)
        if (*x != *y) return *x < *y ? -1 : 1;
    return 0;
}

__attribute__((weak)) size_t strlen(const char *s) {
    size_t n = 0;
    while (s[n]) n++;
    return n;
}

#if defined(__wasm__)
// ---- the host: output, exit and Runtime.ticks () are the imports zs.write (bytes, length),
// zs.exit (code) and zs.ticks (); a program imports only those it uses

__attribute__((import_module("zs"), import_name("write"))) void host_write(const char *p, zs_int n);
__attribute__((import_module("zs"), import_name("exit"))) void host_exit(int32_t code);
__attribute__((import_module("zs"), import_name("ticks"))) int64_t host_ticks(void);

static void write_bytes(const char *p, int64_t n) { host_write(p, (zs_int)n); }

_Noreturn static void stop(int code) {
    host_exit(code);
    __builtin_trap(); // a host whose exit returns
}
#elif defined(ZS_LIB)
// ---- a library in a C firmware: output, stopping and ticks are the firmware's

__attribute__((weak)) void zs_write(const char *p, size_t n) {
    (void)p;
    (void)n;
}

__attribute__((weak, noreturn)) void zs_stop(int code) {
    (void)code;
    __builtin_trap();
}

static void write_bytes(const char *p, int64_t n) { zs_write(p, (size_t)n); }

_Noreturn static void stop(int code) {
    zs_stop(code);
    __builtin_trap(); // a firmware's stop that returns
}
#else
// ---- semihosting (ARM's debug channel; QEMU: -semihosting-config enable=on)

static int semihost(int op, void *arg) {
    register int r0 __asm__("r0") = op;
    register void *r1 __asm__("r1") = arg;
    __asm__ volatile("bkpt 0xab" : "+r"(r0) : "r"(r1) : "memory");
    return r0;
}

static void write_bytes(const char *p, int64_t n) {
    char buf[65];
    while (n > 0) {
        int k = n > 64 ? 64 : (int)n;
        for (int i = 0; i < k; i++) buf[i] = p[i] ? p[i] : ' ';
        buf[k] = 0;
        semihost(0x04, buf); // SYS_WRITE0
        p += k;
        n -= k;
    }
}

static void report(void);

_Noreturn static void stop(int code) {
    report();
    uint32_t block[2] = {0x20026, (uint32_t)code}; // ADP_Stopped_ApplicationExit, exit code
    semihost(0x20, block);                          // SYS_EXIT_EXTENDED
    for (;;) {}
}
#endif

static void write_c(const char *s) { write_bytes(s, (int64_t)strlen(s)); }

// ---- heap: 8-byte header holding the block size; free lists per 8-byte class up to 256 bytes

static uint8_t heap[ZS_HEAP_SIZE] __attribute__((aligned(8)));

// the allocator's state in one place (one base address), with word-sized counters; blocks over
// 256 bytes freed are on one list, reused first fit
static struct {
    size_t top, used, peak;
    zs_int live, allocations;
    void *free_lists[33];
    void *large;
} H;

_Noreturn void zs_panic_c(const char *msg);

void *zs_alloc(zs_int size) {
    size_t need = ((size_t)size + 7) & ~(size_t)7;
    size_t cls = need / 8;
    uint64_t *block = 0;

    if (cls <= 32 && H.free_lists[cls]) {
        block = (uint64_t *)H.free_lists[cls] - 1;
        H.free_lists[cls] = *(void **)H.free_lists[cls];
    } else {
        // ponytail: first fit, a block taken whole and never split or merged; a size-ordered
        // tree if fragmentation shows
        if (cls > 32)
            for (void **at = &H.large; *at; at = (void **)*at)
                if (((uint64_t *)*at)[-1] >= need) {
                    block = (uint64_t *)*at - 1;
                    *at = *(void **)*at;
                    break;
                }
        if (!block) {
            if (H.top + need + 8 > ZS_HEAP_SIZE) zs_panic_c("out of memory");
            block = (uint64_t *)(heap + H.top);
            H.top += need + 8;
            *block = need;
        }
    }

    H.used += (size_t)*block;
    if (H.used > H.peak) H.peak = H.used;
    H.live++;
    H.allocations++;
    return block + 1;
}

void zs_free(void *p) {
    uint64_t *block = (uint64_t *)p - 1;
    size_t cls = (size_t)*block / 8;
    H.used -= (size_t)*block;
    H.live--;

    void **list = cls <= 32 ? &H.free_lists[cls] : &H.large;
    *(void **)p = *list;
    *list = p;
}

zs_int zs_allocations(void) { return H.allocations; }

// Runtime.mallocs (): the times memory was taken for an object (no system allocator here: the
// heap's own), and Runtime.marks (): objects marked shared, none with no threads
zs_int zs_mallocs(void) { return H.allocations; }
zs_int zs_marks(void) { return 0; }

// ---- C's allocator, over the same heap: weak, so C, Rust or Zig code in a program or library
// without a C library allocates where Z# does (a firmware with its own C library keeps its own).
// Running out panics, as it does for Z#.

__attribute__((weak)) void *malloc(size_t n) { return zs_alloc((zs_int)(n ? n : 1)); }

__attribute__((weak)) void free(void *p) {
    if (p) zs_free(p);
}

__attribute__((weak)) void *calloc(size_t n, size_t size) {
    if (size && n > (size_t)-1 / size) zs_panic_c("calloc: too large");
    uint8_t *p = malloc(n * size);
    for (size_t i = 0; i < n * size; i++) p[i] = 0;
    return p;
}

__attribute__((weak)) void *realloc(void *p, size_t n) {
    if (!p) return malloc(n);
    size_t have = (size_t)((uint64_t *)p)[-1];
    if (n <= have) return p;
    uint8_t *q = malloc(n), *from = p;
    for (size_t i = 0; i < have; i++) q[i] = from[i];
    free(p);
    return q;
}

__attribute__((weak, noreturn)) void abort(void) { zs_panic_c("abort"); }

// Ptr.alloc / Ptr.free: C memory for n elements of a size, zeroed
void *zs_ptr_alloc(zs_int n, zs_int size) {
    if (n < 0) zs_panic_c("Ptr.alloc: negative count");
    return calloc((size_t)(n ? n : 1), (size_t)size);
}

void zs_ptr_free(void *p) { free(p); }

// ---- strings

static zs_str *str_new(zs_int len) {
    zs_str *s = zs_alloc((int64_t)sizeof(zs_str) + len + 1);
    s->rc = 1;
    s->len = len;
    s->data[len] = 0;
    return s;
}

static zs_str *str_of(const char *buf, zs_int len) {
    zs_str *s = str_new(len);
    memcpy(s->data, buf, (size_t)len);
    return s;
}

zs_str *zs_str_concat(zs_str *a, zs_str *b) {
    zs_str *s = str_new(a->len + b->len);
    memcpy(s->data, a->data, (size_t)a->len);
    memcpy(s->data + a->len, b->data, (size_t)b->len);
    return s;
}

zs_int zs_str_cmp(zs_str *a, zs_str *b) {
    zs_int n = a->len < b->len ? a->len : b->len;
    int c = memcmp(a->data, b->data, (size_t)n);
    if (c != 0) return c < 0 ? -1 : 1;
    return a->len < b->len ? -1 : a->len > b->len;
}

zs_int zs_str_hash(zs_str *s) {
    uint64_t h = 14695981039346656037ull;
    for (int64_t i = 0; i < s->len; i++) h = (h ^ (uint8_t)s->data[i]) * 1099511628211ull;
    return sizeof(zs_int) < 8 ? (zs_int)(h ^ (h >> 32)) : (zs_int)h; // fold on a 32-bit chip
}

static int u64_text(uint64_t v, char *out) {
    char tmp[24];
    int n = 0;
    do {
        tmp[n++] = (char)('0' + v % 10);
        v /= 10;
    } while (v);
    for (int i = 0; i < n; i++) out[i] = tmp[n - 1 - i];
    return n;
}

static int int_text(zs_int v, char *out) {
    if (v >= 0) return u64_text((uint64_t)v, out);
    out[0] = '-';
    return 1 + u64_text((uint64_t)0 - (uint64_t)v, out + 1);
}

// ---- slices and spans

static int text_of(const char *t, char *out) {
    int k = 0;
    while (t[k]) {
        out[k] = t[k];
        k++;
    }
    return k;
}

// a slice i..j (inclusive) of something of length n that doesn't fit in it
_Noreturn void zs_slice_fail(zs_int i, zs_int j, zs_int n, zs_int kind) {
    static const char *what[] = { "an array", "a Buffer", "a span", "a string" };
    char msg[128];
    int k = text_of("slice ", msg);
    k += int_text(i, msg + k);
    k += text_of("..", msg + k);
    k += int_text(j, msg + k);
    k += text_of(" of ", msg + k);
    k += text_of(what[kind & 3], msg + k);
    k += text_of(" of length ", msg + k);
    k += int_text(n, msg + k);
    msg[k] = 0;
    zs_panic_c(msg);
}

// Fixed.ofArray of an array that hasn't the type's length
_Noreturn void zs_fixed_fail(const char *type, zs_int len) {
    char msg[160];
    int k = text_of(type, msg);
    k += text_of(" from an array of length ", msg + k);
    k += int_text(len, msg + k);
    msg[k] = 0;
    zs_panic_c(msg);
}

static bool inside_char(zs_str *s, zs_int at) { return at > 0 && at < s->len && ((uint8_t)s->data[at] & 0xC0) == 0x80; }

// s.[i..j]: a copy of bytes i to j, which mustn't cut a character
zs_str *zs_str_slice(zs_str *s, zs_int i, zs_int j) {
    if (i < 0 || j >= s->len || i > j + 1) zs_slice_fail(i, j, s->len, 3);
    zs_int at = inside_char(s, i) ? i : inside_char(s, j + 1) ? j + 1 : -1;
    if (at >= 0) {
        char msg[64];
        int k = text_of("byte ", msg);
        k += int_text(at, msg + k);
        k += text_of(" is inside a character", msg + k);
        msg[k] = 0;
        zs_panic_c(msg);
    }
    return str_of(s->data + i, j - i + 1);
}

// the length of the UTF-8 sequence at p (n bytes left) as String.decodeAt reads it, or 0 when
// it's malformed
static zs_int utf8_seq(const uint8_t *p, zs_int n) {
    zs_int k = p[0] < 0x80 ? 1 : (p[0] & 0xE0) == 0xC0 ? 2 : (p[0] & 0xF0) == 0xE0 ? 3 : (p[0] & 0xF8) == 0xF0 ? 4 : 0;
    if (k == 0 || k > n) return 0;
    for (zs_int i = 1; i < k; i++)
        if ((p[i] & 0xC0) != 0x80) return 0;
    return k;
}

// String.ofBytes: a copy of the bytes, each malformed one replaced by U+FFFD (decision 28)
zs_str *zs_str_of_bytes(const uint8_t *p, zs_int n) {
    zs_int len = 0;
    for (zs_int i = 0; i < n;) {
        zs_int k = utf8_seq(p + i, n - i);
        len += k ? k : 3;
        i += k ? k : 1;
    }
    zs_str *s = str_new(len);
    char *out = s->data;
    for (zs_int i = 0; i < n;) {
        zs_int k = utf8_seq(p + i, n - i);
        memcpy(out, k ? (const char *)p + i : "\xEF\xBF\xBD", (size_t)(k ? k : 3));
        out += k ? k : 3;
        i += k ? k : 1;
    }
    return s;
}

zs_str *zs_str_of_u64(uint64_t v) {
    char buf[24];
    return str_of(buf, u64_text(v, buf));
}

zs_str *zs_str_of_i64(int64_t v) {
    char buf[24];
    int n = 0;
    if (v < 0) buf[n++] = '-';
    n += u64_text(v < 0 ? (uint64_t)(-(v + 1)) + 1 : (uint64_t)v, buf + n);
    return str_of(buf, n);
}

// ponytail: integers exactly, others with 6 significant digits (no shortest round-trip, which
// needs a much bigger algorithm); enough for output on a device
zs_str *zs_str_of_f64(double v) {
    char buf[40];
    int n = 0;
    if (v != v) return str_of("nan", 3);
    if (v < 0) {
        buf[n++] = '-';
        v = -v;
    }
    if (v > 1e15) return str_of(n ? "-inf" : "inf", n ? 4 : 3); // ponytail: no exponent form
    uint64_t whole = (uint64_t)v;
    double frac = v - (double)whole;
    n += u64_text(whole, buf + n);
    if (frac > 0) {
        int digits = 6 - (whole ? (int)(n - (buf[0] == '-')) : 0);
        if (digits < 1) digits = 1;
        uint64_t scale = 1;
        for (int i = 0; i < digits; i++) scale *= 10;
        uint64_t f = (uint64_t)(frac * (double)scale + 0.5);
        if (f >= scale) f = scale - 1;
        int k = digits;
        while (k > 0 && f % 10 == 0) {
            f /= 10;
            k--;
        }
        if (k > 0) {
            buf[n++] = '.';
            char tmp[24];
            int m = u64_text(f, tmp);
            for (int i = m; i < k; i++) buf[n++] = '0';
            for (int i = 0; i < m; i++) buf[n++] = tmp[i];
        }
    }
    return str_of(buf, n);
}

zs_str *zs_str_of_f32(float v) { return zs_str_of_f64((double)v); }

// ---- format specifiers (0024): integers as the host's; floats by zs_str_of_f64's rules

static void spec_of(zs_str *spec, char *letter, int *digits) {
    *letter = spec->len > 0 ? spec->data[0] : 'G';
    *digits = -1;
    if (spec->len > 1) {
        *digits = 0;
        for (zs_int i = 1; i < spec->len && i < 3; i++) *digits = *digits * 10 + (spec->data[i] - '0');
    }
}

// the integer part of a decimal text with a comma every three digits
static int group_digits(const char *in, int n, char *out) {
    int k = 0, start = in[0] == '-' ? 1 : 0, whole = start;
    while (whole < n && in[whole] != '.') whole++;
    if (start) out[k++] = '-';
    for (int i = start; i < whole; i++) {
        if (i > start && (whole - i) % 3 == 0) out[k++] = ',';
        out[k++] = in[i];
    }
    for (int i = whole; i < n; i++) out[k++] = in[i];
    return k;
}

zs_str *zs_format_int(int64_t v, int64_t bits, bool isUnsigned, zs_str *spec) {
    char buf[120], grouped[160];
    char letter;
    int d, n = 0;
    spec_of(spec, &letter, &d);
    uint64_t mask = bits >= 64 ? ~(uint64_t)0 : ((uint64_t)1 << bits) - 1;
    uint64_t u = (uint64_t)v & mask;
    if (letter == 'X' || letter == 'x' || letter == 'B' || letter == 'b') {
        int base = letter == 'B' || letter == 'b' ? 2 : 16;
        const char *digits = letter == 'x' ? "0123456789abcdef" : "0123456789ABCDEF";
        char tmp[65];
        int k = 0;
        do { tmp[k++] = digits[u % (uint64_t)base]; u /= (uint64_t)base; } while (u);
        for (int i = k; i < d; i++) buf[n++] = '0';
        while (k) buf[n++] = tmp[--k];
        return str_of(buf, n);
    }
    bool neg = !isUnsigned && v < 0;
    uint64_t mag = isUnsigned ? u : neg ? (uint64_t)(-(v + 1)) + 1 : (uint64_t)v;
    if (neg) buf[n++] = '-';
    char tmp[24];
    int k = u64_text(mag, tmp);
    if (letter != 'F' && letter != 'N') for (int i = k; i < d; i++) buf[n++] = '0';
    for (int i = 0; i < k; i++) buf[n++] = tmp[i];
    if (letter == 'F' || letter == 'N') {
        int decimals = d < 0 ? 2 : d;
        if (decimals > 0) buf[n++] = '.';
        for (int i = 0; i < decimals; i++) buf[n++] = '0';
        if (letter == 'N') return str_of(grouped, group_digits(buf, n, grouped));
    }
    return str_of(buf, n);
}

// ponytail: F and N round half away from zero in double arithmetic, E and G give
// zs_str_of_f64's text; a device's output is checked by eye, not against .NET
zs_str *zs_format_float(double x, zs_str *spec) {
    char letter;
    int d;
    spec_of(spec, &letter, &d);
    if ((letter != 'F' && letter != 'N') || x != x || x > 1e15 || x < -1e15) return zs_str_of_f64(x);
    char buf[80], grouped[120];
    int n = 0, decimals = d < 0 ? 2 : d > 15 ? 15 : d;
    bool neg = x < 0;
    if (neg) x = -x;
    double scale = 1;
    for (int i = 0; i < decimals; i++) scale *= 10;
    uint64_t all = (uint64_t)(x * scale + 0.5);
    uint64_t whole = all / (uint64_t)scale, frac = all % (uint64_t)scale;
    if (neg && all) buf[n++] = '-';
    n += u64_text(whole, buf + n);
    if (decimals > 0) {
        buf[n++] = '.';
        char tmp[24];
        int k = u64_text(frac, tmp);
        for (int i = k; i < decimals; i++) buf[n++] = '0';
        for (int i = 0; i < k; i++) buf[n++] = tmp[i];
    }
    return letter == 'N' ? str_of(grouped, group_digits(buf, n, grouped)) : str_of(buf, n);
}

// ---- Int.parse and Float.parse (0024), as the host's

bool zs_parse_int(zs_str *s, int64_t radix, bool isUnsigned, int64_t bits, int64_t *out) {
    zs_int i = 0, n = s->len;
    bool neg = false;
    if (n > 0 && (s->data[0] == '-' || s->data[0] == '+')) { neg = s->data[0] == '-'; i = 1; }
    if (i == n || radix < 2 || radix > 36) return false;
    uint64_t acc = 0;
    for (; i < n; i++) {
        char c = s->data[i];
        int d = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'z' ? c - 'a' + 10 : c >= 'A' && c <= 'Z' ? c - 'A' + 10 : 99;
        if (d >= radix) return false;
        if (acc > (UINT64_MAX - (uint64_t)d) / (uint64_t)radix) return false;
        acc = acc * (uint64_t)radix + (uint64_t)d;
    }
    if (isUnsigned) {
        uint64_t max = bits >= 64 ? UINT64_MAX : ((uint64_t)1 << bits) - 1;
        if ((neg && acc != 0) || acc > max) return false;
        *out = (int64_t)acc;
    } else {
        uint64_t limit = (uint64_t)1 << (bits - 1);
        if (acc > (neg ? limit : limit - 1)) return false;
        *out = neg ? (int64_t)(0 - acc) : (int64_t)acc;
    }
    return true;
}

// ponytail: digits, a fraction and an exponent in double arithmetic, so the last digit can be
// off by one rounding (the host's strtod is exact); enough to read a setting on a device
bool zs_parse_float(zs_str *s, double *out) {
    zs_int i = 0, n = s->len;
    bool neg = false;
    if (n > 0 && (s->data[0] == '-' || s->data[0] == '+')) { neg = s->data[0] == '-'; i = 1; }
    double v = 0;
    int digits = 0;
    for (; i < n && s->data[i] >= '0' && s->data[i] <= '9'; i++, digits++) v = v * 10 + (s->data[i] - '0');
    if (i < n && s->data[i] == '.') {
        double scale = 0.1;
        for (i++; i < n && s->data[i] >= '0' && s->data[i] <= '9'; i++, digits++, scale /= 10) v += (s->data[i] - '0') * scale;
    }
    if (digits == 0) return false;
    if (i < n && (s->data[i] == 'e' || s->data[i] == 'E')) {
        i++;
        bool eneg = false;
        if (i < n && (s->data[i] == '-' || s->data[i] == '+')) { eneg = s->data[i] == '-'; i++; }
        int e = 0, ed = 0;
        for (; i < n && s->data[i] >= '0' && s->data[i] <= '9'; i++, ed++) e = e * 10 + (s->data[i] - '0');
        if (ed == 0) return false;
        for (int k = 0; k < e && k < 400; k++) v = eneg ? v / 10 : v * 10;
    }
    if (i != n) return false;
    *out = neg ? -v : v;
    return true;
}

// String.isFloat and String.toFloat, over the same reading
bool zs_str_is_float(zs_str *s) {
    double x;
    return zs_parse_float(s, &x);
}

double zs_str_to_float(zs_str *s) {
    double x = 0;
    zs_parse_float(s, &x);
    return x;
}

zs_str *zs_str_of_bool(bool v) { return v ? str_of("true", 4) : str_of("false", 5); }

// a char's text: its UTF-8 encoding (a value that isn't a Unicode scalar becomes U+FFFD)
zs_str *zs_str_of_char(int32_t c) {
    char b[4];
    int n;
    if (c < 0 || c > 0x10FFFF || (c >= 0xD800 && c <= 0xDFFF)) c = 0xFFFD;
    if (c < 0x80) {
        b[0] = (char)c;
        n = 1;
    } else if (c < 0x800) {
        b[0] = (char)(0xC0 | (c >> 6));
        b[1] = (char)(0x80 | (c & 0x3F));
        n = 2;
    } else if (c < 0x10000) {
        b[0] = (char)(0xE0 | (c >> 12));
        b[1] = (char)(0x80 | ((c >> 6) & 0x3F));
        b[2] = (char)(0x80 | (c & 0x3F));
        n = 3;
    } else {
        b[0] = (char)(0xF0 | (c >> 18));
        b[1] = (char)(0x80 | ((c >> 12) & 0x3F));
        b[2] = (char)(0x80 | ((c >> 6) & 0x3F));
        b[3] = (char)(0x80 | (c & 0x3F));
        n = 4;
    }
    return str_of(b, n);
}

zs_str *zs_str_from_c(const char *c) { return str_of(c, (int64_t)strlen(c)); }

zs_str *zs_str_sub(zs_str *s, zs_int start, zs_int len) {
    if (start < 0 || len < 0 || start + len > s->len) zs_panic_c("String.sub: out of range");
    return str_of(s->data + start, len);
}

uint8_t zs_str_byte(zs_str *s, zs_int i) {
    if (i < 0 || i >= s->len) zs_panic_c("String.byte: out of range");
    return (uint8_t)s->data[i];
}

zs_str *zs_str_of_byte(uint8_t b) {
    char c = (char)b;
    return str_of(&c, 1);
}

zs_int zs_str_index_of(zs_str *s, zs_str *sub, zs_int from) {
    if (from < 0) from = 0;
    for (zs_int i = from; i + sub->len <= s->len; i++)
        if (memcmp(s->data + i, sub->data, (size_t)sub->len) == 0) return i;
    return -1;
}

static bool is_space(char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; }

zs_str *zs_str_trim(zs_str *s) {
    zs_int a = 0, b = s->len;
    while (a < b && is_space(s->data[a])) a++;
    while (b > a && is_space(s->data[b - 1])) b--;
    return str_of(s->data + a, b - a);
}

static zs_str *map_ascii(zs_str *s, bool upper) {
    zs_str *r = str_of(s->data, s->len);
    for (zs_int i = 0; i < r->len; i++) {
        char c = r->data[i];
        if (upper && c >= 'a' && c <= 'z') r->data[i] = (char)(c - 32);
        if (!upper && c >= 'A' && c <= 'Z') r->data[i] = (char)(c + 32);
    }
    return r;
}

zs_str *zs_str_upper(zs_str *s) { return map_ascii(s, true); }
zs_str *zs_str_lower(zs_str *s) { return map_ascii(s, false); }

zs_str *zs_str_replace(zs_str *s, zs_str *old, zs_str *with) {
    if (old->len == 0) return str_of(s->data, s->len);
    zs_int n = 0;
    for (zs_int i = 0; (i = zs_str_index_of(s, old, i)) >= 0; i += old->len) n++;
    zs_str *r = str_new(s->len + n * (with->len - old->len));
    zs_int i = 0, o = 0, j;
    while ((j = zs_str_index_of(s, old, i)) >= 0) {
        memcpy(r->data + o, s->data + i, (size_t)(j - i));
        o += j - i;
        memcpy(r->data + o, with->data, (size_t)with->len);
        o += with->len;
        i = j + old->len;
    }
    memcpy(r->data + o, s->data + i, (size_t)(s->len - i));
    return r;
}

// ---- output, panics, exit

void zs_print(zs_str *s) { write_bytes(s->data, s->len); }

void zs_println(zs_str *s) {
    write_bytes(s->data, s->len);
    write_c("\n");
}

void zs_eprintln(zs_str *s) { zs_println(s); }

// the firmware's function, run on a panic before the program stops (zs_set_panic_hook)
static void (*panic_hook)(const char *message);

void zs_set_panic_hook(void (*hook)(const char *message)) { panic_hook = hook; }

_Noreturn void zs_panic_c(const char *msg) {
    write_c("panic: ");
    write_c(msg);
    write_c("\n");
    void (*hook)(const char *) = panic_hook;
    panic_hook = NULL; // a panic inside the hook stops at once
    if (hook) hook(msg);
    stop(134);
}

_Noreturn void zs_panic(zs_str *msg) { zs_panic_c(msg->data); }

_Noreturn void zs_exit(zs_int code) { stop((int)code); }

// ---- callbacks: a callback<F> C calls only where it was passed, as a host's on its own thread
// (rt.c); on a chip the place is thread mode or one interrupt handler (IPSR's exception number)

static uint32_t context(void) {
#if defined(__wasm__)
    return 0;
#else
    uint32_t ipsr;
    __asm__ volatile("mrs %0, ipsr" : "=r"(ipsr));
    return ipsr & 0x1FFu;
#endif
}

void zs_callback_owner(uint64_t *owner) { *owner = context(); }

void zs_callback_thread(uint64_t *owner, const char *type) {
    if (*owner == context()) return;
    char msg[512];
    size_t n = 0;
    const char *parts[] = {"a callback<", type, "> called from another interrupt handler than the code that passed it (declare the parameter callback<share<", type, ">>, and pass a share<", type, ">, for one C may call anywhere)"};
    for (size_t i = 0; i < sizeof parts / sizeof parts[0]; i++)
        for (const char *c = parts[i]; *c && n < sizeof msg - 1; c++) msg[n++] = *c;
    msg[n] = 0;
    zs_panic_c(msg);
}

// ---- handles: a Z# object held by C (zs_handle in a generated header), as the host's (rt.c): a
// count of its own and one reference to the object, which the object's drop function gives up
// when the handle's last reference goes. A Share value's handle may be used anywhere; any other
// only where it was made, the main code or one interrupt handler.
// ponytail: counts change without masking interrupts; with interrupt handlers (0012) a shared
// handle's count goes through Cpu.critical

typedef struct {
    zs_int rc;
    void (*drop)(void *);
    void *obj;
    const char *type;
    uint32_t owner;
    bool shared;
} zs_handle;

zs_handle *zs_handle_new(void *obj, void (*drop)(void *), bool shared, const char *type) {
    zs_handle *h = zs_alloc((zs_int)sizeof(zs_handle));
    h->rc = 1;
    h->drop = drop;
    h->obj = obj;
    h->type = type;
    h->owner = context();
    h->shared = shared;
    return h;
}

// a handle used elsewhere than where it was made: a panic naming what it holds
static void handle_check(zs_handle *h, const char *what) {
    if (h->shared || h->owner == context()) return;
    char msg[512];
    size_t n = 0;
    const char *parts[] = {what, ": a handle of ", h->type, " used from another interrupt handler than the code that made it (make its type Share, or use it where it was made)"};
    for (size_t i = 0; i < sizeof parts / sizeof parts[0]; i++)
        for (const char *c = parts[i]; *c && n < sizeof msg - 1; c++) msg[n++] = *c;
    msg[n] = 0;
    zs_panic_c(msg);
}

// the object, with a new reference for Z#
void *zs_handle_get(zs_handle *h) {
    if (!h) zs_panic_c("a null zs_handle was passed to Z#");
    handle_check(h, "a call into Z#");
    int32_t *rc = h->obj;
    if (*rc > 0) (*rc)++;
    else if (*rc < 0) (*rc)--; // a shared object's count
    return h->obj;
}

void zs_retain(zs_handle *h) {
    if (!h) return;
    handle_check(h, "zs_retain");
    h->rc++;
}

void zs_release(zs_handle *h) {
    if (!h) return;
    handle_check(h, "zs_release");
    if (--h->rc > 0) return;
    void *obj = h->obj;
    void (*drop)(void *) = h->drop;
    zs_free(h);
    drop(obj);
}

void zs_set_args(int32_t argc, char **argv) {
    (void)argc;
    (void)argv;
}

zs_int zs_argc(void) { return 0; }

#if defined(__wasm__)
// ---- startup: the entry runs main (a library, --lib, has none, and no entry) and exits

int main(int argc, char **argv) __attribute__((weak));

void _start(void) { stop(main(0, 0)); }

/// Runtime.ticks (): the host's count.
int64_t zs_ticks(void) { return host_ticks(); }
#elif defined(ZS_LIB)
// ---- a library: no startup. Runtime.ticks (): the DWT's cycle counter on a core with one
// (Cortex-M3 and up), started at the first call; a firmware with its own time base defines
// zs_ticks

__attribute__((weak)) int64_t zs_ticks(void) {
#if defined(__ARM_ARCH_7M__) || defined(__ARM_ARCH_7EM__)
    static uint32_t started, high, last;
    volatile uint32_t *demcr = (volatile uint32_t *)0xE000EDFC, *ctrl = (volatile uint32_t *)0xE0001000, *cyccnt = (volatile uint32_t *)0xE0001004;
    if (!started) {
        *demcr |= 1u << 24; // TRCENA: the DWT on
        *cyccnt = 0;
        *ctrl |= 1u;        // CYCCNTENA
        started = 1;
    }
    uint32_t now = *cyccnt;
    if (now < last) high++; // wrapped: called at least once a wrap (about 4 minutes at 16 MHz)
    last = now;
    return (int64_t)high << 32 | now;
#else
    return 0;
#endif
}
#else
// ---- startup: vector table, reset handler, stack painting, the exit report

extern uint32_t _sidata, _sdata, _edata, _sbss, _ebss, _sstack, _estack;
int main(int argc, char **argv);

static void text(const char *label, uint64_t v) {
    char buf[24];
    write_c(label);
    buf[u64_text(v, buf)] = 0;
    write_c(buf);
}

// one line for the benchmark harness: heap peak (bytes), allocations, objects still live, stack
static void report(void) {
    uint32_t *p = &_sstack;
    while (p < &_estack && *p == 0xCDCDCDCDu) p++;
    text("#zs heap_peak=", H.peak); // live bytes at the high-water mark
    text(" heap_reserved=", H.top);
    text(" allocations=", (uint64_t)H.allocations);
    text(" live=", (uint64_t)H.live);
    text(" stack=", (uint64_t)((uint8_t *)&_estack - (uint8_t *)p));
    write_c("\n");
}

__attribute__((noreturn)) void Reset_Handler(void) {
    uint32_t *src = &_sidata, *dst = &_sdata;
    while (dst < &_edata) *dst++ = *src++;
    for (dst = &_sbss; dst < &_ebss; dst++) *dst = 0;

#if defined(__ARM_FP)
    *(volatile uint32_t *)0xE000ED88 |= 0xFu << 20; // CPACR: enable the FPU (CP10, CP11)
    __asm__ volatile("dsb\n isb");
#endif

    // SysTick counts processor cycles (with QEMU -icount: instructions); its interrupt counts wraps
    *(volatile uint32_t *)0xE000E014 = 0xFFFFFF; // reload
    *(volatile uint32_t *)0xE000E018 = 0;        // current value
    *(volatile uint32_t *)0xE000E010 = 0x7;      // enable, interrupt, processor clock

    // paint the stack below the current frame, to measure its peak use at exit
    uint32_t *sp;
    __asm__ volatile("mov %0, sp" : "=r"(sp));
    for (uint32_t *p = &_sstack; p < sp - 16; p++) *p = 0xCDCDCDCDu;

    stop(main(0, 0));
}

static void fault(void) { zs_panic_c("hard fault"); }

static volatile uint32_t systick_wraps;

static void SysTick_Handler(void) { systick_wraps++; }

/// Runtime.ticks (): SysTick counts since reset (it counts down from 0xFFFFFF and wraps).
int64_t zs_ticks(void) {
    uint32_t w, v;
    do {
        w = systick_wraps;
        v = *(volatile uint32_t *)0xE000E018;
    } while (w != systick_wraps);
    return (int64_t)w * 0x1000000 + (0xFFFFFF - v);
}

__attribute__((section(".vectors"), used)) static void *const vectors[16] = {
    &_estack, Reset_Handler, fault, fault, fault, fault, fault, 0, 0, 0, 0, fault, fault, 0, fault, SysTick_Handler,
};
#endif

// SIMD on a microcontroller: LLVM does a vector's operations lane by lane (with what DSP
// instructions the chip has), so a wide vector needs no more than a word's alignment
void *zs_alloc_wide(zs_int size) { return zs_alloc(size); }

// [<Multiversion>]: a microcontroller runs the baseline version
bool zs_cpu_supports(const char *features) {
    (void)features;
    return false;
}

// a vector's lanes as text, <1, 2, 3> (see rt.c)
zs_str *zs_str_of_lanes(const void *p, zs_int kind, zs_int n) {
    static const int sizes[] = {4, 8, 1, 2, 4, 8, 1, 2, 4, 8, 1};
    char buf[512];
    zs_int len = 0;
    buf[len++] = '<';
    for (zs_int i = 0; i < n; i++) {
        const char *q = (const char *)p + i * sizes[kind];
        zs_str *s;
        switch (kind) {
        case 0: s = zs_str_of_f32(*(const float *)q); break;
        case 1: s = zs_str_of_f64(*(const double *)q); break;
        case 2: s = zs_str_of_i64(*(const int8_t *)q); break;
        case 3: s = zs_str_of_i64(*(const int16_t *)q); break;
        case 4: s = zs_str_of_i64(*(const int32_t *)q); break;
        case 5: s = zs_str_of_i64(*(const int64_t *)q); break;
        case 6: s = zs_str_of_u64(*(const uint8_t *)q); break;
        case 7: s = zs_str_of_u64(*(const uint16_t *)q); break;
        case 8: s = zs_str_of_u64(*(const uint32_t *)q); break;
        case 9: s = zs_str_of_u64(*(const uint64_t *)q); break;
        default: s = zs_str_of_bool(*(const uint8_t *)q != 0); break;
        }
        if (len + s->len + 3 > (zs_int)sizeof buf) zs_panic_c("a vector too long to show");
        if (i > 0) {
            buf[len++] = ',';
            buf[len++] = ' ';
        }
        memcpy(buf + len, s->data, (size_t)s->len);
        len += s->len;
        zs_free(s);
    }
    buf[len++] = '>';
    return str_of(buf, len);
}
