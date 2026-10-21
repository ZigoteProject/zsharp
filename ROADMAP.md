# Z# roadmap

Every phase ends with **exit tests**: programs in `tests/` (or scripted checks) that must pass,
along with the whole `./test.sh`. Design and rationale: [DESIGN.md](DESIGN.md). Learning the
language: [the guide](docs/guide/README.md).

**Development** happens in a container (`.devcontainer/Containerfile`: Fedora 44, .NET 10,
clang/LLVM 22, zig, valgrind, gdb, qemu-user, qemu-system-arm, raylib).
- **Commands:** `./dev ./test.sh` runs the suite, plain `./dev` opens a shell, and `./dev --rebuild` rebuilds the image.
- **Rule:** run one `./dev` at a time. Each start relabels the repository for SELinux, which cuts off a container already running.
- **Test modes:** `./test.sh --valgrind` runs everything under valgrind. `./test.sh --target aarch64-linux-musl` runs it cross-compiled under qemu.

```
 v1 (single-threaded)                                                          v2 (threads)                          v3
 0 ─ 1 ─ 2 ─ 3 ─ 4 C import, tooling, MCUs ─ L language gaps ─┬─ 5 optimizer I ──┐
                                                               └─ 6 CE + Task ────┴─ 7 parallelism ─ 8 SIMD ─ 9 optimizer II ─ 10 effects ─ (11 self-host)
 done ──────────────────────────────────── │ next
```

- **v1 (phases 0–6 and L):** the complete single-threaded language. It is fast, memory-safe, has C interop, and runs async on one event loop.
- **v2 (phases 7–9):** threads, parallelism, SIMD and the final performance work.
- **v3 (phase 10+):** effect handlers.
- **Tracks:** editor tooling (E) and microcontrollers (M) run alongside the main line.

## Where things stand

**Works today:**
- **Language:** inference, records with defaults, unions, exhaustive matching (record, string and character patterns), active patterns, units of measure, traits, derives, members with named and optional arguments, nested modules, closures, generics, custom operators, `char`, multi-line and raw strings.
- **Memory and performance:** Perceus RC with borrowing and reuse, copy-on-write arrays, checked arithmetic. On compute code it's as fast as C on a Cortex-M.
- **Library:** a prelude, Core (collections, text, options, results: every target) and Std (console, environment, files, paths, processes, timing: targets with an OS), in .NET-style namespaces.
- **C:** C import and export.
- **Targets:** x86-64, aarch64 (cross), Cortex-M4 and M0+ (bare metal).
- **Tooling:** projects with path and git dependencies, `zs test`/`fmt`/`doc`, gdb debug info, and an LSP, MCP server and Zed extension.

