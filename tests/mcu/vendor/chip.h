// A vendor's header, as CMSIS's are: it compiles only for the chips it's written for, so
// import c must read it as the chip's compiler does (the chip's triple, freestanding)
#include <stddef.h>
#include <stdint.h>
#if !defined(__ARM_ARCH_7EM__) && !defined(__ARM_ARCH_6M__)
#error "this header is for a Cortex-M4 or a Cortex-M0+"
#endif

typedef struct {
    uint32_t moder;
    uint32_t otyper;
    size_t len;
    void *buf;
} Port;

uint32_t port_sum(Port p);
