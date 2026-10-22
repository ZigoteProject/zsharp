# Z# roadmap

Every phase ends with **exit tests**: programs in `tests/` (or scripted checks) that must pass,
along with the whole `./test.sh`. Design and rationale: [DESIGN.md](DESIGN.md). Learning the
language: [the guide](docs/guide/README.md).

**Development** happens in a container (`.devcontainer/Containerfile`: Fedora 44, .NET 10,
clang/LLVM 22, zig, valgrind, gdb, qemu-user, qemu-system-arm and raylib, plus Rust, Swift and
OCaml for the host benchmarks).
- **Commands:** `./dev ./test.sh` runs the suite, plain `./dev` opens a shell, and `./dev --rebuild` rebuilds the image.
- **One at a time:** run one `./dev` at a time, since runs share `bin/`. The container mounts the repository with a shared SELinux label (`:z`). A tool that mounts it with a private one (`:Z`) cuts off a container that's running.
- **Test modes:** `./test.sh --valgrind` runs everything under valgrind. `./test.sh --target aarch64-linux-musl` runs it cross-compiled under qemu.

```
 v1, single-threaded:  0 ─ 1 ─ 2 ─ 3 ─ 4 ─ L ─ 5 optimizer I ─ V v1 completion ─ 6 CE + Task
 v2, threads:          7 parallelism ─ 8 SIMD ─ 9 optimizer II
 v3:                   10 effect handlers ─ (11 self-hosting)
 alongside:            E editors, M microcontrollers, T more targets

 done: 0–5, L and V        now: 6
```

- **v1 (phases 0–6, L and V):** the complete single-threaded language. It is fast, memory-safe, has C interop, and runs async on one event loop.
- **v2 (phases 7–9):** threads, parallelism, SIMD and the final performance work.
- **v3 (phase 10+):** effect handlers.
- **Tracks:** editor tooling (E), microcontrollers (M) and more targets (T) run alongside the main line.

## Where things stand

**Works today:**
- **Language:** inference (lambdas get their parameter types from the call), records with defaults, unions, exhaustive matching (record, string and character patterns), active patterns, units of measure, traits, `dyn` values, derives, members with named and optional arguments, nested modules with their own fields and traits, closures, generics, custom operators, `char`, multi-line and raw strings, raw pointers in `unsafe`.
- **Memory and performance:** Perceus RC with borrowing and reuse, copy-on-write arrays, weak references, arenas, checked arithmetic, and an optimizer that inlines, uncurries, resolves known constructors and fuses pipelines. On the host benchmarks it's within 1.21× of C with C's peak memory, except `fib` (2.0×: overflow checks; 1.1× of C with the same checks). On compute code it's as fast as C on a Cortex-M.
- **Library:** a prelude, Core (collections, text, options, results: every target) and Std (console, environment, files, paths, processes, timing: targets with an OS), in .NET-style namespaces.
- **C:** C import and export (static and shared libraries), C function pointers, Z# objects held by C as handles, and a panic hook for C hosts.
- **Targets:** x86-64, aarch64 (cross), Cortex-M4 and M0+ (bare metal).
- **Tooling:** projects with path and git dependencies, `zs test`/`fmt`/`doc`, gdb debug info (strings, records and unions as values), and an LSP, MCP server and Zed extension.

**Known gaps** (in priority order, each with the phase or track that closes it):
1. **Concurrency (phase 6):** no computation expressions or `Task`; I/O blocks.
2. **C ABI (track M):** 32-bit ARM passes structs by value with the x86-64 rules.
3. **Weak references and arenas on microcontrollers (track M):** they're hosted-only so far; the embedded runtime lacks their functions.
4. **Debug info (track E):** lists and other boxed unions aren't shown as gdb values (plain unions are).
5. **Editor (track E):** no signature help, rename or code actions; the formatter doesn't reflow long lines.
6. **Targets (track T):** no macOS or Windows builds.

