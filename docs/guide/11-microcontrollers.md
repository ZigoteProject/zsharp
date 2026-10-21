# 11. Microcontrollers

Z# runs bare-metal on ARM Cortex-M chips, with no operating system and no C library. The same
language and standard library are there, with a runtime small enough for a few kilobytes of
RAM. On compute code, the generated code is as fast as C's
([the measurements](../reports/microcontrollers.md)).

| Target | Chips | Tested on |
|---|---|---|
| `cortex-m4` | Cortex-M4F: STM32F4, nRF52, … (single-precision FPU) | QEMU `mps2-an386` |
| `cortex-m0plus` | Cortex-M0/M0+: RP2040, nRF51, STM32G0, … | QEMU `microbit` (16 KB RAM) |

```sh
zs build blink.zs --target cortex-m4 -Os -o blink.elf
qemu-system-arm -M mps2-an386 -nographic -semihosting-config enable=on -kernel blink.elf
```

**What a build contains:**
- **Startup:** the vector table, a reset handler that sets up RAM, enables the FPU and starts SysTick, and `main`.
- **Heap:** a fixed-size heap inside the image, 64 KB on `cortex-m4` and 8 KB on `cortex-m0plus`. When a program exits, it prints its heap peak and stack use.
- **Output:** `println` and panics go through semihosting, the debug channel to a debugger or QEMU. A panic stops the chip and reports exit status 134.
- **Not available:** Std, the part of the library that needs an operating system: `Console`, `Environment`, `IO` (`File`, `Directory`, `Path`) and `Diagnostics`. Using it is a compile error that says so. Core (lists, arrays, maps, strings, `Mmio`, …) is all there.

## Hardware registers

`Mmio.read32`/`write32` and `Mmio.read8`/`write8` access memory-mapped registers. They are volatile accesses, which the optimizer keeps exactly as written. Together with the bitwise operators, they're enough for drivers. Here is the UART driver from `examples/mcu/uart.zs`:

```fsharp
let uart = usize 0x40004000                       // constants: no code, no RAM
let data = uart
let state = uart + usize 4
let ctrl = uart + usize 8

let init () = Mmio.write32 ctrl (u32 1)           // transmit enable

let putByte (b: u8) =
  while Mmio.read32 state &&& u32 1 <> u32 0 do   // wait while the transmit buffer is full
    ()
  Mmio.write32 data (u32 b)

let putString (s: string) =
  for i in 0 .. String.length s - 1 do
    putByte (String.byte s i)
```

A constant like `uart` is inlined, so `Mmio.write32 ctrl …` compiles to a store to an immediate address. Values computed at startup (an `Array.init` table, say) live in RAM.

## Writing fast, small code

The compiler does most of the work. These habits help it:
- **`int` is 32 bits here:** use it for counters and indices. Use `i64` only for values that need it, since 64-bit arithmetic costs two instructions per operation.
- **Arrays:** declare an array you fill or update `let mutable` and write `a.[i] <- x`. Writes happen in place, and inside a loop the compiler checks only once that the array isn't shared.
  - **Bounds checks:** in a `for` loop that reads `a.[i]`, `a.[i + c]` or `a.[c - i]`, they are checked once before the loop instead of on every iteration.
- **Pipelines:** a chain like `List.init n f |> List.map g |> List.filter p |> List.sum` with pure lambdas is compiled into one loop that builds no list. So is one from a list or an array, or into `List.iter`.
- **Small unions:** `option<int>`, enums and state machines with small number fields are plain values, never heap-allocated, and an enum is a single byte.
- **Printing:** `println $"…{x}…"` prints the pieces one after another, without building the string.
- **`-Os`:** for size. At `-O2`, the compiler may unroll loops and version them for speed.

**What still costs more than C:**
- **Overflow checks:** arithmetic is checked for overflow, so `+`, `-` and `*` that the compiler can't prove safe cost an extra instruction or two. For hashes and checksums, mark the function `[<Wrapping>]`, or use `Int.wrappingAdd` and friends.
- **Heap data:** lists, strings and recursive unions are heap-allocated, with reference counting. Each object has a 4-byte count, then a 4-byte length (strings, arrays) or tag (a union with several cases that have fields), plus 8 bytes of allocator header. `[]`, `None` and other cases without fields are never allocated.

## Timing code

`Runtime.ticks ()` reads a cycle counter, the chip's SysTick. Under QEMU with `-icount`, its counts are deterministic and proportional to instructions executed.

```fsharp
let t0 = Runtime.ticks ()
let r = work ()
println $"took {Runtime.ticks () - t0} ticks"
```

`bench/mcu/run.sh` builds each benchmark program in both Z# and C, runs them under QEMU, and prints a table of instructions, flash, heap and stack.
