// A C program with no C library calling the Z# library built from lib.zs, as main.c calls it on a
// host: a Cortex-M firmware (zs build --lib --target cortex-m4 or cortex-m0plus), with its own
// vector table, reset handler and output (semihosting, under QEMU), giving the library's output a
// place (zs_write) and its stop (zs_stop) as a firmware with a Z# library does; or a WebAssembly
// program (zs build --lib --target wasm32 -o lib.a), whose output is the host's zs.write, as the
// Z# runtime's is, and whose main the runtime's _start runs (runtime/run-wasm.mjs).
#include <stddef.h>
#include <stdint.h>
#include "lib.h"

#if defined(__wasm__)
// ---- the host's console and exit (runtime/run-wasm.mjs)

__attribute__((import_module("zs"), import_name("write"))) void host_write(const char *p, intptr_t n);
__attribute__((import_module("zs"), import_name("exit"))) void host_exit(int32_t code);

static void say(const char *s) {
    intptr_t n = 0;
    while (s[n]) n++;
    host_write(s, n);
}

_Noreturn static void quit(int code) {
    host_exit(code);
    __builtin_trap();
}
#else
// ---- semihosting: the debugger's (QEMU's) console and exit

static int semihost(int op, void *arg) {
    register int r0 __asm__("r0") = op;
    register void *r1 __asm__("r1") = arg;
    __asm__ volatile("bkpt 0xab" : "+r"(r0) : "r"(r1) : "memory");
    return r0;
}

static void say(const char *s) { semihost(0x04, (void *)s); } // SYS_WRITE0

_Noreturn static void quit(int code) {
    uint32_t block[2] = {0x20026, (uint32_t)code}; // ADP_Stopped_ApplicationExit, the code
    semihost(0x20, block);                         // SYS_EXIT_EXTENDED
    for (;;) {}
}

// what the library needs of a firmware: its output and its stop
void zs_write(const char *p, size_t n) {
    char buf[65];
    while (n > 0) {
        size_t k = n > 64 ? 64 : n;
        for (size_t i = 0; i < k; i++) buf[i] = p[i];
        buf[k] = 0;
        say(buf);
        p += k;
        n -= k;
    }
}

void zs_stop(int code) { quit(code); }
#endif

static void say_int(long long v) {
    char buf[24];
    int i = 23;
    unsigned long long u = v < 0 ? 0 - (unsigned long long)v : (unsigned long long)v;
    buf[i] = 0;
    do {
        buf[--i] = (char)('0' + u % 10);
        u /= 10;
    } while (u);
    if (v < 0) buf[--i] = '-';
    say(buf + i);
}

// the C function lib.zs calls back through (its int is the target's word)
void each(intptr_t n, void (*cb)(void *, intptr_t), void *user) {
    for (intptr_t i = 1; i <= n; i++) cb(user, i);
}

// the program's panic hook: it can log and stop its own way
static void on_panic(const char *message) {
    say("hook: ");
    say(message);
    say("\n");
    quit(3);
}

int main(void) {
    Vec2 c = geo_add((Vec2){1, 2}, (Vec2){3, 4});
    say("add "); say_int((long long)c.x); say(" "); say_int((long long)c.y); say("\n");
    Box r = {{0, 0}, {2, 3}, 7};
    say("area "); say_int((long long)geo_area(r)); say("\n");
    Box g = geo_grow(r, 1.0);
    say("grow "); say_int((long long)g.hi.x); say(" "); say_int((long long)g.hi.y); say(" "); say_int(g.id); say("\n");
    Pair p = geo_swap((Pair){1, 2});
    say("swap "); say_int(p.a); say(" "); say_int(p.b); say("\n");
    say("sum of squares "); say_int(geo_sum_squares(4)); say("\n");
    say("label "); say_int(geo_label_length("hello")); say("\n");
    say("square "); say_int(geo_is_square(r)); say(" "); say_int(geo_is_square((Box){{0, 0}, {2, 2}, 0})); say("\n");
    say("ratio "); say_int(geo_ratio(r)); say("\n");
    zs_set_panic_hook(on_panic);
    geo_ratio((Box){{1, 0}, {1, 2}, 0}); // zero width: division by zero
    say("not reached\n");
    return 0;
}

#if !defined(__wasm__)
// ---- startup: the vector table and the reset handler, as a firmware's startup file has them

extern uint32_t _sidata, _sdata, _edata, _sbss, _ebss, _estack;

void Reset_Handler(void) {
    uint32_t *src = &_sidata, *dst = &_sdata;
    while (dst < &_edata) *dst++ = *src++;
    for (dst = &_sbss; dst < &_ebss; dst++) *dst = 0;
#if defined(__ARM_FP)
    *(volatile uint32_t *)0xE000ED88 |= 0xFu << 20; // CPACR: the FPU on (CP10, CP11)
    __asm__ volatile("dsb\n isb");
#endif
    quit(main());
}

static void fault(void) {
    say("hard fault\n");
    quit(1);
}

__attribute__((section(".vectors"), used)) static void *const vectors[16] = {
    &_estack, Reset_Handler, fault, fault, fault, fault, fault, 0, 0, 0, 0, fault, fault, 0, fault, fault,
};
#endif
