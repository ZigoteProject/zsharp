# Z# roadmap

Every phase ends with **exit tests**: programs in `tests/` (or scripted checks) that must pass,
along with the whole `./test.sh`. Design and rationale: [DESIGN.md](DESIGN.md). Learning the
language: [the guide](docs/guide/README.md).

**Development** happens in a container (`.devcontainer/Containerfile`: Fedora 44, .NET 10,
clang/LLVM 23.1 (LLVM's release), zig, valgrind, gdb, qemu-user, qemu-system-arm, Wine and raylib, plus
Rust, Swift and OCaml for the host benchmarks).
- **Commands:** `./dev ./test.sh` runs the suite, plain `./dev` opens a shell, and `./dev --rebuild` rebuilds the image.
- **One at a time:** run one `./dev` at a time, since runs share `bin/`. The container mounts the repository with a shared SELinux label (`:z`). A tool that mounts it with a private one (`:Z`) cuts off a container that's running.
- **Test modes:** `./test.sh --valgrind` runs everything under valgrind. `./test.sh --target aarch64-linux-musl` runs it cross-compiled under qemu.

```
 v1, single-threaded:  0 ─ 1 ─ 2 ─ 3 ─ 4 ─ L ─ 5 optimizer I ─ V v1 completion ─ 6 CE + Task
 v2, threads:          7 parallelism ─ 8 SIMD ─ 9 optimizer II ─ 9.5 incremental, threads
                       ─ 9.6 ergonomics, systems ─ third design review
 v3:                   10 effect handlers ─ (11 self-hosting) ─ 12 release 0.1
 alongside:            E editors, D testing, profiling and debugging, M microcontrollers,
                       T more targets, P type providers, S library, K packages

 done: 0–11, L, V and the third design review      now: phase 11.5
```

- **v1 (phases 0–6, L and V):** the complete single-threaded language. It is fast, memory-safe, has C interop, and runs async on one event loop.
- **v2 (phases 7–9.6, done):** threads and parallelism, SIMD and the final performance work, incremental builds, and what F#, systems and C programmers miss first.
- **v3 (phases 10 and 11, done):** effect handlers, then the compiler in Z#, which builds itself. The F# compiler as phase 10 left it is tagged `v0.5`, and `v0.6` is the last version with both compilers: its release is stage 0 now (tags of the repository, not the public release 0.1 below).
- **v1, v2 and v3 are stages of the language, not release numbers.** The first public release is 0.1 (phase 12); 1.0 is the release that freezes the language and the library's names.
- **Tracks:** editor tooling (E), testing, profiling and debugging (D), microcontrollers (M), more targets (T), type providers (P), the library (S) and packages (K) run alongside the main line.

## Where things stand

**Works today:**
- **Language:** inference (lambdas get their parameter types from the call), records with defaults, unions, exhaustive matching (record, string and character patterns), active patterns, units of measure, traits, `dyn` values, derives, members with named and optional arguments, nested modules with their own fields and traits, closures, generics, custom operators, `char`, multi-line and raw strings, raw pointers in `unsafe`, computation expressions (`option { }`, `result { }`, `task { }`), list and array expressions, `function`, compound assignment (`+=`), `?` on results and options, generic constants (`Map.empty`), and effect handlers with inferred, row-polymorphic effect types: generators (`seq { }`), typed exceptions (`Throw`) and handlers of a program's own.
- **Memory and performance:** Perceus RC with borrowing and reuse, copy-on-write arrays, spans and slices (windows without copies), weak references, arenas, checked arithmetic, a pool allocator under a one-word header, an optimizer that inlines, uncurries, resolves known constructors and fuses pipelines, ThinLTO and PGO. On the host benchmarks it's at C's speed or better, with at most C's peak memory, except `fib` (1.76×: overflow checks, which cost C with `-ftrapv` the same). On compute code it's as fast as C on a Cortex-M.
- **Library:** a prelude, Core (collections, lazy sequences, text, options, results, typed exceptions: every target) and Std (console, environment, files, paths, processes, timing, tasks and TCP: targets with an OS), in .NET-style namespaces.
- **Concurrency:** `Task` on an event loop per thread, compiled to state machines (a wait allocates nothing), with structured concurrency, cancellation that disposes `use` values (on other threads too, for spawned tasks), timers, TCP sockets, `Task.spawn` to run tasks on every core, and `Task.blocking` for C calls that block.
- **Parallelism:** a work-stealing thread pool (`Parallel.both`, `for`, `reduce`, `Array.Parallel`) any thread forks onto, with spare workers for jobs waiting in a channel or a mutex; `Atomic`, `Mutex` and `Channel` (capacity 0 is a rendezvous); what crosses threads is checked at compile time (`Share`, `share<F>`), and only shared objects have atomic reference counts.
- **SIMD:** portable vectors of every number type at 128, 256 and 512 bits (`f32x8`, `u8x16`, …) with masks and shuffles, `[<FastMath>]`, `--cpu`, `[<Target>]` and `[<Multiversion>]`, and x86-64 and aarch64 intrinsics; within 10% of C with intrinsics on both.
- **C:** C import and export (static and shared libraries), structs with array fields (`fixed<u8, 16>`), spans passed as a pointer and a length, C function pointers, Z# objects held by C as handles (a Share value's on any of the host's threads, any other checked to stay on its own), callbacks C may call on any thread (`callback<share<F>>`), and a panic hook for C hosts.
- **Targets:** Linux on x86-64 and aarch64, Windows on x64 (its suite under Wine) and arm64, macOS on arm64 and x86-64 (built, not yet run on a Mac), Cortex-M4 and M0+ (bare metal); the compiler builds for each.
- **Tooling:** projects with path and git dependencies, debug and release builds, builds and editor checks incremental by module (one cache for the CLI, LSP, MCP and `zs doc`, and a build server that keeps the compiler warm), `zs test`/`fmt`/`doc`, gdb debug info (strings, records and unions as values), and an LSP, MCP server and Zed extension.
- **The compiler:** Z# (`src/`), built by the previous release and building itself to the same bytes; its passes and code generation run on every core, and it reports every mistake of a declaration, in the editor too.

**Known gaps** (in priority order, each with the phase or track that closes it):
1. **C ABI (track M):** 32-bit ARM passes structs by value with the x86-64 rules.
2. **Weak references and arenas on microcontrollers (track M):** they're hosted-only so far; the embedded runtime lacks their functions.
3. **Debug info (track D):** lists and other boxed unions aren't shown as gdb values (plain unions are).
4. **Targets (phase 11.5):** macOS and Windows programs and compilers build (`--target`), and Windows's suite passes under Wine, but nothing has run on a Mac or a Windows machine yet: the suite on each in CI, and their release archives on clean machines, close the phase.
5. **`use` under effects (track S):** a throw, or a clause that doesn't resume, passes over a `use` without disposing what it bound (it's freed). Item 10 of track S disposes it.
6. **Generators (track S):** a pipeline of `Seq` functions allocates nothing per element but isn't one loop yet, as a list pipeline is: each stage is an indirect call per element (4.8× a fused list pipeline's time). Item 9 of track S fuses it.

## Next

### Phase 11.5: cross-platform: macOS, Windows and Linux on arm64 and x86-64
Z# builds programs for, and runs its compiler on, the platforms people develop on: macOS arm64
and x86-64, Windows x64 and arm64, and Linux arm64 beside Linux x86-64. It comes before 0.1, so the
release ships on all of them, and because each port (a calling convention, the runtime off POSIX,
a loop on kqueue and on IOCP, the compiler's own processes and paths) costs less before 0.1 has
users than after. **Design:** [proposal 0022](docs/proposals/0022-targets-macos-windows.md) for
macOS arm64 and Windows x64; its decisions carry to the other three, settled as each starts.
- **Programs for each** (`zs build --target`, through `zig cc` as the Linux cross builds are, so no SDK is installed):
  - **macOS** (`aarch64-macos`, `x86_64-macos`): Mach-O, ad-hoc signed; Apple's arm64 calling convention, SysV on x86-64; kqueue behind the loop's interface (decision 48); a kernel wait for `Mutex`; `sysctl` for CPU features; backtraces from libSystem.
  - **Windows** (`x86_64-windows-gnu`, `aarch64-windows-gnu`): PE, mingw-w64's C runtime; the Microsoft x64 and ARM64 conventions; `rt.c` off POSIX in one `_WIN32` part: wepoll (epoll's API over IOCP) so the loop keeps its shape, `WaitOnAddress` for `Mutex`, Win32 threads, files, directories, processes and sockets behind the same `Native` functions, a UTF-8 console, drives and backslashes in `Path`.
  - **Linux arm64** (`aarch64-linux-gnu`, and native on an aarch64 machine): what `aarch64-linux-musl` has today, and host detection, so a native build there uses AAPCS64's struct rules, not x86-64's.
