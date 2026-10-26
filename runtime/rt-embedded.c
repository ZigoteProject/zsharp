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

#if defined(__ARM_ARCH)
// ---- C's atomics where the core has no instructions for them (a Cortex-M0's, of every size; a
// Cortex-M4's, of 8 bytes), which LLVM calls: one core, so with interrupts masked each is whole.
// For Atomic and the counts of objects a program shares with its interrupt handlers (0012)
static uint32_t masked(void) {
    uint32_t m;
    __asm__ volatile("mrs %0, primask\n cpsid i" : "=r"(m) : : "memory");
    return m;
}

static void unmasked(uint32_t m) { __asm__ volatile("msr primask, %0" : : "r"(m) : "memory"); }

// named by asm labels: clang won't define its builtins' names itself
#define ZS_ATOMICS(n, T)                                                                                       \
    T zs_atomic_load_##n(const volatile void *p, int order) __asm__("__atomic_load_" #n);                    \
    T zs_atomic_load_##n(const volatile void *p, int order) {                                                \
        (void)order;                                                                                          \
        uint32_t m = masked();                                                                                \
        T v = *(const volatile T *)p;                                                                         \
        unmasked(m);                                                                                          \
        return v;                                                                                             \
    }                                                                                                         \
    void zs_atomic_store_##n(volatile void *p, T v, int order) __asm__("__atomic_store_" #n);               \
    void zs_atomic_store_##n(volatile void *p, T v, int order) {                                            \
        (void)order;                                                                                          \
        uint32_t m = masked();                                                                                \
        *(volatile T *)p = v;                                                                                 \
        unmasked(m);                                                                                          \
    }                                                                                                         \
    T zs_atomic_exchange_##n(volatile void *p, T v, int order) __asm__("__atomic_exchange_" #n);             \
    T zs_atomic_exchange_##n(volatile void *p, T v, int order) {                                             \
        (void)order;                                                                                          \
        uint32_t m = masked();                                                                                \
        T old = *(volatile T *)p;                                                                             \
        *(volatile T *)p = v;                                                                                 \
        unmasked(m);                                                                                          \
        return old;                                                                                           \
    }                                                                                                         \
    bool zs_atomic_compare_exchange_##n(volatile void *p, void *expected, T desired, bool weak, int ok,       \
                                        int fail) __asm__("__atomic_compare_exchange_" #n);                   \
    bool zs_atomic_compare_exchange_##n(volatile void *p, void *expected, T desired, bool weak, int ok,       \
                                        int fail) {                                                           \
        (void)weak, (void)ok, (void)fail;                                                                     \
        uint32_t m = masked();                                                                                \
        T now = *(volatile T *)p;                                                                             \
        bool same = now == *(T *)expected;                                                                    \
        if (same) *(volatile T *)p = desired;                                                                 \
        else *(T *)expected = now;                                                                            \
        unmasked(m);                                                                                          \
        return same;                                                                                          \
    }                                                                                                         \
    T zs_atomic_fetch_add_##n(volatile void *p, T v, int order) __asm__("__atomic_fetch_add_" #n);           \
    T zs_atomic_fetch_add_##n(volatile void *p, T v, int order) {                                            \
        (void)order;                                                                                          \
        uint32_t m = masked();                                                                                \
        T old = *(volatile T *)p;                                                                             \
        *(volatile T *)p = (T)(old + v);                                                                      \
        unmasked(m);                                                                                          \
        return old;                                                                                           \
    }                                                                                                         \
    T zs_atomic_fetch_sub_##n(volatile void *p, T v, int order) __asm__("__atomic_fetch_sub_" #n);           \
    T zs_atomic_fetch_sub_##n(volatile void *p, T v, int order) {                                            \
        (void)order;                                                                                          \
        uint32_t m = masked();                                                                                \
        T old = *(volatile T *)p;                                                                             \
        *(volatile T *)p = (T)(old - v);                                                                      \
        unmasked(m);                                                                                          \
        return old;                                                                                           \
    }
ZS_ATOMICS(1, uint8_t)
ZS_ATOMICS(2, uint16_t)
ZS_ATOMICS(4, uint32_t)
ZS_ATOMICS(8, uint64_t)
#endif

// ---- libm's functions compiler-rt lacks (it has floor, exp, log, sin and the others Math
// uses): pow, atan and atan2 are fdlibm's (Sun Microsystems, 1993-2004: "Permission to use,
// copy, modify, and distribute this software is freely granted, provided that this notice is
// preserved."); the float ones go through double
// ZS_LIBM_BEGIN (tests/libm.sh compiles this section on the host against its libm)

static uint32_t hi_word(double x) {
    uint64_t u;
    __builtin_memcpy(&u, &x, 8);
    return (uint32_t)(u >> 32);
}

static uint32_t lo_word(double x) {
    uint64_t u;
    __builtin_memcpy(&u, &x, 8);
    return (uint32_t)u;
}

static double of_words(uint32_t hi, uint32_t lo) {
    uint64_t u = (uint64_t)hi << 32 | lo;
    double x;
    __builtin_memcpy(&x, &u, 8);
    return x;
}

// x * 2^n, rounded once (musl's scalbn)
static double scaled(double x, int n) {
    if (n > 1023) {
        x *= 0x1p1023;
        n -= 1023;
        if (n > 1023) {
            x *= 0x1p1023;
            n -= 1023;
            if (n > 1023) n = 1023;
        }
    } else if (n < -1022) {
        x *= 0x1p-1022 * 0x1p53;
        n += 1022 - 53;
        if (n < -1022) {
            x *= 0x1p-1022 * 0x1p53;
            n += 1022 - 53;
            if (n < -1022) n = -1022;
        }
    }
    return x * of_words((uint32_t)(0x3ff + n) << 20, 0);
}

// Math.round: to the nearest, halves to the even one
__attribute__((weak)) double roundeven(double x) {
    double f = __builtin_floor(x), d = x - f;
    if (d > 0.5 || (d == 0.5 && f != 2.0 * __builtin_floor(f * 0.5))) f += 1.0;
    return f;
}

