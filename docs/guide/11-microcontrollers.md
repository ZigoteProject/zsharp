# 11. Microcontrollers

Z# runs bare-metal on ARM Cortex-M chips, with no operating system and no C library. The same
language and standard library are there, with a runtime small enough for a few kilobytes of
RAM. On compute code, the generated code is as fast as C's
([the measurements](../reports/microcontrollers.md)).

| Target | Chips | Tested on |
|---|---|---|
| `cortex-m4` | Cortex-M4F: STM32F4, nRF52, … (single-precision FPU) | QEMU `mps2-an386` |
| `cortex-m0plus` | Cortex-M0/M0+: RP2040, nRF51, STM32G0, … | QEMU `microbit` (16 KB RAM) |
| `nucleo-f401` | the ST Nucleo-F401RE board: an STM32F401RE, a Cortex-M4F with 512 KB of flash and 96 KB of RAM | QEMU `netduinoplus2` (an STM32F405, the same memory map) |

```sh
zs build blink.zs --target cortex-m4 -Os -o blink.elf
qemu-system-arm -M mps2-an386 -nographic -semihosting-config enable=on -kernel blink.elf
```

`zs run --target cortex-m4` does both. A core's name builds for its QEMU board; a board's name
(`nucleo-f401`) builds for the real board's memory map, and `zs run` flashes it with
[probe-rs](https://probe.rs) over the board's debug probe (the Nucleo's ST-Link), shows its output
and returns its exit status:

```sh
zs run examples/mcu/nucleo-f401.zs --target nucleo-f401 -Os
```

A project for a chip says so in its `zs.toml`, and then `zs build` and `zs run` need no
`--target`:

```toml
[package]
name = "blink"
main = "src/main.zs"
target = "cortex-m4"

[target.cortex-m4]
heap = "16K"
```

**What a build contains:**
- **Startup:** the vector table, a reset handler that sets up RAM, enables the FPU and starts SysTick, and `main`.
- **Heap:** a fixed-size heap inside the image, 64 KB on `cortex-m4` and `nucleo-f401` and 8 KB on `cortex-m0plus` unless `[target.<chip>]` sets `heap`. When a program exits, it prints its heap peak and stack use. C's `malloc`, `free`, `calloc` and `realloc` are there too, over the same heap, for C, Rust or Zig code linked in.
- **Output:** `println` and panics go through semihosting, the debug channel to a debugger or QEMU. A panic stops the chip and reports exit status 134.
- **Output on a real board:** RTT, a ring in RAM that the probe reads while the chip runs (probe-rs, a J-Link or OpenOCD find it by its symbol, `_SEGGER_RTT`); nothing to wire, no pins or clocks taken. A board with no probe attached never waits: output that doesn't fit in the ring (1 KB) is dropped, and an exit or a panic leaves the core asleep, since semihosting's breakpoint without a debugger would fault.
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

**Registers as records:** a `[<Bits>]` record is one unsigned integer whose fields are ranges of its bits, so a register is written with its fields' names instead of masks:

```fsharp
[<Bits 32>]
type Cr1 =                                        // USART control register 1
  { sbk: bool = false                             // bit 0
    re: bool = false                              // bit 1 (fields fill from bit 0)
    te: bool = false
    ps: Parity = Even                             // an enum: the bits its cases need
    [<Width 4>] div: u8 = 0                       // four bits of a u8
    [<Bit 13>] ue: bool = false }                 // at bit 13; the bits between are a gap

let write (r: Cr1) = Mmio.write32 cr1 (Bits.toU32 r)
let read () : Cr1 = Bits.ofU32 (Mmio.read32 cr1)

write { ue = true; te = true; re = true }         // one store of a constant
write { read () with sbk = false }                // a load, an and, a store: the gaps kept
```

- **Fields:** a `bool` is one bit, an enum the bits its cases need, `u8` to `u64` their size or `[<Width n>]` bits; `[<Bit n>]` places one, and the next follows it. Fields left out of a literal take their defaults, so a register's reset value is its defaults.
- **Values:** reading a field is a shift and a mask; writing one too wide for its bits panics, as an overflow does; an enum field read from bits that name no case panics. Equality, ordering and hashing are the integer's (gaps included), and the record prints with its fields.
- **The integer:** `Bits.toU32` and `Bits.ofU32` (and 8, 16 and 64) convert at the record's width, `Bits.raw` gives a `u64`. To C, a `[<Bits>]` record is its integer.

## Interrupts

A function marked `[<Interrupt …>]` is the handler of an interrupt line: the hardware calls it, between two instructions of the program, when the line fires.

```fsharp
let presses = Atomic.make 0                       // a count both sides change
let rx: Spsc<u8> = Spsc.create 64                 // from the handler to the program

[<Interrupt "UARTRX0">]                           // by the board's name, or [<Interrupt 0>]
let onReceive () =
  Spsc.push rx (u8 (Mmio.read32 uartData)) |> ignore   // false when full: the byte is dropped

[<Interrupt 8>]
let onTimer () = Atomic.add presses 1 |> ignore

let main () =
  Irq.enable 0
  Irq.enable 8
  while true do
    match Spsc.pop rx with
    | Some b -> handle b
    | None -> ()
  0
```

- **Which line:** a number, a device's name from the board's table (`runtime/boards/mps2-an386.irq`, `microbit.irq`), or a core exception: `HardFault`, `NMI`, `SVCall`, `PendSV`, … (CMSIS's names) and `SysTick`, which runs at the end of each of SysTick's periods (2^24 cycles, or until a sleeping task's deadline: the runtime keeps SysTick for `Runtime.ticks` and the tasks' timers). A handler takes and returns `unit`, performs nothing, and is only for a chip.
- **Lines:** `Irq.enable n` and `Irq.disable n` turn a line on and off in the interrupt controller; `Irq.pend n` sets it pending, as its device would, so a handler can be tested with no device. A line without a handler is disabled the first time it fires.
- **The processor's instructions:** `Cpu.wfi ()` sleeps until an interrupt (a loop with nothing to do waits there), `Cpu.dmb`, `dsb` and `isb` are barriers, `Cpu.wfe` and `sev` wait for and signal events, and `Cpu.disableInterrupts` and `enableInterrupts` mask and unmask them. `Cpu.critical (fun () -> …)` runs its body with interrupts masked and gives its value, for a change a handler mustn't see halfway; one inside another is fine.
- **No heap in a handler:** a handler is `[<NoAlloc>]` (below), since the allocator isn't reentrant, and so is `Cpu.critical`'s body.
- **Sharing with the program:** a handler interrupts the program as another thread would, so what it reaches must be `Share`, checked when compiling: `interrupt handler 'tick' uses the top-level value 'count' : ref<int>, which a handler can't share with the program`. It shares through an `Atomic` (a number, a bool or a char) or an `Spsc<'a>`, a queue of fixed capacity with one producer and one consumer: `Spsc.push` and `Spsc.pop` copy a value and move an index, neither waiting nor locking. On a Cortex-M0, which has no atomic instructions, an `Atomic`'s operations mask interrupts around them.

## Tasks

The same `task { }` and `Task` functions as on a computer run on a chip, on the runtime's event loop. A task waits for a timer, an interrupt or another task; with nothing to run, the core sleeps (`wfi`) until the next deadline or interrupt.

```fsharp
let blink (ms: int) =
  task {
    while true do
      toggleLed ()
      do! Task.sleep ms                              // SysTick wakes the core at the deadline
  }

/// The next byte received, waiting for the receive interrupt when none is there.
let rec getByte () : Task<u8> =
  task {
    if Mmio.read32 uartState &&& rxFull = u32 0 then
      do! Irq.wait 0                                 // UARTRX0: asleep until a byte comes
      return! getByte ()
    else
      Mmio.write32 uartIntClear (u32 2)              // this byte's interrupt is done
      return u8 (Mmio.read32 uartData)
  }

let main () =
  Task.run (Task.both (blink 500) (echo ())) |> ignore
  0
```

`examples/mcu/uart.zs` is such a driver, run under QEMU with its serial as the input.

- **Time:** `Task.sleep ms` counts SysTick's cycles at the board's clock: 25 MHz on QEMU's `mps2-an386`, 16 MHz on the micro:bit and on the Nucleo-F401RE after reset. Firmware that changes the clock (its PLL) calls `Runtime.setClock hz`. `Task.timeout`, `race`, `both`, `all` and `Task.scope` work as on a computer.
- **Interrupts:** `Irq.wait n` enables line `n` and goes on once it fires. The runtime's handler disables the line again, so the task goes on with it quiet: clear the device's flag before waiting again. One task waits on a line at a time.
- **A handler of the program's** owns its line, so no task waits for it: it hands what it read to an `Spsc` and calls `Signal.set`, which never waits or allocates, and a task waits with `do! Signal.wait s`. A set with nobody waiting stays set.
- **No Z# code runs in the runtime's handlers:** they mark the line or the signal, and the loop runs the waiting task in the program's context, where the heap is consistent.
- **Memory:** a task's frame (what lives across its waits) is allocated when the task starts. Waiting allocates nothing that stays (`live=0` in the exit report after thousands of waits), and a `--no-heap` program can't have tasks.
- **Not on a chip:** `Task.spawn` and `Task.blocking` need threads and `Task.waitFor` file descriptors, so reaching one is a compile error naming the chain: `Task.spawn needs a thread, and cortex-m4 has none: run the task on this loop with let! (main -> serve -> Task.spawn)`.
- **Cooperative:** a task runs until it waits, so one that computes for 10 ms delays the others by 10 ms; handlers still run. What must answer in microseconds is a handler.

## Code that doesn't touch the heap

Z# allocates where it needs to (a string, a closure, a list's cells), and firmware needs to know where. `[<NoAlloc>]` on a function makes it a compile error for the function, or anything it calls, to allocate or free:

```fsharp
[<NoAlloc>]
let reply (n: int) : int = report n + 1
```

```text
main.zs:2: error: reply is [<NoAlloc>], but reply -> describe builds a string
```

- **What passes:** numbers, records, tuples and small unions, `option<int>`, parameters it only reads (strings, arrays and lists it borrows), `Mmio`, `Cpu`, `Irq`, `Atomic`, `Spsc.push` and `pop`, `Signal.set`, C functions, a fused pipeline, a literal string, a panic.
- **What doesn't:** building an object (a string, a list's cell, an array, a closure that captures), dropping a reference that may be the last (a parameter it owns), writing an array something else may hold (it's copied first), and calling a function value, whose code the check can't see.
- **Where:** checked on the code after Z#'s optimizations, so the verdict is the same at `-Os` and `-O2`; inlining can change it, and the chain says what changed.
- **Interrupt handlers** and `Cpu.critical`'s bodies are checked the same way, without the attribute.

**`--no-heap`** checks the whole program, its startup values included, and builds the image with no heap at all: the exit report has only the stack. A top-level value computed at startup into the heap is an error naming it.

```sh
zs build firmware.zs --target cortex-m0plus --no-heap -Os -o firmware.elf
```

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

## C on a chip

C interop works on a chip as on a host, with the chip's calling convention (AAPCS: structs by value
in core registers and on the stack, and on the hard-float Cortex-M4 floats and small float structs
in float registers).
- **Calling C:** `import c` and `[<Link "driver.c">]` work as on a host; `import c` reads a header as the chip's compiler does (a vendor's header sees the chip it's for), and the C sources are compiled for the chip and linked into the image. C on a chip has no C library, as is usual for firmware: vendor drivers, CMSIS and DSP code are fine, and `malloc` and `free` are the runtime's (from the Z# heap), but `printf` isn't there. `size_t` is `usize` on every target.
- **Rust and Zig:** a `no_std` Rust crate or a freestanding Zig library, built for the chip as a static library, links the same way (`[c.cortex-m4]` in `zs.toml`); `examples/rust` and `examples/zig` run under QEMU, both ways.
- **A Z# library in a C firmware:** `zs build lib.zs --lib --target cortex-m4 -o libsensor.a` makes an archive and its header (`libsensor.h`), with the runtime but no startup: the firmware has its vector table, reset handler and `main`, and links the archive with its own toolchain. A library's `[<Export>]` functions can't use top-level values computed at startup, since there is none.
- **What the library asks of the firmware:** three functions, each with a default the firmware replaces by defining its own: `void zs_write(const char *p, size_t n)` takes the library's output (dropped by default: a debugger's semihosting isn't always there), `void zs_stop(int code)` stops after a panic (by default a trap, into the firmware's HardFault handler; `zs_set_panic_hook` runs before it) and `int64_t zs_ticks(void)` is `Runtime.ticks ()` (the DWT cycle counter on a Cortex-M4, 0 on a Cortex-M0+).
- **Callbacks:** a `callback<F>` C calls only where it was passed, in the main code or in the same interrupt handler, as on a host it's called only on the thread that passed it; a `callback<share<F>>` C may call anywhere.

`tests/cexport/bare.c` is such a firmware, run under QEMU on both chips.

## Freestanding WebAssembly

`--target wasm32` is the same bare-metal build for a WebAssembly host (a browser, Node, an engine
embedded in a program) instead of a chip: no Std, a 1 MB heap inside the module.

```sh
zs build hello.zs --target wasm32 -o hello.wasm
node run-wasm.mjs hello.wasm                    # beside zs; runtime/ in a checkout
```

- **Imports:** output, exit and `Runtime.ticks ()` come from the host as `zs.write (ptr, len)` (bytes in the module's memory), `zs.exit (code)` (it must not return: throw) and `zs.ticks ()`. A module imports only those it uses. `run-wasm.mjs` is the whole host, about twenty lines.
- **Exports:** `memory`, `_start` (runs `main`, then calls `zs.exit`) and each `[<Export>]` function, with WebAssembly's C ABI: a `[<CLayout>]` record by a pointer into memory, returned through a pointer the caller passes first. `--lib` builds a module with no `main` and no `_start`.
- **With C:** `[<Link "lib.c">]` sources are compiled for WebAssembly and linked in, and `--lib -o lib.a` makes an archive and its header for a C program built for WebAssembly (`zig cc -target wasm32-freestanding`), whose `main` the runtime's `_start` runs.
