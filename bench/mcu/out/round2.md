**cortex-m4** (mps2-an386 under QEMU, -O2; instructions = ticks × 39.9992; static RAM includes the 65536-byte heap array)

| benchmark | result (Z# / C) | instructions Z# | instructions C | Z# / C | flash Z# | flash C | heap peak Z# | stack Z# | stack C |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| crc32 | 3953169762 / 3953169762 | 1495250 | 1474611 | 1.01 | 7292 | 6160 | 4208 | 196 | 204 |
| fib | 46368 / 46368 | 1350453 | 1171737 | 1.15 | 6632 | 5648 | 88 | 424 | 424 |
| fib64 | 46368 / 46368 | 1350453 | 2193396 | 0.62 | 6632 | 5708 | 96 | 424 | 808 |
| fir | -2301 / -2301 | 145037 | 145037 | 1.00 | 8412 | 7056 | 4328 | 204 | 212 |
| isort | 1511 / 1511 | 469431 | 450991 | 1.04 | 9340 | 6696 | 2152 | 436 | 308 |
| pipeline | 660000 / 660000 | 784304 | 14160 | 55.39 | 7664 | 5728 | 3216 | 220 | 196 |
| tokens | 149335 / 149335 | 52719 | 33599 | 1.57 | 7396 | 6628 | 2152 | 204 | 204 |

**cortex-m4** (mps2-an386 under QEMU, -Os; instructions = ticks × 40.0000; static RAM includes the 65536-byte heap array)

| benchmark | result (Z# / C) | instructions Z# | instructions C | Z# / C | flash Z# | flash C | heap peak Z# | stack Z# | stack C |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| crc32 | 3953169762 / 3953169762 | 1495280 | 2580560 | 0.58 | 3384 | 2148 | 4208 | 224 | 224 |
| fib | 46368 / 46368 | 1350480 | 1143120 | 1.18 | 2604 | 2096 | 88 | 424 | 416 |
| fib64 | 46368 / 46368 | 1350480 | 1968360 | 0.69 | 2604 | 2140 | 96 | 424 | 608 |
| fir | -2301 / -2301 | 423080 | 262200 | 1.61 | 3884 | 2420 | 4328 | 240 | 224 |
| isort | 1511 / 1511 | 469480 | 599520 | 0.78 | 4776 | 2176 | 2152 | 464 | 216 |
| pipeline | 660000 / 660000 | 770600 | 28160 | 27.37 | 3336 | 2088 | 3216 | 248 | 216 |
| tokens | 149335 / 149335 | 52680 | 37720 | 1.40 | 3060 | 2256 | 2152 | 232 | 216 |

**cortex-m0plus** (microbit under QEMU, -O2; instructions = ticks × 62.5000; static RAM includes the 8192-byte heap array)

| benchmark | result (Z# / C) | instructions Z# | instructions C | Z# / C | flash Z# | flash C | heap peak Z# | stack Z# | stack C |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| crc32 | C doesn't build |
| fib | 46368 / 46368 | 1350438 | 1096750 | 1.23 | 5516 | 4864 | 88 | 424 | 424 |
| fib64 | 46368 / 46368 | 1350438 | 2775938 | 0.49 | 5516 | 4904 | 96 | 424 | 988 |
| fir | C doesn't build |
| isort | 1511 / 1511 | 503875 | 521375 | 0.97 | 7112 | 5632 | 2152 | 320 | 312 |
| pipeline | 660000 / 660000 | 1029875 | 13625 | 75.59 | 6460 | 4972 | 3216 | 272 | 256 |
| tokens | 149335 / 149335 | 100000 | 32812 | 3.05 | 6308 | 5872 | 2152 | 280 | 264 |

**cortex-m0plus** (microbit under QEMU, -Os; instructions = ticks × 62.5000; static RAM includes the 8192-byte heap array)

| benchmark | result (Z# / C) | instructions Z# | instructions C | Z# / C | flash Z# | flash C | heap peak Z# | stack Z# | stack C |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| crc32 | C doesn't build |
| fib | 46368 / 46368 | 1350438 | 1021688 | 1.32 | 2748 | 2248 | 88 | 424 | 416 |
| fib64 | 46368 / 46368 | 1350438 | 2625875 | 0.51 | 2748 | 2312 | 96 | 424 | 796 |
| fir | C doesn't build |
| isort | 1511 / 1511 | 503875 | 600000 | 0.84 | 3736 | 2480 | 2152 | 352 | 288 |
| pipeline | 660000 / 660000 | 1014188 | 22125 | 45.84 | 3440 | 2252 | 3216 | 304 | 288 |
| tokens | 149335 / 149335 | 99750 | 37125 | 2.69 | 3292 | 2412 | 2152 | 312 | 288 |