## Next

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
  - **Shared RC:** atomic RC only on objects marked shared, as DESIGN §7.1 describes.
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
  - **Build speed:** the passes after type checking run over the whole program in every build (in parallel since phase 5, but most of a rebuild of a large program: 0.6 s of the 0.86 s a 2,600-line program of 30 modules takes); keeping their result per source file would make a rebuild follow the size of the change.
  - **Object header:** one word: a 32-bit count, the tag and the number of fields to scan, as in Koka. A union cell with a tag has two words today, as do strings and arrays (a count and a length).
- **Exit tests:**
  - A Task microbenchmark makes zero allocations per await.
  - The phase 5 suite reaches **1.2× of C** (`fib`: of C with `-ftrapv`).

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

## Tracks

### Microcontrollers (M)
Tier 2 (DESIGN §10): every phase keeps `bench/mcu` working and within its ratios.
- **Next:**
  1. **Interrupt handlers:** `[<Interrupt "SysTick">] let tick () = …`, placed in the vector table, with the rules for sharing state with them.
  2. **`[<NoAlloc>]` (DESIGN §10):** a compile error if a function, or anything it calls, may allocate or free heap memory. The error names the call chain down to the allocation (a string, a closure, a boxed union, …).
     - **Checked on Z#'s own IR,** after borrow inference, unboxing and list fusion, so the result doesn't depend on `-O`, and a fused pipeline or a small union passes.
     - **Externs** count as not allocating: C is outside the check.
     - **Interrupt handlers** are `NoAlloc` implicitly, since the allocator isn't reentrant.
     - **`--no-heap`:** the whole program is checked, and the image has no heap.
  3. **Constants in flash:** constant arrays placed in flash, instead of startup values copied to RAM.
  4. **More boards:** linker scripts for STM32F4 and RP2040, flashing through `probe-rs` or OpenOCD, and RTT output as an alternative to semihosting.
  5. **RISC-V:** ESP32-C3, under QEMU first.
  6. **32-bit ARM C ABI:** AAPCS for structs by value.
  7. **Heap:** reusing blocks larger than 256 bytes, and a heap size set in `zs.toml`.
  8. **Weak references and arenas:** the embedded runtime's versions of their functions (the host's use the C library's allocator).
- **Later:** async on bare metal (phase 6 `Task` over interrupts, with no OS).

### Editor tooling (E)
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
- **Debug info, rest:** lists and other boxed unions as gdb values.
- **Exit tests:**
  - A 2,000-line file re-checks within 100 ms in Zed.
  - Given a file with a type error, Zed's agent fixes it using only the MCP tools.

### More targets (T)
Tier 3 (DESIGN §10), through `zig cc` as the Linux cross builds are.
- **Next:**
  1. **macOS arm64:** Mach-O output and Apple's arm64 calling convention. Phase 6's event loop uses kqueue there.
  2. **Windows x64:** PE output, the Microsoft x64 calling convention, and a port of `rt.c` off POSIX.
- **Testing:** build-only until a machine runs the suite: a build-only mode of `./test.sh --target` cross-compiles every test program.
- **Exit test:** every test program builds for both.

## Ordering rationale
- **Phase L came before 5 and 6.** Builders, `Task` and optimizations should be built on the language's final shape. Top-level constants also unblocked microcontroller work.
- **Phase 5 comes before V and 6.** CPS tasks are only cheap once inlining and reuse work, and benchmarking first keeps that claim honest.
- **Phase V comes before 6,** for phase L's reason: `dyn Trait`, `weak` and `unsafe` are part of the language CEs and `Task` build on.
- **Phase 7 comes after 6.** The thread pool backs both `Task.blocking` and the multi-threaded scheduler.
- **Phase 8 comes after 5 and 7.** Vectorization relies on phase 5's representation and aliasing work, and parallel SIMD kernels are the real-world case.
- **Phase 10 comes last.** It needs Task's API stable and opaque, and Perceus; DESIGN §6.1 lists what must stay true until then.
- **The tracks (E, M, T) run alongside.** Each phase keeps their tests passing.

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
