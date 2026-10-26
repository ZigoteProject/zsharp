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
`[<EntryPoint>] let main argv` and `printfn`). Most of what you know carries over; here is what does and doesn't.

### The same as F#

Indentation; `let`, `let rec` and `let mutable`; `|>`, `>>` and partial application; records and
`{ r with … }`; unions; `match` with guards, nested patterns and `as`; `function`; active
patterns; units of measure; `option`, `result`, `list`, `Map` and `Set`; `option { }`,
`result { }` and `task { }`; `$"…"` strings; list and array expressions; `module`, `namespace`
and `open`; members with named and optional arguments; structural equality, comparison and
printing; Hindley–Milner inference.

### Different from F#

| F# | Z# |
|---|---|
| `printfn "%d" n`, `sprintf` | `println $"{n}"` and `$"…"`: interpolation only |
| `[<EntryPoint>] let main argv` | `let main () = …` returns the exit code; `Environment.args ()` gives the arguments |
| `int` is 32 bits | `int` is the machine word: 64 bits on a desktop, 32 on a Cortex-M. `i32`, `i64`, `u8`, … keep their size |
| `float`, `float32` | `f64`, `f32`; `float` still works, as a name for `f64` and as the conversion |
| integer overflow wraps | it panics; `[<Wrapping>]` on a function, or `Int.wrappingAdd`, wraps |
| `null`, `opt.Value` | no null; read an `option` with `match` or `Option.defaultValue` |
| `failwith`, `raise`, `try … with` | return a `result` (`?` returns early), or perform `Throw`, which shows in the type; a panic is a bug and can't be caught |
| classes, interfaces, inheritance | records, unions and modules; members on records and unions; traits |
| `inline` with SRTP, `static member (+)` | `impl Add<T>`, resolved at compile time, no `inline` |
| `async { }`, which is cold, and `task { }`, which is hot | one `Task<'a>`, cold, written `task { }`, compiled to a state machine |
| arrays are shared and mutable | arrays are values with copy-on-write: `let mutable a`, then `a.[i] <- x`. `Buffer<'a>` is the shared kind |
| `mutable` record fields | none: `{ r with x = … }`, a `let mutable` record, or a `ref` field |
| a closure captures a `let mutable` as a hidden ref cell | it's an error: make the `ref` yourself |
| a `.fsproj` listing the files in order | a `zs.toml`; each file is a module named by its path, and nothing is listed |
| NuGet and the .NET library | C libraries through `import c`, and Z# packages by path or git |
| `List.map (fun s -> s.Length) names` needs an annotation | it compiles: a lambda is typed after the call's other arguments |

**Not there yet:** list ranges (`[1 .. 10]`; use `List.init` or a `for` loop), typed tuple
parameters (`let f (a: int, b: int)`), and patterns in top-level `let`s.

### Stricter than F#