__attribute__((weak)) float roundevenf(float x) {
    float f = __builtin_floorf(x), d = x - f;
    if (d > 0.5f || (d == 0.5f && f != 2.0f * __builtin_floorf(f * 0.5f))) f += 1.0f;
    return f;
}

static const double atanhi[] = {
    4.63647609000806093515e-01, // atan(0.5)hi 0x3FDDAC67, 0x0561BB4F
    7.85398163397448278999e-01, // atan(1.0)hi 0x3FE921FB, 0x54442D18
    9.82793723247329054082e-01, // atan(1.5)hi 0x3FEF730B, 0xD281F69B
    1.57079632679489655800e+00, // atan(inf)hi 0x3FF921FB, 0x54442D18
};

static const double atanlo[] = {
    2.26987774529616870924e-17, // atan(0.5)lo 0x3C7A2B7F, 0x222F65E2
    3.06161699786838301793e-17, // atan(1.0)lo 0x3C81A626, 0x33145C07
    1.39033110312309984516e-17, // atan(1.5)lo 0x3C700788, 0x7AF0CBBD
    6.12323399573676603587e-17, // atan(inf)lo 0x3C91A626, 0x33145C07
};

static const double aT[] = {
    3.33333333333329318027e-01,  // 0x3FD55555, 0x5555550D
    -1.99999999998764832476e-01, // 0xBFC99999, 0x9998EBC4
    1.42857142725034663711e-01,  // 0x3FC24924, 0x920083FF
    -1.11111104054623557880e-01, // 0xBFBC71C6, 0xFE231671
    9.09088713343650656196e-02,  // 0x3FB745CD, 0xC54C206E
    -7.69187620504482999495e-02, // 0xBFB3B0F2, 0xAF749A6D
    6.66107313738753120669e-02,  // 0x3FB10D66, 0xA0D03D51
    -5.83357013379057348645e-02, // 0xBFADDE2D, 0x52DEFD9A
    4.97687799461593236017e-02,  // 0x3FA97B4B, 0x24760DEB
    -3.65315727442169155270e-02, // 0xBFA2B444, 0x2C6A6C2F
    1.62858201153657823623e-02,  // 0x3F90AD3A, 0xE322DA11
};

__attribute__((weak)) double atan(double x) {
    uint32_t hx = hi_word(x), ix = hx & 0x7fffffff;
    int id;
    if (ix >= 0x44100000) { // |x| >= 2^66
        if (ix > 0x7ff00000 || (ix == 0x7ff00000 && lo_word(x) != 0)) return x + x; // NaN
        return (hx >> 31) ? -atanhi[3] - atanlo[3] : atanhi[3] + atanlo[3];
    }
    if (ix < 0x3fdc0000) { // |x| < 0.4375
        if (ix < 0x3e400000) return x; // |x| < 2^-27
        id = -1;
    } else {
        x = __builtin_fabs(x);
        if (ix < 0x3ff30000) {          // |x| < 1.1875
            if (ix < 0x3fe60000) {      // 7/16 <= |x| < 11/16
                id = 0;
                x = (2.0 * x - 1.0) / (2.0 + x);
            } else { // 11/16 <= |x| < 19/16
                id = 1;
                x = (x - 1.0) / (x + 1.0);
            }
        } else if (ix < 0x40038000) { // |x| < 2.4375
            id = 2;
            x = (x - 1.5) / (1.0 + 1.5 * x);
        } else { // 2.4375 <= |x| < 2^66
            id = 3;
            x = -1.0 / x;
        }
    }
    double z = x * x, w = z * z;
    // the sum of aT[i] z^(i+1), its odd and even terms apart
    double s1 = z * (aT[0] + w * (aT[2] + w * (aT[4] + w * (aT[6] + w * (aT[8] + w * aT[10])))));
    double s2 = w * (aT[1] + w * (aT[3] + w * (aT[5] + w * (aT[7] + w * aT[9]))));
    if (id < 0) return x - x * (s1 + s2);
    z = atanhi[id] - ((x * (s1 + s2) - atanlo[id]) - x);
    return (hx >> 31) ? -z : z;
}

__attribute__((weak)) double atan2(double y, double x) {
    static const double pi_o_4 = 7.8539816339744827900e-01, pi_o_2 = 1.5707963267948965580e+00,
                        pi = 3.1415926535897931160e+00, pi_lo = 1.2246467991473531772e-16;
    uint32_t hx = hi_word(x), ix = hx & 0x7fffffff, lx = lo_word(x);
    uint32_t hy = hi_word(y), iy = hy & 0x7fffffff, ly = lo_word(y);
    if ((ix | ((lx | -lx) >> 31)) > 0x7ff00000 || (iy | ((ly | -ly) >> 31)) > 0x7ff00000) return x + y; // NaN
    if (((hx - 0x3ff00000) | lx) == 0) return atan(y);                                                   // x = 1
    int m = (int)(((hy >> 31) & 1) | ((hx >> 30) & 2)); // 2 * sign of x + sign of y
    if ((iy | ly) == 0) { // y = 0
        switch (m) {
        case 0:
        case 1: return y;
        case 2: return pi;
        default: return -pi;
        }
    }
    if ((ix | lx) == 0) return (hy >> 31) ? -pi_o_2 : pi_o_2; // x = 0
    if (ix == 0x7ff00000) { // x infinite
        if (iy == 0x7ff00000) {
            switch (m) {
            case 0: return pi_o_4;
            case 1: return -pi_o_4;
            case 2: return 3.0 * pi_o_4;
            default: return -3.0 * pi_o_4;
            }
        }
        switch (m) {
        case 0: return 0.0;
        case 1: return -0.0;
        case 2: return pi;
        default: return -pi;
        }
    }
    if (iy == 0x7ff00000) return (hy >> 31) ? -pi_o_2 : pi_o_2; // y infinite
    int k = ((int)iy - (int)ix) >> 20;
    double z;
    if (k > 60) z = pi_o_2 + 0.5 * pi_lo;              // |y/x| > 2^60
    else if ((hx >> 31) && k < -60) z = 0.0;           // |y|/x < -2^60
    else z = atan(__builtin_fabs(y / x));
    switch (m) {
    case 0: return z;
    case 1: return -z;
    case 2: return pi - (z - pi_lo);
    default: return (z - pi_lo) - pi;
    }
}

