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
- **Not available:** Std, the part of the library that needs an operating system: `Console`, `Environment`, `IO` (`File`, `Directory`, `Path`), `Diagnostics`, `Threading` (`Mutex`, `Channel`, `Alt`, `Parallel`) and `Net` (`Tcp`, `Udp`, `Unix`). Using it is a compile error that says so (`Ch.make`, `Dns.lookup` and `DateTime.utcNow` are an unknown function there instead), and a dependency that uses it is named when the build starts: `package 'logger' uses File, part of Std, which needs an operating system; a build for cortex-m4 has none, so it can't depend on this package`. Core (lists, arrays, maps, strings, `Mmio`, `Weak`, `Arena`, …) is all there.
- **Debug info:** `-g` alone builds the code as written, at `-O0`, for stepping; on the Cortex-M0+ and wasm32, whose `-O0` can't lower Z#'s tail calls, it stays the optimized build, with its lines. `-g` with `-Os` or `-O2` is that optimized build with its lines ([Tools](10-tools.md#debugging)).

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

A constant like `uart` is inlined, so `Mmio.write32 ctrl …` compiles to a store to an immediate address. A table written as a literal is a constant too: a top-level array or list of numbers, bools or strings, or a tree of a union's cases, is an object in the image, its bytes in flash, and a record or a tuple of constants is written into its global. They nest (an array of records, a record holding an array), with no startup code and nothing on the heap (`tests/static.zs`, `tests/mcu/static.zs`), but for a record holding a list, which is computed at startup. A write to such an array copies it first. Values computed at startup (an `Array.init` table, say) live in RAM.

`--no-heap` and `[<NoAlloc>]` take reading these tables only in part yet. An element of an array of numbers, strings or records of numbers used in place (`String.length words.[i]`), a `for` over an array of numbers or of such records, a record's or a tuple's numbers and arrays, and the first cell of a list or a tree pass. A list or a tree read past its first cell (a walk, `List.length`, a nested match), a string bound to a name (`let w = words.[1]`, a `for`'s variable), and a record or a tuple holding a string, alone or in an array, are refused, as dropping what may be the last reference: `main drops a C it holds, which may free it`.

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
- **Sharing with the program:** a handler interrupts the program as another thread would, so what it reaches must be `Share`, checked when compiling: `interrupt handler 'tick' uses the top-level value 'count' : ref<int>, which a handler can't share with the program`. It shares through an `Atomic` (a number, a bool or a char) or an `Spsc<'a>`, a queue of fixed capacity with one producer and one consumer: `Spsc.push` and `Spsc.pop` copy a value and claim a slot, neither waiting nor locking. Two handlers that push to one queue are safe too: a pop finds nothing while the value it would take is still being pushed (by a handler the pop interrupted, or one interrupted by it), and a push finds the queue full while the slot it would fill is still being popped. On a Cortex-M0, which has no atomic instructions, an `Atomic`'s operations mask interrupts around them.

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

`examples/mcu/uart.zs` is such a driver, run under QEMU with its serial as the input, and [examples/nucleo](../../examples/nucleo) a firmware of three tasks for a real board: an LED, a button and a serial shell.

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

- **What passes:** numbers, records, tuples and small unions, `option<int>`, parameters it only reads (strings, arrays and lists it borrows), `Mmio`, `Cpu`, `Irq`, `Atomic`, `Spsc.push` and `pop`, `Signal.set`, C functions, a fused pipeline, a literal string, a panic. And writing a Buffer's element when its type isn't counted (a number, a bool, a record of those): the write borrows the Buffer as a read does, so a parameter's, a field's, an element's or a top-level Buffer is written in place and nothing is freed.
- **What doesn't:** building an object (a string, a list's cell, an array, a closure that captures), dropping a reference that may be the last (a parameter it owns), writing an array something else may hold (it's copied first), and calling a function value, whose code the check can't see. A Buffer's write is refused when it drops what it overwrites (a `Buffer<string>`'s element may be the last reference to its string), and when the Buffer may go with the write: one a call gave, or one taken out of a value the write frees (`(Option.get o).[0] <- 7`), on any path of a match or an if.
- **Printing:** a literal string, or a string interpolated, passes; a number interpolated (`println $"{n}"`) builds its text, a small string, so it doesn't.
- **Where:** checked on the code after Z#'s optimizations, so the verdict is the same at `-Os` and `-O2`; inlining can change it, and the chain says what changed. A `[<NoAlloc>]` function the program never calls isn't in that code, so it isn't checked. `-g` alone and `--coverage` keep the code as written, so there a function that passes a lambda to a library's higher-order function (`Array.fold`, `List.iter`) can be refused where `-O2` accepts it.
- **Interrupt handlers** and `Cpu.critical`'s bodies are checked the same way, without the attribute.

**`--no-heap`** checks the whole program, its startup values included, and builds the image with no heap at all: the exit report has only the stack. A top-level value computed at startup into the heap is an error naming it.

```sh
zs build firmware.zs --target cortex-m0plus --no-heap -Os -o firmware.elf
```

## Memory with an address

A top-level constant table, `Buffer.create n x` or `ref x` with constant arguments can say where its storage goes. `[<Section ".noinit">]` (or any section named `.noinit…`, as the boards' linker scripts take them) puts a ref or a Buffer in memory the reset handler neither copies nor zeroes, so it holds what the last run left: a boot counter, a crash log, validated by a magic word before it's trusted. What it holds must be plain values (numbers, bools, chars, records and unions of those): a string or other object there would point into memory the reset left, and a constant table would never be loaded, so those are errors. Any other name goes where the board's linker script puts that section (a DMA region, a second SRAM); on a chip, a ref's or Buffer's storage in a section the script doesn't name is copied from a flash image at startup. A constant table alone in a section of its own is read-only, and the linker keeps it in flash; one in a section that also holds a ref or Buffer would be RAM never loaded, and one in `.bss…` would be zeroed, so those are errors. A ref or Buffer in `.bss…` must start at zero, which the reset leaves there, and one in flash (`.text…`, `.rodata…`) is an error; the board's own `.vectors` (the vector table, which starts the image) and `.ARM…` take nothing. `[<Align 32>]` aligns the storage as a DMA controller or a cache line asks. A section's name is letters, digits, `.`, `_` and `$`. On a function, on a value computed at startup, or with an alignment that isn't a power of two from 8 to 4096, the attribute is an error that says what it takes. The storage is in the image and nothing is allocated, so it passes `--no-heap`; startup only writes a `.noinit` ref's header or copies that flash image, both on a chip alone, and a chip's library (`--lib`) has no startup for them, so there a placed value must need neither.

```fsharp
[<Section ".noinit">]
let magic = ref (u32 0)

[<Section ".noinit">]
let boots = ref 0

[<Section ".noinit"; Align 32>]
let frame = Buffer.create 1536 (u8 0)

let countBoot () =
  if magic.Value <> u32 0xB007C0DE then           // after power-on the memory is noise
    magic.Value <- u32 0xB007C0DE
    boots.Value <- 0
  boots.Value <- boots.Value + 1                  // after a reset, the last run's count plus one

[<Section ".data">]
let sine = [| 0; 49; 97; 142 |]   // a table read from RAM, for a hot loop on a chip with flash wait states
```

A push past a placed Buffer's room moves its contents to the heap and leaves the storage. `tests/mcu/noinit.zs` counts boots this way across resets under QEMU, on both chips. `[<Align>]` on a type isn't there yet.

## Weak references and arenas

`Weak` and `Arena` work on a chip as on a computer ([Memory](12-memory.md)), over the chip's
heap. The weak references' table is heap memory, and so are an arena's blocks: an eighth of the
heap each (4 KB at most), bumped through, and given back once the arena's last object has died.
Neither is an object, so the exit report's `live` counts the program's own. A block an arena
gave back is kept for the next arena, and the heap takes those back before it runs out
(`tests/mcu/weak.zs`, `tests/mcu/arena.zs`, `tests/mcu/arena_rounds.zs`, both chips). With no
system allocator under the heap, `Runtime.mallocs ()` counts every object the heap gave.

## Fixed point

A chip without an FPU, as the Cortex-M0+ is, does DSP in fixed point: `q7`, `q15` and `q31` in
`Numerics` ([Basics](02-basics.md#numbers)) are numbers in [-1, 1) held in an `i8`, `i16` or
`i32`, the formats of CMSIS-DSP and the chips' saturating instructions. Each is its integer's
size and allocates nothing; `+`, `-`, `*` and `/` saturate at the ends of the range instead of
panicking (a division by zero still panics); and `Q15.mulAdd a b acc` is a filter's step,
rounded once. `Q7` and `Q15` compute in 32 bits, the chips' word, and `Q15.ofFloat` on a
literal is a constant, so a table of them is in flash:

```zsharp
open Numerics

/// A smoothing filter's taps: constants, in flash on a chip.
let taps = [| Q15.ofFloat 0.25; Q15.ofFloat 0.5; Q15.ofFloat 0.25 |]

/// The filter at sample i: a quarter of each neighbour and half of itself.
[<NoAlloc>]
let smoothAt (x: array<q15>) (i: int) =
  let mutable acc = Q15.zero
  for k in 0 .. 2 do
    acc <- Q15.mulAdd taps.[k] x.[i + k] acc
  acc

let main () =
  let x = [| Q15.ofFloat 0.0; Q15.ofFloat 0.5; Q15.ofFloat 0.9; Q15.ofFloat 0.9; Q15.ofFloat -1.0 |]
  println $"{smoothAt x 0} {smoothAt x 1} {smoothAt x 2}"
  println $"{Q15.max + Q15.ofFloat 0.5} {Q15.min * Q15.min} {Q15.raw (Q15.ofFloat 0.5)} {sizeof<q15>}"
  0
```

```text
0.47501 0.80002 0.42502
0.99997 0.99997 16384 2
```

`bench/mcu/firq15.zs`, a 32-tap `q15` filter, executes 1.05 times the instructions of C in
CMSIS-DSP's style on the Cortex-M4 and 1.01 times on the Cortex-M0+, at `-O2`
([the measurements](../reports/microcontrollers.md)). The vector forms (a `q15` multiply on
every lane of an `i16x8`) aren't there yet.

## Writing fast, small code

The compiler does most of the work. These habits help it:
- **`int` is 32 bits here:** use it for counters and indices. Use `i64` only for values that need it, since 64-bit arithmetic costs two instructions per operation.
- **Arrays:** declare an array you fill or update `let mutable` and write `a.[i] <- x`. Writes happen in place, and inside a loop the compiler checks only once that the array isn't shared.
  - **Bounds checks:** in a `for` loop that reads `a.[i]`, `a.[i + c]` or `a.[c - i]`, they are checked once before the loop instead of on every iteration.
- **Pipelines:** a chain like `List.init n f |> List.map g |> List.filter p |> List.sum` with pure lambdas is compiled into one loop that builds no list. So is one from a list or an array, or into `List.iter`.
- **Small unions:** `option<int>`, enums and state machines with small number fields are plain values, never heap-allocated, and an enum is a single byte.
- **Printing:** `println $"…{x}…"` prints the pieces one after another, without building the whole string; a number's text is still a small string of its own.
- **`-Os`:** for size. At `-O2`, the compiler may unroll loops and version them for speed.

**What still costs more than C:**
- **Overflow checks:** arithmetic is checked for overflow, so `+`, `-` and `*` that the compiler can't prove safe cost an extra instruction or two. For hashes and checksums, mark the function `[<Wrapping>]`, or use `Int.wrappingAdd` and friends; `Int.saturatingAdd` and `Int.checkedAdd` are the other answers, and `Int.leadingZeros`, `popCount` and `rotateLeft` the bit operations, each an instruction where the chip has one (`CLZ`, the M4's saturating `QADD`).
- **Heap data:** lists, strings and recursive unions are heap-allocated, with reference counting. Each object has a 4-byte count, then a 4-byte length (strings, arrays) or tag (a union with several cases that have fields), plus 8 bytes of allocator header. `[]`, `None` and other cases without fields are never allocated.

## Timing code

`Runtime.ticks ()` reads a cycle counter, the chip's SysTick. Under QEMU with `-icount`, its counts are deterministic and proportional to instructions executed.

```fsharp
let t0 = Runtime.ticks ()
let r = work ()
println $"took {Runtime.ticks () - t0} ticks"
```

`bench/mcu/run.sh` builds each benchmark program in both Z# and C, runs them under QEMU, and prints a table of instructions, flash, heap and stack.

## Tests on the chip

`zs test file.zs --target cortex-m4` builds a file's `[<Tests>]` into one image and runs it on
the chip's QEMU board, or on a real board through probe-rs (`--target nucleo-f401`), so code that
depends on the chip (its 32-bit `int`, its runtime, its instructions) is tested where it runs:

```zsharp
open Testing

/// The CRC-8 of the bytes (polynomial 0x07), as a sensor's frames carry it.
let crc8 (bytes: list<u8>) =
  let step (crc: u8) (b: u8) =
    let mutable c = crc ^^^ b
    for _ in 1 .. 8 do
      c <- if c &&& u8 0x80 <> u8 0 then (c <<< u8 1) ^^^ u8 0x07 else c <<< u8 1
    c
  List.fold step (u8 0) bytes

let ascii (s: string) = List.init (String.length s) (fun i -> String.byte s i)

[<Tests>]
let tests =
  testList "crc8" [
    test "of nothing" (fun () -> assert (crc8 [] = u8 0))
    test "of 123456789" (fun () -> assert (crc8 (ascii "123456789") = u8 0xF4))
    testProperty "is 0 with the crc appended" (fun (bytes: list<u8>) -> crc8 (bytes @ [ crc8 bytes ]) = u8 0)
  ]
```

On the Cortex-M0+ under QEMU's micro:bit:

```text
$ zs test crc.zs --target cortex-m0plus
ok   crc8/of nothing
ok   crc8/of 123456789
ok   crc8/is 0 with the crc appended
3 passed, 0 failed
```

- **One process:** a chip has no processes, so the tests run one after another in the image (Core's `Testing.runAll`). A failing test's panic ends the run: `zs test` names the test with what it printed, and the tests after it don't run.
- **Properties** run their cases there, with nothing recorded or shrunk; a test that returns a task runs on the chip's event loop.
- **Not yet:** path filters (every test in the file runs) and `--stress` aren't taken with `--target`; `--coverage` is an error, since the chip has no file to write the counts to; and `--target wasm32` has no board to run on.

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

## Registers from the chip's SVD file

The vendor's SVD file describes every peripheral and register; `import svd` declares them, a
module per peripheral with each register a `[<Bits>]` record whose defaults are its reset value,
and `read`, `write` and `modify` as the file allows ([type providers](18-type-providers.md)):

```fsharp
import svd ("stm32f401-part.svd", only = "GPIOA,GPIOC,RCC,USART2")

let init () =
  Rcc.Ahb1enr.modify (fun r -> { r with gpioaen = true; gpiocen = true })
  Gpioa.Moder.modify (fun r -> { r with moder5 = u8 1 }) // PA5 as an output
  Usart2.Cr1.write { ue = true; te = true; re = true }
```

A wrong field or a write to a read-only register is a compile error, and the code compiles to
the same volatile accesses as `Mmio.write32` with the address by hand:
[examples/mcu/nucleo-f401-svd.zs](../../examples/mcu/nucleo-f401-svd.zs) is the Nucleo firmware
written this way.