- **A `match` that misses a case doesn't compile,** and the error names the case: `match is not exhaustive; missing case: Dot`. Neither does a case that can never match. F# warns about both.
- **Integer overflow panics** at run time (`panic: integer overflow`), where F# wraps silently.
- **A data race doesn't compile:** `this function crosses threads, but it captures 'hits' : ref<int>, which can't be shared between threads; share state through Atomic, Mutex or Channel, or return a result per job`.
- **F# habits get errors that say what to write:** `there's no null: a missing value is None, of type option<'a>`. [tests/newcomer](tests/newcomer) has 33 of them, for the first mistakes of F# and C programmers.

### New in Z#

- **Effects in the type.** A function that can fail says so, and the compiler infers it: `parse : string -> Entry / Throw<string>`. Handlers also inject dependencies: a test runs the whole program against an in-memory terminal and disk, with no mocking library. Pure code compiles as if effects didn't exist.
- **Thread safety in the type.** `Array.Parallel.map` takes a `share<'a -> 'b>`: what the function captures must be immutable, or an `Atomic`, a `Mutex` or a `Channel`.
- **Traits instead of SRTP and interfaces,** resolved at compile time, with `dyn` values for mixed lists. `derive` writes impls by walking a type's fields, as `[<Derive(Json)>]` does.
- **Record fields with defaults:** with `type Config = { host: string = "localhost"; port: int = 8080 }`, the literal `{ port = 9000 }` is a whole `Config`.
- **Types for systems code:** `u8` to `u64`, `usize`, `f32x8`, `fixed<u8, 16>`, `[<CLayout>]` records, `span<'a>`, and `ptr<'a>` inside `unsafe`.
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
| **A server** | The [echo server](examples/echo/server.zs) held 10,000 connections for an hour: 33.1 million round trips, none failed, its memory flat at 26 MB. |
| **A program** | [logstat](examples/logstat/README.md) counts 1 million log lines (50 MB) in 0.72 s on one thread and 0.20 s on 16, from a 394 KB binary. |
| **Binary size** | A hello world is 17 KB on Linux x86-64, 11.7 KB stripped. |
| **The compiler** | 27,815 lines of Z#. A debug build of itself takes 14.9 s from nothing (the F# compiler it replaced: 15.2 s), and 0.43 s after a one-function change. [Report](docs/reports/self-hosting.md) |

Desktop numbers come from an AMD Ryzen 7 PRO 8840U laptop running Linux x86-64; Cortex-M numbers
are instructions executed under QEMU, each program written in both languages. Each report gives
its method.

## Systems programming

### Memory without a garbage collector

The compiler inserts reference counting, then removes most of it, as Koka and Lean 4 do
(Perceus). A value is freed at its last use, a function that only reads a value borrows it with
no count traffic, and rebuilding a unique list or tree reuses its cells in place. Small unions
such as `option<int>` are never allocated. Arrays are values with copy-on-write, so a write to a
unique array happens in place. Weak references break cycles, arenas free in bulk, and raw
pointers work inside `unsafe`.

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

- **Tasks:** `task { }` compiles to a state machine, so a wait allocates nothing: a task that waits 200,000 times makes the same 7 allocations as one that waits 10 times. Cancellation disposes what a task bound with `use`.
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
| Bare metal | Cortex-M4F, Cortex-M0 and M0+ | `--target cortex-m4`, `--target cortex-m0plus` |
| WebAssembly | wasm32, freestanding | `--target wasm32`, run by a 25-line Node host |

Cross builds link through `zig cc`, so there's no SDK or sysroot to install.

## Microcontrollers

Z# runs bare-metal on ARM Cortex-M, with no operating system and no C library. Core comes along
(lists, arrays, maps, strings, options, results, effects, `Mmio`); using Std, the part that needs
an OS (files, processes, sockets), is a compile error that says so.

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
`zs build --target cortex-m4 -Os`, the whole firmware is 4,216 bytes of flash. `Mode` is a plain
value that never touches the heap, and in the machine code `setLed` is one store instruction and
`buttonDown` one load. (Flashing it waits for the STM32F4 linker script: `cortex-m4` links for
QEMU's board today.)

| Target | Chips | Heap | Tested on |
|---|---|---|---|
| `cortex-m4` | Cortex-M4F: STM32F4, nRF52, … | 64 KB | QEMU `mps2-an386` |
| `cortex-m0plus` | Cortex-M0 and M0+: RP2040, nRF51, STM32G0, … | 8 KB | QEMU `microbit`, 16 KB of RAM |

```sh
zs build examples/mcu/uart.zs --target cortex-m4 -Os -o uart.elf     # 2,284 bytes of flash
qemu-system-arm -M mps2-an386 -nographic -semihosting-config enable=on -kernel uart.elf
```

**Against C on the same chip.** Each program is written in both languages, the way each is
normally written ([bench/mcu](bench/mcu)). The ratios are instructions executed, Z# ÷ C, so below
1.00 Z# is faster:

| Program | M4 `-O2` | M4 `-Os` | M0 `-Os` | Flash, M4 `-Os`: Z# / C |
|---|---:|---:|---:|---:|
| `crc32`: CRC-32 of 4 KB, 10 times | 1.00 | 1.00 | 1.00 | 2,304 / 2,084 B |
| `fir`: a 32-tap filter over 1,024 `f32` samples | 1.06 | 1.12 | 1.01 | 2,564 / 2,356 B |
| `isort`: insertion sort of 512 `i32`, in place | 1.04 | 1.00 | 0.90 | 2,720 / 2,112 B |
| `pipeline`: `List.init 200 \|> map \|> filter \|> sum`, against a C loop | 1.26 | 1.00 | 1.28 | 2,348 / 2,024 B |
| `fib64`: recursion on Z#'s `int`, against C's `int64_t` | 0.62 | 0.72 | 0.57 | |
| `fib`: recursion on `i32`, every `+` checked | 1.15 | 1.25 | 1.47 | 2,356 / 2,032 B |
| `tokens`: a tokenizer state machine over 2 KB | 1.39 | 1.25 | 2.52 | 2,716 / 2,192 B |

- **Where the speed comes from:** `int` is the chip's 32-bit word; reading an array doesn't touch its reference count; bounds checks are proved once per loop; a pipeline of pure lambdas becomes one loop that builds no list; small unions are plain values, and an enum is one byte.
- **Where it's slower:** every `+` and `-` the compiler can't prove safe is checked for overflow, which C doesn't do (`fib`); `[<Wrapping>]` on a function turns the checks off. The tokenizer's tuples and checked arithmetic cost the most on the M0's few registers.
- **RAM:** the programs built on lists and unions peak at 32 bytes of heap, and stack use is within 10% of C's on all but `isort` at `-O2`. A program that allocates nothing links no heap at all.
- **Not yet:** interrupt handlers, `[<NoAlloc>]` (a compile error for code that may allocate), constants in flash, RISC-V, and linker scripts for real boards: each target links for its QEMU machine today. They're track M of the [roadmap](ROADMAP.md).

More: [the guide's chapter](docs/guide/11-microcontrollers.md),
[the measurements](docs/reports/microcontrollers.md).

## Tooling

One `zs` binary holds the compiler and its tools.

| Command | What it does |
|---|---|
| `zs new`, `zs build`, `zs run` | projects in a `zs.toml`, with path and git dependencies; builds cached by module |
| `zs build --release` | optimized, with ThinLTO; `--profile-generate` and `--profile-use` for PGO |
| `zs build -g` | DWARF for gdb: breakpoints on lines; strings, records and plain unions shown as values |
| `zs test` | tests as values, each in its own process; expect tests that `zs test --update` rewrites |
| `zs fmt`, `zs doc` | one canonical format; Markdown docs from `///` comments |
| `zs lsp`, `zs mcp` | a language server (types on hover, rename, code actions) and an MCP server for AI agents |