__attribute__((weak)) double pow(double x, double y) {
    static const double bp[] = {1.0, 1.5}, dp_h[] = {0.0, 5.84962487220764160156e-01},
                        dp_l[] = {0.0, 1.35003920212974897128e-08}, two53 = 9007199254740992.0,
                        huge = 1.0e300, tiny = 1.0e-300,
                        // (3/2) (log x - 2s - 2/3 s^3)'s polynomial
                        L1 = 5.99999999999994648725e-01, L2 = 4.28571428578550184252e-01,
                        L3 = 3.33333329818377432918e-01, L4 = 2.72728123808534006489e-01,
                        L5 = 2.30660745775561754067e-01, L6 = 2.06975017800338417784e-01,
                        P1 = 1.66666666666666019037e-01, P2 = -2.77777777770155933842e-03,
                        P3 = 6.61375632143793436117e-05, P4 = -1.65339022054652515390e-06,
                        P5 = 4.13813679705723846039e-08, lg2 = 6.93147180559945286227e-01,
                        lg2_h = 6.93147182464599609375e-01, lg2_l = -1.90465429995776804525e-09,
                        ovt = 8.0085662595372944372e-17, // -(1024 - log2(ovfl + .5ulp))
                        cp = 9.61796693925975554329e-01, // 2 / (3 ln2)
                        cp_h = 9.61796700954437255859e-01, cp_l = -7.02846165095275826516e-09,
                        ivln2 = 1.44269504088896338700e+00, ivln2_h = 1.44269502162933349609e+00,
                        ivln2_l = 1.92596299112661746887e-08;
    int32_t hx = (int32_t)hi_word(x), hy = (int32_t)hi_word(y);
    uint32_t lx = lo_word(x), ly = lo_word(y);
    int32_t ix = hx & 0x7fffffff, iy = hy & 0x7fffffff;
    if ((iy | ly) == 0) return 1.0;            // x^0
    if (hx == 0x3ff00000 && lx == 0) return 1.0; // 1^y, NaN y too
    if (ix > 0x7ff00000 || (ix == 0x7ff00000 && lx != 0) || iy > 0x7ff00000 || (iy == 0x7ff00000 && ly != 0)) return x + y;
    // when x < 0: whether y is an odd integer (1), an even one (2) or not one (0)
    int yisint = 0;
    if (hx < 0) {
        if (iy >= 0x43400000) yisint = 2;
        else if (iy >= 0x3ff00000) {
            int k = (iy >> 20) - 0x3ff;
            if (k > 20) {
                uint32_t j = ly >> (52 - k);
                if ((j << (52 - k)) == ly) yisint = 2 - (int)(j & 1);
            } else if (ly == 0) {
                int32_t j = iy >> (20 - k);
                if ((j << (20 - k)) == iy) yisint = 2 - (int)(j & 1);
            }
        }
    }
    if (ly == 0) {
        if (iy == 0x7ff00000) { // y infinite
            if (((ix - 0x3ff00000) | lx) == 0) return 1.0; // (-1)^inf
            if (ix >= 0x3ff00000) return hy >= 0 ? y : 0.0; // |x| > 1
            return hy < 0 ? -y : 0.0;                       // |x| < 1
        }
        if (iy == 0x3ff00000) return hy < 0 ? 1.0 / x : x; // y = +-1
        if (hy == 0x40000000) return x * x;                // y = 2
        if (hy == 0x3fe00000 && hx >= 0) return __builtin_sqrt(x); // y = 0.5
    }
    double ax = __builtin_fabs(x), z;
    if (lx == 0 && (ix == 0x7ff00000 || ix == 0 || ix == 0x3ff00000)) { // x is +-0, +-inf, -1
        z = ax;
        if (hy < 0) z = 1.0 / z;
        if (hx < 0) {
            if (((ix - 0x3ff00000) | yisint) == 0) z = (z - z) / (z - z); // (-1)^non-integer
            else if (yisint == 1) z = -z;
        }
        return z;
    }
    if (hx < 0 && yisint == 0) return (x - x) / (x - x); // a negative to a non-integer
    double s = (hx < 0 && yisint == 1) ? -1.0 : 1.0;      // the result's sign
    double t1, t2;
    if (iy > 0x41e00000) { // |y| > 2^31
        if (iy > 0x43f00000) { // |y| > 2^64: overflows or underflows
            if (ix <= 0x3fefffff) return hy < 0 ? huge * huge : tiny * tiny;
            return hy > 0 ? huge * huge : tiny * tiny;
        }
        if (ix < 0x3fefffff) return hy < 0 ? s * huge * huge : s * tiny * tiny;
        if (ix > 0x3ff00000) return hy > 0 ? s * huge * huge : s * tiny * tiny;
        // |1 - x| <= 2^-20: log(x) by x - x^2/2 + x^3/3 - x^4/4
        double t = ax - 1.0;
        double w = (t * t) * (0.5 - t * (0.3333333333333333333333 - t * 0.25));
        double u = ivln2_h * t, v = t * ivln2_l - w * ivln2;
        t1 = of_words(hi_word(u + v), 0);
        t2 = v - (t1 - u);
    } else {
        int n = 0;
        if (ix < 0x00100000) { // subnormal
            ax *= two53;
            n -= 53;
            ix = (int32_t)hi_word(ax);
        }
        n += (ix >> 20) - 0x3ff;
        int32_t j = ix & 0x000fffff;
        int k;
        ix = j | 0x3ff00000; // normalized
        if (j <= 0x3988E) k = 0;        // |x| < sqrt(3/2)
        else if (j < 0xBB67A) k = 1;    // |x| < sqrt(3)
        else {
            k = 0;
            n += 1;
            ix -= 0x00100000;
        }
        ax = of_words((uint32_t)ix, lo_word(ax));
        // ss = s_h + s_l = (x - 1) / (x + 1) or (x - 1.5) / (x + 1.5)
        double u = ax - bp[k], v = 1.0 / (ax + bp[k]);
        double ss = u * v, s_h = of_words(hi_word(ss), 0);
        double t_h = of_words((uint32_t)(((ix >> 1) | 0x20000000) + 0x00080000 + (k << 18)), 0);
        double t_l = ax - (t_h - bp[k]);
        double s_l = v * ((u - s_h * t_h) - s_h * t_l);
        // log(ax)
        double s2 = ss * ss;
        double r = s2 * s2 * (L1 + s2 * (L2 + s2 * (L3 + s2 * (L4 + s2 * (L5 + s2 * L6)))));
        r += s_l * (s_h + ss);
        s2 = s_h * s_h;
        t_h = of_words(hi_word(3.0 + s2 + r), 0);
        t_l = r - ((t_h - 3.0) - s2);
        u = s_h * t_h;
        v = s_l * t_h + t_l * ss;
        double p_h = of_words(hi_word(u + v), 0);
        double p_l = v - (p_h - u);
        double z_h = cp_h * p_h, z_l = cp_l * p_h + p_l * cp + dp_l[k];
        // log2(ax) = n + dp_h + z_h + z_l
        double t = (double)n;
        t1 = of_words(hi_word(((z_h + z_l) + dp_h[k]) + t), 0);
        t2 = z_l - (((t1 - t) - dp_h[k]) - z_h);
    }
    // (y1 + y2) (t1 + t2), y split
    double y1 = of_words(hi_word(y), 0);
    double p_l = (y - y1) * t1 + y * t2, p_h = y1 * t1;
    z = p_l + p_h;
    int32_t j = (int32_t)hi_word(z);
    int32_t i = (int32_t)lo_word(z);
    if (j >= 0x40900000) { // z >= 1024
        if (((j - 0x40900000) | i) != 0) return s * huge * huge;
        if (p_l + ovt > z - p_h) return s * huge * huge;
    } else if ((j & 0x7fffffff) >= 0x4090cc00) { // z <= -1075
        if (((j - (int32_t)0xc090cc00) | i) != 0) return s * tiny * tiny;
        if (p_l <= z - p_h) return s * tiny * tiny;
    }
    // 2^(p_h + p_l)
    i = j & 0x7fffffff;
    int k = (i >> 20) - 0x3ff;
    int n = 0;
    if (i > 0x3fe00000) { // |z| > 0.5: n = [z + 0.5]
        n = j + (0x00100000 >> (k + 1));
        k = ((n & 0x7fffffff) >> 20) - 0x3ff;
        double t = of_words((uint32_t)(n & ~(0x000fffff >> k)), 0);
        n = ((n & 0x000fffff) | 0x00100000) >> (20 - k);
        if (j < 0) n = -n;
        p_h -= t;
    }
    double t = of_words(hi_word(p_l + p_h), 0);
    double u = t * lg2_h, v = (p_l - (t - p_h)) * lg2 + t * lg2_l;
    z = u + v;
    double w = v - (z - u);
    t = z * z;
    t1 = z - t * (P1 + t * (P2 + t * (P3 + t * (P4 + t * P5))));
    double r = (z * t1) / (t1 - 2.0) - (w + z * w);
    z = 1.0 - (r - z);
    j = (int32_t)hi_word(z) + (n << 20);
    if ((j >> 20) <= 0) z = scaled(z, n); // a subnormal result
    else z = of_words((uint32_t)j, lo_word(z));
    return s * z;
}