- **The compiler on each** (Z# since phase 11, so it ports with the runtime): `src/release.sh` makes each platform's release by building `src/` with `--target`; libclang found per platform (a `.dylib` beside clang or Xcode's, `libclang.dll` beside LLVM's clang); the cache's and the build server's paths (a named pipe on Windows); clang and zig started as processes there; `./dev`'s stage 0 picked by the host.
- **Testing:** the whole suite on each in CI (GitHub's macOS arm64 and x86-64, Windows x64 and arm64, and Linux arm64 runners), not only built. Without one, `./test.sh --target <triple> --build-only` builds every test program for it, and qemu-user runs Linux arm64's.
- **Exit tests:** `./test.sh` green on the five in CI, `tests/bootstrap.sh` included (each builds its own compiler to the same bytes); a release archive per platform, six with Linux x86-64; on a clean machine of each, the archive to a running hello world, following the guide.
- **Status (2026-10-24):** built, waiting on machines. Every target builds programs and the compiler (decision 82): the host architecture from the compiler's own `host.c`, so a native aarch64 build uses AAPCS64; Microsoft x64's struct rules; `rt.c` on kqueue and `__ulock_wait` for macOS, on wepoll, winpthreads, Winsock and `WaitOnAddress` for Windows; `Path` and `Directory.temp` by the OS; UTF-8 file names on Windows through each program's manifest; `import c` reading zig's headers for the target. Here, `./test.sh` passes on Linux x86-64, under qemu for aarch64, under Wine for Windows x64 (`--target x86_64-windows-gnu`, which runs the programs there), and `--target aarch64-macos --build-only` builds every program; the Windows compiler runs under Wine up to clang; the Linux arm64 compiler, under qemu, builds itself to the same bytes (gen 1 = gen 2 = gen 3); and every target's build of the compiler is the same bytes twice from empty caches. `src/release.sh <zs> <version> <target>…` makes each platform's archive, and `.github/workflows/test.yml` runs the suite on each platform's runner with its archive's compiler. Left: a remote for that workflow to run on, and so the five green in CI and the clean-machine checks; lldb (phase 12).

### Phase 12: release 0.1
The first public release: the language works for people other than its author, in one niche
first. It isn't 1.0: the language and the library's names may still change in 0.x releases,
each change listed in `CHANGELOG.md` with what to rewrite. Optimization waits for profiles of
real programs.
**Design** of the deferred features: [proposal 0004](docs/proposals/0004-c-layout.md) (C unions, layout facts), [0006](docs/proposals/0006-anonymous-records.md) (top-level patterns) and [0021](docs/proposals/0021-warnings.md) (warnings).
- **Scope:**
  - **The "before 0.1" list,** sorted by the third design review from the deferred features and the tracks' *after phase 11* items, and nothing else:
    - **K2 (versions):** packages written against 0.1 must survive 0.2.
    - **Track S, what an F# programmer reaches for on the first day:** the rest of `List`/`Array`/`Map`/`Set` (S2), `Math` and `Random` (S3), UTF-8 (S4).
    - **Track D:** lldb (debugging 2), since macOS is in 0.1; doc tests (D8), so the guide can't go stale at launch.
    - **The deferred features below,** anonymous records excepted (cut).
    - **If the flagship is a microcontroller:** M4 (one real board), M9 (bit fields), M11 (`Cpu`) and async on bare metal (0016).
    - Everything else marked *after phase 11* follows 0.1.
  - **A flagship project:** one real program in the niche Z# is best at, built alongside the release, so it decides what the library and the first packages need. The niche is picked at the start of the phase; microcontrollers are the strongest case (SVD registers, bit fields, `[<NoAlloc>]`, interrupt handlers). Picking them moves track M's async on bare metal into the "before 0.1" list.
  - **Every platform (phase 11.5):** the release's archives for the six, built and tested in CI.
  - **Installing:** phase 11.5's release archive per platform, with `zs`, the runtime and the library. `zs doctor` checks for clang or zig, and libclang for `import c`, and says how to get what's missing.
  - **Deferred here:** features that aren't needed before phase 11, moved out of earlier phases so those stay small. The third design review checked them against "Simple" (anonymous records were cut) and put the rest on the list above.
    - **From phase 9.5, cycle warnings:** a type that can reach itself through a `ref` or `Buffer` field, not through `weak`, is warned about where it's declared. The warning names the path (`Node.next: ref<option<Node>>`) and suggests `weak`, and `[<Cyclic>]` on the type silences it.
      - **The warning:** the severity, `--strict`, `[<NoWarn>]` and the editor's side came with `unused-value` before phase 11 (0021); this adds the kind `cycle` and `[<Cyclic>]`.
      - **Closures:** a function type doesn't say what it captures, so a cycle through a closure isn't caught. `ZS_LEAKCHECK=1` stays the backstop.
    - **From phase 9.6, ergonomics:**
      - **Patterns at the top level:** `let (a, b) = …` and other patterns, as inside functions.
      - **Z# for F# programmers:** a guide page listing the differences: `int` is the machine word, `?`, traits instead of SRTP and interfaces, no classes or exceptions, `ref` instead of capturing a `let mutable`, and the four kinds of function types (functions, `share<F>`, `callback<F>`, `fnptr`) and when each is needed.
    - **From phase 9.6, layout:**
      - **Layout facts:** `sizeof<T>`, `alignof<T>` and `offsetof<T> "field"` as constants. A top-level `assert` on constants is checked at compile time, so a record's layout is checked against C's with the `assert` the language already has, not a new `static assert`.
      - **C unions:** `import c` brings them in as `[<CLayout>]` unions, read only in `unsafe`.
    - **Kept before phase 11:** compound assignment, `function`, list expressions, slices and `span`, tests as values, assertions, inline expect tests, the iteration trait, and rename and code actions. They change how code and tests are written, or break an API, so they're cheaper before the compiler is rewritten in Z# and before 0.1 has users.
    - **From the tracks:** the items marked *after phase 11* in E, D, M, S and K, and track P whole.
  - **Launch:** the guide, the "Z# for F# programmers" page, the flagship project as the example, and a post for each of the strongest results (Perceus on a Cortex-M, atomic counts only on shared objects, SIMD next to C).
- **Status (2026-10-26):** the flagship is a microcontroller, an ST Nucleo-F401RE, so M4, M9, M11 and async on bare metal are on the list; impls across packages take Rust's orphan rule (K9). Done: top-level patterns (`tests/top_pattern.zs`); layout facts and compile-time asserts (`tests/layout.zs`).
- **Exit tests:**
  - On clean Fedora, Ubuntu, macOS and Windows machines, a newcomer gets from the release archive to a running hello world in five minutes, following only the guide.
  - The flagship project builds from its repository with `zs build` alone, and runs on its hardware.
  - The "before 0.1" list is empty, and `CHANGELOG.md` has its first entry.
  - Each deferred feature taken into 0.1 passes its exit test:
    - Top-level patterns have a test.
    - `import c` of a header with a union imports it, and a top-level `assert (sizeof<Packet> = 20)` fails to compile when a field changes.
    - A doubly linked list with `ref` back-pointers gets the warning; with `weak`, or `[<Cyclic>]`, it doesn't. The repository's own code has no warnings.

## Tracks
Before phase 11, a track does what the self-hosted compiler needs, what closes a known gap, and what would cost more later: a change to how code or tests are written, or to an API.
Items marked *after phase 11* wait for phase 12, which picks what 0.1 needs from them.

### Microcontrollers (M)
Tier 2 (DESIGN §10): every phase keeps `bench/mcu` working and within its ratios.
**Design:** [proposal 0012](docs/proposals/0012-interrupts-noalloc-intrinsics.md) (interrupt handlers, `[<NoAlloc>]`, `Cpu` intrinsics), [0013](docs/proposals/0013-bit-fields.md) (bit fields), [0014](docs/proposals/0014-placement.md) (constants in flash, sections, alignment, the heap), [0015](docs/proposals/0015-fixed-point.md) (fixed-point numbers) and [0016](docs/proposals/0016-async-bare-metal.md) (async on bare metal).
- **Next:**
  1. **Interrupt handlers:** `[<Interrupt "SysTick">] let tick () = …`, placed in the vector table, with the rules for sharing state with them.
  2. **`[<NoAlloc>]` and `--no-heap`** (DESIGN §10, decision 42): a compile error naming the call chain if a function, or anything it calls, may allocate or free heap memory; `--no-heap` checks the whole program.
  3. **Constants in flash:** constant arrays placed in flash, instead of startup values copied to RAM.
  4. **More boards:** *(after phase 11)* linker scripts for STM32F4 and RP2040, flashing through `probe-rs` or OpenOCD, and RTT output as an alternative to semihosting.
  5. **RISC-V:** *(after phase 11)* ESP32-C3, under QEMU first.
  6. **32-bit ARM C ABI:** AAPCS for structs by value.
  7. **Heap:** reusing blocks larger than 256 bytes, and a heap size set in `zs.toml`.
  8. **Weak references and arenas:** the embedded runtime's versions of their functions (the host's use the C library's allocator).
  9. **Bit fields:** *(after phase 11)* a `[<Bits>]` record packs its fields into one integer, each field's width given by `[<Width n>]` or taken from its type: a `bool` is one bit, and a union of cases without fields (an enum) as many as its cases need. So `mode: Mode` reads as `Mode.Fast`, not as a number. The shifts and masks are generated, `{ r with mode = Fast }` is a masked write, and a number too wide for its field panics as an overflow does. No new integer types (`u2`, `u5`) are needed.
  10. **Fixed-point numbers:** *(after phase 11; a Core library, approved at the third design review with decision 66 as its one language change)* `q7`, `q15` and `q31`, the formats CMSIS-DSP and the chips' saturating instructions use, as library types with `Add`, `Num` and `Show`, for DSP on chips without an FPU (Cortex-M0+). A general `fix<i, f>` would need numbers as type arguments beyond `fixed`'s size, for formats no hardware has.
  11. **Core intrinsics:** *(after phase 11)* `Cpu.wfi`, `wfe`, `dsb`, `dmb`, `isb`, `nop`, and `Cpu.critical (fun () -> …)` with interrupts masked for its body, instead of inline assembly. The rules for state shared with interrupt handlers (item 1) build on `critical` and `Atomic`.
  12. **Placement:** *(after phase 11)* `[<Section ".noinit">]` on a top-level value (memory kept across a reset, or a DMA region a linker script names) and `[<Align 32>]` on a value or a type (DMA buffers, cache lines).
- **Later:** async on bare metal (phase 6 `Task` over interrupts, with no OS; [proposal 0016](docs/proposals/0016-async-bare-metal.md), approved at the third design review, decision 71; before 0.1 if the flagship is a microcontroller).

### Editor tooling (E)
Zed first. Everything is plain tree-sitter, LSP and MCP, so other editors and agents get the
same support through a thin extension each.
**Design:** [proposal 0019](docs/proposals/0019-syntax-tree.md) (the lossless syntax tree, reflow, rename, code actions, signature help).

**Done:**
- **E1:** a tree-sitter grammar (checked against every `.zs` file by `./test.sh`), and a Zed extension (grammar pinned by commit, `./test.sh` checks the pin).
- **E2a:** `zs lsp` with diagnostics, hover with types, constraints and doc comments, inlay hints, symbols and formatting.
- **E2b (part):** definition, references, completion (C names included).
- **E3:** `zs mcp` with `check`, `type_at`, `docs`, `build`, `run`, `emit_llvm`, `format`.
- **E4:** VS Code and Rider (`editors/vscode`, `editors/rider`): one TextMate grammar (its keywords checked against the tree-sitter highlights by `./test.sh`), the language server and, in VS Code, the MCP server.
- **F:** `zs fmt`, meaning-preserving, keeping the repository formatted.
- **F2:** a lossless syntax tree ([0019](docs/proposals/0019-syntax-tree.md)); `zs fmt` on it reflows lines over 100 columns, keeping comments; `zs fmt --stdin`; range formatting.
- **Documentation:** `///` doc comments and `zs doc`.

**Next:**
- **E2b, rest:** done: signature help, rename, code actions (add missing match cases, add an `open`, add an annotation).
- **E3, rest:** *(after phase 11)* `definition` and `explain` tools.
- **Exit tests:**
  - A 2,000-line file re-checks within 100 ms in Zed.
  - `zs fmt` reflows a 150-column line and keeps its comments.
  - Renaming a record field updates every module that uses it.
  - Given a file with a type error, Zed's agent fixes it using only the MCP tools.

### More targets (T)
Phase 11.5 takes this track whole, before 0.1: macOS arm64 and x86-64, Windows x64 and arm64, and
the compiler on Linux arm64 (reordered on 2026-10-24; proposal 0022 had macOS in 0.1 and Windows
after it). Tier 3 (DESIGN §10), through `zig cc` as the Linux cross builds are.
**Design:** [proposal 0022](docs/proposals/0022-targets-macos-windows.md).

### Type providers (P)
*After 0.1*, the whole track. **Design:** [proposal 0001](docs/proposals/0001-type-providers.md), approved in principle at the third design review (decision 56).
F#'s type providers, built on what `import c` already does for C headers: the compiler reads a
data source at compile time and declares the types (and functions) for it, so code against a
JSON API, a CSV file or a database is checked against its shape.
- **The design, in short:** `module Weather = import json "weather.json"`, or a bare `import svd "STM32F401.svd"` as `import c`. A provider is a program, `zs`'s own or a `zs-provider-<name>` on PATH, that writes Z# source; the compiler checks it as a module of its own and caches it in `.zs-cache/providers/` with the hashes of its inputs, so an editor or a machine without the provider still gets the types. No code runs inside the compiler (decision 20), and `zs provide json weather.json` prints the module, to read or to keep in place of the import.
- **Scope:**
  - **Providers:** JSON (from a sample or a JSON Schema) and CSV (from the header and the rows), to records with the `Json` derive and parse and print functions; then SQL (records from the `CREATE TABLE`s of a `.sql` file; typed queries are the proposal's open question).
  - **SVD:** a microcontroller's SVD file (the vendor's description of its peripherals) to a module per peripheral, with each register a `[<Bits>]` record (track M's bit fields) whose defaults are its reset value, and only the access the file allows (`Gpioa.Moder.modify (fun r -> { r with moder5 = Output })`, `Usart2.Cr1.write { ue = true; te = true; re = true }`), as Rust's svd2rust does. A wrong field or a write to a read-only register is a compile error instead of a wrong constant in `Mmio.write32`; `only = "GPIOA,RCC"` keeps the module to the peripherals a program uses.
  - **Editors:** the types in the editor are the checker's, with no build run: `zs lsp` runs the providers (`zs`'s own in-process, so they work in Zed's sandbox where clang can't), watches their inputs, and re-checks the provided module and the modules that use it when a sample changes. Hover shows where each field came from, and definition opens the provided module. The result is cached in `.zs-cache` with the hashes of what it was made from, as `import c`'s is, so a machine without an external provider still gets the types.
- **Order:** `zs provide json` and `csv` first, with no language change (they need S3's number parsing and S5's `Json`); then the `import` form, the cache and the editor; `svd` after M9; `sql`; providers on PATH, and from packages after K2.
- **Exit tests:**
  - A program reads a JSON document and a CSV file through provided types, with completion and hover on their fields in Zed and no build run; a key added to `weather.json` is in completion after the edit, and one removed is an error at its use.
  - A changed sample makes the code that no longer fits a compile error that names the field.
  - `examples/mcu/nucleo-f401.zs`, rewritten on the STM32F401's SVD, has no `Mmio` call and compiles to the same register accesses.
  - `zs provide json weather.json > Weather.zs` gives a module that builds with the import line removed, and a build with the provider absent uses the cache.

### Testing, profiling and debugging (D)
What a programmer runs when the code is wrong or slow. Wrap before writing, as packages do:
gdb, lldb, rr, perf, samply, llvm-cov and libFuzzer already exist, and Z# gives them what they
need to show Z# code, instead of a tool of its own.
**Design:** [proposal 0009](docs/proposals/0009-tests-as-values.md) (tests as values), [0010](docs/proposals/0010-properties-and-fuzzing.md) (properties and fuzzing) and [0011](docs/proposals/0011-debug-info-profiles-traces.md) (debug info, profiles and traces).

**Today:** `[<Test>]` functions run by `zs test`, each in its own process; `assert` with its file
and line; `--sanitize` (address, undefined, thread); `ZS_LEAKCHECK=1`; `zs build --time`; and
`-g` at `-O0` for gdb, showing numbers, strings, tuples, records and plain unions.

**Testing, next:** Expecto's model, which F# programmers already know: tests are values, not
attributed functions, so they compose with ordinary code.
1. **Tests as values:** `test "parses" (fun () -> …)` is a `Test`, and `testList "parser" [ … ]` groups them. A top-level value marked `[<Tests>]` is found by `zs test`, statically, with no reflection.
   - **Generated tests:** cases are data, so `cases |> List.map (fun (input, expected) -> test input (fun () -> …))` is a parameterized test with no special support.
   - **Kinds:** `testTask` awaits a `Task` on the event loop, `testProperty` runs a property (item 5), and a test returning a `result` fails on an `Error`.
   - **Focus and pending:** `ftest`/`ftestList` run only the focused tests while debugging, `ptest` skips one and says so, and `zs test --fail-on-focused` (for CI) fails a run that has any focus left.
   - **Order:** tests run in parallel by default; `testSequenced` runs a list one at a time, for tests that share a file or a port.
   - **Isolation stays:** each test still runs in its own process, picked by its path (`parser/parses`), so a panic fails only it. That's what Expecto can't do in .NET.
   - **`[<Test>]` goes:** five files use it today, and one way to write a test is simpler than two.
2. **Assertions that explain:** a failed `assert` on a comparison (`assert (parse s = Ok expected)`) prints both sides through `Show`, and for records, unions and collections the first place they differ, as power asserts do. The compiler knows the expression, so there's no `Expect.equal` family to learn, and no message strings to keep in sync; an operand without `Show` is shown by its source text.
3. **Running:** `zs test parser/` runs the tests whose path starts with it, with a timeout per test (a hang fails the test and names it). `--summary` lists every test with its time, slowest first.
4. **Stress:** *(after phase 11)* `zs test --stress 10m` runs the tests at random, on every core, over and over for that long, as Expecto's `--stress` does. With `ZS_LEAKCHECK=1` and `--sanitize=thread` it finds what a single run hides: a leak that grows, a race, a deadlock.
5. **Properties:** *(after phase 11)* `testProperty "name" (fun (x: int) (xs: list<int>) -> …)` runs a property on generated values, and a failure is shrunk to a smallest case. Its settings are a record with defaults, `testPropertyWith { runs = 1000 } "name" …` (DESIGN §2's field defaults), not an attribute.
   - **One source of randomness:** a generator reads its choices from a stream of bytes, and shrinking shrinks the stream (Hypothesis's design). So every generator shrinks, mapped and filtered ones included, keeping their invariants, with no shrinking code anywhere. FsCheck's shrinking goes by type and loses them: a generator of even numbers can shrink to an odd one.
   - **Generators:** `Gen.int`, `range`, `elements`, `frequency`, `sized`, `map`, `filter`, `list`, `oneOf` and a `gen { }` builder. An `Arbitrary` trait gives each type its default generator, derived for records and unions (DESIGN §3.1) and written by hand where an invariant needs it.
   - **Properties:** `Prop.assume cond` discards a case (FsCheck's `==>`), `Prop.label` names what failed, and `Prop.classify` reports how the cases were distributed, so a generator that only makes trivial cases shows.
   - **Replay:** a failure's byte stream is saved in `.zs-cache/failures` and replayed first on the next run, exactly, not just from a seed.
   - **Stateful:** `Prop.model` checks an API against a model: commands are a union with a derived `Arbitrary`, each is applied to both, and the results must agree; a failure shrinks to the shortest command sequence. `HashMap`, `Channel` and the runtime's pool are its first users.
   - **Types:** a property's parameters have concrete types, since generics are monomorphized; a generic one is a compile error that says to annotate them (FsCheck substitutes `obj`, which Z# has no equivalent of).
6. **Fuzzing, the same properties:** *(after phase 11)* `zs fuzz name` runs a property under libFuzzer, which supplies the byte stream the generators read, guided by coverage instead of random. So a fuzz target is any property, typed (a `Packet`, a `list<Command>`), with no separate attribute; a property over `span<u8>` takes the raw bytes. Builds use the address and undefined-behavior sanitizers, a panic is a failure, and a crash's stream is shrunk by the property shrinker, saved, and replayed by `zs test`.
7. **Expect tests, inline:** `expect value """…"""` compares a value's `Show` with the string literal next to it, and `zs test --update` rewrites the literal in the source, through track E's lossless syntax tree (F2), as OCaml's ppx_expect and Rust's insta do. The expectation sits next to the code that makes it, instead of in a file to find.
8. **Doc tests:** *(after phase 11)* the examples in `///` comments compile and run under `zs test`, their output checked as inline expectations, so the docs can't go stale.
9. **Benchmarks:** *(after phase 11)* `bench "insert" (fun () -> …)` is a value too, run by `zs bench`: warm-up, then enough runs for a median and a confidence interval. A run compares with the last saved one and reports only changes beyond the noise. `testFaster "reuse beats copy" fast slow` is a test that passes when one is faster with statistical confidence (Expecto's `isFasterThan`), so a performance claim can't silently regress.
10. **Coverage:** *(after phase 11)* `zs test --coverage` instruments with LLVM's source-based coverage (counters and a region map the compiler emits for Z#'s source), so `llvm-cov` reports lines and branches, match cases included.
11. **Microcontrollers:** *(after phase 11)* `zs test --target cortex-m4` runs the tests under QEMU, and with `--probe` on a board through probe-rs, with results over semihosting or RTT.

**Profiling, next:**
1. **Where it allocates, before running:** *(after phase 11)* `zs lsp` marks, as inlay hints that can be turned on, the lines that allocate, copy an array on write, or count atomically, and the calls that reuse a cell in place. It's what the compiler already decided, so performance can be read like types. `[<NoAlloc>]` (track M) is the same analysis made an error.
2. **Sampling:** `zs build --profile` keeps frame pointers and debug lines at `-O2`, and symbols carry Z# names (`Map.add<string, int>`, `Parser.expr`), so perf, samply and the Firefox Profiler show Z# code. `zs profile -- args` runs the program under samply (perf without it) and opens the result.
3. **Counts:** `ZS_STATS=1` prints at exit what Perceus's choices cost: allocations and frees by size class, peak memory, reuse hits, copy-on-write copies, and atomic counts on shared objects.
4. **Traces:** *(after phase 11)* `ZS_TRACE=file` writes one trace in Perfetto's format, with what's asked for: sampled allocations with their call stacks and types (the runtime's pool hides them from heaptrack and massif, so it reports them itself), and tasks and threads (time running, waiting and idle per thread, each task's spans between awaits). One format and one viewer, instead of a tool per question.
5. **Microcontrollers:** *(after phase 11)* sampling the program counter through the probe (SWO, via probe-rs), which needs no change to the code, and `Runtime.ticks` around a block for exact cycles.

**Debugging, next:**
1. **Every value, from DWARF:** unions are described with DWARF's variant parts (as Rust's are) and cells as pointers to their layout, so gdb and lldb show lists, boxed unions, records, `ref`, `weak`, `span` and arrays with no scripts. Pretty-printers that ship with `zs` and load automatically cover only what DWARF can't say: `Map`, `Set` and `HashMap` as their entries rather than their trees, and closures as their function and captures.
2. **lldb:** *(after phase 11)* the same as gdb, since lldb is the debugger on macOS (phase 12).
3. **Optimized builds:** `-g` at `-O1` and `-O2`, with lines and locals where LLVM keeps them, so a release build's crash can be debugged.
4. **Editors:** *(after phase 11)* debugging from Zed through the Debug Adapter Protocol, using gdb's and lldb's own adapters with a launch configuration `zs` writes, not an adapter of its own.
5. **Panics:** a panic's backtrace shows Z# names and source lines on every target with an OS. `ZS_ABORT=1` already makes a panic a real `abort()`, so a debugger or a core dump catches it; no other switch is needed.
6. **Tasks:** *(after phase 11)* a gdb and lldb command lists the tasks waiting on a thread's event loop, with what each waits on (a timer, a socket, a child task).
7. **Recording:** *(after phase 11)* rr records a run and replays it backwards; a test checks it works on Z# binaries.
8. **Microcontrollers:** *(after phase 11)* gdb on the board through probe-rs or OpenOCD, and under QEMU's gdb stub, with the same DWARF and pretty-printers.

**Exit tests:**
- A failed `assert (a = b)` on two records prints both and the field that differs.
- A `[<Tests>]` list built with `List.map` over cases runs each case as its own test; an `ftest` runs alone, and `--fail-on-focused` fails the run.
- `zs test` runs a `testTask`, a test that hangs (failed by its timeout), and an inline expect test that `--update` rewrites in place.
- *After phase 11:* a doc test runs under `zs test`.
- *After phase 11:* `zs test --stress 1m` with `ZS_LEAKCHECK=1` finds a planted leak that one run doesn't show.
- *After phase 11:* `zs bench` reports a planted 20% slowdown and nothing for an unchanged build; `testFaster` passes for reuse over copying an array.
- *After phase 11:* a property with a filtered generator of even numbers finds a planted bug and shrinks it to the smallest even case; its replay file reproduces it; a stateful test against a model finds a planted `HashMap` bug and shrinks the commands.
- *After phase 11:* `zs fuzz` on a typed parser property finds a planted out-of-bounds read within a minute.
- *After phase 11:* `llvm-cov` reports a match case the tests never reach.
- *After phase 11:* `zs lsp`'s hints mark the allocations in `examples/complex.zs`, and none in a function `[<NoAlloc>]` accepts.
- A samply profile of the binary-trees benchmark shows Z# function names, and `ZS_STATS=1` reports its reuse hits.
- *After phase 11:* a `ZS_TRACE` of the echo server opens in Perfetto with its tasks.
- gdb shows a `list<Map<string, int>>` and a closure's captures as values, in an `-O2 -g` build too (lldb after phase 11).
- *After phase 11:* Zed stops at a breakpoint in a Z# program and shows its locals.

### Library (S)
The prelude, Core and Std grow toward what an F# programmer reaches for on the first day, in
DESIGN §9's layers.
**Design:** [proposal 0017](docs/proposals/0017-iteration.md) (iteration), [0023](docs/proposals/0023-json-in-core.md) (JSON in Core) and [0024](docs/proposals/0024-library-api.md) (the rest of the first-day API).
- **What goes where:**
  - **Prelude:** a name is global only if F# has it global and most programs use it. It stays small.
  - **Core:** needs no OS, so every target gets it. Most new code goes here.
  - **Std:** needs the OS, or defines a type that packages must agree on (a time; the JSON value is Core's, item 5, so every target and the type providers have it).
  - **A package (track K):** formats and protocols with many reasonable designs, such as HTTP, regex, argument parsing, TLS and databases.
- **Each addition:** `///` docs, its reference page, a test, and for Core, a microcontroller build.
- **Next:**
  1. **Iteration:** `for x in` works on lists, arrays, spans, strings and `Seq` (phase 10: a handle whose clause is the body). A trait would make it work on `Map`, `Set`, `HashMap` and user types. It iterates internally (a `forEach` that can stop early), as CE `for` already does. **Design:** [proposal 0017](docs/proposals/0017-iteration.md), approved at the third design review (decision 57); `Seq`'s impl handles `Yield`.
  2. **Collections:** a mutable `HashSet`, and `Buffer`'s missing functions (push, pop, clear), which the compiler's maps and growing arrays need. *After phase 11:* the rest of F#'s `List`/`Array`/`Map`/`Set` (`groupBy`, `countBy`, `chunkBySize`, `windowed`, `pairwise`, `scan`, `foldBack`, `tryFindIndex`, `Array.binarySearch`, `Map.change`, `Set.isSubset`, …), and `Queue`, `Stack` and `PriorityQueue`.
  3. **Numbers:**
     - **Parsing:** `Float.parse` and `Int.parse` in a radix, returning an `option`; the compiler's lexer and `import c` need them.
     - **`Math`:** *(after phase 11)* it has only `abs` and `sqrt` so far. The rest of libm comes as LLVM intrinsics (`floor`, `ceil`, `round`, `pow`, `exp`, `log`, trigonometry), plus `clamp`, `pi` and `e`.
     - **Integers:** *(after phase 11)* `Int.checkedAdd` (returning an `option`), saturating arithmetic, and the bit operations (`popCount`, `leadingZeros`, `rotateLeft`) that microcontroller code needs.
     - **`Random`:** *(after phase 11)* a seeded PCG in Core, and `Random.shared`, seeded from the OS, in Std.
     - **Bytes:** *(after phase 11)* `Bytes.readU16BE`, `readU32LE`, `writeI64BE`, … over a `span<u8>` (phase 9.6) at an offset, for binary formats and protocols, compiled to one load and a byte swap where the order differs.
  4. **Text:**
     - **Functions:** `padLeft`/`padRight`, `trimStart`/`trimEnd` and `splitLines`.
     - **Formatting:** format specifiers and widths in interpolation, in .NET's syntax (`$"{x:F2}"`, `{n:X8}`, `{name,-20}`).
     - **UTF-8:** *(after phase 11)* `Text.Utf8` converts between bytes and strings, with validation.
     - **`StringBuilder`:** only if measuring shows that reuse doesn't already make `s <- s + x` in a loop linear.
  5. **JSON in Core:** a `Json` union with parse and print, plus `ToJson`/`FromJson` derives (the example in DESIGN §3.1). Track P's provider and the packages build on it.
  6. **Time:** `DateTime.utcNow`, which the compiler's cache needs. *After phase 11:* `Duration` as an integer of nanoseconds, using units of measure, and ISO 8601 parsing and printing. Time zones are a package.
  7. **IO:**
     - **Streams:** `File.openRead` and `openWrite` give readers and writers (`readLine`, `readBytes`, `write`), closed by `use`.
     - **Files and directories:** `readAllBytes`, `File.exists`, `Directory.exists`, recursive listing, copy, move and temporary files.
     - **Processes:** `Process.start` with pipes, an exit code and an environment, awaitable from a task.
  8. **Net:** Unix sockets (`Unix.listen`, `accept`, `connect`: `Tcp`'s functions over a path, on the event loop), which the build server needs (phase 11, decision 76). *After phase 11:* UDP, and name lookup through `Task.blocking getaddrinfo`. TLS and HTTP are packages.
  9. **Generators as one loop:** *(after phase 11)* a `Seq` pipeline compiled as a fused list pipeline is. Simplify floats `let`s and resolves the match on a `Seq` built in the same function, so a stage's handle encloses the generator's code, and Evidence calls a clause that resumes last right where the handle it's in is known (its frame is the one just made) instead of through the frame. Pure code stays as it is (phase 10's exit test).
  10. **`use` under effects:** a stop (a throw, a generator a consumer stopped) runs the disposals of the `use`s it passes over, newest first, as a task's cancellation does: Evidence gives a function that has a `use` open at a call that may yield a stop branch that disposes, instead of only returning.
  11. **Spawned tasks' cancellation, waited for:** *(done in phase 11.5: GitHub's runner lost the race without valgrind)* `Task.run` closes its loop once each spawned task it cancelled has said it's done (its token, `zs_loop_fulfill`), so their `use` values are disposed before it returns, as `tests/task/cancel.zs` says. A runtime change: the loop waits for its tokens still out.
- **Freeze at 1.0:** a review checks every name against .NET and F#. After it, renaming something takes a `[<Deprecated "use X">]` warning for one release.
- **Exit tests:**
  - *After phase 11:* ten Advent of Code puzzles written with only the prelude, Core and Std, with no helper that F#'s library already has.
  - *After phase 11:* in `examples/`, grep, a JSON pretty-printer and `tail -f`, each under 100 lines.
  - Every Core module builds for Cortex-M0+.

### Packages (K)
**Today:** path and git dependencies, `zs.lock` pinning commits, `zs fetch` and `zs update`,
and modules found transitively. Packages stay source (decision 27).
**Design:** [proposal 0018](docs/proposals/0018-packages.md).
- **Wrap before writing:** a community big enough to write and maintain large libraries in Z# isn't coming soon, so a package first wraps a proven C library (or a C++ one through its C API), and Z# code is the typed, idiomatic layer on top. A package is written in Z# from scratch only when no fitting library exists, or the wrapper would be bigger than the code.
  - **C++:** `import c` reads C headers only, so a C++ library without a C API gets a thin `extern "C"` shim, compiled by `zig c++` from the package's `[c]` section (item 4).
  - **Choosing a library:** permissive license, a C API, and builds with `zig cc` for every target with an OS, macOS included; one that also builds for Cortex-M is preferred (mbedTLS over OpenSSL).
- **Next:**
  1. **Namespaced dependencies:** a dependency's modules sit under the name it has in `zs.toml` (`Json.Parser`), so two packages that both have a `Util` module don't collide. This comes first, before there are packages to break.
  2. **Versions:** *(after phase 11)* `json = { git = "…", version = "1.2" }` picks among `v1.x.y` tags.
     - **Minimal version selection,** as in Go: each package gets the highest of the minimum versions asked for it. A build is reproducible without a solver.
     - **Major versions are separate packages** (`json` and `json/v2`), so one program can use both.
  3. **Internal modules:** *(after phase 11)* modules under a package's `internal/` directory are visible only inside it (Go's rule, with no new keyword).
  4. **C dependencies:** a `[c]` section (`link`, `pkg-config`, and C sources compiled with `zig cc`) means a package that wraps sqlite or raylib needs no flags from the projects that use it.
  5. **Targets:** *(after phase 11)* a package that uses Std can't be a dependency of a microcontroller build. The error comes when the build starts and names the package, not some module deep inside it.
  6. **Integrity:** *(after phase 11)* `zs.lock` keeps a hash of each checkout's contents and checks it. `zs vendor` copies the dependencies into the repository, and `--offline` fails instead of fetching.
  7. **Commands:** *(after phase 11)* `zs add json@1.2`, `zs remove` and `zs tree`.
  8. **Workspaces:** *(after phase 11)* `[workspace] members = […]`, with one lock file and one cache.
  9. **Impls across packages (undecided):** an impl may be written in any module for any trait and type, and the program has one impl per (trait, head type) (`Typer.fs` `declareImpl`). So two packages that both write `impl Describe<Point>` each build alone, but a program using both fails with `Describe<Point> is already implemented`, in whichever module is checked second: an error its author didn't write and can't fix. A rule is needed before packages are published, since adding one later breaks them. Candidates: Rust's orphan rule (an impl lives in the trait's package or the head type's; another implementation is a one-case wrapper, free by decision 66), or Haskell's (allowed, a warning on an orphan). Also to settle: a manual impl in a later module suppressing an automatic derive an earlier module needed (`manualImpls` collects every module's).
- **Later: an index, not a registry.** Git URLs work without anyone running a service. When names are worth having, an index can be a git repository that maps each name to a URL and a hash, so that `json = "1.2"` works. `zs publish` opens a pull request against it.
- **First-party packages** (`zsharp/…`, kept building by the compiler's CI): before phase 11, `libclang` and `xxhash`, which the compiler itself uses. *After phase 11:* `http` (client and server on `Net.Tcp` and `Task`, parsing with llhttp), `regex` (over PCRE2), `tls` (over mbedTLS), `sqlite`, `raylib`, and `cli` (argument parsing derived from a record, the one written in Z#).
- **Exit tests:**
  - *After phase 11:* a diamond (A needs C ≥ 1.1, B needs C ≥ 1.3) resolves to C 1.3 on every machine, and `json` and `json/v2` build in one program.
  - *After phase 11:* a project uses `zsharp/sqlite` after nothing more than `zs add`.
  - *After phase 11:* a microcontroller project that depends on a Std package fails with an error naming that package.
  - *After phase 11:* `examples/echo`, rebuilt on `zsharp/http`, serves HTTP.

## Ordering rationale
- **Phase L came before 5 and 6.** Builders, `Task` and optimizations should be built on the language's final shape. Top-level constants also unblocked microcontroller work.
- **Phase 5 came before V and 6.** CPS tasks are only cheap once inlining and reuse work, and benchmarking first kept that claim honest.
- **Phase V came before 6,** for phase L's reason: `dyn Trait`, `weak` and `unsafe` are part of the language CEs and `Task` build on.
- **Phase 7 came after 6.** The thread pool backs both `Task.blocking` and the multi-threaded scheduler.
- **Phase 8 came after 5 and 7.** Vectorization relies on phase 5's representation and aliasing work, and parallel SIMD kernels are the real-world case.
- **Phases 9.5 and 9.6 split infrastructure from language.** Incremental builds and threads come first, so the language features that follow are tested on fast builds.
- **The third design review comes before phase 10.** Effect handlers add effect rows to every function type, the biggest change to the language left, so what the language already has is settled and pruned first.
- **Phase 10 comes last** of the language phases. It needs Task's API stable and opaque, and Perceus; DESIGN §6.1 lists what must stay true until then.
- **Phase 11.5, the platforms, comes before the release:** 0.1 ships where people develop, and each port changes code 0.1's users would otherwise wait on: a calling convention, the runtime off POSIX, the compiler's own processes and paths.
- **Phase 12 comes after 11 and 11.5** (or after 10 if 11 is skipped): a release is worth making once the language is settled, self-hosting has shaken out the bugs a large program finds, and it runs where its users are.
- **The tracks (E, D, M, T, P, S, K) run alongside.** Each phase keeps their tests passing.
- **K1 (namespaced dependencies) comes before anything else in S or K:** it's the only change that would break packages people have already written. The first-party packages come after K2, so they can have versions.

## Done

### Phase 0: skeleton ✅
`int`, `let`, functions, `if`, `extern` (variadic too), `|>`, textual LLVM IR passed to clang.
**Exit test:** `tests/fib.zs`.

### Phase 1: types and data ✅
Unification-based inference with kinds, a typed Core IR, tuples, records, unions, nested
patterns with guards, or-patterns and `as`, and the exhaustiveness and redundancy checker.
**Exit test:** `tests/eval.zs`, an evaluator and pretty-printer for a small expression language.

### Phase 2: core FP and memory ✅
- **Functions:** closures, local functions, partial application, `>>`, tail calls.
- **Generics:** let-polymorphism and monomorphization.
- **Numbers:** every integer and float type.
- **Mutation:** `let mutable`, `for`/`while`, `ref`, arrays.
- **Panics:** bounds, division and `assert` failures.
- **Strings:** with interpolation.
- **Prelude:** written in Z#.
- **Memory:** Perceus RC with drop specialization and in-place reuse. `ZS_LEAKCHECK=1` reports leaks.

**Exit tests:**
- `tests/rbtree.zs`: 1M inserts and lookups, valgrind-clean.
- `tests/binarytrees.zs`: depth 16.
- A reuse check: mapping a unique 100k list doesn't allocate.

### Phase 3: traits, modules, members, derive, C export ✅
- **Traits:** with inferred requirements; operators are traits.
- **Derive:** `derive` with the built-in `Eq`/`Ord`/`Hash`/`Show` derives.
- **Members:** members and type extensions, with named, optional and default arguments.
- **Records and unions:** record defaults, named union fields.
- **Modules:** with `private` and import-cycle errors.
- **Patterns and units:** active patterns, units of measure.
- **Errors:** `?` over `result`.
- **C export:** `[<Export>]`, `[<CLayout>]`, `callback<…>`, `zs build --lib`.

**Exit tests:**
- `tests/cexport`: C calls a Z# library with structs of every ABI class, and back.
- `tests/units`: units mismatch errors, and IR identical to the unitless program.
- `tests/json.zs`: a JSON derive written in Z#.

### First design review ✅
- **Arrays:** copy-on-write values, with `Buffer<'a>` for shared mutation.
- **Overflow:** traps in every build, with `Int.wrapping*`.
- **Compile time:** measured, with `zs build --time`.
- **Panics:** exit 134 without a core dump.

**Exit tests:** `tests/cow.zs`, `tests/overflow.zs`, `tests/panic_div.zs`.

### Phase 4: C import, tooling, targets ✅
- **`import c "header.h"`:**
  - through clang's JSON AST and macro listing: functions, structs, enums and `#define` constants, with `[<Link>]`;
  - saved imports for editors without clang;
  - C hover, completion and definition.
- **Debug info:** `zs build -g` for gdb: lines, functions, backtraces, number locals.
- **Testing:** `zs test` with `[<Test>]`, one process per test; asserts name their file and line.
- **Cross-compilation:** `--target <triple>` through `zig cc` (static musl binaries), with the AAPCS64 C ABI.
- **CLI stdlib:** `Env`, `File`, `Dir`, `Process.run`, exit codes, stdin.
- **Collections:** `Map`/`Set` (AVL) and `HashMap` (a copy-on-write value).
- **Projects:** `zs.toml` with path and git dependencies, `zs.lock`, `zs new`/`fetch`/`update`.
- **The guide:** `docs/guide`, eleven chapters whose examples `./test.sh` runs.

**Exit tests:**
- `examples/raylib`, a window demo written only against `import c "raylib.h"`, builds.
- `./test.sh --target aarch64-linux-musl` passes under qemu. It includes `tests/cexport` and `tests/cimport/abi.zs`, so the C ABI is checked on both architectures.
- `tests/project/wc` is a `wc` clone from a `zs.toml` with a path dependency. `tests/project/git.sh` checks git dependencies.
- `tests/debug/gdb.sh` checks breakpoints, stepping, locals and backtraces.

### Microcontrollers, first part (track M) ✅
- **Targets:** bare-metal `--target cortex-m4` and `cortex-m0plus`, with no OS and no libc.
  - **Runtime:** `rt-embedded.c`, with a static heap, semihosting, a vector table and SysTick.
  - **Boards:** linker scripts for QEMU's `mps2-an386` and `microbit`.
- **Language changes from it:**
  - `int` is the machine word;
  - the bitwise operators `&&& ||| ^^^ <<< >>> ~~~`;
  - `0x`/`0b`/`0o` literals;
  - `Mmio.read32/write32/read8/write8` and `Runtime.ticks`.
- **Optimizations from it** (they help every target):
  - borrowed reads and borrowed parameters;
  - small unions as plain values;
  - list fusion;
  - moves out of mutable variables;
  - copy-on-write checks hoisted out of loops;
  - loop versioning for bounds checks;
  - range, `nuw` and allocator facts for LLVM;
  - piecewise printing of interpolations.

**Exit tests:**
- `bench/mcu/run.sh`: seven programs in Z# and C under QEMU.
  - **Results:** at `-Os` on the Cortex-M4, `crc32`, `isort` and `pipeline` take exactly as many instructions as C. At `-O2`, all of them are within 1.4×; `fib`'s 1.15× is its overflow checks.
  - **Details:** [the report](docs/reports/microcontrollers.md).
- `examples/mcu/uart.zs`: a UART driver in Z#.
- `tests/fusion.zs`, `tests/bitwise.zs`.

### Phase L: language gaps ✅
The syntax freeze ended here. This phase filled in the F# syntax Z# was still missing, before
more features build on the language. New syntax that F# doesn't have needs a design
discussion first.
1. **Top-level values:** constants are inlined at each use, and other values are computed once at startup, in order, then freed at exit. `(e: T)` expression annotations came with them.
2. **Record patterns:** `{ x = 0; y = y }` in matches, `let`, parameters, lambdas and `for`. The record comes from the matched value's type, else from the fields, and missing cases are named in record syntax.
3. **`let rec … and …`:** at the top level (generalized jointly, `private` allowed per function) and locally (lifted with the group's shared captures).
4. **`char`:** a Unicode scalar with literals (`'a'`, `'\u{e9}'`), patterns, conversions, the `Char` functions (ASCII), and `for c in s` decoding UTF-8 in Z#. Strings gained the `\r`, `\'` and `\u{…}` escapes.
5. **Nested modules:** `module Inner =` with an indented block; enclosing modules' names are in scope, `private` reaches nested modules, `open` is scoped to the block.
6. **Custom operators:** `let (>>=) r f = …`, prefix ones (`!r`, `~~x`), `(op)` as a function (built-in operators too), and F#'s precedence by first character; `|>` and `>>` moved to the comparison level, as in F#. A line starting with an operator continues the previous one.
7. **Blocks inside brackets:** a line ending in `->` (or `then`, `else`, `do`) inside a bracket opens a block, so multi-line lambdas and matches work inside parentheses, lists and records; `zs fmt` puts the block one level past its line.
8. **`[<Wrapping>]` on a function:** its integer `+ - *` wrap instead of trapping, lambdas inside included; floats and strings keep their meaning.
9. **String patterns:** `match s with "open" -> …`, in lists and or-patterns too; a match on strings needs a case for the rest.
10. **Multi-line strings:** a string can span lines, and `"""…"""` is raw; `zs fmt` leaves the lines inside a string as written.

**Exit tests:**
- The guide's examples use each feature.
- `examples/mcu/uart.zs` declares its registers as constants.
- The tree-sitter grammar parses all of it.

### Library organization ✅
- **Layers:** the one prelude file became `lib/`: the prelude (global names), Core (no OS needed, so every target) and Std (needs an OS). A microcontroller build leaves Std out, and using it there is a compile error instead of a link error.
- **Namespaces, as in .NET:** `Collections`, `Text`, `IO` and `Diagnostics`, open everywhere at the lowest precedence; full names work too. `namespace X` file headers put types and same-named modules side by side (`Collections.Map`).
- **Names:** .NET's module names (`Directory`, `Environment`) and F#-style functions (`File.readAllText`, `Environment.getVariable`, `Environment.exit`). The old names are gone.
- **New:** `IO.Path`, `Diagnostics.Stopwatch`, `File.writeAllLines`, `String.lastIndexOf`, `Console.Error.writeLine`, and `Show` for `Map` and `Set` (`map [(1, a)]`, `set [1; 2]`).
- **Reference:** one page per module in `docs/reference`, built-in functions included.
- **Fixed on the way:** an `impl` inside a module was registered under the type's short name, so it never applied.

**Exit tests:**
- `tests/library.zs`: namespaces, precedence, full names, `Path`, `Stopwatch`.
- `tests/mcu/std.zs`: Std on a microcontroller is a compile error.
- `./test.sh` checks the library on its own and keeps `docs/reference` current.

### Second design review ✅
Before more of phase 5:
- **Module scope (was a known gap):** record field names, traits and derives belong to their module, like types. Two modules can use the same names, and a record is found by its fields only where its module is in scope.
- **Member access in lambdas:** a lambda without parameter types is typed after the call's other arguments, with the parameter types the call expects. So `names |> List.map (fun s -> s.Length)` needs no annotation, and neither does `List.map (fun s -> s.Length) names`, which F# rejects. An F# programmer meets this on the first day.
- **Panics in a C host:** `zs_set_panic_hook` runs before the process stops. DESIGN §11 has the policy: `result` for errors a caller handles, panics for bugs.
- **Threads:** how a value crosses threads is decided now (DESIGN §7.1), before the optimizer is tuned.
- **Cycles:** DESIGN §5.2 says which values can form them, that they leak, and how to avoid and find them.
- **"Simple":** there's no page budget; a feature has to replace code people would write by hand, and need no runtime.
- **Planning:** phase V and the targets track give every v1 promise and known gap a place.

**Exit tests:**
- `tests/cexport`: the hook runs on a panic, and ends the process its own way.
- `tests/modules/scope.zs`: two modules with the same record, trait and derive names; `err_field_scope.zs`: a record out of scope, found by its fields, is an error that says how to reach it.
- `tests/pipe_inference.zs`: members inside lambdas, through `|>` and without it.

### Phase 5: optimizer I ✅
- **On the microcontroller track, early:** borrow inference, unboxed small unions, bounds-check hoisting (loop versioning), LLVM aliasing and range facts, list fusion (first form).
- **Host benchmark suite:** `bench/host/run.sh` runs fib, binary-trees, nbody, spectral-norm and a red-black tree in Z#, C (clang -O2, and with `-ftrapv`), Rust, Swift, Zig, OCaml and F# (a Release build on .NET, startup included). Outputs must agree; times are best of 3, with peak memory. `./test.sh` fails when a Z# program needs more than 5% more instructions (cachegrind, deterministic) than in `bench/host/baseline.txt`. Details: [the report](docs/reports/host.md).
  - `Math.sqrt` came with it: the LLVM intrinsic, one instruction where the hardware has it.
- **Inlining and re-matching:**
  - A call to a small function that doesn't call itself becomes a copy of its body (callees first; not with `-g`).
  - A branch where a matched value dies matches it again, so it takes the cell apart itself and can reuse it, even when another branch returns the value.
  - Together they rebuild a red-black tree's path in place: 80.9M → 35.5M instructions (C: 16.5M).
- **Decision trees:**
  - A match whose patterns nest becomes a tree of one-level matches, so no value is tested twice.
  - A part reached on several paths is built once, as a join point the paths jump to; reuse tokens and borrowed fields go along as parameters.
  - Measured: the red-black tree's `balance` gains little (35.5M → 35.4M), because LLVM had already merged the repeated tests. Their value is in larger matches and in keeping reuse whole.
- **Reference counts:** the fast paths test the count's sign, as phase 7 needs (DESIGN §7.1): the red-black tree runs 1.7% fewer instructions.
- **Representation** (DESIGN §5.1):
  - **Cases without fields** (`[]`, `Leaf`, `Empty`) are static cells, and a match tells them apart by address, loading nothing.
  - **No tag in a cell** when the union has one case with fields: a list cell or a `binarytrees` node is 24 bytes instead of 32. `binarytrees` now needs C's peak memory (it needed 46% more), and runs 4.8% fewer instructions; the red-black tree 1.4% fewer.
  - **The `option` niche:** `option<string>`, `option<list<int>>` and any union of `option`'s shape over a pointer are the pointer, or one static object for `None`, so `Some s` allocates nothing.
  - **Enums are a byte.** A byte tag next to fields was measured too: it costs an extension at every test on a Cortex-M (4% on `tokens`) and saves no space, so other small unions keep 32 bits.
  - **Not done as first planned:** nullary cases as tagged odd numbers, and `None` as null. Both put a test in every dup and drop of a union (measured: 3.8% more instructions on the red-black tree); static cells keep dup and drop as they were, and matching still loads nothing.
- **Uncurrying:**
  - A function whose body is a lambda takes its parameters (`let add x = fun y -> …` has two), and a lambda returning a lambda merges.
  - A closure applied to several arguments calls code taking all of them when it takes that many, which the closure's static description (drop function, arity, that code) tells. A `List.fold` whose lambda captures a variable built a closure per element: 1,001 allocations over 1,000 elements, now 1.
- **Simplification after inlining** (`Simplify`, DESIGN §9.1):
  - **Known constructors:** a match on a value whose case is known (built there, bound by `let`, or taken by an enclosing case) takes its case at compile time, matching inside its fields directly.
  - **Case of case:** a match on a match or an `if` moves into its branches, and those that build a value take their case; a body reached from several branches becomes a join point.
  - **Lambdas:** one bound by `let` and only called is applied in place.
  - So `match Option.map f o with …`, a `Result.map` on a known result, or an `if` on an inlined `List.isEmpty` build no `option`, `result` or `bool`.
- **Fusion:** a pipeline of `map`s and `filter`s from `List.init`, a list, `Array.init` or an array into `sum`, `sumBy`, `length`, `fold` or `iter` is one loop; one of several stages that builds a list or an array builds only that one (in place when its source's cells are unique). `iter`'s function may print: the stages before it must then be unable to panic (DESIGN decision 36).
- **Compile time:**
  - **The checked library is cached:** the type checker's state after the library, and after a main file's other modules, saved in `~/.cache/zs/checked` under a hash of the compiler and of their sources, and read back in 10 ms without reflection. A build checks only the main file, or its modules too when one of them changed.
  - **A module per source file:** a program of several files becomes one LLVM module per file, each with a copy of the library functions (and generic instances) it uses, so LLVM inlines as it did in one module; a single-file program is one module, as before. The modules, and the runtime, compile in parallel, and each object is kept in `~/.cache/zs/objects` under a hash of its IR, so a rebuild compiles only the modules whose code changed.
  - **Stable code:** every pass names what it makes per function (Mono, fusion, inlining, simplification, decision trees, lifting, reference counting), so a file whose functions didn't change compiles to byte-identical IR, whatever else changed.
  - **Every core:** simplification, decision trees, lifting, reference counting and code generation run per function (or per module) in parallel, with the server GC.
  - **Startup:** the published compiler is precompiled (ReadyToRun: a one-line program then built in 0.42 s instead of 0.71 s), and now as one composite image with FSharp.Core and .NET when self-contained, which the JIT has less left to compile in.
  - **Measured** (the published compiler, wall time): a one-line program builds in 0.20 s, against 0.39 s with the compiler before this work. `bench/compile/run.sh` times a generated program of modules, built from nothing and then after a one-function change: with 10 modules (877 lines), 1.1 s from nothing and **0.46 s** after a change in the main file or a module (2.7 s before); with 30 modules (2,617 lines), 2.5 s and **0.86 s** (8.1 s before).
  - `tests/cache.sh` checks that a program from the cache is the same as one without it, and which modules a change compiles again; every test program was compared the same way. `tests/modules/parts.zs`: what's shared between modules (a case without fields, `None`, a top-level value) is the same object in each.
- **Exit tests:**
  - All five programs within **1.5× of C** (clang -O2), `fib` against C built with `-ftrapv`, whose overflow checks Z# keeps in every build (DESIGN decision 4): `fib` 1.12× of checked C; binary-trees 1.21×, nbody 0.96×, spectral-norm 0.97× and the red-black tree 1.07× of C ([the report](docs/reports/host.md)).
  - The microcontroller suite: the same counts, flash and memory as before, on both chips at both levels ([the report](docs/reports/microcontrollers.md)).
  - A one-function change rebuilds in **under 1 second**: 0.46 s for 10 modules (877 lines), 0.86 s for 30 (2,617 lines), with the published compiler (`bench/compile/run.sh`).
  - `tests/representation.zs`, `tests/uncurry.zs`, `tests/simplify.zs`, `tests/fusion.zs`, `tests/cache.sh`, `tests/modules/parts.zs`.

### Phase V: v1 completion ✅
What DESIGN kept in v1 beyond the syntax (decision 35), and the gaps left in C interop and
debugging, before phase 6 builds computation expressions and `Task` on the final language.
- **`dyn Trait`** (DESIGN §3, decision 43): a value of any type implementing the trait, as a heap object holding the value and a pointer to its type's table of the trait's methods (made when the value is, at its type, by monomorphization: each entry an ordinary function the later passes optimize). A value becomes a `dyn` where one is expected (a declared type, a parameter, a result, through `if` and `match` branches and list elements), with no conversion written. A trait whose method doesn't take the value first, or mentions its type elsewhere (`Ord`'s `compare`), can't be `dyn`, with an error that says which method.
- **Weak references** (DESIGN §5.2): `weak<'a>` to an object, `Weak.create` and `Weak.get`. The weak references to an object share a cell found from it through a table; an object dying empties the cell, whether it's freed or Perceus reuses its cell for another object (which the reuse reports). Only a program with weak references or arenas allocates and frees through the runtime's checked functions: the host benchmarks' instruction counts are unchanged.
- **Arenas** (DESIGN §5.2, decision 44): `Arena.with (fun () -> …)`. What the function allocates comes from the arena's 64 KB blocks, a malloc each (the arena's own record is in its first block), and the blocks go together when the arena's last object does. An object that lives on keeps its blocks, so an arena is memory-safe with no escape analysis. (DESIGN had `fun a ->`; the arena needs no handle, since it's the allocations of the function's run.)
- **Unsafe code** (DESIGN §11): `ptr<'a>` to C data with `Ptr.read`, `write`, `add`, `alloc`, `free` and `cast` inside `unsafe` (an expression or an indented block), and C function pointers, `fnptr<A -> R>`, called like functions inside `unsafe` with C's conventions. `import c` brings function pointer fields and parameters across as `fnptr`s.
- **C interop:**
  - **Argument registers:** on x86-64, a struct whose parts don't all fit in the registers left (6 integer, 8 SSE, less an sret pointer) goes on the stack whole, and later scalars still take the registers left, as C does; for externs, exports and function pointers.
  - **Shared libraries:** `--lib -o x.so` builds one, and the `--lib` archive's code is position-independent, so a C shared library links it whole.
  - **Handles** (decision 45): any other reference-counted Z# value crosses as an opaque `zs_handle` with its own count, `zs_retain` and `zs_release` in the generated header: a handle a function returns is the caller's, one passed in is lent for the call (exported functions now own their parameters, as main does).
- **Debug info:** gdb shows strings as their text, and tuples, records and plain unions (a union's case as an enumeration, then each case's fields) by field; an enum is its case's name.
- **Units of measure:** Kennedy's general case. When no variable's exponent divides the others, the one with the smallest becomes a fresh variable times the rest's quotients, and the rest is solved again: `same (sq x) (cube y)` makes x's unit some `'w^3` and y's `'w^2`, with no annotations.
- **Exit tests:**
  - A tree with `weak` parent links is freed completely, valgrind- and `ZS_LEAKCHECK`-clean, and a weak reference sees its object die when Perceus reuses the object's cell (`tests/weak.zs`).
  - `binarytrees` with an arena per tree calls `malloc` per arena block, not per node: 2 mallocs per tree of 31 nodes, 3 per tree of 2,047, against 2,047 without the arena (`tests/arena.zs`).
  - A list of `dyn Shape` values from different types, built-in and derived impls through `dyn Show` (`tests/dyn.zs`), and a C library's struct of function pointers called from Z# (`tests/cimport/ops.zs`).
  - A C program links the library as a `.so`, and a C shared library links a `--lib` archive whole (`--whole-archive`) with a C program calling Z# through it (`test.sh`, over `tests/cexport`).
  - C holds a tree and a closure as handles, valgrind-clean (`tests/chandle`); structs past the argument registers (`tests/cimport/abi.zs`).
  - `tests/debug/gdb.sh` prints a string, a record and a union.
  - Kennedy's general case (`tests/units/kennedy.zs`).

### Phase 6: computation expressions and Task ✅
- **The gate** (DESIGN §6): the spike compiled one built-in `Async` effect by evidence passing with yield bubbling, and CPS, by hand (`bench/effects`, [the report](docs/reports/effects-spike.md)). The effect allocates less (none for an await that completes at once, against CPS's 5; 2 for one that suspends, against 7), but it can't be type-checked without effect rows on function types, polymorphic through generic code, which are phase 10's. So `Task` is CPS, as planned; phase 9's state machines take the allocations away.
- **Computation expressions** (DESIGN §4, decision 46): `w { }` uses the module `W.Builder`. The parser rewrites `let!`, `do!`, `return`, `return!`, `use`, `for` and an `if` without `else` into its `bind`, `ret`, `using`, `forEach` and `zero`, and the whole body into `delay`, so a cold task runs it when it runs. A form whose function the builder lacks is an error at that form; DESIGN's `Builder` trait couldn't name functions over a type constructor. A line ending in `name {` opens a block, as `->` does. `use x = e` works in plain code too, with the prelude's `Dispose` trait.
- **Libraries:** `option { }` and `result { }` (`Option.Builder`, `Result.Builder`).
- **`Task<'a>`** (`lib/std/Threading/Task.zs`): cold, its work given a cancellation and a continuation.
  - **Structured concurrency:** `Task.both`, `all`, `race`, `timeout`, and `Task.scope` with `Task.start` (a `Promise` gives a started task's result; `Task.wait`, `Task.fulfill`). Child tasks can't outlive what started them.
  - **Cancellation** flows down through each task's cancellation, and a race cancels its loser: what it waits on is dropped (RC releases the continuation) and what it bound with `use` is disposed, newest first.
  - **The stack:** a continuation called inside another is counted, and the 64th goes through the event loop, so a run of awaits that complete at once doesn't grow the stack.
- **Runtime** (`runtime/rt.c`): an epoll event loop (kqueue with macOS, track T) owning Z# closures (each program's IR has the functions it calls them with), with descriptors, a timer heap and a ready queue; `Task.blocking` runs a function on a helper thread that signals the loop through a pipe, and the runtime counts objects atomically only in programs that use it.
- **I/O and timing:** `Task.sleep`; `Net.Tcp`'s `listen`, `accept`, `connect`, `read`, `write` and `writeText` over non-blocking sockets (`Task.waitFor` for others); `File.readAllTextAsync` and `writeAllTextAsync` on the helper thread.
- **Exit test:** the echo server (`examples/echo`) holding 10,000 connections, each sending a line a second and checking its echo: for the hour of `bench/echo/soak.sh`, 32,564,673 round trips with none failed, and the server's memory the same 20,936 KB at every minute from the first to the last (the machine slept for 3.5 hours after minute 47, and the connections went on after it). Under valgrind with 10,000 connections for 30 s (288,928 round trips), stopped by a client's `quit` with the connections still open: exit 0, no errors or leaks. `./test.sh` runs it with 1,000 connections (under valgrind with `--valgrind`): `tests/task/echo.sh`.
- **Tests:** `tests/ce.zs`, `tests/err_builder.zs`, `tests/task/basics.zs` (timers, both, all, race and timeout cancelling with `use`, scope, `Task.blocking`, async files).

### Phase 7: parallelism ✅
- **Thread pool** (`runtime/rt.c`, DESIGN §7): Chase–Lev deques (Lê et al.'s C11 version with release/acquire and sequentially consistent operations instead of fences, which ThreadSanitizer doesn't model), a thread per core (`ZS_WORKERS`), work stealing, sleeping workers woken by a fork. A job is a `share<unit -> 'a>` closure and a runner in the program's IR that stores its result in the job, so `Parallel.both`'s results and `Array.Parallel`'s parts come back to the joining thread without being marked shared.
- **What crosses threads** (decision 47): the `Share` trait, built in and structural (numbers, strings, records, unions, tuples, lists and arrays of Share; `share<F>`; `Atomic`, `Mutex`, `Channel`; not `ref`, `Buffer`, `weak`, `dyn`, C pointers or plain functions). `share<F>` is the type of a function another thread runs: a lambda, local or top-level function where one is expected is checked there (what it captures, through captured local functions), and after monomorphization the compiler follows its calls to any top-level value that isn't Share. A `share<F>` is called and passed as an `F`.
- **Shared reference counts** (DESIGN §7.1): a program with threads has `dup` and `release` that count a shared object (negative count) atomically; the rest is unchanged. Each type has a function marking a value's objects shared (a closure's description has one for what it captured), run where a value crosses: a job's closure, `Task.spawn`'s and `Task.blocking`'s functions, `Mutex` contents, `Channel.send`, and top-level values at startup. Perceus's specialized drop dups a non-unique cell's kept fields before giving up its reference, and copy-on-write copies an array from past its count.
- **Library:** `Parallel.both`, `for` (``` ``for`` ```: the lexer and the grammar take F#'s double-backtick names) and `reduce`; `Array.Parallel.init` and `map` (each part built on its thread, then joined); `Atomic` (numbers, `bool`, `char`: get, set, exchange, compareExchange, add), `Mutex` (a futex lock: get, set, update), `Channel` (bounded, any number of senders and receivers). `Array.concat` in Core.
- **Tasks on every core** (decision 48): an event loop per thread; `Task.spawn` runs a task on one of a set of loop threads to the end, and its result comes back through the spawning loop's inbox (a pipe its epoll watches), which `Task.blocking`'s helper also uses now. The echo server spreads its connections over them with `--threads`. Weak references and arenas lock their tables in a program with threads; an arena is per thread.
- **Tools:** `zs build --sanitize=thread` (ThreadSanitizer).
- **Exit tests** (`bench/parallel/run.sh`, best of 3 runs, next to C versions with pthreads that take one row, or 16 bodies, at a time):

  | Program | 1 thread | 8 | 16 | ×8 | ×16 |
  |---|---|---|---|---|---|
  | mandelbrot 8000×8000 | 2213 ms | 319 ms | 243 ms | 6.94 | 9.11 |
  | mandelbrot, C | 2070 ms | 304 ms | 245 ms | 6.81 | 8.45 |
  | nbody, 6000 bodies, 10 steps | 1553 ms | 280 ms | 306 ms | 5.55 | 5.08 |
  | nbody, C | 1556 ms | 269 ms | 300 ms | 5.78 | 5.19 |

  - **On this machine** (a laptop's 8-core Ryzen 7 PRO 8840U with SMT, whose clock drops as more cores run): mandelbrot reaches 0.87 × 8 cores; nbody 0.69 ×, as C's nbody does (0.72 ×), so the bar of 0.8 × measures the machine there: Z# scales as C does, within 4%.
  - **ThreadSanitizer** reports nothing for both, nor for `tests/parallel/basics.zs` and `tests/task/spawn.zs`, which `./test.sh` runs under it.
  - **A `ref` sent to another thread** is a compile error, captured directly, through a local function, in a record, sent on a channel, or reached as a top-level value (`tests/err_share.zs`, `err_share_global.zs`, `err_share_param.zs`).
- **Tests:** `tests/parallel/basics.zs` (every API; captured and top-level values; copy-on-write of a shared array; trees built in arenas on other threads; the same output on 1, 2 and 16 workers), `tests/task/spawn.zs`, and `tests/task/echo.sh` with `--threads`. Valgrind and the aarch64 suite pass.

### Phase 8: SIMD ✅
- **Vector types** (DESIGN §8, decisions 49 and 50): every number type at 128, 256 and 512 bits (`f32x4` … `u64x8`, 30 types) and masks (`mask2` … `mask64`), built in as LLVM's `<n x T>`, printed as `<1, 2, 3>`.
  - **Operators:** `+ - * / %` lane by lane through `Add`, `Num` and `Eq` (`=` on whole vectors); integer vectors wrap, and integer division checks every lane; `&&& ||| ^^^`, and shifts by an `int`, on integer vectors and masks.
  - **Functions,** a module per type (`F32x8.load`): `splat`, `init`, `load`, `store` (in place when unique), `get`, `set`, `sum`, `min`, `max`, `reduceMin`, `reduceMax`, `abs`, six comparisons giving masks, `select`, `shuffle` (constant indices, checked), conversions between vectors with as many lanes (saturating into integers), and `sqrt`, `floor`, `ceil`, `round`, `mulAdd` for floats; masks' `any`, `all`, `count`, `not`, `get`.
  - **Memory:** a program with 32- or 64-byte vectors allocates 64-byte aligned (`zs_alloc_wide`), and arrays of them size their header by the vector's alignment.
- **Bounds checks out of loops:** loop versioning takes `for` loops with any constant step, SIMD loads, and indices that are the loop variable plus or minus values the loop doesn't change (`up + x - 1`); reading an array through a record field (`b.x`) borrows it as reading a variable's does.
- **`[<FastMath>]`:** a function's float `+ - * /` become LLVM's `fast` ones, so its reductions vectorize.
- **Targets:** `--cpu` (`-march` on x86-64, `-mcpu` elsewhere); `[<Target "avx2,fma">]` (LLVM's target-features; such a function isn't inlined into others); `[<Multiversion("avx2,fma", "sse4.2")>]`: a version for each and the baseline, behind a dispatcher that asks the runtime once (`zs_cpu_supports`: cpuid on x86-64, the auxiliary vector on aarch64 Linux).
- **Intrinsics:** `Simd.X86` (16: `rsqrt`, `rcp`, `hadd`, `movemask`, `pshufb`, `pmaddwd`, `psadbw` at 128 and 256 bits) and `Simd.Arm` (5: `frsqrte`, `frecpe`, `faddp`, `tbl`, `sdot`). One for the other architecture, or needing a feature the build doesn't have (a known `--cpu` level, or the function's `[<Target>]`), is a compile error saying which.
- **Library:** `Array.copy` copies at once (a builtin).
- **Exit test** (`bench/simd/run.sh`, best of 3 runs, C with AVX or NEON intrinsics; x86-64 for x86-64-v3, aarch64 cross-compiled and run under qemu-user):

  | | dot | nbody | blur |
  |---|---|---|---|
  | x86-64, Z# / C | 65 / 63 ms (1.03) | 83 / 82 ms (1.01) | 77 / 74 ms (1.04) |
  | aarch64, Z# / C | 6062 / 6132 ms (0.99) | 14662 / 14722 ms (1.00) | 3266 / 3135 ms (1.04) |

  The same Z# source for both: a `f32x8` is one AVX register on x86-64 and two NEON registers on aarch64. The blur blurs between two images in both (allocating an image a pass cost Z# 2.5× before).
- **Tests:** `tests/simd/basics.zs` (every operation, at 128, 256 and 512 bits), `attributes.zs`, `x86.zs`, `arm.zs` (built for aarch64 and run under qemu by `./test.sh`), `err_simd.zs`. The microcontroller suite runs as before.

### Phase 9: optimizer II ✅
- **Task state machines** (DESIGN §6): `task { }` is compiled in direct style. The parser turns `let!`, `do!` and `return!` into waits in the task's body, and the code generator makes the task's work an LLVM coroutine (switched resume). Its frame is allocated once, when the work starts, behind a closure header (the face); a wait passes the face as the continuation of the task it waits for, with its code set for that task's result type, so a wait allocates nothing, and one whose task is ready goes on at once. A task cancelled at a wait is destroyed there, dropping what it held. `task { }` needs no builder now (`option { }` and `result { }` keep theirs).
- **The pool** (DESIGN §5.2): in a program without threads, objects up to 256 bytes come from free lists of 8-byte size classes, carved from 64 KB chunks: no system allocator call per object. Larger objects, threads, sanitizers and valgrind (`ZS_NO_POOL`) use `malloc`.
- **A one-word header** (DESIGN §5.1): the 32-bit count, and on 64-bit targets the tag of a union's case and the pool's size class beside it. A union cell with a tag lost its tag word, and a pooled object needs no allocator word before it. On 32-bit chips the count is the word, and a tag keeps a word of its own, as before. A count past 2³¹ references turns negative and stays: the object is never freed. **Not done as planned:** Koka's number of fields to scan, which drops generated per type have no use for.
- **ThinLTO** on the host: the modules and the runtime are compiled to bitcode and optimized together at the link (lld, with its cache), so the runtime's allocation functions inline into the program (`ZS_NO_LTO=1` turns it off). `binarytrees`: 0.43 s without it, 0.31 s with it.
- **PGO:** `zs build --profile-generate`, a run, `llvm-profdata merge`, then `zs build --profile-use <file>`. A module's IR is named after its source file, so the profile finds its internal functions in the next build: named after a temporary file, it found none, and `binarytrees` got 9% slower. With the profile, `binarytrees` is 6% faster and `rbtree` 1–4% (`tests/pgo.sh`).
- **The module cache:** each module's object is kept under a key of everything its code is made from (the compiler and settings, the types, its functions after lambda lifting with their borrowed parameters, the signatures of what it calls in other modules), so a rebuild runs reference counting, LLVM IR and clang only for the modules that changed. Borrowed parameters are found for the whole program first, in parallel rounds that walk each body once. With the published compiler, a one-function change rebuilds a 30-module program (2,617 lines) in 0.61 s (0.86 s before) and a 10-module one in 0.35 s (0.46 s); a one-line program builds in 0.17 s (0.20 s). First builds are slower with ThinLTO: 2.8 s and 1.4 s (2.5 s and 1.1 s).
- **LLVM 23.1** in the dev container: LLVM's own release, in `/opt/llvm`.
- **Microcontrollers, measured again:** linking the runtime as bitcode changes nothing at `-Os`, and at `-O2` costs 1.4–3.1 KB of flash for gains that aren't the runtime's, so it stays a separate object ([the report](docs/reports/microcontrollers.md)).
- **Not done as planned: the LLVM C API backend.** DESIGN made it wait until compile time demands it, and it doesn't: on a program's 8 MB of IR, clang spends 2.6% of its time parsing the text (0.22 s of 8.4 s), compiling from bitcode instead saves 3%, and the module cache skips unchanged modules' IR altogether. LLVM's release also has no shared libLLVM to bind to.
- **Exit tests:**
  - **No allocation per await:** a task that waits 10 times and one that waits 200,000 times both make 7 allocations (`tests/task/awaits.zs`, half the waits on ready tasks, half suspending through the event loop).
  - **The phase 5 suite within 1.2× of C** (best of 3, [the report](docs/reports/host.md)): `fib` 1.00× of C with `-ftrapv` (1.76× of plain C), `binarytrees` 0.26×, `nbody` 0.88×, `spectralnorm` 0.96× and `rbtree` 0.89×, with less memory than C on the tree programs (26 MB against 34 and 31).
- **Tests:** `tests/task/awaits.zs`, `tests/pgo.sh`; `tests/cache.sh` checks the module cache, and `tests/arena.zs` gives the same counts with the pool and without it. The suite passes under valgrind and on aarch64 (qemu); the microcontroller suite gives the same counts and flash, except two ratios clang 23 moved.

### Phase 9.5: incremental builds and threads ✅
- **Checking by module** ([proposal 0007](docs/proposals/0007-incremental-builds.md)): each module's checked result (what it adds to the checker's state, its functions' Core and its hovers) is kept under a key of its source, the C declarations it imports and the interfaces of the modules it sees, so a body change re-checks its module alone and a changed signature the modules that use it. The checker's state is tables that log what each module adds; an interface is a hash of the module's declarations with their types as they print. The two snapshot layers are gone.
- **Code by file:** a file's code is two LLVM modules, its own functions and its copies of the library's and of generic functions (`weak_odr`), made from its world: its functions, the copies they use, and of other files only their ABI (types after uncurrying, borrowed parameters, what threads can't share). A world is kept under the keys it was made from and checked when found, so a file whose code didn't change skips monomorphization through code generation. Nothing of another file's code is inlined into a file's (ThinLTO inlines across files at the link).
- **One cache:** the CLI, `zs lsp`, `zs mcp` and `zs doc` share `~/.cache/zs`, and a running server keeps the 512 most recent results in memory; an unchanged file isn't parsed (a summary of it is kept). In the editor a keystroke re-checks the edited module (43 ms on a 2,000-line file), and the open documents whose programs have it are checked again.
- **Threads** ([proposal 0008](docs/proposals/0008-threads.md)): any thread forks onto the pool, with a deque of its own given back when it ends. A job waiting in a channel, or for a mutex past a short spin, starts a spare worker (up to twice the cores; past that a panic counts the blocked jobs), so a channel of capacity 0 is a rendezvous between jobs. Cancelling a task cancels the tasks it spawned, each on its own loop, which disposes their `use` values. A handle of a Share value is marked shared and works on any thread; any other panics on another thread, naming its type, and so does a `callback<F>`, while a `callback<share<F>>` parameter takes one C may call on any thread.
- **Debug and release builds:** `zs build` is a debug build (the program at `-O0`, the runtime at `-O2`, linked by lld without ThinLTO); `zs build --release` is the optimized one, with ThinLTO and PGO. Z#'s own passes run in both, so a program allocates the same in both, and tail calls stay constant-stack (`musttail` at `-O0`). `-O0` to `-O3` set the level; a microcontroller's build stays optimized. The benchmarks build with `--release`.
- **The build server:** `zs build` hands its work to a `zs server` that stays running (a Unix socket in the cache, one per cache directory and environment), so a rebuild skips starting .NET and finds the compiler warm and the results in memory; the first build starts it and builds on its own, and it ends after ten idle minutes or with `zs server stop` (`ZS_NO_SERVER=1` builds in the process). A build it serves is the binary an in-process build makes (`tests/server.sh`).
- **Compile time** (`bench/compile/run.sh`, the published compiler, on AC power): on 30 modules (2,617 lines) an unchanged rebuild takes 0.11 s, a body change in the main file 0.11 s and in a module 0.18 s, an interface change 0.15 s; a first build 1.9 s, and one without the cache 0.93 s. Each timed build follows a change of its own (phase 9's 0.61 s was the best of three builds of one change, the last two from its caches). Built with `--release` and in its own process, a module's body change takes 0.51 s: ThinLTO's backend for the changed module (0.17 s) and clang (0.07 s) are most of it.
- **Exit tests:**
  - **Under 0.2 s:** in the 30-module program a body change rebuilds in 0.11 s (in the main file) and 0.18 s (in a module), re-checking its module alone, and a signature change re-checks exactly the modules that use it (`tests/cache.sh`, from the modules `zs build --time` names).
  - **The same binary:** a build after the edits is the binary a build from an empty cache makes, and every test program built from the cache is the one built from nothing (`tests/cache.sh`).
  - **Forking from any thread:** `Parallel.for` inside a spawned task uses every worker, and two pool jobs pass values through a channel of capacity zero (`tests/parallel/anythread.zs`, under TSan too).
  - **Cancelling across threads** disposes the `use` values of the tasks spawned on other threads (`tests/task/cancel.zs`).
  - **C's threads:** a C thread releasing a non-Share handle panics with its type; a Share one works from 16 threads under Helgrind (`tests/cthreads`).
- **Tests:** `tests/cache.sh` checks each step against a build without the cache; `tests/lsp/modules.sh` checks a document whose module changed in another one.

### Phase 9.6: ergonomics, spans and C structs ✅
- **The F# forms** ([proposal 0005](docs/proposals/0005-ergonomics.md)):
  - **Generic constants:** a constant whose type has type variables is generic, each use an instance of its own, so `Map.empty`, `Set.empty` and `HashMap.empty` are values (`HashMap.empty` makes its buckets at the first `add`). A generic value computed at startup is an error that says to make it a function. `[]` is a constant (a static cell), and hover shows a generic constant's scheme.
  - **`?` on `option`:** the errors are at the `?`. One on an `option` in a function returning `result`, or the reverse, names the conversion, and one in a function returning `unit` says so.
  - **Compound assignment** on every place `<-` assigns: a `let mutable`, a `ref`'s `.Value`, an element, a field of a mutable record however nested, a `fixed`'s element, a `Buffer`'s. The place's parts are evaluated once.
  - **`function`**, the first case's bar optional as in F#.
  - **List and array expressions:** `for`s, `if`s, `let`s, `match`es, `yield`, `yield!` (of a list, an array or a string) and ranges. One `for` over a list, an array or an int range, with `if`s and a value whose parts are arithmetic on immutable locals, is the pipeline fusion makes one loop of: `[ for x in xs do if x % 2 = 0 then yield x * 10 ]` allocates only its result, and under `List.sum` nothing. Any other body runs in order, consing onto a list reversed in place at the end.
- **Spans and slices** ([proposal 0003](docs/proposals/0003-spans-and-slices.md)): a `span<'a>` is its owner, a pointer to its first element and a length, three words in registers, and a `Buffer` is now the same window, writable, so a Buffer's slice is a Buffer sharing its storage. `a.[i..j]`, `a.[..j]` and `a.[i..]` slice arrays, Buffers and spans (a slice out of range panics, naming the range and the length); a string's slice is a string, at byte offsets between characters. An array or a Buffer becomes a span where one is expected, as a value becomes a `dyn`, and the library's reading functions (`Array.sum`, `fold`, `iter`, `exists`, `contains`, `map`, `mapi`, `filter`, `rev`, `sort`, `toList`, `Buffer.toArray`) and SIMD loads take spans. An `extern`'s span parameter is a pointer and a length, and `Span.ofPtr` makes a span over C memory in `unsafe`. New: the `Span` module, `Array.ofSpan`, `Buffer.ofSpan`, `Buffer.slice`, `String.bytes` and `String.ofBytes` (a malformed byte becomes U+FFFD, as decoding does).
- **Fixed-size arrays** ([proposal 0004](docs/proposals/0004-c-layout.md)'s first part): `fixed<'a, N>` is a value of N elements inline. A number is a type argument there only, and a type variable only in `Fixed`'s own functions, which work for every N. It has `f.[i]`, `f.[i] <- x` on a place, `Fixed.init`, `create`, `get`, `set`, `length`, `toArray`, `ofArray`, `iter`, `map` and `fold`, `for x in f`, and element-wise `Eq`, `Ord`, `Hash` and `Show`. `import c` brings array fields in (`uint8_t data[16]`, and `float m[2][2]` as `fixed<fixed<f32, 2>, 2>`), takes array parameters as pointers, and passes structs with arrays by value under each calling convention; the generated header writes them back as C arrays.
- **Left to other proposals:** `Bytes.readU32LE` and the rest of 0003's byte readers are [proposal 0024](docs/proposals/0024-library-api.md)'s (track S); C unions and layout facts (0004's other parts) and anonymous records (0006) wait for phase 12.
- **The grammar** has the new syntax (its generated parser grew from 6.0 to 8.4 MB), and the Zed extension pins it.
- **Exit tests:**
  - **C structs:** `import c` of a header with array fields imports them, and a function taking a `CXCursor`-shaped struct (32 bytes, with `const void *data[3]`) by value works (`tests/cimport/fixed.zs`).
  - **Generic constants:** `Map.empty` and `Set.empty` work without `()` at two types in one function (`tests/generic_constants.zs`), and `examples/` and the guide use them so.
  - **`?` on options:** it returns `None` early (`tests/question_option.zs`), and its errors' carets are under the `?` (`tests/err_question*.zs`).
  - **A test each** for `function`, list and array expressions and slices (`tests/function.zs`, `tests/listexpr.zs`, `tests/spans.zs`); a list expression with a filter allocates only its result (3 objects for 3 elements, none under `List.sum`).
  - **Spans:** a parser over `span<u8>` reads a file's bytes without copying them (its only allocations are its result's cells), and a span keeps its array alive after the array's last other reference goes, with nothing leaked (`tests/spans.zs`).
  - **`+=`** on a `ref`, an array element and a mutable record's field, with an index whose expression has an effect, evaluates the place once (`tests/compound.zs`).
  - **`Array.sum`** takes an array, a Buffer and a slice of either (`tests/spans.zs`), and a string slice that would cut a character panics (`tests/slice_char.zs`).
- **Tests:** also `tests/fixed.zs`, `tests/fixed_length.zs` and `tests/slice_range.zs`, and one for each new error.

### Third design review ✅
Before phase 10, with phases 9–9.6 built:
- **"Simple" again:** every feature since the second review was checked against decision 39. Built: all pass (each replaced code written by hand, and none added a runtime). Planned: anonymous records are cut (they replace a one-line declaration, not code, and give a record two spellings); fixed-point numbers stay as a Core library whose one language change is decision 66; bit fields, layout facts, C unions, `[<Section>]` and `[<Align>]`, the `Cpu` intrinsics, async on bare metal and type providers pass.
- **How many kinds:** the five references (`ref`, `Buffer`, `weak`, `span`, `ptr`) and four functions (plain, `share<F>`, `callback<F>`, `fnptr<F>`) stay, and none merge: each differs in what it holds or where it may go, and the newcomer errors name the right one. No fifth function kind: 0012's `noalloc<F>` is declined, a call through a closure counts as allocating. Phase 10's effect rows go on the function type inside each kind, so they add none. The guide's memory chapter has the table of when to use which (decision 67).
- **Errors a newcomer meets:** `tests/newcomer/`, 34 programs with the first mistakes of F# and C programmers. About 25 messages were added or extended so each names the problem, points at it and says what to write: F#'s `printfn`, `sprintf`, `null`, `try`, `raise`, classes, `mutable` fields, `.Value`, `.ToString()`, `async`, `seq` and a function that calls itself without `rec`; C's `=`, `++`, braces, `return`, `!`, an int as a condition, an int where a float is, a tuple passed to a curried function; and what to use instead of a `ref` or `Buffer` that crosses threads.
- **Scope:** phase 12's "before 0.1" list is written out there; everything else marked *after phase 11* follows 0.1. A non-unit value discarded in statement position (F#'s warning 20) becomes a warning kind in 0021, `unused-value`.
- **Proposals:** approved in principle: 0001 (after 0.1), 0013, 0015 (as a library), 0016, 0017 (before phase 11), 0020, and the draft parts of 0004, 0012 (without `noalloc<F>`) and 0014. Declined: 0006's anonymous records; its top-level patterns stay. 0002's open questions: named handler instances wait for a program that needs them; rows are written after the result type, as proposed; polymorphic operations are allowed; interrupt handlers have empty rows; `Task` on `Async` is phase 10's measurement.
- **Phase 11, go:** 0020's first criterion holds (every replacement is scheduled before phase 11, 0017 now among them), and the "before 0.1" list is short enough for the third. The second (a 1,000-line Z# program of the compiler's shape within 1.5× of F#) is phase 11's first step; a miss sends 0.1 out on the .NET compiler, with the rewrite after it.

**Exit tests:**
- `tests/newcomer/`: 34 programs, each with its expected error, checked by `./test.sh`.
- DESIGN §13: decisions 56–71 record each feature kept or cut, with the reason.

### Phase 10: effect handlers ✅
**Design:** [proposal 0002](docs/proposals/0002-effect-handlers.md); the guide's [chapter 16](docs/guide/16-effects.md); the measurements in [the report](docs/reports/effects.md).
- **Effect types:** `effect` declarations and `handle … with`, with rows of effects after a function's result (`a -> b / E`, `/ <E, F | 'e>`, `/ <>`), Leijen's scoped labels. Inferred and row-polymorphic: the library's higher-order functions (`List.iter : ('a -> unit / 'e) -> list<'a> -> unit / 'e`) carry their arguments' effects with no signature rewritten. A function's effects are on its last parameter's arrow; a row ending a top-level function's own is closed when it's generalized and opened where it's referenced. Hover shows rows, and an inlay hint a function's inferred effects before its `=`.
- **Empty rows where no handler can be**, each an error naming the effect: `main`, a top-level value's initializer, a `task { }` body, an `[<Export>]` and a `callback<F>` (the C-callback rule), a `share<F>` and a trait's method.
- **Compilation** (the Evidence pass, after Simplify): evidence passing with yield bubbling. A function with effects takes a frame per effect; a clause's path that resumes last, or stops without the resumption, runs where the operation is performed; any other path yields, each function on the way making the rest of itself a closure. A loop with calls that may yield runs its rounds from a driver, so no stack grows with them at `-O0` either. The yield state is a thread-local (`zs_yield`; a global on bare metal) that a program with effects defines itself, so the runtime is unchanged. Resumptions are one-shot (a second call panics).
- **The library:** the prelude's `Yield` and `Throw` effects; `Throw.catch`, `recover`, `ofResult` and `ofOption`; `seq { }` (`yield` anywhere in it, `yield!`) and the `Seq` module (`map`, `filter`, `take`, `skip`, `takeWhile`, `collect`, `append`, `unfold`, `fold`, `sum`, `toList`, `exists`, `tryFind`, …); `for x in s` over a `Seq`.
- **The `Task` measurement** (`bench/effects/async.zs`): `Task` over an `Async` effect allocates 7 objects per wait that suspends (the frames waiting, the resumption) and takes 61 ms for a million rounds of a ready wait and a suspending one; `task { }` allocates none per wait and takes 24 ms. So `Task` stays on phase 9's state machines (decision 72), and the echo soak and `tests/task/awaits.zs` are as they were.
- **Generators** (`bench/effects/seq.zs`): a million elements through `filter`, `map` and `sum` allocate 11 objects in all (none per element) in 2.96 ms; the same over a list, fused into one loop, 0.62 ms. Fusing generator pipelines is track S's item 9.
- **The benchmarks** (host, SIMD, parallel, microcontrollers) measure the same binaries as before: a program without effects compiles to the binary the compiler made before the phase. Compile time: checking a module 2–9% longer, a rebuild 1–4% ([the report](docs/reports/effects.md)).
- **Found by the release's soak:** since phase 9's state machines, a `return!` that ends a task waited for the task it names, so each round kept a state machine: the echo server, whose connections loop by `return!` (as `Tcp`'s own loops do), grew 170 MB a minute. `return!` last now gives that task what waits for this one (`Task.handOff`, DESIGN §6), as phase 6's builder did: a million rounds peak at 2 MB, not 252. `tests/task/awaits.zs` checks 20,000 rounds of 8 KB state machines in steady memory (165 MB before). The soak: 33.1 million round trips in the hour, none failed, and the server's memory the same 26,428 KB at every minute.
- **Editors:** the grammar has `effect`, `handle` and rows (its generated parser grew from 8.4 to 9.2 MB), and the Zed extension pins it. Hover on an operation shows its type and goes to its declaration; a clause's operation is a reference to it.
- **Exit tests:**
  - **A generator pipeline and a typed-exception example:** `tests/effects/generators.zs` (`evens 100 |> Seq.map … |> Seq.take 3 |> Seq.toList` is `[4; 16; 36]`; infinite sequences, `yield!`, a recursive generator, a million elements) and `tests/effects/exceptions.zs` (a throw from inside loops and local functions, caught into a `result`), with `tests/effects/handlers.zs` (state, collecting, nested handlers, resumptions kept for later, a clause performing an outer effect, ten million rounds through a handler), `modules.zs` (effects across modules), `corners.zs` (an effect in a member, in a record field's type, through a partial application, a handle at every level of a recursion) and `oneshot.zs`. All pass under valgrind, in `-g` builds and on aarch64; `tests/mcu/effects.zs` runs on a Cortex-M0+.
  - **Pure functions compile to identical IR:** all 106 programs without effects (the tests', the benchmarks and the examples) compile to byte-identical LLVM IR, debug binaries and release binaries before the phase and after it (one test renames a record field named `handle`, now reserved), but for the four that end a task with `return!` (the `return!` fix above): the echo server and client, `tests/task/cancel.zs` and `awaits.zs`.
  - **The C-callback rule:** a function given to C that performs an effect is an error naming it (`tests/effects/err_callback.zs`), as is one run on another thread (`err_thread.zs`), and `main`'s unhandled effect (`err_unhandled.zs`); also errors for a clause's type, an unknown operation, a declared row, a `seq { }` performing more, and a task's body.
  - **`Task` on `Async`:** measured, and not moved (above), so its benchmarks are unchanged, and so is the echo soak but for the `return!` fix.

### Phase 11: self-hosting ✅
**Design:** [proposal 0020](docs/proposals/0020-self-hosting.md); the phase 11 review (decisions 73–79); the compiler's map, [src/ARCHITECTURE.md](src/ARCHITECTURE.md); the measurements in [the report](docs/reports/self-hosting.md).
- **The compiler is Z#** (`src/`, 27,800 lines): the lexer and parser on 0019's lossless tree, the checker (`Infer`, the F# `Typer` ported), the passes through `Rc`, textual LLVM IR, the driver with 0007's caches (checked modules, worlds, module objects, objects, ThinLTO's), `zs fmt`/`check`/`build`/`run`/`test`/`doc`, the project commands, the LSP, the MCP server and the build server, and `--check-ir` (`Core.Check` after each pass, on in `./test.sh`). The F# compiler (`src/*.fs`, `Zs.fsproj`) and the .NET SDK left the repository and the container; it's tagged `v0.5`, and `v0.6` is the last commit with both.
- **The bootstrap:** `./dev` fetches stage 0, the release it pins (0.6, from `$ZS_RELEASES`, `dist/` until releases have a public home), and `./test.sh` builds `src/` with it. `tests/bootstrap.sh` (in `./test.sh`) builds `src/` `--release` by the compiler, by that build and by that one: gen 2 and gen 3 are the same bytes, under one worker and under the cores, and each generation's IR is kept to name the module that differs if one does (one run of the suite had the one worker's gen 3 differ: another session edited `src/Infer/Derive.zs` mid-run and the last generation compiled it, so every generation builds one copy of the tree now). `src/release.sh` makes a release the same way and archives gen 3 with its library and runtime (`src/install.sh`).
- **The suite under it:** every `.out`, `.err`, transcript and benchmark contract the F# compiler passed, with `--check-ir` on; the aarch64 cross suite; `bench/mcu`'s table on a Cortex-M4 and a Cortex-M0+, the F# compiler's to the byte.
- **Every mistake of a declaration** (`tests/err_many.zs`, `tests/lsp/many.sh`): a statement whose check fails reports its error (`Fails.report`, through the handlers that place and word a failure) and its block goes on, what it binds of its declared type or a fresh one, the types it bound undone (`Vars.mark`/`undo`); a declaration's errors come in the file's order, the same from `zs check`, `zs build` and `zs lsp`. The error type that unifies with anything is still to come.
- **On the pool:** `Lift`, `Simplify`, `Decide` and `Rc` per function (`Rc` across the modules too), code generation per LLVM module and the library's parsing, through `Array.Parallel` (decision 76), each job with tables of its own; a job owns what it walks (its functions moved in, a copy of the types decoded from bytes). Checking and borrowing's rounds stay on one thread. The runtime counts objects per thread and gives each thread a pool of its own: its global atomic counters made 16 threads slower than one.
- **Speed and memory** (against the F# compiler published with ReadyToRun): the compiler builds itself from nothing in 14.90 s debug and 45.60 s release (the F# compiler 15.16 s and 46.84 s, stage 0 93 s), is faster on every incremental build and every row of `bench/compile`, and takes a quarter of the F# compiler's memory there and 57% of it debug and 88% release on itself. Clang runs as the F# compiler ran it, a core taking the next module when it's free (the biggest first), and code generation writes into a `StringBuilder` as the F# compiler's did. The per-function passes summed over their jobs take no longer than one worker under the same load (between 26% less and 6% more on 2, 4 and 8 workers: the report), 0020's 10% as it's meant; code generation's jobs, per module, take up to twice as long, still to explain.
- **Found on the way:** maps and sets compared by their trees' shapes, `File.writeAllBytes` through text, a mutable lost in an effectful lambda without `Simplify`, ThinLTO inlining into a `musttail` call (both compilers: a call into another LLVM module is a plain tail call now), range formatting's no-op edit, a quadratic `String.join`, clang run in batches that waited for their slowest, the object cache evicting an object the link was about to read.
- **Exit tests:** `cmp` of gen 2 and gen 3 under `ZS_WORKERS=1` and the cores; `./test.sh` green under the Z# compiler with `--check-ir`; `bench/compile` and the self-build against the F# compiler (the report); `tests/err_many.zs`; `ZS_STATS=1` on `tests/stats/parallel_unique.zs` (no object marked shared) and on the compiler building itself, where lifting and code generation mark only the environment their jobs read and `Simplify`, `Decide` and `Rc` also what their jobs share (a callee inlined at several call sites, a library instance in several modules' copies); hover on an `import c` name with no `clang` on PATH (`tests/lsp/cimport.sh`, and `import c without clang` from the saved import); `unsafe` only in `zsharp/libclang` (the compiler names the keyword where it lexes, checks and documents it).
