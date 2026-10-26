#include "chip.h"

uint32_t port_sum(Port p) { return p.moder + p.otyper + (uint32_t)p.len + (p.buf ? 100u : 0u); }