// ponytail: the float ones through double: right, but soft double on a Cortex-M4's
// single-precision FPU; fdlibm's float versions when a loop needs them faster
__attribute__((weak)) float atanf(float x) { return (float)atan(x); }
__attribute__((weak)) float atan2f(float y, float x) { return (float)atan2(y, x); }
__attribute__((weak)) float powf(float x, float y) { return (float)pow(x, y); }
// ZS_LIBM_END

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

#ifdef ZS_RTT
// ---- RTT (SEGGER's Real-Time Transfer), a real board's output (ZS_RTT, 0027): a ring in RAM that
// a debug probe reads while the core runs (probe-rs run, a J-Link, OpenOCD), found by this
// symbol or its ID; nothing to wire. One channel up; its mode is the host's to set: 0 (the
// default, so a board with no probe never waits) drops a write that doesn't fit, 1 writes what
// fits, 2 waits for the host to make room.
typedef struct {
    const char *name;
    char *buf;
    uint32_t size;
    volatile uint32_t wr, rd, flags;
} rtt_up;

static char rtt_buf[1024];

struct {
    char id[16];
    int32_t ups, downs;
    rtt_up up;
} _SEGGER_RTT = {"SEGGER RTT", 1, 0, {"Terminal", rtt_buf, sizeof rtt_buf, 0, 0, 0}};

static void write_bytes(const char *p, int64_t n) {
    rtt_up *u = &_SEGGER_RTT.up;
    uint32_t m = masked(); // a handler's output doesn't land inside the program's
    while (n > 0) {
        uint32_t wr = u->wr, rd = u->rd;
        uint32_t room = (rd > wr ? rd - wr : u->size - wr + rd) - 1; // a full ring isn't an empty one
        if (room == 0 || (room < n && (u->flags & 3) == 0)) {
            if ((u->flags & 3) != 2) break;
            continue;
        }
        uint32_t k = n < room ? (uint32_t)n : room;
        if (k > u->size - wr) k = u->size - wr; // to the end, then from the start
        memcpy(u->buf + wr, p, k);
        __asm__ volatile("dmb" ::: "memory"); // the bytes before the offset that shows them
        u->wr = wr + k == u->size ? 0 : wr + k;
        p += k;
        n -= k;
    }
    unmasked(m);
}
#else
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

#endif

static void report(void);