**Known gaps** (in priority order; each is in a phase below):
1. **Optimizer (phase 5):**
   - no case-of-case;
   - fusion only starts from `List.init`;
   - no host benchmark suite in CI;
   - the library is re-checked on every build: about 200 ms of each compile, and 20 ms more since it is split into modules (caching each module's checked Core removes it).
2. **C ABI:**
   - running out of argument registers isn't modelled (x86-64 then passes a struct on the stack whole);
   - 32-bit ARM passes structs by value with the x86-64 rules;
   - C function pointers can't be called from Z#;
   - no `.so` output.
3. **Debug info:** strings, records and unions aren't shown as gdb values.
4. **Editor:** no signature help, rename or code actions; the formatter doesn't reflow long lines.
5. **Units of measure:** Kennedy's general case (a fresh variable) isn't implemented, so unannotated `*` across different units needs annotations.
6. **Modules:** record field names, traits and derives share one global namespace.

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

### Design-review fixes ✅
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
- **The guide:** `docs/guide`, eleven chapters whose 39 examples `./test.sh` runs.

**Exit tests:**
- `examples/raylib`, a window demo written only against `import c "raylib.h"`, builds.
- `./test.sh --target aarch64-linux-musl` passes under qemu. It includes `tests/cexport` and `tests/cimport/abi.zs`, so the C ABI is checked on both architectures.
- `tests/project/wc` is a `wc` clone from a `zs.toml` with a path dependency. `tests/project/git.sh` checks git dependencies.
- `tests/debug/gdb.sh` checks breakpoints, stepping, locals and backtraces.

### Microcontrollers (track M, first part) ✅
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
- `bench/mcu/run.sh`: six programs in Z# and C under QEMU.
  - **Results:** at `-Os` on the Cortex-M4, `crc32`, `fir` and `isort` take exactly as many instructions as C. At `-O2`, all of them are within 1.4× except `fib`, which pays 1.15× for overflow checks.
  - **Details:** [the report](docs/reports/microcontrollers.md).
- `examples/mcu/uart.zs`: a UART driver in Z#.
- `tests/fusion.zs`, `tests/bitwise.zs`.

### Phase L: language gaps ✅
The syntax freeze is over. This phase fills the F# syntax Z# is still missing, before more
features build on the language. New syntax that F# doesn't have needs a design discussion
first.
- **Scope**, in order:
  1. **Top-level values (done):** constants are inlined at each use, and other values are computed once at startup, in order, then freed at exit.
     - **Annotations (done):** `(e: T)` expression annotations came with them.
     - **Still to do:** constant *arrays* in flash on microcontrollers; today they are startup values in RAM.
  2. **Record patterns (done):** `{ x = 0; y = y }` in matches, `let`, parameters, lambdas and `for`. The record comes from the matched value's type, else from the fields, and missing cases are named in record syntax.
  3. **`let rec … and …` (done):** at the top level (generalized jointly, `private` allowed per function) and locally (lifted with the group's shared captures).
  4. **`char` (done):** a Unicode scalar with literals (`'a'`, `'\u{e9}'`), patterns, conversions, the `Char` functions (ASCII), and `for c in s` decoding UTF-8 in Z#. Strings gained the `\r`, `\'` and `\u{…}` escapes.
  5. **Nested modules (done):** `module Inner =` with an indented block; enclosing modules' names are in scope, `private` reaches nested modules, `open` is scoped to the block.
  6. **Custom operators (done):** `let (>>=) r f = …`, prefix ones (`!r`, `~~x`), `(op)` as a function (built-in operators too), and F#'s precedence by first character; `|>` and `>>` moved to the comparison level, as in F#. A line starting with an operator continues the previous one.
  7. **Blocks inside brackets (done):** a line ending in `->` (or `then`, `else`, `do`) inside a bracket opens a block, so multi-line lambdas and matches work inside parentheses, lists and records; `zs fmt` puts the block one level past its line.
  8. **`[<Wrapping>]` on a function (done):** its integer `+ - *` wrap instead of trapping, lambdas inside included; floats and strings keep their meaning.
  9. **String patterns (done):** `match s with "open" -> …`, in lists and or-patterns too; a match on strings needs a case for the rest.
  10. **Multi-line strings (done):** a string can span lines, and `"""…"""` is raw; `zs fmt` leaves the lines inside a string as written.
- **Exit tests:**
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

## Next

### Phase 5: optimizer I
**Done early, on the microcontroller track:**
- borrow inference;
- unboxed small unions;
- bounds-check hoisting (loop versioning);
- LLVM aliasing and range facts;
- list fusion (first form).

**Started:**
- **Host benchmark suite (done):** `bench/host/run.sh` runs fib, binary-trees, nbody, spectral-norm and a red-black tree in Z#, C (clang -O2), Rust, Swift, Zig and OCaml. Outputs must agree; times are best of 3, with peak memory. `./test.sh` fails when a Z# program needs more than 5% more instructions (cachegrind, deterministic) than in `bench/host/baseline.txt`.
  - **Details:** [the report](docs/reports/host.md).
  - **First measurements** (time Z# / C): fib 1.87, binary-trees 1.30, nbody 0.93, spectral-norm 0.98, red-black tree 1.79 (4.9× the instructions).
  - `Math.sqrt` came with it: the LLVM intrinsic, one instruction where the hardware has it.
- **Inlining and re-matching (done):**
  - A call to a small function that doesn't call itself becomes a copy of its body (callees first; not with `-g`).
  - A branch where a matched value dies matches it again, so it takes the cell apart itself and can reuse it, even when another branch returns the value.
  - Together they rebuild a red-black tree's path in place: 80.9M → 35.5M instructions (C: 16.5M).
- **Decision trees (done):**
  - A match whose patterns nest becomes a tree of one-level matches, so no value is tested twice.
  - A part reached on several paths is built once, as a join point the paths jump to; reuse tokens and borrowed fields go along as parameters.
  - Measured: the red-black tree's `balance` gains little (35.5M → 35.4M), because LLVM had already merged the repeated tests. Their value is in larger matches and in keeping reuse whole.

**Scope:**
- **Core IR passes:** case-of-known-constructor, case-of-case, uncurrying.
- **Representation:** `i8` enums, the null niche for `option<ref>`, tagged nullary constructors.
- **Fusion:** from lists and arrays as sources, `map` into list consumers, and `iter`.
- **Host benchmark suite in CI:** against C, OCaml and F#; a regression of more than 5% fails.
- **Compile time:** checked Core cached per module, keyed by content hash (libraries are source, DESIGN §9). A one-function change rebuilds in under 1 second.

**Exit tests:**
- fib, binary-trees, nbody, spectral-norm and the red-black tree each run within **1.5× of C** (clang -O2) on the host.
- The microcontroller suite stays within its current ratios.

### Phase 6: computation expressions and Task
- **Gate first** (DESIGN §6): a time-boxed spike of a single `Async` effect with evidence passing. Its result decides whether `Task` is a library over effects (and phase 10 moves up) or CPS.
- **Scope:**
  - **CE syntax:** builders as modules plus a `Builder` trait: `let!`, `do!`, `return`, `return!`, `use`, `for`, `if`.
  - **Libraries:** `result { }`, `option { }`.
  - **`Task<'a>`:** cold, with structured concurrency (`both`, `all`, `race`, `scope`) and cancellation that runs `use` cleanup.
  - **Runtime:** a single-threaded epoll/kqueue event loop in `rt.c`, and `Task.blocking`.
  - **I/O and timing:** sockets, files and timers.
- **Exit test:** a TCP echo server holding 10k concurrent connections, with flat memory over a 1-hour soak test, valgrind-clean on shutdown.

### Phase 7: parallelism
- **Scope:**
  - **Thread pool:** work-stealing, with Chase–Lev deques.
  - **Safety:** the `Share` auto-trait, checked at `Parallel.*` and channel boundaries.
  - **Shared RC:** atomic RC only on objects marked shared.
  - **Parallel APIs:** `Parallel.both`, `for` and `reduce`, and `Array.Parallel.map`/`init`.
  - **Sync primitives:** `Atomic`, `Mutex`, `Channel`.
  - **Scheduler:** the Task scheduler becomes multi-threaded.
- **Exit tests:**
  - Parallel mandelbrot and nbody scale to at least 0.8 × the core count (8 cores), clean under ThreadSanitizer.
  - Sending a `ref` to another thread is rejected at compile time.

### Phase 8: SIMD
- **Scope:**
  - **Vector types:** portable `f32x4`, `f32x8`, `f64x4`, `i32x8`, … with operators, `load`/`store`/`splat`/`shuffle`/`select` and reductions.
  - **Float control:** `[<FastMath>]`.
  - **Target control:** `--cpu`, `[<Target>]`, `[<Multiversion>]`.
  - **Intrinsics:** `Simd.X86`, `Simd.Arm`.
- **Exit test:** dot product, nbody and an image blur in SIMD Z# run within **10% of C with intrinsics**, from the same source on x86-64 and aarch64.

### Phase 9: optimizer II
- **Scope:**
  - **Task speed:** `task { }` as stackless state machines, with no allocation per `let!`.
  - **Linking and profiling:** ThinLTO and PGO on the host. Measure again on microcontrollers, where bitcode linking of the runtime lost.
  - **Backend:** the LLVM C API instead of textual IR.
  - **Build speed:** parallel module compilation.
- **Exit tests:**
  - A Task microbenchmark makes zero allocations per await.
  - The phase 5 suite reaches **1.2× of C**.

### Phase 10: effect handlers (v3)
- **Scope:**
  - `effect` and `handle`, with inferred row-polymorphic effect types.
  - One-shot resumptions compiled by evidence passing.
  - The C-callback rule.
  - Generators (`seq { }`) and typed exceptions.
- **Exit tests:**
  - A generator pipeline and a typed-exception example.
  - Pure functions compile to identical IR before and after this phase.

### Phase 11: self-hosting (optional)
The compiler, rewritten in Z#, compiles itself, and the second-generation build is
byte-identical.

## Microcontroller track (M)
Tier 2 (DESIGN §10): every phase keeps `bench/mcu` working and within its ratios.
- **Next:**
  1. **Interrupt handlers:** `[<Interrupt "SysTick">] let tick () = …`, placed in the vector table, with the rules for sharing state with them.
  2. **Constants in flash:** this needs top-level values from phase L.
  3. **More boards:** linker scripts for STM32F4 and RP2040, flashing through `probe-rs` or OpenOCD, and RTT output as an alternative to semihosting.
  4. **RISC-V:** ESP32-C3, under QEMU first.
  5. **32-bit ARM C ABI:** AAPCS for structs by value.
  6. **Heap:** reusing blocks larger than 256 bytes, and a heap size set in `zs.toml`.
- **Later:** async on bare metal (phase 6 `Task` over interrupts, with no OS).

## Editor tooling track (E)
Zed first. Everything is plain tree-sitter, LSP and MCP, so other editors and agents get the
same support through a thin extension each.

**Done:**
- **E1:** a tree-sitter grammar (checked against every `.zs` file by `./test.sh`), and a Zed extension (grammar pinned by commit, `./test.sh` checks the pin).
- **E2a:** `zs lsp` with diagnostics, hover with types, constraints and doc comments, inlay hints, symbols and formatting.
- **E2b (part):** definition, references, completion (C names included).
- **E3:** `zs mcp` with `check`, `type_at`, `docs`, `build`, `run`, `emit_llvm`, `format`.
- **F:** `zs fmt`, token-based, meaning-preserving, keeping the repository formatted.
- **Documentation:** `///` doc comments and `zs doc`.

**Next:**
- **E2b, rest:** signature help, rename, code actions (add missing match cases, add an annotation).
- **F2:** a lossless syntax tree, so `zs fmt` can reflow lines to 100 columns; `zs fmt --stdin`; range formatting.
- **E3, rest:** `definition` and `explain` tools.
- **Exit tests:**
  - A 2,000-line file re-checks within 100 ms in Zed.
  - Given a file with a type error, Zed's agent fixes it using only the MCP tools.

## Ordering rationale
- **Phase L comes before 5 and 6.** Builders, `Task` and optimizations should be built on the language's final shape. Top-level constants also unblock microcontroller work.
- **Phase 5 comes before 6.** CPS tasks are only cheap once inlining and reuse work, and benchmarking first keeps that claim honest.
- **Phase 7 comes after 6.** The thread pool backs both `Task.blocking` and the multi-threaded scheduler.
- **Phase 8 comes after 5 and 7.** Vectorization relies on phase 5's representation and aliasing work, and parallel SIMD kernels are the real-world case.
- **Phase 10 comes last.** It needs Task's API stable and opaque, and Perceus; DESIGN §6.1 lists what must stay true until then.
- **The tracks (E, M) run alongside.** Each phase keeps their tests passing.
