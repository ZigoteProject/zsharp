# Z#

**An ML-family language with F#'s syntax, compiled to native code.**

Z# is a functional language in the ML tradition: Hindley–Milner inference, algebraic data
types, exhaustive pattern matching, immutable values by default, modules, and effect handlers
in the type system. Its syntax and most of its features are F#'s, so it's written first for F#
developers, and for anyone who likes typed functional programming and wants it without a
runtime. It compiles through LLVM to one native binary: no garbage collector, no VM, nothing to
install. The same code serves 10,000 TCP connections on a laptop and fits a Cortex-M0 with
16 KB of RAM.

[The language](#the-language) · [Coming from F#](#coming-from-f) · [In numbers](#in-numbers) ·
[Systems programming](#systems-programming) · [Microcontrollers](#microcontrollers) ·
[Tooling](#tooling) · [Getting started](#getting-started) · [Documentation](#documentation)

```fsharp
type Shape =
  | Circle of radius: float
  | Rect of width: float * height: float

let area shape =
  match shape with
  | Circle r -> 3.14159 * r * r
  | Rect (w, h) -> w * h

/// An effect: operations a function may perform, and someone up the stack must handle.
effect Log =
  abstract note : string -> unit

/// Inferred: list<Shape> -> float / Log
let total shapes =
  Log.note $"{List.length shapes} shapes"
  shapes |> List.sumBy area

let main () =
  let t =
    handle total [ Circle 1.0; Rect (2.0, 3.0) ] with
    | Log.note msg, k ->
      println $"log: {msg}"
      k ()
  println $"total area {t}"
  0
```

`total` performs `Log`, and its type says so; the compiler inferred it. `main` handles it, and
`k ()` resumes `total` where it left off. A handler that resumes at its end compiles to a plain
function call, and the list is freed at its last use, by reference counting the compiler mostly
optimizes away.

## The language

- **ML at the core.** Types are inferred across whole functions, with let-polymorphism; type annotations are documentation. Unions and records are the data model, and a `match` that misses a case is a compile error that names it.
- **Functional by default.** Values are immutable, functions are curried, `|>` and `>>` compose them, and data is persistent: a rebuilt list or tree shares what didn't change, and reuses its own cells in place when nothing else holds them.
- **Effects instead of exceptions and dependency injection.** An effect declares operations; the type of a function shows which it performs (`parse : string -> Entry / Throw<string>`), and a handler decides what they do, as in Koka or OCaml 5. Tests swap the real terminal and disk for in-memory ones with no mocking library.
- **Low-level when you ask for it.** Sized integers, SIMD vectors, C-layout records, spans, and raw pointers inside `unsafe`, in the same language, under the same type checker.

## Coming from F#

The example at the top is F#, but for `effect`, `handle` and `main` (F# writes
`[<EntryPoint>] let main argv` and `printfn`). Most of what you know carries over; here is what does and doesn't, and [the guide's page for F# programmers](docs/guide/17-from-fsharp.md) has the rest.

### The same as F#

Indentation; `let`, `let rec` and `let mutable`; `|>`, `>>` and partial application; records and
`{ r with … }`; unions; `match` with guards, nested patterns and `as`; `function`; active
patterns; units of measure; `option`, `result`, `list`, `Map` and `Set`; `option { }`,
`result { }` and `task { }`; `$"…"` strings; list and array expressions and ranges
(`[ 1 .. 10 ]`, `[ 1 .. 2 .. 9 ]`, `[| 0 .. n |]`); `module`, `namespace` and `open`; members
with named and optional arguments; typed tuple parameters (`let f (a: int, b: string)`, one
parameter of type `int * string`); structural equality, comparison and printing; Hindley–Milner
inference.

### Different from F#

| F# | Z# |
|---|---|
| `printfn "%d" n`, `sprintf` | `println $"{n}"` and `$"…"`: interpolation only |
| `[<EntryPoint>] let main argv` | `let main () = …` returns the exit code; `Environment.args ()` gives the arguments |
| `int` is 32 bits | `int` is the machine word: 64 bits on a desktop, 32 on a Cortex-M. `i32`, `i64`, `u8`, … keep their size |
| `float`, `float32` | `f64`, `f32`; `float` still works, as a name for `f64` and as the conversion |
| integer overflow wraps | it panics; `[<Wrapping>]` on a function, or `Int.wrappingAdd`, wraps; `Int.checkedAdd` gives an `option`, `Int.saturatingAdd` stops at the type's bound |
| `null`, `opt.Value` | no null; read an `option` with `match` or `Option.defaultValue` |
| `failwith`, `raise`, `try … with` | return a `result` (`?` returns early), or perform `Throw`, which shows in the type and, as an exception does, disposes the `use` values it passes over (not yet one inside a `task { }` body); a panic is a bug and can't be caught |
| classes, interfaces, inheritance | records, unions and modules; members on records and unions; traits |
| `inline` with SRTP, `static member (+)` | `impl Add<T>`, resolved at compile time, no `inline` |
| `async { }`, which is cold, and `task { }`, which is hot | one `Task<'a>`, cold, written `task { }`, compiled to a state machine |
| arrays are shared and mutable | arrays are values with copy-on-write: `let mutable a`, then `a.[i] <- x`. `Buffer<'a>` is the shared kind |
| `mutable` record fields | none: `{ r with x = … }`, a `let mutable` record, or a `ref` field |
| a closure captures a `let mutable` as a hidden ref cell | it's an error: make the `ref` yourself |
| a `.fsproj` listing the files in order | a `zs.toml`; each file is a module named by its path, and nothing is listed |
| NuGet and the .NET library | C libraries through `import c`, and Z# packages by path or git (`zs add`) |
| `List.map (fun s -> s.Length) names` needs an annotation | it compiles: a lambda is typed after the call's other arguments |
| Expecto or xUnit, FsCheck, BenchmarkDotNet, coverlet | in Core and `zs`: tests as values, `testProperty` with `[<Derive(Arbitrary)>]`, `zs fuzz`, `zs bench`, `zs test --coverage` |
| type providers as compiler plugins (`JsonProvider<"weather.json">`) | `module Weather = import json "weather.json"`, and `import csv`, `sql`, `svd` and `c`: Z# source written from the file at compile time, which `zs provide` prints to keep ([the guide](docs/guide/18-type-providers.md)) |

### Stricter than F#

- **A `match` that misses a case doesn't compile,** and the error names the case: `match is not exhaustive; missing case: Dot`. Neither does a case that can never match. F# warns about both.
- **Integer overflow panics** at run time (`panic: integer overflow`), where F# wraps silently.
- **A data race doesn't compile:** `this function crosses threads, but it captures 'hits' : ref<int>, which can't be shared between threads; share state through Atomic, Mutex or Channel, or return a result per job`.
- **F# habits get errors that say what to write:** `there's no null: a missing value is None, of type option<'a>`. [tests/newcomer](tests/newcomer) has 34 of them, for the first mistakes of F# and C programmers.

### New in Z#

- **Effects in the type.** A function that can fail says so, and the compiler infers it: `parse : string -> Entry / Throw<string>`. Handlers also inject dependencies: a test runs the whole program against an in-memory terminal and disk, with no mocking library. Pure code compiles as if effects didn't exist.
- **Thread safety in the type.** `Array.Parallel.map` takes a `share<'a -> 'b>`: what the function captures must be immutable, or an `Atomic`, a `Mutex` or a `Channel`.
- **Traits instead of SRTP and interfaces,** resolved at compile time, with `dyn` values for mixed lists. `derive` writes impls by walking a type's fields, as `[<Derive(Json)>]` does.
- **Record fields with defaults:** with `type Config = { host: string = "localhost"; port: int = 8080 }`, the literal `{ port = 9000 }` is a whole `Config`.
- **Types for systems code:** `u8` to `u64`, `usize`, `f32x8`, `fixed<u8, 16>` arrays, `q15` and the other fixed-point numbers, `[<CLayout>]` records, `span<'a>`, and `ptr<'a>` inside `unsafe`.
- **Four kinds of function:** `'a -> 'b`; `share<'a -> 'b>`, which another thread may run; `callback<'a -> 'b>`, which C calls back; `fnptr<'a -> 'b>`, a bare C function pointer. The errors name the one you need ([the table](docs/guide/12-memory.md#which-reference-which-function)).

The tour is [examples/logstat](examples/logstat/README.md): a log summary tool written for F#
developers, with effects as dependency injection, tasks with timeouts, checked parallelism and
property tests.

## In numbers

| | |
|---|---|
| **Cortex-M, against C** | CRC-32 executes the same number of instructions as C. A `List.init \|> List.map \|> List.filter \|> List.sum` pipeline executes as many as C's hand-written loop (Cortex-M4, `-Os`). Flash is 0.2–0.6 KB larger. [Report](docs/reports/microcontrollers.md) |
| **Desktop, against C** | At C's speed or faster on 4 of 5 benchmarks. `binarytrees` takes 0.31 s and 26 MB, C 1.16 s and 34 MB. [Report](docs/reports/host.md) |
| **Against F# on .NET** | 3.9× faster on `binarytrees` and 3.7× on a red-black tree; F# uses 3.6–4.7× the memory on both. [Report](docs/reports/host.md) |
| **Real programs** | A JSON round trip (parse, typed decode, re-encode) in 1.3× C's time with 13% less memory; word counts, an interpreter, Dijkstra and SHA-256 at 1.5–3.5× C, the gaps measured and named. [Report](docs/reports/realworld.md) |
| **A server** | The [echo server](examples/echo/server.zs) held 10,000 connections for an hour: 33.1 million round trips, none failed, its memory flat at 26 MB. |
| **A program** | [logstat](examples/logstat/README.md) counts 1 million log lines (50 MB) in 0.72 s on one thread and 0.20 s on 16, from a 357 KB binary. |
| **Binary size** | A hello world is 16 KB on Linux x86-64, 13 KB stripped. |
| **The compiler** | 36,575 lines of Z# (`src/`, 2026-11-05: `wc -l` of the `.zs` files git tracks). When it replaced the F# compiler (27,815 lines then), a debug build of itself took 14.9 s from nothing (the F# compiler: 15.2 s) and 0.43 s after a one-function change; its own passes have since gone from 8.1 s to 3.7 s. [Report](docs/reports/self-hosting.md) |
| **The rest** | The library is 8,257 lines of Z# (`lib/`), the tests 9,872 in 386 files (`tests/`) and the examples 2,638 (`examples/`), counted the same way; the runtime is 6,388 lines of C (`runtime/rt.c` and `rt-embedded.c`). |

Desktop numbers come from an AMD Ryzen 7 PRO 8840U laptop running Linux x86-64, but for the two
binary sizes, built with `--release` on Ubuntu 24.04 and clang 23 on 2026-11-05; Cortex-M numbers
are instructions executed under QEMU, each program written in both languages. Each report gives
its method.

## Systems programming

### Memory without a garbage collector

The compiler inserts reference counting, then removes most of it, as Koka and Lean 4 do
(Perceus). A value is freed at its last use, a function that only reads a value borrows it with
no count traffic, and rebuilding a unique list or tree reuses its cells in place. Small unions
such as `option<int>` are never allocated, and a one-case union over a plain value is that value
(`type UserId = UserId of int` is an `int`). Arrays are values with copy-on-write, so a write to
a unique array happens in place, and `m <- HashMap.add k v m` updates the map in place too. Weak
references break cycles, arenas free in bulk, and raw pointers work inside `unsafe`.

| Program, Linux x86-64 | Z# | C | Rust | F# (.NET 10) |
|---|---:|---:|---:|---:|
| `binarytrees`, depth 18: millions of tiny trees | 0.31 s | 1.16 s | 1.61 s | 1.19 s |
| `rbtree`: 1 million inserts and lookups | 0.52 s | 0.58 s | 0.56 s | 1.90 s |
| `spectralnorm` 4000: matrix-vector products | 0.63 s | 0.66 s | 0.68 s | 0.79 s |
| `nbody`, 20 million steps | 1.02 s | 1.16 s | 0.69 s | 1.05 s |
| `fib` 42, with every `+` checked for overflow | 0.86 s | 0.49 s | 0.48 s | 0.67 s |
| Peak memory, `binarytrees` | 26 MB | 34 MB | 34 MB | 93 MB |

- **`fib`:** the cost of overflow checks. C compiled with them (`-ftrapv`) takes 0.86 s too.
- **`rbtree`:** Z# and F# run the same persistent tree (Okasaki's); C and Rust update one in place.
- **`binarytrees`:** small objects come from a pool that ThinLTO inlines into the program, where C calls `malloc` and `free` for every node.

The full tables, with Swift, Zig and OCaml, and how they could mislead: [docs/reports/host.md](docs/reports/host.md).

### C, both ways

`import c` reads a header with clang and brings its functions, structs, enums and `#define`s
across, with no bindings to write:

```fsharp
[<Link "raylib">]
import c "raylib.h"

let main () =
  InitWindow 800 450 "Z# + raylib"
  while not (WindowShouldClose ()) do
    BeginDrawing ()
    ClearBackground RAYWHITE
    DrawText "Hello from Z#" 10 10 20 DARKGRAY
    EndDrawing ()
  CloseWindow ()
  0
```

`module Ray = import c "raylib.h"` puts the header's names in a module instead (`Ray.InitWindow`),
each with its C signature as its doc, the library linked by `zs.toml`'s `[c]` section;
`zs provide c raylib.h` prints that binding as Z# to keep.

The other way, `[<Export>]` functions and `zs build --lib` make a static library (or a `.so`) and
its header:

```fsharp
[<CLayout>]
type Vec2 = { x: f32; y: f32 }

// the header declares: Vec2 vec_add(Vec2 p0, Vec2 p1);
[<Export "vec_add">]
let add (a: Vec2) (b: Vec2) : Vec2 = { x = a.x + b.x; y = a.y + b.y }
```

Structs pass by value as C passes them on every target, a microcontroller's included, C can call
back into Z# closures, and C can hold Z# values as counted handles. A Z# library for a chip is an
archive a C firmware links. Rust and Zig come through the same door:
[examples/rust](examples/rust/README.md) uses crates.io's `regex` and `sha2` from Z# and a Z#
library from Rust, and [examples/zig](examples/zig/README.md) Zig's cryptography from Z# and a Z#
library from Zig, each on an OS and on a Cortex-M4. More:
[the guide's chapter](docs/guide/09-c-interop.md).

### Tasks, threads and SIMD

- **Tasks:** `task { }` compiles to a state machine, so a wait allocates nothing: a task that waits 200,000 times makes the same 7 allocations as one that waits 10 times. Cancellation disposes what a task bound with `use`. TCP, UDP and Unix sockets wait on the event loop, and `Dns.lookup` looks a name up off the event loop's thread.
- **Threads:** a work-stealing pool (`Parallel.for`, `Array.Parallel.map`, …), `Atomic`, `Mutex` and `Channel`. What crosses threads is checked at compile time, so a data race doesn't compile, and only objects actually shared pay for atomic counts. Mandelbrot at 8000×8000 takes 2,213 ms on one thread and 243 ms on 16; C with pthreads, 2,070 ms and 245 ms.
- **SIMD:** portable vectors (`f32x8`, `u8x16`, …) with masks and shuffles, and x86-64 and arm64 intrinsics. Against C with AVX intrinsics: 65 ms against 63 for a dot product, 83 against 82 for n-body, 77 against 74 for a blur. The same source, on arm64 under qemu-user, is within 4% of C with NEON.

More: [tasks](docs/guide/13-tasks.md), [parallelism](docs/guide/14-parallel.md),
[SIMD](docs/guide/15-simd.md).

### Platforms

| Platform | Architectures | Build |
|---|---|---|
| Linux | x86-64, arm64 | native, or `--target aarch64-linux-musl` for a static binary |
| macOS | arm64, x86-64 | native, or `--target aarch64-macos` |
| Windows | x64, arm64 | native through mingw-w64, or `--target x86_64-windows-gnu` |
| Bare metal | Cortex-M4F, Cortex-M0 and M0+; the Nucleo-F401RE board | `--target cortex-m4`, `--target cortex-m0plus`, `--target nucleo-f401` |
| WebAssembly | wasm32, freestanding | `--target wasm32`, run by a 25-line Node host |

Cross builds link through `zig cc`, so there's no SDK or sysroot to install.

## Microcontrollers

Z# runs bare-metal on ARM Cortex-M, with no operating system and no C library. Core comes along
(lists, arrays, maps, strings, options, results, effects, `Mmio`); using Std, the part that needs
an OS (files, processes, sockets), is a compile error that says so, and a dependency that uses it
is named as the build starts.

```fsharp
type Mode =
  | Off
  | On
  | Blink of periodMs: int

/// The button cycles the modes: off, on, blinking twice a second, off.
let pressed (mode: Mode) =
  match mode with
  | Off -> On
  | On -> Blink 500
  | Blink _ -> Off

let gpioaBsrr = usize 0x40020018 // STM32F401 registers: constants, inlined where they're used
let gpiocIdr = usize 0x40020810

let bit (n: int) = u32 1 <<< u32 n

let setLed (lit: bool) = Mmio.write32 gpioaBsrr (if lit then bit 5 else bit 21)

/// B1 pulls PC13 low while it's pressed.
let buttonDown () = Mmio.read32 gpiocIdr &&& bit 13 = u32 0
```

This is part of [examples/mcu/nucleo-f401.zs](examples/mcu/nucleo-f401.zs): an LED with three
modes, a debounced button and a serial command line, for an ST Nucleo-F401RE. Built with
`zs build --target nucleo-f401 -Os`, the whole firmware is 5,156 bytes of flash. `Mode` is a plain
value that never touches the heap, and in the machine code `setLed` is one store instruction and
`buttonDown` one load. `zs run --target nucleo-f401` flashes it through
[probe-rs](https://probe.rs), and its `println` comes back over RTT.

[examples/nucleo](examples/nucleo) is the same firmware as a project and three tasks, the core
asleep between their events: the LED's, the button's (`Irq.wait` for its edge) and a shell's, fed
by USART2's interrupt handler through an `Spsc` and a `Signal`. `zs build` there builds it for the
board, and `zs test` tests its shell on the computer.

| Target | Chips | Heap | Tested on |
|---|---|---|---|
| `cortex-m4` | Cortex-M4F: STM32F4, nRF52, … | 64 KB | QEMU `mps2-an386` |
| `cortex-m0plus` | Cortex-M0 and M0+: RP2040, nRF51, STM32G0, … | 8 KB | QEMU `microbit`, 16 KB of RAM |
| `nucleo-f401` | the ST Nucleo-F401RE board (STM32F401RE) | 64 KB | QEMU `netduinoplus2`, the same memory map; output over RTT |

```sh
zs run examples/mcu/uart.zs --target cortex-m4      # type a line: a task waits for the UART's interrupt
zs build examples/mcu/uart.zs --target cortex-m4 -Os -o uart.elf
qemu-system-arm -M mps2-an386 -nographic -semihosting-config enable=on -kernel uart.elf
```

**Against C on the same chip.** Each program is written in both languages, the way each is
normally written ([bench/mcu](bench/mcu)). The ratios are instructions executed, Z# ÷ C, so below
1.00 Z# is faster:

| Program | M4 `-O2` | M4 `-Os` | M0 `-Os` | Flash, M4 `-Os`: Z# / C |
|---|---:|---:|---:|---:|
| `crc32`: CRC-32 of 4 KB, 10 times | 1.00 | 1.00 | 1.00 | 2,304 / 2,084 B |
| `fir`: a 32-tap filter over 1,024 `f32` samples | 1.06 | 1.12 | 1.01 | 2,564 / 2,356 B |
| `firq15`: the same filter in `q15` fixed point, against C in CMSIS-DSP's style | 1.05 | 1.43 | 1.49 | 3,012 / 2,364 B |
| `isort`: insertion sort of 512 `i32`, in place | 1.04 | 1.00 | 0.90 | 2,720 / 2,112 B |
| `pipeline`: `List.init 200 \|> map \|> filter \|> sum`, against a C loop | 1.26 | 1.00 | 1.28 | 2,348 / 2,024 B |
| `fib64`: recursion on Z#'s `int`, against C's `int64_t` | 0.62 | 0.72 | 0.57 | |
| `fib`: recursion on `i32`, every `+` checked | 1.15 | 1.25 | 1.47 | 2,356 / 2,032 B |
| `tokens`: a tokenizer state machine over 2 KB | 1.39 | 1.25 | 2.52 | 2,716 / 2,192 B |

- **Where the speed comes from:** `int` is the chip's 32-bit word; reading an array doesn't touch its reference count; bounds checks are proved once per loop; a pipeline of pure lambdas becomes one loop that builds no list; small unions are plain values, and an enum is one byte.
- **Where it's slower:** every `+` and `-` the compiler can't prove safe is checked for overflow, which C doesn't do (`fib`); `[<Wrapping>]` on a function turns the checks off. The tokenizer's tuples and checked arithmetic cost the most on the M0's few registers. At `-Os`, the bounds of a loop whose body is large (`firq15`'s, with its multiply-add inlined) aren't proved once for the loop, so each tap checks them.
- **RAM:** the programs built on lists and unions peak at 32 bytes of heap, and stack use is within 10% of C's on all but `isort` at `-O2`. A program that allocates nothing links no heap at all.
- **Also there:** interrupt handlers (`[<Interrupt "USART2">]`), `[<NoAlloc>]` and `--no-heap` (a compile error naming the chain that may allocate), `[<Bits>]` records for registers, `Cpu.critical` and the other intrinsics, and tasks on the runtime's loop with the core asleep between events.
- **Constants in flash:** a top-level array or list literal of numbers, bools or strings (a CRC table, a font, a list of commands) is a static object in the image, read in place: no startup code, no RAM, and a write to it copies it; so is a tree of union cases, and a record, tuple or plain union of constants is written into its global, tables and all. Arithmetic and conversions on literals are computed at compile time first, so a table of `Q15.ofFloat` values is one too, and a library built with `--lib`, which has no startup code, may hold such constants.
- **Tests on the chip:** `zs test firmware.zs --target cortex-m4` builds the file's `[<Tests>]` into one image and runs them under QEMU (`--target nucleo-f401` on the board through probe-rs, not yet run on one), each named as it passes; a property runs its cases there too, though a case that panics isn't shrunk and nothing is saved.
- **Fixed-point numbers:** `q7`, `q15` and `q31` in Core, saturating, with rounding products and `mulAdd`, as CMSIS-DSP has them: a `q15` filter is plain arithmetic (`firq15` above), printed as decimals with no float.
- **Placement:** `[<Section ".noinit">]` on a top-level `ref` or `Buffer` keeps it where a reset neither copies nor zeroes (a boot counter, a crash log), any other section name puts it where the linker script says (a DMA region), and `[<Align 32>]` aligns its storage; a constant table takes them too (`[<Section ".data">]` for one read from RAM). The storage is in the image: no startup code, and nothing allocated.
- **Weak references and arenas** work on a chip as on the host: an arena's blocks are an eighth of the heap each, and go back at once when its last object has died.
- **Not yet:** `[<Align>]` on a type, fixed-point arithmetic on SIMD vectors, RISC-V, and boards beyond the Nucleo-F401RE. The flagship has run under QEMU's STM32F405, not yet on the board itself. They're track M of the [roadmap](ROADMAP.md).

The registers can come from the chip's SVD file: `import svd ("stm32f401-part.svd", only = "GPIOA,RCC")` gives a module per peripheral with each register a `[<Bits>]` record ([examples/mcu/nucleo-f401-svd.zs](examples/mcu/nucleo-f401-svd.zs) is the firmware written that way, compiled to the same accesses).

More: [the guide's chapter](docs/guide/11-microcontrollers.md),
[the measurements](docs/reports/microcontrollers.md).

## Tooling

One `zs` binary holds the compiler and its tools.

| Command | What it does |
|---|---|
| `zs new`, `zs build`, `zs run`, `zs check` | projects in a `zs.toml`, with path and git dependencies (versions by minimal version selection, a `[c]` section for C sources); builds cached by module, and a build server that keeps the compiler warm |
| `zs add`, `zs remove`, `zs tree`, `zs vendor` | a dependency written into `zs.toml` and fetched, or taken out; the dependencies as resolved; copied into `vendor/`; `--offline` makes a fetch an error. `zs.lock` hashes each git dependency's files, a `[workspace]` resolves its packages into one lock, and a package's `internal/` modules are its own |
| `zs build --release` | optimized, with ThinLTO; `--profile-generate` and `--profile-use` for PGO |
| `zs build -g` | DWARF for gdb and lldb: breakpoints on lines; strings, records and plain unions shown as values, lists, arrays, trees and refs through their objects (`print *xs`); `-g --release` keeps the lines in an optimized build. On Linux, a panic's backtrace names the Z# functions, with or without `-g` |
| `zs test` | tests as values, each in its own process; expect tests that `zs test --update` rewrites; `--doc` runs the examples in `///` comments; `--stress 10m` runs them at random on every core for that long; `--target cortex-m4` runs them in one image under QEMU (`--target nucleo-f401` on the board through probe-rs, not yet run on one) |
| `zs bench` | `bench` values timed with a median and a confidence interval, a change from the last saved run reported; `testFaster` for a performance claim |
| `zs test --coverage` | the lines run and not run per file, and `coverage.lcov` for `genhtml` |
| properties | `testProperty "name" (fun (xs: list<int>) -> …)`: cases drawn with `Arbitrary` (derived for your types), a failure shrunk to a smallest case and shown with its seed; `prop { }` draws as it goes, and `Prop.model` checks a system against a model with a sequence of commands |
| `zs fuzz` | a property under libFuzzer, guided by coverage; a crash shrunk and saved for `zs test` to replay first |
| `zs doctor` | what builds need (clang 23 or later, zig, libclang, …), found or not, and how to get what's missing |
| `zs fmt`, `zs doc` | one canonical format; Markdown docs from `///` comments |
| `zs provide`, `import json "weather.json"` | type providers ([the guide's chapter](docs/guide/18-type-providers.md)): the types of a JSON sample, a CSV file, a SQL schema and its queries, a chip's SVD file or a C header, declared from the file when the program is compiled and checked against it; `zs provide` prints the module to keep instead; a `zs-provider-<name>` on PATH is one of your own |
| `zs lsp`, `zs mcp` | a language server (types on hover, rename, code actions, allocation hints per line) and an MCP server for AI agents (`check`, `type_at`, `definition`, `explain`, `build`, `run`, …) |

Editors: the [Zed extension](editors/zed), the [VS Code extension](editors/vscode), the
[Rider plugin](editors/rider), and the [tree-sitter grammar](editors/tree-sitter-zsharp) for the others.

## Getting started

Each [release](https://github.com/ZigoteProject/zsharp/releases) has an archive per platform
(`linux`, `macos` or `windows`, on `x86_64` or `aarch64`): the compiler, its library and its
runtime in one folder. Unpack it and put the folder on `PATH`:

```sh
tar -xzf zs-0.6.2-linux-x86_64.tar.gz
export PATH="$PWD/zs-0.6.2-linux-x86_64:$PATH"
```

With `zs` on your PATH (in the dev container below, it's `bin/zs`):

```sh
zs doctor                              # what builds need: clang 23 or later, zig, libclang, …
zs run hello.zs                        # build and run a debug build
zs build hello.zs --release            # optimized
zs new greeter                         # a project: zs.toml, src/main.zs and a test
zs build blink.zs --target cortex-m4 -Os -o blink.elf
```

The compiler is written in Z# and builds itself, starting from an earlier release (stage 0,
pinned in `dev`). The dev container has everything it needs: clang and LLVM 23, zig, QEMU, gdb
and valgrind. It needs [podman](https://podman.io).

```sh
./dev ./test.sh                        # build the compiler, then run every test
./dev bin/zs run examples/simple.zs    # run a program with it
```

`./dev` fetches stage 0 from this repository's
[GitHub releases](https://github.com/ZigoteProject/zsharp/releases) on first use. To build
without the container, see [the guide](docs/guide/01-getting-started.md).

## Documentation

| To | Read |
|---|---|
| learn the language | [the guide](docs/guide/README.md): 18 chapters, one [for F# programmers](docs/guide/17-from-fsharp.md); the tests compile and run their examples but for fragments, errors shown on purpose and those that need a C library, a chip or a data file |
| read whole programs | [examples/logstat](examples/logstat/README.md), the [Nucleo-F401RE firmware](examples/nucleo/README.md), [ten Advent of Code puzzles](examples/aoc/README.md), [grep, a JSON pretty-printer and `tail -f`](examples/tools/README.md), and the rest of [examples](examples) |
| look up a function | [the library reference](docs/reference/README.md), generated by `zs doc` |
| know why it's designed this way | [DESIGN.md](DESIGN.md) |
| check a number | [docs/reports](docs/reports): the host, real programs, microcontrollers, effects and self-hosting; and the posts on the strongest results: [Perceus on a Cortex-M](docs/posts/perceus-on-a-cortex-m.md), [atomic counts only where threads meet](docs/posts/atomic-counts-only-where-threads-meet.md), [SIMD next to C](docs/posts/simd-next-to-c.md) |
| see what's next | [ROADMAP.md](ROADMAP.md), and [docs/proposals](docs/proposals/README.md) for designs under discussion |
| find your way around the compiler | [src/ARCHITECTURE.md](src/ARCHITECTURE.md) |

## Status

Z# is pre-1.0: the language and the library still change between releases, each change listed in
[CHANGELOG.md](CHANGELOG.md) with what to rewrite. Done: the language through effect handlers,
the compiler in Z#, which builds itself to the same bytes, and the ports to macOS, Windows and
Linux arm64.

**Released:** 0.6.2 (2026-10-30), the first public release, with firmware for a microcontroller
board as its flagship. Of its archives, Linux x86-64's suite passes natively, Linux arm64's under
QEMU and Windows x64's under Wine; the macOS builds and arm64 Windows haven't run on a real
machine yet, and the flagship has run under QEMU, not on its board.

**0.7.0 (unreleased), as of 2026-11-05:** type providers (a JSON sample, a CSV file, a SQL
schema and its queries, a chip's SVD file, a C header, and providers of your own); properties,
`zs fuzz`, `zs bench`, coverage, `zs test --stress` and tests on a chip; constants in flash,
placement, fixed-point numbers, and weak references and arenas on a chip; debug info for every
value, `-g` on optimized builds and Z# names in a panic's backtrace; workspaces, `zs add`,
`zs remove`, `zs tree`, `zs vendor` and a lock that hashes its git dependencies; UDP, name
lookup, ISO 8601 dates and `Int`'s checked, saturating and bit operations; F#'s ranges and typed
tuple parameters, and a `use` disposed when a throw passes it, but for one in a `task { }` body.
Two memory errors 0.6.2 had are fixed: a value lent to a read or a call that another of its
arguments freed first (`tests/buffer_lend.zs`), and a weak reference to an object the runtime
frees itself taking a later object at the same address for it (`tests/weak_runtime.zs`). The
compiler is fuzzed in every run of the suite and stressed in every run on Linux
(`tests/fuzz.sh`, `tests/stress.sh`), and what that found is fixed: a stack overflow is a panic,
and programs as long or as deep as generated code makes them build (an array literal of 50,000
elements, parentheses nested 10,000 deep). No archive of it is built yet. Its suite passes on
Linux x86-64 but for three checks that depend on the machine it last ran on (`tests/pgo.sh`,
`bench/host`'s `fib`, `tests/debug/lldb.sh`); the two that failed in CI's dev container on
2026-11-05 (`tests/debug/kinds.zs`'s DWARF check under LLVM 23, and the tree-sitter grammar on a
typed `_` parameter) are fixed. Linux arm64's under QEMU and Windows x64's under Wine, which 0.6.2
ran, haven't been run for it.

**Left of 0.7's plan:** its first item, which needs machines, not code: the suites on the five CI
runners, the archives on clean machines, and the flagship on its board. Also `[<Align>]` on a
type, `Seq` pipelines as one loop, fixed point's vector forms, a new seed for `tests/fuzz.sh` on each run (it takes 1 unless
`ZS_FUZZ_SEED` says otherwise), and the stress run over the pool, tasks and `Alt` under
ThreadSanitizer. The [roadmap](ROADMAP.md) has the details.

## License

Z# is under the [MIT license](LICENSE). It includes:

| Component | Where | License |
|---|---|---|
| [xxHash](https://github.com/Cyan4973/xxHash) | `packages/xxhash/c` | [BSD 2-Clause](packages/xxhash/c/LICENSE) |
| [wepoll](https://github.com/piscisaureus/wepoll) | `runtime/wepoll` | [BSD 2-Clause](runtime/wepoll/LICENSE) |
| [tree-sitter](https://github.com/tree-sitter/tree-sitter)'s parser headers | `editors/tree-sitter-zsharp/src/tree_sitter` | [MIT](editors/tree-sitter-zsharp/src/tree_sitter/LICENSE) |

`import c` opens the system's libclang (LLVM, Apache 2.0 with LLVM exceptions) at run time; none
of LLVM is shipped.