_Noreturn static void stop(int code) {
    report();
#ifdef ZS_RTT
    // with no debugger attached (DHCSR's C_DEBUGEN, ARMv7-M) the bkpt below would fault, so the
    // core sleeps; with one, it gets a moment to read the output, then the exit (probe-rs run
    // returns it)
    if (!(*(volatile uint32_t *)0xE000EDF0 & 1))
        for (;;) __asm__ volatile("wfi");
    for (uint32_t i = 0; i < 1000000 && _SEGGER_RTT.up.rd != _SEGGER_RTT.up.wr; i++) {}
#endif
    uint32_t block[2] = {0x20026, (uint32_t)code}; // ADP_Stopped_ApplicationExit, exit code
    semihost(0x20, block);                          // SYS_EXIT_EXTENDED
    for (;;) {}
}
#endif

static void write_c(const char *s) { write_bytes(s, (int64_t)strlen(s)); }

// ---- heap: 8-byte header holding the block size; free lists per 8-byte class up to 256 bytes.
// With --no-heap (ZS_NO_HEAP) there's none: zs_alloc is declared and not defined, so whatever
// would still allocate fails the link, naming its caller (0012)

_Noreturn void zs_panic_c(const char *msg);

#ifdef ZS_NO_HEAP
void *zs_alloc(zs_int size);
void zs_free(void *p);
zs_int zs_allocations(void) { return 0; }
zs_int zs_mallocs(void) { return 0; }
#else
static uint8_t heap[ZS_HEAP_SIZE] __attribute__((aligned(8)));

// the allocator's state in one place (one base address), with word-sized counters; blocks over
// 256 bytes freed are on one list, reused first fit
static struct {
    size_t top, used, peak;
    zs_int live, allocations;
    void *free_lists[33];
    void *large;
} H;

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
#endif
// objects marked shared: with an interrupt handler (0012), the values it can reach, at startup
zs_int zs_marked;
zs_int zs_marks(void) { return zs_marked; }

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

// ---- Spsc (0012): a ring between one producer and one consumer, an interrupt handler and the
// program, or two threads, neither waiting or locking: the producer alone moves the tail and the
// consumer alone the head, each after the value it wrote or read. One slot stays empty, so a full
// ring isn't an empty one. A Z# object: the drop function it was made with drops what's still in
// it when it's freed.
typedef struct {
    zs_int rc;
    zs_int cap, size;
    zs_int head, tail; // each written by its side alone, read by the other atomically
    void (*drop)(void *slot);
    char slots[];
} zs_spsc;

void *zs_spsc_new(zs_int cap, zs_int size, void (*drop)(void *)) {
    if (cap < 1) zs_panic_c("an Spsc holds at least one value");
    zs_spsc *q = zs_alloc((zs_int)sizeof(zs_spsc) + (cap + 1) * (size ? size : 1));
    q->rc = 1;
    q->cap = cap + 1;
    q->size = size;
    q->head = q->tail = 0;
    q->drop = drop;
    return q;
}

bool zs_spsc_push(zs_spsc *q, const void *v) {
    zs_int t = q->tail;
    zs_int next = (t + 1) % q->cap;
    if (next == __atomic_load_n(&q->head, __ATOMIC_ACQUIRE)) return false; // full
    memcpy(q->slots + t * q->size, v, (size_t)q->size);
    __atomic_store_n(&q->tail, next, __ATOMIC_RELEASE);
    return true;
}

bool zs_spsc_pop(zs_spsc *q, void *out) {
    zs_int h = q->head;
    if (h == __atomic_load_n(&q->tail, __ATOMIC_ACQUIRE)) return false; // empty
    memcpy(out, q->slots + h * q->size, (size_t)q->size);
    __atomic_store_n(&q->head, (h + 1) % q->cap, __ATOMIC_RELEASE);
    return true;
}