Editors: the [Zed extension](editors/zed), the [VS Code extension](editors/vscode), the
[Rider plugin](editors/rider), and the [tree-sitter grammar](editors/tree-sitter-zsharp) for the others.

## Getting started

The compiler is written in Z# and builds itself, starting from the previous release (stage 0,
pinned in `dev`). The dev container has everything it needs: clang and LLVM 23, zig, QEMU, gdb
and valgrind. It needs [podman](https://podman.io).

```sh
./dev ./test.sh                        # build the compiler, then run every test
./dev bin/zs run examples/simple.zs    # run a program with it
```

With `zs` on your PATH (in the container, it's `bin/zs`):

```sh
zs run hello.zs                        # build and run a debug build
zs build hello.zs --release            # optimized
zs new greeter                         # a project: zs.toml, src/main.zs and a test
zs build blink.zs --target cortex-m4 -Os -o blink.elf
```

`./dev` fetches stage 0 from this repository's
[GitHub releases](https://github.com/ZigoteProject/zsharp/releases) on first use. To build
without the container, see [the guide](docs/guide/01-getting-started.md).

## Documentation

| To | Read |
|---|---|
| learn the language | [the guide](docs/guide/README.md): 16 chapters, every example compiled and run by the tests |
| read whole programs | [examples/logstat](examples/logstat/README.md), and the rest of [examples](examples) |
| look up a function | [the library reference](docs/reference/README.md), generated by `zs doc` |
| know why it's designed this way | [DESIGN.md](DESIGN.md) |
| check a number | [docs/reports](docs/reports): the host, microcontrollers, effects and self-hosting |
| see what's next | [ROADMAP.md](ROADMAP.md), and [docs/proposals](docs/proposals/README.md) for designs under discussion |
| find your way around the compiler | [src/ARCHITECTURE.md](src/ARCHITECTURE.md) |

## Status

Z# is pre-1.0: the language and the library still change between releases. Done: the language
through effect handlers, and the compiler in Z#, which builds itself to the same bytes. Now: the
ports to macOS, Windows and Linux arm64, with the whole suite in CI on each. Next: release 0.1.
The [roadmap](ROADMAP.md) has the details.

## License

Z# is under the [MIT license](LICENSE). It includes:

| Component | Where | License |
|---|---|---|
| [xxHash](https://github.com/Cyan4973/xxHash) | `packages/xxhash/c` | [BSD 2-Clause](packages/xxhash/c/LICENSE) |
| [wepoll](https://github.com/piscisaureus/wepoll) | `runtime/wepoll` | [BSD 2-Clause](runtime/wepoll/LICENSE) |
| [tree-sitter](https://github.com/tree-sitter/tree-sitter)'s parser headers | `editors/tree-sitter-zsharp/src/tree_sitter` | [MIT](editors/tree-sitter-zsharp/src/tree_sitter/LICENSE) |

`import c` opens the system's libclang (LLVM, Apache 2.0 with LLVM exceptions) at run time; none
of LLVM is shipped.
