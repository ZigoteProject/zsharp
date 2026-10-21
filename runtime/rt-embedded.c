// Z# runtime for bare-metal ARM Cortex-M (zs build --target cortex-m4 | cortex-m0plus): no OS
// and no libc. The heap is a static array with size-class free lists; output and the exit code
// go to the debugger or emulator through semihosting. The vector table and reset handler are
// here too. What needs an OS (files, processes, environment) isn't provided, so a program that
// uses it fails to link, naming the function.
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

void *memcpy(void *d, const void *s, size_t n) {
    uint8_t *dp = d;
    const uint8_t *sp = s;
    while (n--) *dp++ = *sp++;
    return d;
}

void *memmove(void *d, const void *s, size_t n) {
    uint8_t *dp = d;
    const uint8_t *sp = s;
    if (dp < sp)
        while (n--) *dp++ = *sp++;
    else
        while (n--) dp[n] = sp[n];
    return d;
}

void *memset(void *d, int c, size_t n) {
    uint8_t *dp = d;
    while (n--) *dp++ = (uint8_t)c;
    return d;
}

int memcmp(const void *a, const void *b, size_t n) {
    const uint8_t *x = a, *y = b;
    for (; n; n--, x++, y++)
        if (*x != *y) return *x < *y ? -1 : 1;
    return 0;
}

size_t strlen(const char *s) {
    size_t n = 0;
    while (s[n]) n++;
    return n;
}

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

static void write_c(const char *s) { write_bytes(s, (int64_t)strlen(s)); }

static void report(void);

_Noreturn static void stop(int code) {
    report();
    uint32_t block[2] = {0x20026, (uint32_t)code}; // ADP_Stopped_ApplicationExit, exit code
    semihost(0x20, block);                          // SYS_EXIT_EXTENDED
    for (;;) {}
}

// ---- heap: 8-byte header holding the block size; free lists per 8-byte class up to 256 bytes

static uint8_t heap[ZS_HEAP_SIZE] __attribute__((aligned(8)));

// the allocator's state in one place (one base address), with word-sized counters
static struct {
    size_t top, used, peak;
    zs_int live, allocations;
    void *free_lists[33];
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
        if (H.top + need + 8 > ZS_HEAP_SIZE) zs_panic_c("out of memory");
        block = (uint64_t *)(heap + H.top);
        H.top += need + 8;
        *block = need;
    }

    H.used += (size_t)*block;
    if (H.used > H.peak) H.peak = H.used;
    H.live++;
    H.allocations++;
    return block + 1;
}

// ponytail: blocks over 256 bytes are never reused; a first-fit list if programs need it
void zs_free(void *p) {
    uint64_t *block = (uint64_t *)p - 1;
    size_t cls = (size_t)*block / 8;
    H.used -= (size_t)*block;
    H.live--;

    if (cls <= 32) {
        *(void **)p = H.free_lists[cls];
        H.free_lists[cls] = p;
    }
}

zs_int zs_allocations(void) { return H.allocations; }

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

void zs_set_args(int32_t argc, char **argv) {
    (void)argc;
    (void)argv;
}

zs_int zs_argc(void) { return 0; }

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
