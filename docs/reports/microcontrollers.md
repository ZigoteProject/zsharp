# Z# on microcontrollers: performance and memory against C

**Question:** can Z# be used for microcontroller firmware, and how does it compare with C on
the same chip, in speed, flash and RAM?

**Answer:** yes, for bare-metal Cortex-M.
- **Speed:** on compute code (CRC, filters, sorting, list pipelines) Z# executes the same number of instructions as C, or within a few percent. On a 64-bit workload it's faster, because its default `int` follows the chip's word.
- **What remains slower:** overflow checks on recursive arithmetic (`fib`, 1.15–1.47×), and a byte-level state machine on the Cortex-M0 (2.5–2.9×).
- **Flash:** Z# programs are 0.2–0.6 KB larger than the C ones at `-Os`.

## Setup

| | |
|---|---|
| Chips | Cortex-M4F (QEMU `mps2-an386`, 4 MB/4 MB) and Cortex-M0 (QEMU `microbit`, 256 KB flash, 16 KB RAM) |
| Compilers | Z#: `zs build --target cortex-m4\|cortex-m0plus`. C: clang 22 through `zig cc`, same CPU flags. Both at `-O2` and at `-Os` |
| Runtime | Both link `runtime/rt-embedded.c` (startup, semihosting output, SysTick). The C programs use it only for printing and timing |
| Heap | Z#: 64 KB on the M4, 8 KB on the M0. C: 1 KB, since C doesn't need one |
| Speed measure | Instructions executed in the timed part only (printing excluded). QEMU runs with `-icount`, so virtual time advances per instruction, and SysTick reads it. A calibration loop with a known instruction count gives the factor (40 per tick on the M4, 62.5 on the M0). Results are deterministic |
| Sizes | `llvm-size`: flash = text + data; heap peak from the allocator; stack peak by stack painting |
| Measured | the compiler at commit `63850ee` |
| Reproduce | `./dev bash bench/mcu/run.sh cortex-m4 -O2` (or `-Os`, or `cortex-m0plus`) |

## The programs

Each is written twice, as each language would normally write it (`bench/mcu/*.zs` and `*.c`).
Both versions print the same result.

| Program | Work | What it stresses |
|---|---|---|
| `crc32` | CRC-32 (bitwise) of a 4 KB buffer, 10 times | bit operations, byte arrays, nested loops |
| `fib` | recursive Fibonacci(24) on `i32` | calls, checked arithmetic |
| `fib64` | the same on Z#'s default `int` against C's `int64_t` | the cost of word size |
| `fir` | a 32-tap FIR filter over 1024 `f32` samples | float arrays, bounds checks |
| `isort` | insertion sort of 512 `i32`, in place | array writes (copy-on-write), bounds checks |
| `tokens` | a tokenizer state machine over 2 KB (a union state) | unions, small structs, branches |
| `pipeline` | `List.init 200 \|> map \|> filter \|> sum`, 20 times (C: a loop) | idiomatic functional code |

## Results

**Z# ÷ C, instructions executed** (1.00 means the same; below 1, Z# is faster):

| Program | M4 `-O2` | M4 `-Os` | M0 `-O2` | M0 `-Os` |
|---|---:|---:|---:|---:|
| crc32 | **1.00** | **1.00** | 1.02 | **1.00** |
| fib | 1.15 | 1.25 | 1.23 | 1.47 |
| fib64 | **0.62** | **0.72** | **0.49** | **0.57** |
| fir | 1.06 | 1.12 | **1.01** | **1.01** |
| isort | 1.04 | **1.00** | **0.97** | 1.12 |
| pipeline | 1.26 | **1.00** | 1.48 | 1.28 |
| tokens | 1.38 | 1.25 | 2.86 | 2.52 |

