# Perceus on a Cortex-M: functional code at C's instruction count

Z# is a functional language with F#'s syntax and no garbage collector: the compiler inserts the
reference counts, then optimizes most of them away. That's Perceus, the design Koka and Lean
use. We wanted to know whether it holds up on the smallest machines Z# builds for, a Cortex-M4
and a Cortex-M0+ with 16 KB of RAM, against C on the same chip.

## The comparison

Seven programs, each written twice, as each language would normally write it: the C version
with arrays and loops, the Z# version with lists, unions and pipelines where that's natural
([bench/mcu](../../bench/mcu)). Both run under QEMU with `-icount`, so the count of
instructions executed is exact and repeats; the table is Z#'s count over C's, so below 1.00 Z#
executes fewer.

| Program | M4 `-O2` | M4 `-Os` | M0 `-Os` | Flash, M4 `-Os` (Z# / C) |
|---|---:|---:|---:|---:|
| `crc32`: CRC-32 of 4 KB, 10 times | 1.00 | 1.00 | 1.00 | 2,304 / 2,084 B |
| `isort`: insertion sort of 512 `i32`, in place | 1.04 | 1.00 | 0.90 | 2,720 / 2,112 B |
| `fir`: a 32-tap filter over 1,024 `f32` | 1.06 | 1.12 | 1.01 | 2,564 / 2,356 B |
| `pipeline`: `List.init \|> map \|> filter \|> sum` (C: a loop) | 1.26 | 1.00 | 1.28 | 2,348 / 2,024 B |
| `fib`: recursive, on `i32` | 1.15 | 1.25 | 1.47 | 2,356 / 2,032 B |
| `tokens`: a tokenizer's state machine | 1.39 | 1.25 | 2.52 | 2,716 / 2,192 B |

Most of it is at C's count. The two outliers have one cause each: `fib` is overflow checks (Z#
checks every `+` it can't prove safe; C's overflow is undefined behaviour), and `tokens` on the
M0 is checked arithmetic and a returned tuple on a core with few registers. Every program is
0.2 to 0.6 KB of flash bigger, which is the panic paths and their messages.

## Where the counts went

The first measurement, before any of this work, had `pipeline` at **67.7×** C and `isort` at
8×. What closed the gaps:

- **Borrowing.** A function that only reads a parameter gets it without a count: no increment on
  the way in, no decrement and test on the way out. Array reads in a loop touch no count at all.
- **Reuse.** When a cell's count is 1 at its last use, Perceus builds the next value in the same
  memory. The tokenizer's state is rebuilt on every byte, in place.
- **Fusion.** A pipeline of pure maps and filters over a list becomes one loop that builds no list.
  That's `pipeline` going from 37× (without fusion) to 1.00× at `-Os`.
- **Copy-on-write that LLVM can see through.** An array is a value; writing to one that's shared
  copies it first. The test for that is inlined and hoisted out of loops, so `isort` writes in
  place.
- **A native `int`.** Z#'s `int` is the machine word, 32 bits on these chips. `fib` on C's
  `int64_t` executes 1.4 to 2 times what Z#'s `int` version does: that's what 64 bits cost on a
  32-bit core, not a faster addition.

## Memory you can count

On a chip, the heap is a fixed region in the image: 64 KB on the M4, 8 KB on the M0+. An object
costs 16 bytes of overhead there (an 8-byte header, 8 bytes of allocator header), and the
programs above peak at 32 bytes of heap (the printed result), apart from the arrays they're
about. Stack use is within 10% of C's but for one program.

Release 0.6.2 makes that something the compiler checks rather than something you measure:

- `[<NoAlloc>]` on a function is a compile error if it, or anything it calls, may allocate or
  free, checked on the code after Perceus's optimizations, so a fused pipeline or a borrowed
  parameter passes. Interrupt handlers are checked the same way, implicitly.
- `--no-heap` builds a firmware image with no heap at all.
- Tasks run on the chip (`task { }`, `Task.sleep` on SysTick, `Irq.wait` for an interrupt line):
  a task's frame is allocated once when it starts, and its waits allocate nothing that stays
  (`live` is 0 at exit in `tests/mcu/task.zs`).

The flagship for the release is firmware for a real board, an ST Nucleo-F401RE: an LED, a button
and a serial shell, as three tasks, its registers as `[<Bits>]` records
([examples/nucleo](../../examples/nucleo)).

## How this could mislead

- **Instructions aren't cycles.** QEMU counts instructions; on a real chip, loads, branches and
  flash wait states cost differently. Ratios on one chip are a good guide; absolute times aren't.
- **Two compilers.** Z#'s IR goes through clang 23, the C programs through Zig's clang 21. Part of
  `isort`'s 0.90× on the M0 is that difference.
- **`pipeline` is fusion.** Stages that aren't pure lambdas don't fuse, and then the list is built.

The full report, with RAM and the history of each number, is
[docs/reports/microcontrollers.md](../reports/microcontrollers.md). To run it:
`./dev bash bench/mcu/run.sh cortex-m4 -Os`.
