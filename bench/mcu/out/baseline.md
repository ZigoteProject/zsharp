**cortex-m4** (mps2-an386 under QEMU, -O2; instructions = ticks × 39.9992; static RAM includes the 65536-byte heap array)

| benchmark | result (Z# / C) | instructions Z# | instructions C | Z# / C | flash Z# | flash C | heap peak Z# | stack Z# | stack C |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| crc32 | 3953169762 / 3953169762 | 2253315 | 1474611 | 1.53 | 7488 | 6140 | 4240 | 228 | 204 |
| fib | 46368 / 46368 | 1350453 | 1171737 | 1.15 | 6788 | 5628 | 112 | 424 | 424 |
| fib64 | 46368 / 46368 | 2475790 | 2193396 | 1.13 | 6836 | 5688 | 120 | 612 | 808 |
| fir | -2301 / -2301 | 1632567 | 145037 | 11.26 | 8960 | 7036 | 4368 | 228 | 212 |
| isort | 1511 / 1511 | 3597408 | 450991 | 7.98 | 8596 | 6676 | 2184 | 228 | 308 |
| pipeline | 660000 / 660000 | 958541 | 14160 | 67.69 | 8256 | 5708 | 6424 | 228 | 196 |
| tokens | 149335 / 149335 | 256875 | 33599 | 7.65 | 8584 | 6608 | 2208 | 228 | 204 |

**cortex-m4** (mps2-an386 under QEMU, -Os; instructions = ticks × 40.0000; static RAM includes the 65536-byte heap array)

| benchmark | result (Z# / C) | instructions Z# | instructions C | Z# / C | flash Z# | flash C | heap peak Z# | stack Z# | stack C |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| crc32 | 3953169762 / 3953169762 | 2253360 | 2580560 | 0.87 | 3336 | 2160 | 4240 | 256 | 224 |
| fib | 46368 / 46368 | 1350480 | 1143120 | 1.18 | 2776 | 2108 | 112 | 424 | 416 |
| fib64 | 46368 / 46368 | 2475840 | 1968360 | 1.26 | 2808 | 2152 | 120 | 612 | 608 |
| fir | -2301 / -2301 | 1632600 | 262200 | 6.23 | 4300 | 2432 | 4368 | 256 | 224 |
| isort | 1511 / 1511 | 3861200 | 599520 | 6.44 | 3832 | 2188 | 2184 | 256 | 216 |
| pipeline | 660000 / 660000 | 940840 | 28160 | 33.41 | 3880 | 2100 | 6424 | 256 | 216 |
| tokens | 149335 / 149335 | 253720 | 37720 | 6.73 | 4020 | 2268 | 2208 | 256 | 216 |

**cortex-m0plus** (microbit under QEMU, -O2; instructions = ticks × 62.5000; static RAM includes the 8192-byte heap array)

| benchmark | result (Z# / C) | instructions Z# | instructions C | Z# / C | flash Z# | flash C | heap peak Z# | stack Z# | stack C |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| crc32 | C doesn't build |
| fib | 46368 / 46368 | 1350438 | 1096750 | 1.23 | 5672 | 4880 | 112 | 424 | 424 |
| fib64 | 46368 / 46368 | 3076000 | 2775938 | 1.11 | 5704 | 4920 | 120 | 612 | 988 |
| fir | C doesn't build |
| isort | 1511 / 1511 | 6588250 | 521375 | 12.64 | 7872 | 5648 | 2184 | 312 | 312 |
| pipeline |  / 660000 | 0 | 13625 | 0.00 | 7108 | 4988 | 6424 | 304 | 256 |
| tokens | 149335 / 149335 | 369875 | 32812 | 11.27 | 7656 | 5888 | 2208 | 304 | 264 |

**cortex-m0plus** (microbit under QEMU, -Os; instructions = ticks × 62.5000; static RAM includes the 8192-byte heap array)

| benchmark | result (Z# / C) | instructions Z# | instructions C | Z# / C | flash Z# | flash C | heap peak Z# | stack Z# | stack C |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| crc32 | C doesn't build |
| fib | 46368 / 46368 | 1350438 | 1021688 | 1.32 | 2904 | 2264 | 112 | 424 | 416 |
| fib64 | 46368 / 46368 | 3076000 | 2625875 | 1.17 | 2952 | 2328 | 120 | 612 | 796 |
| fir | C doesn't build |
| isort | 1511 / 1511 | 7048750 | 600000 | 11.75 | 4208 | 2496 | 2184 | 336 | 288 |
| pipeline |  / 660000 | 0 | 22125 | 0.00 | 4040 | 2268 | 6424 | 336 | 288 |
| tokens | 149335 / 149335 | 366250 | 37125 | 9.87 | 4252 | 2428 | 2208 | 336 | 288 |

