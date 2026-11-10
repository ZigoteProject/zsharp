# Z#

**A functional language with F#'s syntax that compiles to native code: no garbage collector,
no VM, no runtime to install.**

Z# is an ML-family language: Hindley–Milner inference, algebraic data types, exhaustive
pattern matching, immutable values by default, and effect handlers in the type system. It
compiles through LLVM to a single native binary, manages memory by reference counting the
compiler mostly optimizes away, and links directly with C. The same language targets Linux,
macOS and Windows, bare-metal Cortex-M microcontrollers, and WebAssembly.

> **Status: pre-1.0.** The current release is 0.7.0 (2026-11-05). The language and library
> still change between releases; [CHANGELOG.md](CHANGELOG.md) says what to rewrite. See
> [Status and limitations](#status-and-limitations) before depending on it.

```fsharp
type Shape =
  | Circle of radius: float
  | Rect of width: float * height: float

let area shape =
  match shape with
  | Circle r -> 3.14159 * r * r
  | Rect (w, h) -> w * h

/// An effect: operations a function may perform, which a caller up the stack handles.
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

`total` performs `Log`, and its inferred type says so. `main` handles it; `k ()` resumes
`total` where it left off. A handler that resumes last compiles to a plain call.

**Contents:** [For F# programmers](#for-f-programmers) ·
[For systems programmers](#for-systems-programmers) ·
[For embedded developers](#for-embedded-developers) · [Getting started](#getting-started) ·
[Tooling](#tooling) · [Platforms](#platforms) ·
[Status and limitations](#status-and-limitations) · [Documentation](#documentation)

## For F# programmers

Most of the language carries over unchanged: indentation, `let` / `let rec` / `let mutable`,
`|>` and `>>`, records and `{ r with … }`, unions, `match` with guards and active patterns,
units of measure, `option` / `result` / `list` / `Map` / `Set`, computation expressions,
`$"…"` strings, list and array expressions, modules, and members with named and optional
arguments.

What differs:

| F# | Z# |
|---|---|
| `int` is 32 bits; overflow wraps | `int` is the machine word; overflow **panics** (`[<Wrapping>]` or `Int.wrappingAdd` to wrap) |
| exceptions, `try … with` | `result` with `?`, or the `Throw` effect, which shows in the type; a panic can't be caught |
| classes, interfaces, SRTP, `inline` | records, unions and modules; **traits**, resolved at compile time, with `dyn` for mixed collections |
| `async { }` and `task { }` | one cold `Task<'a>`, written `task { }` |
| arrays are shared and mutable | arrays are values with copy-on-write; `Buffer<'a>` is the shared kind |
| a closure captures a `let mutable` | an error; use a `ref` |
| a warning for an incomplete `match` | an error that names the missing case |
| `printfn "%d" n` | `println $"{n}"` |
| `.fsproj` with files in order | `zs.toml`; a file is a module named by its path |
| NuGet, type providers as plugins | C libraries via `import c`; Z# packages by path or git; `import json "sample.json"` |

What is new: **effects in types** (also the dependency-injection mechanism: tests swap the
real disk for an in-memory one with a handler), **thread safety in types** (`share<'a -> 'b>`),
`derive` instead of reflection, and record fields with defaults.

There is no .NET interop. More: [Z# for F# programmers](docs/guide/17-from-fsharp.md).

## For systems programmers

**Memory.** Reference counting in the style of Koka and Lean 4 (Perceus): a value is freed
at its last use, a function that only reads a value borrows it, and rebuilding a unique list
or tree reuses its cells in place. Small unions such as `option<int>` are never allocated.
Reference cycles through mutable cells leak; `weak<'a>` breaks them. Arenas free in bulk, and
raw pointers exist inside `unsafe`.

**Safety.** Code without `unsafe` has no use-after-free, no null, no out-of-bounds access, no
silent integer overflow and no data races: what crosses threads must be immutable or an
`Atomic`, `Mutex` or `Channel`, checked at compile time.

**C, both ways.** `import c "raylib.h"` reads a header with libclang and declares its
functions, structs, enums and `#define`s; structs pass by value with the target's ABI.
`[<Export>]` and `zs build --lib` produce a static or shared library with its C header. Rust
and Zig libraries link the same way ([examples/rust](examples/rust/README.md),
[examples/zig](examples/zig/README.md)).

```fsharp
[<CLayout>]
type Vec2 = { x: f32; y: f32 }

// the generated header declares: Vec2 vec_add(Vec2 p0, Vec2 p1);
[<Export "vec_add">]
let add (a: Vec2) (b: Vec2) : Vec2 = { x = a.x + b.x; y = a.y + b.y }
```

**Concurrency.** `task { }` compiles to a state machine (a wait allocates nothing) over
epoll, kqueue or wepoll; a work-stealing pool runs `Parallel.for` and `Array.Parallel.map`;
portable SIMD vectors (`f32x8`, `u8x16`, …) sit beside x86-64 and arm64 intrinsics.

**Performance.** Measured on one laptop (Ryzen 7 PRO 8840U, Linux x86-64, `--release`,
clang 23); each report states its method and how the numbers could mislead.

| Program | Z# | C | Rust | F# (.NET 10) |
|---|---:|---:|---:|---:|
| `binarytrees`, depth 18 | 0.31 s | 1.16 s | 1.61 s | 1.19 s |
| `rbtree`, 1 M inserts and lookups | 0.52 s | 0.58 s | 0.56 s | 1.90 s |
| `spectralnorm` 4000 | 0.63 s | 0.66 s | 0.68 s | 0.79 s |
| `nbody`, 20 M steps | 1.02 s | 1.16 s | 0.69 s | 1.05 s |
| `fib` 42 | 0.86 s | 0.49 s | 0.48 s | 0.67 s |

- `fib` shows the cost of checked overflow; C with `-ftrapv` takes 0.86 s too.
- `binarytrees` favours Z#'s pooled allocator over `malloc` per node. In `rbtree`, Z# and F#
  run a persistent tree while C and Rust update one in place.
- Larger programs (JSON, an interpreter, Dijkstra, SHA-256) run at 1.3–3.5× C's time.

A hello world is 16 KB. Reports: [host](docs/reports/host.md),
[real programs](docs/reports/realworld.md), [effects](docs/reports/effects.md).

## For embedded developers

Z# runs bare-metal on ARM Cortex-M with no operating system and no C library. The core
library comes along (lists, arrays, maps, strings, options, effects, tasks); the part that
needs an OS is a compile error there.

```fsharp
let gpioaBsrr = usize 0x40020018   // a constant: inlined where it's used
let bit (n: int) = u32 1 <<< u32 n

/// One store instruction in the machine code.
let setLed (lit: bool) = Mmio.write32 gpioaBsrr (if lit then bit 5 else bit 21)
```

- **`int` is the chip's word**, enums are a byte, small unions never touch the heap, and a
  program that allocates nothing links no heap.
- **`[<NoAlloc>]` and `--no-heap`** make allocation a compile error that names the call
  chain. Interrupt handlers (`[<Interrupt "USART2">]`) are checked this way implicitly.
- **Registers** as `[<Bits>]` records, optionally generated from the chip's SVD file
  (`import svd`); `Cpu.critical`, `Irq.wait`, `Atomic` and a lock-free `Spsc` queue.
- **Constants in flash:** top-level tables are static objects with no startup code;
  `[<Section ".noinit">]` and `[<Align n>]` place storage.
- **Fixed point:** saturating `q7`, `q15` and `q31`, as in CMSIS-DSP.
- **Tasks** run on the runtime's loop with the core asleep between events.
- **Tests:** `zs test --target cortex-m4` runs a file's tests in one image under QEMU.

| Target | Chips | Default heap | Tested on |
|---|---|---|---|
| `cortex-m4` | Cortex-M4F: STM32F4, nRF52, … | 64 KB | QEMU `mps2-an386` |
| `cortex-m0plus` | Cortex-M0/M0+: RP2040, nRF51, STM32G0, … | 8 KB | QEMU `microbit` (16 KB RAM) |
| `nucleo-f401` | ST Nucleo-F401RE | 64 KB | QEMU `netduinoplus2`; flashing via probe-rs, output over RTT |

**Against C on the same chip** (instructions executed under QEMU, Z# ÷ C, Cortex-M4 `-Os`):
CRC-32 1.00, insertion sort 1.00, a `List` pipeline against a hand-written loop 1.00, a
32-tap `f32` FIR 1.12, a tokenizer 1.25, the same filter in `q15` 1.43. Flash is 0.2–0.6 KB
larger than C's. The LED-button-shell firmware in
[examples/mcu/nucleo-f401.zs](examples/mcu/nucleo-f401.zs) is 5,156 bytes.

**Not yet:** the firmware has run under QEMU but not on the physical board; RISC-V and
further boards are planned. More: [the guide's chapter](docs/guide/11-microcontrollers.md),
[the measurements](docs/reports/microcontrollers.md), [examples/nucleo](examples/nucleo).

## Getting started

Each [release](https://github.com/ZigoteProject/zsharp/releases) has an archive per platform
with the compiler, library and runtime in one folder. Builds need clang 23 or later;
cross-compiling uses `zig`.

```sh
tar -xzf zs-0.7.0-linux-x86_64.tar.gz
export PATH="$PWD/zs-0.7.0-linux-x86_64:$PATH"

zs doctor                          # what builds need, found or missing
zs run hello.zs                    # build and run
zs build hello.zs --release        # optimized, with ThinLTO
zs new greeter                     # a project: zs.toml, src/main.zs and a test
zs build blink.zs --target cortex-m4 -Os -o blink.elf
```

The compiler is written in Z# and builds itself from an earlier release. To work on it, the
dev container (podman) has everything:

```sh
./dev ./test.sh                    # build the compiler, then run every test
```

Building without the container: [the guide](docs/guide/01-getting-started.md).

## Tooling

One `zs` binary holds the compiler and its tools.

| | |
|---|---|
| **Projects** | `zs new`, `build`, `run`, `check`; `zs.toml` with path, git and versioned dependencies; `zs add`, `remove`, `tree`, `vendor`; incremental builds |
| **Testing** | `zs test` (tests as values, one process each, expect tests, doc tests, `--coverage`, `--stress`); property tests with shrinking; `zs fuzz` (libFuzzer); `zs bench` |
| **Debugging** | `zs build -g`: DWARF for gdb and lldb, also on optimized builds; `--sanitize`, `--sanitize=thread` |
| **Editors** | `zs lsp` (hover, rename, completion, code actions, allocation hints), `zs fmt`, `zs doc`; extensions for [Zed](editors/zed), [VS Code](editors/vscode) and [JetBrains IDEs](editors/rider); a [tree-sitter grammar](editors/tree-sitter-zsharp) |
| **Type providers** | `import json`, `csv`, `sql`, `svd`, `c`: declarations generated from a file at compile time; `zs provide` prints them to keep |
| **AI agents** | `zs mcp`: an MCP server exposing `check`, `type_at`, `definition`, `build`, `run` |

## Platforms

| Platform | Architectures | Build |
|---|---|---|
| Linux | x86-64, arm64 | native, or `--target aarch64-linux-musl` for a static binary |
| macOS | arm64, x86-64 | native, or `--target aarch64-macos` |
| Windows | x64, arm64 | native through mingw-w64, or `--target x86_64-windows-gnu` |
| Bare metal | Cortex-M4F, Cortex-M0/M0+ | `--target cortex-m4`, `cortex-m0plus`, `nucleo-f401` |
| WebAssembly | wasm32, freestanding | `--target wasm32` |

Cross builds link through `zig cc`: no SDK or sysroot to install.

## Status and limitations

Z# is not production-ready. Know this before using it:

- **No stability yet.** Releases before 1.0 may break source. 1.0 freezes the language and
  the library's names.
- **Platform maturity varies.** Linux x86-64 is the primary platform. The test suite passes
  on CI's five runners (Linux x86-64 and arm64, macOS, Windows x64 and arm64), but the
  release archives have not been verified on clean macOS and Windows machines.
- **Microcontrollers are tested under QEMU.** No firmware has yet been verified on physical
  hardware.
- **Reference cycles leak.** There is no cycle collector; the compiler warns about types
  that can form one, and `ZS_LEAKCHECK=1` reports leaks at exit.
- **A panic ends the process**, a C host included. It cannot be caught.
- **Small ecosystem.** There is no package registry; dependencies are paths and git
  repositories, and libraries beyond the standard one mostly come from C.
- **Known gaps:** `Seq` pipelines are not fused into one loop as list pipelines are; a `use`
  inside a `task { }` body is not disposed when a throw passes it; editor extensions are
  installed from source.

What is planned: [ROADMAP.md](ROADMAP.md). What changed: [CHANGELOG.md](CHANGELOG.md).

## Documentation

| To | Read |
|---|---|
| learn the language | [the guide](docs/guide/README.md), 18 chapters whose examples the test suite runs |
| know exactly what a construct means | [the language specification](docs/spec/README.md) |
| look up a function | [the library reference](docs/reference/README.md) |
| read whole programs | [logstat](examples/logstat/README.md) (a CLI with effects, tasks and property tests), the [Nucleo firmware](examples/nucleo/README.md), [Advent of Code](examples/aoc/README.md), [small tools](examples/tools/README.md) |
| understand the design | [DESIGN.md](DESIGN.md) and [the proposals](docs/proposals/README.md) |
| check a number | [docs/reports](docs/reports) |
| work on the compiler | [src/ARCHITECTURE.md](src/ARCHITECTURE.md) |

## License

[MIT](LICENSE). The repository includes [xxHash](packages/xxhash/c/LICENSE) and
[wepoll](runtime/wepoll/LICENSE) (BSD 2-Clause) and
[tree-sitter's parser headers](editors/tree-sitter-zsharp/src/tree_sitter/LICENSE) (MIT).
`import c` loads the system's libclang at run time; no part of LLVM is shipped.