void zs_spsc_free(zs_spsc *q) {
    if (q->drop)
        for (zs_int i = q->head; i != q->tail; i = (i + 1) % q->cap) q->drop(q->slots + i * q->size);
    zs_free(q);
}

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
// (with no heap, the stack alone)
static void report(void) {
    uint32_t *p = &_sstack;
    while (p < &_estack && *p == 0xCDCDCDCDu) p++;
#ifdef ZS_NO_HEAP
    text("#zs stack=", (uint64_t)((uint8_t *)&_estack - (uint8_t *)p));
#else
    text("#zs heap_peak=", H.peak); // live bytes at the high-water mark
    text(" heap_reserved=", H.top);
    text(" allocations=", (uint64_t)H.allocations);
    text(" live=", (uint64_t)H.live);
    text(" stack=", (uint64_t)((uint8_t *)&_estack - (uint8_t *)p));
#endif
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

static void nothing(void) {}

// the core exceptions' handlers, by CMSIS's names: weak, so a program's [<Interrupt "HardFault">]
// (or a C file's) is the one the table calls (0012)
__attribute__((weak, alias("fault"))) void NMI_Handler(void);
__attribute__((weak, alias("fault"))) void HardFault_Handler(void);
__attribute__((weak, alias("fault"))) void MemManage_Handler(void);
__attribute__((weak, alias("fault"))) void BusFault_Handler(void);
__attribute__((weak, alias("fault"))) void UsageFault_Handler(void);
__attribute__((weak, alias("nothing"))) void SVC_Handler(void);
__attribute__((weak, alias("nothing"))) void DebugMon_Handler(void);
__attribute__((weak, alias("nothing"))) void PendSV_Handler(void);

// Runtime.ticks is the cycles before SysTick's current period plus what it has run of it; a
// period is 2^24 cycles, or until the loop's next deadline while it sleeps (0016)
static volatile uint64_t systick_base;
static volatile uint32_t systick_len = 0x1000000;

#define SYST_RVR (*(volatile uint32_t *)0xE000E014)
#define SYST_CVR (*(volatile uint32_t *)0xE000E018)
#define ICSR (*(volatile uint32_t *)0xE000ED04)

// a program's [<Interrupt "SysTick">], at the end of each period: SysTick is the runtime's, for
// Runtime.ticks and the loop's timers
__attribute__((weak)) void zs_systick_user(void) {}

void SysTick_Handler(void) {
    uint32_t m = masked(); // whole, for a handler above this one reading the time
    systick_base += systick_len;
    unmasked(m);
    zs_systick_user();
}

// SysTick's next interrupt in `cycles` (65 to 2^24), what the current period has run counted
// first. ponytail: the few cycles between reading the count and restarting it are lost, each
// time the loop sleeps; a free-running timer of the board's if a clock mustn't drift
static void systick_period(uint32_t cycles) {
    uint32_t m = masked();
    uint32_t v = SYST_CVR;
    if (ICSR & (1u << 26)) { // a wrap its handler hasn't counted (PENDSTSET): counted here
        ICSR = 1u << 25;     // PENDSTCLR
        v = SYST_CVR;
        systick_base += systick_len;
    }
    systick_base += systick_len - 1 - v;
    systick_len = cycles;
    SYST_RVR = cycles - 1;
    SYST_CVR = 0; // the period starts over, from the new reload
    unmasked(m);
}

// the board's lines (runtime/boards/<board>.irq), a multiple of ten
#ifndef ZS_IRQ_COUNT
#define ZS_IRQ_COUNT 0
#endif

// the lines that fired since the loop last looked, for the tasks waiting for them (Irq.wait)
static volatile uint32_t lines_fired[(ZS_IRQ_COUNT + 31) / 32 + 1];

// a device line no handler of the program's has: disabled in the NVIC, so it doesn't fire again
// until a task waits for it, and marked for the loop
static void irq_default(void) {
    uint32_t n;
    __asm__ volatile("mrs %0, ipsr" : "=r"(n));
    n -= 16;
    ((volatile uint32_t *)0xE000E180)[n / 32] = 1u << (n % 32); // ICER
    uint32_t m = masked(); // a handler above this one may mark a line in the same word
    lines_fired[n / 32] |= 1u << (n % 32);
    unmasked(m);
}

// the device lines' handlers, IRQ0_Handler up: weak, so a program's [<Interrupt 38>] (or
// [<Interrupt "USART2">], by the board's table) replaces one; in tens, up to 240
#define ZS_IRQ(n) __attribute__((weak, alias("irq_default"))) void IRQ##n##_Handler(void);
#define ZS_IRQ_TEN(d) ZS_IRQ(d##0) ZS_IRQ(d##1) ZS_IRQ(d##2) ZS_IRQ(d##3) ZS_IRQ(d##4) ZS_IRQ(d##5) ZS_IRQ(d##6) ZS_IRQ(d##7) ZS_IRQ(d##8) ZS_IRQ(d##9)
ZS_IRQ(0) ZS_IRQ(1) ZS_IRQ(2) ZS_IRQ(3) ZS_IRQ(4) ZS_IRQ(5) ZS_IRQ(6) ZS_IRQ(7) ZS_IRQ(8) ZS_IRQ(9)
ZS_IRQ_TEN(1) ZS_IRQ_TEN(2) ZS_IRQ_TEN(3) ZS_IRQ_TEN(4) ZS_IRQ_TEN(5) ZS_IRQ_TEN(6) ZS_IRQ_TEN(7) ZS_IRQ_TEN(8)
ZS_IRQ_TEN(9) ZS_IRQ_TEN(10) ZS_IRQ_TEN(11) ZS_IRQ_TEN(12) ZS_IRQ_TEN(13) ZS_IRQ_TEN(14) ZS_IRQ_TEN(15)
ZS_IRQ_TEN(16) ZS_IRQ_TEN(17) ZS_IRQ_TEN(18) ZS_IRQ_TEN(19) ZS_IRQ_TEN(20) ZS_IRQ_TEN(21) ZS_IRQ_TEN(22)
ZS_IRQ_TEN(23)

/// Runtime.ticks (): the cycles SysTick has counted since reset (down from its reload, and over).
int64_t zs_ticks(void) {
    uint32_t m = masked();
    uint64_t base = systick_base;
    uint32_t len = systick_len, v = SYST_CVR;
    // a wrap its handler hasn't counted yet (ICSR's PENDSTSET): the value may be from either side
    // of it, so it's read again, now after it, and the wrap counted
    if (ICSR & (1u << 26)) {
        v = SYST_CVR;
        base += len;
    }
    int64_t t = (int64_t)(base + (len - 1 - v));
    // and never behind a value already given: QEMU can show the count reloaded before its timer
    // sets PENDSTSET, which hardware does in the same cycle
    static int64_t given;
    if (t < given) t = given;
    else given = t;
    unmasked(m);
    return t;
}
#define ZS_VEC(n) IRQ##n##_Handler,
#define ZS_VEC_TEN(d) ZS_VEC(d##0) ZS_VEC(d##1) ZS_VEC(d##2) ZS_VEC(d##3) ZS_VEC(d##4) ZS_VEC(d##5) ZS_VEC(d##6) ZS_VEC(d##7) ZS_VEC(d##8) ZS_VEC(d##9)

__attribute__((section(".vectors"), used)) static void *const vectors[] = {
    &_estack, Reset_Handler, NMI_Handler, HardFault_Handler, MemManage_Handler, BusFault_Handler, UsageFault_Handler,
    0, 0, 0, 0, SVC_Handler, DebugMon_Handler, 0, PendSV_Handler, SysTick_Handler,
#if ZS_IRQ_COUNT >= 10
    ZS_VEC(0) ZS_VEC(1) ZS_VEC(2) ZS_VEC(3) ZS_VEC(4) ZS_VEC(5) ZS_VEC(6) ZS_VEC(7) ZS_VEC(8) ZS_VEC(9)
#endif
#if ZS_IRQ_COUNT >= 20
    ZS_VEC_TEN(1)
#endif
#if ZS_IRQ_COUNT >= 30
    ZS_VEC_TEN(2)
#endif
#if ZS_IRQ_COUNT >= 40
    ZS_VEC_TEN(3)
#endif
#if ZS_IRQ_COUNT >= 50
    ZS_VEC_TEN(4)
#endif
#if ZS_IRQ_COUNT >= 60
    ZS_VEC_TEN(5)
#endif
#if ZS_IRQ_COUNT >= 70
    ZS_VEC_TEN(6)
#endif
#if ZS_IRQ_COUNT >= 80
    ZS_VEC_TEN(7)
#endif
#if ZS_IRQ_COUNT >= 90
    ZS_VEC_TEN(8)
#endif
#if ZS_IRQ_COUNT >= 100
    ZS_VEC_TEN(9)
#endif
#if ZS_IRQ_COUNT >= 110
    ZS_VEC_TEN(10)
#endif
#if ZS_IRQ_COUNT >= 120
    ZS_VEC_TEN(11)
#endif
#if ZS_IRQ_COUNT > 120
#error "the runtime's vector table has 120 device lines; add tens above"
#endif
};
#endif

// ---- the event loop (0016): Task's, on one core with no threads. Ready callbacks in a ring and
// timers in a heap by deadline (Runtime.ticks), both on the heap, so a program without tasks
// links none of it. On a chip with the runtime's startup, a task waits for an interrupt line
// (Irq.wait) or a Signal too: handlers mark them in bitmasks the loop drains, so no Z# code runs
// in a handler. With nothing to run, the core sleeps until the next deadline or interrupt
// (WebAssembly and a library spin until the deadline).

void zs_clo_run(void *c);
void zs_clo_drop(void *c);

#ifndef ZS_CLOCK_HZ
#define ZS_CLOCK_HZ 16000000
#endif

// Runtime.ticks per second: the board's clock at reset, or Runtime.setClock's
static uint32_t clock_hz = ZS_CLOCK_HZ;

void zs_set_clock(uint32_t hz) { clock_hz = hz; }

typedef struct {
    int64_t at; // Runtime.ticks
    zs_int id;
    void *cb;
} loop_timer;

static struct {
    bool stepping; // inside zs_loop_step: a callback can't run Task.run itself
    int depth;     // continuations called inside others (zs_loop_enter)
    void **queue;  // ready callbacks, a ring
    uint32_t qhead, qlen, qcap;
    loop_timer *timers; // a min-heap by deadline
    uint32_t ntimers, tcap;
    zs_int next_timer;
    uint32_t waits; // interrupt lines and signals tasks wait for
} L;

void zs_loop_post(void *cb) {
    if (L.qlen == L.qcap) {
        uint32_t cap = L.qcap ? 2 * L.qcap : 16;
        void **q = zs_alloc((zs_int)(cap * sizeof(void *)));
        for (uint32_t i = 0; i < L.qlen; i++) q[i] = L.queue[(L.qhead + i) % L.qcap];
        if (L.queue) zs_free(L.queue);
        L.queue = q;
        L.qhead = 0;
        L.qcap = cap;
    }
    L.queue[(L.qhead + L.qlen++) % L.qcap] = cb;
}

static void *queue_pop(void) {
    void *cb = L.queue[L.qhead];
    L.qhead = (L.qhead + 1) % L.qcap;
    L.qlen--;
    return cb;
}

// a continuation may be called inside the current one (true: the caller calls zs_loop_leave
// after it), or should go through the queue, so a run of awaits that complete at once doesn't
// grow the stack without end
bool zs_loop_enter(void) {
    if (L.depth >= 64) return false;
    L.depth++;
    return true;
}

void zs_loop_leave(void) { L.depth--; }

// no threads: nothing of this loop's runs elsewhere
zs_int zs_loop_jobs(void) { return 0; }

static void timer_swap(uint32_t i, uint32_t j) {
    loop_timer t = L.timers[i];
    L.timers[i] = L.timers[j];
    L.timers[j] = t;
}

static void timer_up(uint32_t i) {
    for (; i > 0 && L.timers[(i - 1) / 2].at > L.timers[i].at; i = (i - 1) / 2) timer_swap(i, (i - 1) / 2);
}

static void timer_down(uint32_t i) {
    for (;;) {
        uint32_t c = 2 * i + 1;
        if (c >= L.ntimers) return;
        if (c + 1 < L.ntimers && L.timers[c + 1].at < L.timers[c].at) c++;
        if (L.timers[c].at >= L.timers[i].at) return;
        timer_swap(i, c);
        i = c;
    }
}

// the timer at i taken out of the heap: its callback
static void *timer_remove(uint32_t i) {
    void *cb = L.timers[i].cb;
    L.timers[i] = L.timers[--L.ntimers];
    if (i < L.ntimers) {
        timer_up(i);
        timer_down(i);
    }
    return cb;
}

// cb runs in ms milliseconds; the result names the timer for zs_loop_untimer
zs_int zs_loop_timer(zs_int ms, void *cb) {
    if (L.ntimers == L.tcap) {
        uint32_t cap = L.tcap ? 2 * L.tcap : 8;
        loop_timer *t = zs_alloc((zs_int)(cap * sizeof(loop_timer)));
        if (L.ntimers) memcpy(t, L.timers, L.ntimers * sizeof(loop_timer));
        if (L.timers) zs_free(L.timers);
        L.timers = t;
        L.tcap = cap;
    }
    int64_t at = zs_ticks() + (ms > 0 ? (int64_t)ms * clock_hz / 1000 : 0);
    L.timers[L.ntimers] = (loop_timer){at, ++L.next_timer, cb};
    timer_up(L.ntimers++);
    return L.next_timer;
}

// the timer goes, its callback uncalled (its task was cancelled). ponytail: found by a scan,
// fine for the few a chip has pending; an index by id for hundreds
void zs_loop_untimer(zs_int id) {
    for (uint32_t i = 0; i < L.ntimers; i++)
        if (L.timers[i].id == id) {
            zs_clo_drop(timer_remove(i));
            return;
        }
}

#if !defined(__wasm__) && !defined(ZS_LIB)
// ---- waiting for interrupts: a task per line (Irq.wait), and Signals, which a program's own
// handlers set (at most 32: a word of bits)

static void *line_waiter[ZS_IRQ_COUNT + 1];
static volatile uint32_t signals_set;
static uint32_t signal_count;
static void *signal_waiter[32];

void zs_loop_irq_wait(zs_int n, void *cb) {
    if (n < 0 || n >= ZS_IRQ_COUNT) zs_panic_c("Irq.wait: the line is past the board's table");
    if (vectors[16 + n] != (void *)irq_default) zs_panic_c("Irq.wait: the line has a handler of its own, which wakes no task: set a Signal from it");
    if (line_waiter[n]) zs_panic_c("two tasks wait for one interrupt line (one Irq.wait per line at a time)");
    line_waiter[n] = cb;
    L.waits++;
    uint32_t m = masked();
    lines_fired[n / 32] &= ~(1u << (n % 32)); // a fire from before the wait isn't its
    unmasked(m);
    ((volatile uint32_t *)0xE000E100)[n / 32] = 1u << (n % 32); // ISER
}

// the task waiting for line n was cancelled: the line quiet again
void zs_loop_irq_unwait(zs_int n) {
    void *cb = line_waiter[n];
    if (!cb) return;
    line_waiter[n] = NULL;
    L.waits--;
    ((volatile uint32_t *)0xE000E180)[n / 32] = 1u << (n % 32); // ICER
    zs_clo_drop(cb);
}

zs_int zs_signal_new(void) {
    if (signal_count == 32) zs_panic_c("more than 32 Signals");
    return (zs_int)signal_count++;
}

void zs_signal_set(zs_int s) {
    uint32_t m = masked();
    signals_set |= 1u << s;
    unmasked(m);
}

// whether the signal was set, clearing it
bool zs_signal_take(zs_int s) {
    uint32_t m = masked();
    bool was = signals_set >> s & 1;
    signals_set &= ~(1u << s);
    unmasked(m);
    return was;
}

void zs_signal_wait(zs_int s, void *cb) {
    if (signal_waiter[s]) zs_panic_c("two tasks wait on one Signal");
    signal_waiter[s] = cb;
    L.waits++;
}

void zs_signal_unwait(zs_int s) {
    void *cb = signal_waiter[s];
    if (!cb) return;
    signal_waiter[s] = NULL;
    L.waits--;
    zs_clo_drop(cb);
}

// the tasks waiting for the lines that fired and the signals that were set, to the ready queue
static void drain(void) {
    for (uint32_t w = 0; w < sizeof lines_fired / sizeof lines_fired[0]; w++) {
        if (!lines_fired[w]) continue;
        uint32_t m = masked();
        uint32_t bits = lines_fired[w];
        lines_fired[w] = 0;
        unmasked(m);
        for (; bits; bits &= bits - 1) {
            uint32_t n = w * 32 + (uint32_t)__builtin_ctz(bits);
            if (n < ZS_IRQ_COUNT && line_waiter[n]) {
                zs_loop_post(line_waiter[n]);
                line_waiter[n] = NULL;
                L.waits--;
            }
        }
    }
    for (uint32_t s = 0; s < signal_count; s++)
        if (signal_waiter[s] && zs_signal_take((zs_int)s)) {
            zs_loop_post(signal_waiter[s]);
            signal_waiter[s] = NULL;
            L.waits--;
        }
}

// whether a line fired or a signal was set since the drain (looked at with interrupts masked)
static bool marked(void) {
    for (uint32_t w = 0; w < sizeof lines_fired / sizeof lines_fired[0]; w++)
        if (lines_fired[w]) return true;
    return signals_set != 0;
}
#endif

// nothing to run until `at` (Runtime.ticks; -1 for no timer): the core sleeps until then, or
// until an interrupt
static void sleep_until(int64_t at) {
#if defined(__wasm__) || defined(ZS_LIB)
    while (zs_ticks() < at) {}
#else
    // masked: an interrupt between the look and the wfi still wakes it (a pending interrupt does,
    // masked or not), and its handler runs after
    uint32_t m = masked();
    if (!marked()) {
        int64_t d = at < 0 ? 0x1000000 : at - zs_ticks();
        if (d > 64) {
            systick_period(d < 0x1000000 ? (uint32_t)d : 0x1000000);
            __asm__ volatile("wfi");
            systick_period(0x1000000);
        }
    }
    unmasked(m);
#endif
}

bool zs_loop_step(void) {
    if (L.stepping) zs_panic_c("Task.run inside a task: use let! there instead");
    L.stepping = true;
    for (uint32_t n = L.qlen; n > 0 && L.qlen; n--) zs_clo_run(queue_pop());
    L.stepping = false;
    int64_t now = zs_ticks();
    while (L.ntimers && L.timers[0].at <= now) zs_loop_post(timer_remove(0));
#if !defined(__wasm__) && !defined(ZS_LIB)
    drain();
#endif
    if (L.qlen) return true;
    if (!L.ntimers && !L.waits) return false;
    sleep_until(L.ntimers ? L.timers[0].at : -1);
    return true;
}

// Task.run has finished: what still waits goes, uncalled, and the loop's memory is freed (a later
// Task.run starts afresh)
void zs_loop_close(void) {
    while (L.qlen) zs_clo_drop(queue_pop());
    while (L.ntimers) zs_clo_drop(timer_remove(L.ntimers - 1));
#if !defined(__wasm__) && !defined(ZS_LIB)
    for (zs_int n = 0; n < ZS_IRQ_COUNT; n++) zs_loop_irq_unwait(n);
    for (zs_int s = 0; s < (zs_int)signal_count; s++) zs_signal_unwait(s);
#endif
    if (L.queue) zs_free(L.queue);
    if (L.timers) zs_free(L.timers);
    L.queue = NULL;
    L.timers = NULL;
    L.qhead = L.qcap = L.tcap = 0;
}

// SIMD on a microcontroller: LLVM does a vector's operations lane by lane (with what DSP
// instructions the chip has), so a wide vector needs no more than a word's alignment
void *zs_alloc_wide(zs_int size) { return zs_alloc(size); }

// a task's coroutine frame (its locals across waits), freed through zs_free
void *zs_coro_alloc(zs_int size) { return zs_alloc(size); }

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