**Flash, bytes** (Z# / C, including the shared runtime):

| Program | M4 `-Os` | M0 `-Os` |
|---|---:|---:|
| crc32 | 2304 / 2084 | 2496 / 2268 |
| fib | 2356 / 2032 | 2532 / 2208 |
| fir | 2564 / 2356 | 4428 / 4092 |
| isort | 2720 / 2112 | 3080 / 2440 |
| pipeline | 2348 / 2024 | 2524 / 2212 |
| tokens | 2716 / 2192 | 2980 / 2372 |

**RAM:**
- **Stack:** Z#'s peak is within 10% of C's, except `isort` at `-O2` (436 bytes against 308). `fib64` needs half of C's (416 against 808), since its `int` is 32-bit.
- **Heap:**
  - Programs using lists or unions now have a 32-byte heap peak (the printed result string).
  - Array programs keep their array on the heap: 4,144 bytes for `crc32`'s 4 KB buffer, where C uses a static array.
  - Every Z# heap object has 8 bytes of header plus 8 bytes of allocator header.

## From the first measurement to now

The first run used Z# as it was, with 64-bit `int`. On the Cortex-M4 at `-O2`:

| Program | First run | Now | What closed the gap |
|---|---:|---:|---|
| crc32 | 1.53 | 1.00 | borrowed array reads (no reference count per read), native-width `int`, allocator facts for LLVM |
| fir | 11.26 | 1.06 | FPU enabled (a toolchain bug), borrowed reads, `!range` on lengths (LLVM drops impossible overflow and bounds checks), loop versioning (bounds proved once per loop) |
| isort | 7.98 | 1.04 | an inlined copy-on-write test, the test hoisted out of loops, native-width `int` |
| tokens | 7.65 | 1.38 | moves out of mutable variables (the state stays unique and is reused), unions without heap data as plain values |
| pipeline | 67.69 | 1.26 | borrowed parameters (no RC on the closure per element), a compact allocator, list fusion (one loop, no lists) |
| fib | 1.15 | 1.15 | unchanged: overflow checks |

On the way, the measurements found gaps that blocked ordinary firmware code, and these were fixed:
- **Missing syntax:** there were no bitwise operators and no hex or binary literals.
- **No register access:** there was no way to read or write a hardware register; that's what `Mmio.*` is for now.
- **Tuple hashing:** it could panic on overflow.

## What is left, and why

- **`fib`, 1.15–1.47×:** every `+` and `-` that the compiler can't prove safe is overflow-checked (DESIGN decision 4). C has none of these checks; overflow there is undefined behaviour.
- **`tokens` on the Cortex-M0, 2.5–2.9×:** the state machine's checked arithmetic and its returned tuple cost more on the M0, which has fewer registers and simpler instructions. Core-level inlining, which phase 5 has added since, didn't change it.
- **`fir` at `-Os`, 1.12×:** loop versioning is limited to small loops at `-Os`. Its check runs once per outer iteration, and at `-Os` LLVM doesn't fold it.
- **Flash, +0.2–0.6 KB:** this comes from overflow and bounds panic paths, their message strings, and the copy-on-write copy function. That suits devices with 32 KB or more of flash. On 16 KB parts it matters, and a smaller panic path (one shared handler, short codes) would recover some.
- **Not measured yet:** interrupt latency (Z# has no interrupt handlers yet), real hardware (QEMU counts instructions, not cycles or wait states), and RISC-V.

## How the comparison could mislead

- **Instructions are not cycles:** loads, branches and flash wait states cost differently on a real chip. Ratios between two programs on the same chip are a good guide; absolute times aren't.
- **`pipeline`:** the Z# version is idiomatic, and fusion turns it into a loop. The C version is the loop a C programmer would write. Without fusion the Z# version was 37× C, so code that fusion doesn't cover yet (for example `List.map` feeding another list) still allocates.
- **`fib64`:** this compares Z#'s default `int` (32-bit on these chips) with C's `int64_t`. It shows the benefit of a native-width `int`, not a faster 64-bit addition.
