# Proposal 0011: debug info, profiles and traces

| | |
|---|---|
| **Status** | Approved in principle: debugging items 1, 3 and 5 and profiling items 2 and 3 before phase 11; the items the roadmap marks *after phase 11* stay so |
| **Decided at** | track D's plan ([ROADMAP](../../ROADMAP.md#testing-profiling-and-debugging-d)), closing known gap 3 ([where things stand](../../ROADMAP.md#where-things-stand)) |
| **Builds** | track D: profiling and debugging |
| **Rests on** | decisions 2 (Perceus), 5 (panics), 32 (editor support), 42 (`[<NoAlloc>]`) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §12](../../DESIGN.md#12-tooling) Debugging and Profiling |
| **Related** | [0009 tests as values](0009-tests-as-values.md) (coverage shares the positions and the `llvm-profdata` tools), [0012 interrupts, NoAlloc, intrinsics](0012-interrupts-noalloc-intrinsics.md) (`[<NoAlloc>]` is the allocation analysis made an error), [0022 macOS and Windows](0022-targets-macos-windows.md) (lldb and symbols on macOS), [0003 spans](0003-spans-and-slices.md) (a span printer), [0008 threads](0008-threads.md) (`ZS_STATS` counts spare threads), [0007 incremental builds](0007-incremental-builds.md) (hints kept per module), [0021 warnings](0021-warnings.md) (hints aren't warnings) |

- [x] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

Track D's rule: wrap before writing. gdb, lldb, rr, perf, samply, Perfetto and the Firefox
Profiler exist; Z# gives them what they need to show Z# code, and writes no tool of its own.
What that takes, in one place:

- **Debug info for every value:** unions as DWARF variant parts, heap cells as pointers to their layout, arrays and strings with their lengths, so gdb and lldb show lists, boxed unions, `ref`, `weak`, spans and arrays with no scripts. Pretty-printers, shipped inside `zs` and loaded by the debugger itself, cover only `Map`, `Set` and `HashMap` (entries, not trees), closures (function and captures) and a span's elements.
- **`-g` at any optimization level,** `--profile` (frame pointers, line tables and symbols at `-O2`, so perf and samply show Z# names and lines) and `--stats` (counters in compiled code).
- **Panics** name Z# functions in their backtrace from the binary's symbol table, with lines in `-g` and `--profile` builds.
- **`zs profile`** runs samply (perf without it) and opens the result; **`zs debug`** starts gdb or lldb with the printers, or writes an editor's launch configuration for gdb's and lldb's own Debug Adapter Protocol servers.
- **`ZS_STATS=1`** prints what Perceus's choices cost; **`ZS_TRACE=file`** writes one trace in Chrome's JSON trace-event format, which Perfetto reads, with sampled allocations, tasks, threads and pool jobs.
- **Allocation hints in the editor:** `zs lsp` marks the lines that allocate, free, reuse a cell, copy on write or mark objects shared, from the allocation analysis [0012](0012-interrupts-noalloc-intrinsics.md) defines.

```sh
zs build server.zs -g -O2 -o server          # DWARF with LLVM's locations, optimized
zs debug server.zs -- --port 8080            # gdb with the printers; `zs tasks` lists what waits
zs profile server.zs -- --port 8080          # samply, Z# names and lines, opened in the browser
ZS_STATS=1 ./server                          # at exit: allocations by size, peak, reuse hits …
ZS_TRACE=trace.json ./server                 # open in ui.perfetto.dev
```

Approval adds a new decision row, numbered by the coordinator: debugging and profiling wrap
the existing tools; DWARF carries every value and printers only what DWARF can't say; the
runtime's counters print in any build and compiled code counts only under `--stats`.

## Motivation

- **A release build's crash.** `-g` builds at `-O0` only (`Driver.fs`, the `opt` flags, facts sheet §11), so a crash that happens only at `-O2` is debugged by reading IR. gdb at `-O2` with LLVM's locations shows the line and most locals, which is what C programmers have.
- **A list in gdb.** A `list<int>` local shows nothing today: `diType'` describes numbers, strings, tuples, records and plain unions and gives up on everything boxed (`Codegen.fs` `| _ -> None`, facts sheet §11), so `declareVar` skips the variable. Known gap 3.
- **A panic's backtrace** prints what `backtrace_symbols_fd` finds (`rt.c` `zs_panic_c`, about line 56): the dynamic symbol table, which holds `main` and the runtime's functions, not Z#'s internal symbols, so a Z# frame is `./prog(+0x4f2a)`. Lines never. On musl builds there is no backtrace at all.
- **Where the time goes.** perf on a release build shows function names but no lines, and without frame pointers samply's stacks break at Z# frames. Nothing opens a profile for you.
- **What Perceus decided** is invisible unless `ZS_DUMP_CORE` is read. Whether `List.map` reused its cells, whether an array copied on write, whether a value's counts went atomic: a programmer tuning a program needs the numbers, and `Runtime.allocations` (rt.c, about line 151) is the only one today.
- **A hung server** shows ten loop threads in `epoll_wait` and nothing about the tasks waiting on them.
- **Microcontrollers** have the same gdb through a probe or QEMU's stub, and no way to profile but a stopwatch.

## Detailed design

### Debugging

| # | Item | Design | When |
|---|---|---|---|
| 1 | every value, from DWARF | unions as variant parts, cells as pointers to their layout, arrays and strings with their lengths (*DWARF for every value*, below); printers for `Map`, `Set`, `HashMap`, closures and spans (*Pretty-printers*) | next |
| 2 | lldb | the same DWARF; the printers' lldb half in the same file; `zs debug --lldb` imports it (default on macOS, [0022](0022-targets-macos-windows.md)); the gdb tests run under lldb in macOS CI | after phase 11 |
| 3 | optimized builds | `-g` with `-O1`, `-O2` or `-Os` keeps the level; `-g` alone stays `-O0` (stepping follows the source, [guide](../guide/10-tools.md)). At `-O1` and above the compiler describes variables with `#dbg_value` on SSA values instead of stack slots and `#dbg_declare` (today's `declareVar`, `Codegen.fs` about line 1826), marks the compile unit `isOptimized: true`, and LLVM keeps what it can: a dropped local prints `<optimized out>`, an inlined call shows as an inlined frame. `musttail` calls (every non-self tail call, `Codegen.fs` about line 2660) replace the caller's frame, so a backtrace skips them, and a self tail call is a loop | next |
| 4 | editors | `zs debug --config zed` writes `.zed/debug.json` (`--config vscode`: `.vscode/launch.json`) naming the program, its arguments, gdb's built-in adapter (`gdb -i dap`, gdb 14 and later) or `lldb-dap`, and for lldb the printer import; the editor starts the adapter. No adapter of Z#'s own | after phase 11 |
| 5 | panics | the runtime walks the stack (`backtrace` on glibc; frame pointers in `-g` and `--profile` builds, musl included), reads `.symtab` and `.strtab` from `/proc/self/exe` with the load address from `dl_iterate_phdr` (about 100 lines of C, an estimate; run only at the panic), and prints Z# names: `  at Parser.expr`. With `-g` or `--profile` it adds `file:line` through `llvm-symbolizer` or `addr2line` when one is on PATH, as the sanitizers do. Symbols are kept in every build (the table isn't loaded at run time: file size, not memory); `zs.` and ThinLTO's `.llvm.<n>` suffixes are stripped. `ZS_BACKTRACE=0` and `ZS_ABORT=1` keep their meanings; macOS's lookup is [0022](0022-targets-macos-windows.md)'s | next |
| 6 | tasks | `zs tasks`, a command in the shipped script for gdb and lldb, reads each loop thread's state (the thread-local loop struct in `rt.c`, about line 1052: the timer heap, the descriptor waits, the ready ring, the inbox) and prints one line per waiting callback: what it waits on (a timer and its deadline, a descriptor and the direction, a helper job, a spawned task's token) and the task's function, taken from the coroutine frame's resume pointer behind the face (`Codegen.fs` about line 1778). With `-g` the frame's locals print too (LLVM describes coroutine frames). The runtime is compiled with the program's `-g`, so the structures have DWARF | after phase 11 |
| 7 | recording | nothing in the runtime changes for rr (epoll, futex, `pthread`, `posix_spawn` are all it uses); `tests/debug/rr.sh` records `prog`, replays it, and reverse-continues to a breakpoint, skipped where `rr record true` fails (no performance counters: most containers) | after phase 11 |
| 8 | microcontrollers | `zs debug --target cortex-m4 prog.zs` starts QEMU with its gdb stub (`-s -S`) and gdb on the ELF; `--probe` connects to `probe-rs gdb` or OpenOCD instead. The DWARF is the same, and gdb reads the printers from the ELF's section. A panic under an attached debugger ends in `bkpt`, so gdb stops with the stack intact; without one it exits through semihosting as today (facts sheet §8) | after phase 11 |

### DWARF for every value

Today's `diType'` (`Codegen.fs` about line 1615, facts sheet §11) describes a plain union as a
struct whose first member `case` is an enumeration, followed by every case's fields, so gdb
prints `{case = Large, Small = 0, Large.0 = 14, Large.1 = 7}` (`tests/debug/gdb.expected`).
The design replaces that and adds the heap:

- **Variant parts.** A union's struct holds one `DW_TAG_variant_part` whose discriminant is the tag member and whose variants are one `DW_TAG_member` per case with the case's value, each a struct of that case's fields with their names, as Rust's enums are described and LLVM's `DICompositeType(tag: DW_TAG_variant_part, discriminator: …)` writes. gdb prints only the live case: `{case = Large, Large = {0 = 14, 1 = 7}}`. Plain unions keep their inline tag; a boxed cell's tag lives in the header word beside the count (DESIGN §5.1; `rt.c` `meta`), described as a bit-field member, or as the word after the count on a 32-bit chip. A union with one fielded case has no tag: its cell is that case's struct, and the cases without fields are static cells.
- **Cells as pointers to their layout.** A `list<int>` variable is a pointer to `{count, head, tail}`, `ref<T>` to `{count, value}`, `weak<T>` to the weak cell `{count, object}`, a closure to its object (below). The static cell of a case without fields is an ELF symbol named after the case, so gdb prints its pointer as `0x402010 <[]>` or `<None>`. The `option` niche needs nothing: `option<string>` is the string's pointer or `<None>`.
- **Arrays and strings** are `{count, length, elements}` with the element count taken from the `length` member, through an expression-valued `DISubrange` count (`DW_OP_push_object_address`), as flang describes assumed-shape arrays, so `print *a` shows `{count = 1, length = 3, elements = {1, 2, 3}}`. A string variable stays a `char*` to its bytes, as today.
- **Closures.** Each lifted function's closure object gets a struct type: `{count, code, description}` then the captures under their source names (`Lift` knows them). A variable of function type is a pointer to the common header, since any closure of that type may sit there; the printer casts it to the object's type found from `code`'s symbol.
- **Spans** are `{owner, offset, length}` ([0003](0003-spans-and-slices.md)); the printer shows the elements.
- **Records, tuples, numbers, strings** are as today. The compile unit stays `DW_LANG_C11` (`Codegen.fs` about line 1555), DWARF 5; qualified names need quotes in gdb: `break 'Parser.expr'`.

### Pretty-printers

- **What they cover:** `Map` and `Set` (in-order entries, `display_hint 'map'`), `HashMap` (its live entries), closures (`closure add at prog.zs:12 = {n = 3}`), spans (the elements). Nothing else: a value DWARF describes is left to the debugger, so rr, core dumps and lldb show it without Python.
- **One file, two halves:** `tools/printers.py` in the repository, with the gdb half and the lldb half (the APIs differ), built into `zs`.
- **gdb loads it from the binary:** the compiler emits a `.debug_gdb_scripts` section holding the script as an inlined entry (type 4, `gdb.inlined-script`), a non-allocated section, so it costs file size only; file entries, which Rust uses, need an `auto-load safe-path` setting, and inlined ones don't. `set auto-load python-scripts off` turns it off.
- **lldb has no such section:** `zs debug --lldb` starts lldb with `command script import` of the script written to `~/.cache/zs/printers.py`, and the launch configuration carries the same line in `initCommands` (*Unresolved questions* 1).
- **Microcontrollers:** gdb reads the section from the ELF, so the board and QEMU get the same printers.

### Profiling

| # | Item | Design | When |
|---|---|---|---|
| 1 | where it allocates, before running | inlay hints from the allocation analysis (*Allocation hints*, below) | after phase 11 |
| 2 | sampling | `zs build --profile`: `-O2`, line tables (`-gline-tables-only`), frame pointers (Codegen adds `"frame-pointer"="all"` to every function, since clang sets it for C and not for IR it's given; `rt.c` gets `-fno-omit-frame-pointer`), symbols kept, and each allocation call carries its type's name (one constant argument more, for traces). Symbols are the Z# names Mono writes (`Map.add<string,int>`, `Mono.mangle`, about line 17) under the `zs.` prefix, no mangling and no demangler. `zs profile [file.zs] [--save out.json] -- args` builds so, runs `samply record` and opens the Firefox Profiler; without samply, `perf record --call-graph fp` and `perf report`; `--save` keeps the profile | next |
| 3 | counts | `ZS_STATS=1` prints the counters at exit (*`ZS_STATS` and `--stats`*, below) | next |
| 4 | traces | `ZS_TRACE=file` (*`ZS_TRACE`*, below) | after phase 11 |
| 5 | microcontrollers | `zs profile --probe` samples the program counter through probe-rs (the DWT's periodic samples over SWO where the board wires it, halt-and-read where the chip has no ITM, as the M0+), and turns the samples into the Firefox Profiler's format with the ELF's symbols and line table, so the view is the host's. For exact cycles, `Runtime.ticks ()` around a block (SysTick counts on the chip, nanoseconds on the host, facts sheet §8) and `Runtime.allocations ()` for the count | after phase 11 |

### Allocation hints

One allocation analysis, after Rc and before IR emission, gives each site a verdict:
allocates, frees, reuses, copies on write, atomic (marks shared). [0012](0012-interrupts-noalloc-intrinsics.md)
defines it, with `[<NoAlloc>]` as the error it raises; this proposal shows the verdicts.

- **In the editor:** `zs lsp` publishes them as inlay hints at the end of the line, one word per verdict (`allocates ×2, reuses`), with a tooltip naming the object (`a list cell, 24 bytes`) or the reason (`copies on write: a is shared here`). Hints are off by default and turned on by `allocationHints: true` in the server's initialization options (Zed: `lsp.zs.initialization_options`); the type hints that exist today (facts sheet §1) stay as they are.
- **Where they come from:** the server runs the passes to the analysis for the open document's program when hints are on, after the check, and refreshes the hints (`workspace/inlayHint/refresh`); the verdicts are kept per module in the cache beside the hovers ([0007](0007-incremental-builds.md)), so an unchanged module's hints cost nothing. A generic function shows its instances' verdicts merged, naming the instance when they differ (`allocates in Map.add<string,int>`).
- **Not diagnostics:** hints never appear in `zs build`'s output and have no severity, so [0021](0021-warnings.md)'s `[<NoWarn>]` doesn't apply; where a verdict must be an error, `[<NoAlloc>]` is the spelling.
- **MCP:** `check` returns the verdicts with positions on request, so an agent asked to remove an allocation can see where it is.

### `ZS_STATS` and `--stats`

Perceus's choices have two kinds of cost, counted in two places:

- **The runtime's counters** are kept in every build, beside the `allocations`, `mallocs` and `live` it keeps already (`rt.c` about lines 33 and 75, one add on paths that count anyway): allocations and frees by size class (the pool's 8-byte classes to 256 bytes, then `malloc`), peak live bytes, spare threads started and jobs stolen from outside deques ([0008](0008-threads.md)). `ZS_STATS=1` only prints them, at exit, on standard error.
- **Counters in compiled code** need `zs build --stats`: reuse hits (the reuse branch of each allocation with a token, `Codegen.fs` about line 2484), copy-on-write copies (the copy branch of `unique.array<T>`, about line 1123) and atomic marks (objects whose count `shareFn` turned negative, about line 1037). Each is a relaxed add on a runtime counter, inlined by ThinLTO; without `--stats` the sites emit nothing, so a release build's code is unchanged. A binary built without it prints the runtime's counters and names the missing ones.
- **The output:**

```
zs stats: 1203445 allocations, 1203440 frees, peak live 12582912 bytes
  by size: 16 B 800000, 24 B 300000, 32 B 100000, 48 B 3000, malloc 445
  reuse hits 650000, copy-on-write copies 12, atomic marks 3
  threads: 2 spare started, 1204 jobs stolen from outside deques
```

- **Microcontrollers:** `--stats` adds the counters to the `#zs heap_peak=…` exit line (facts sheet §8); there is no environment to read.
- **Coverage** ([0009](0009-tests-as-values.md)) instruments with LLVM's `instrprof` counters and a region map from the same source positions; its counters and these combine in one build.

### `ZS_TRACE`

- **The format:** Chrome's JSON trace-event format, in its array form (whose closing bracket is optional, so a run that panicked still opens). Perfetto reads it, and the Firefox Profiler too; from C it's `fprintf`, where Perfetto's native format is protobuf and its SDK C++.
- **Kinds,** all on by default, chosen with `ZS_TRACE_KINDS=alloc,tasks,pool`:
  - **`tasks`:** each run of a task's continuation is a complete event (`X`) on the loop thread that ran it, named after the task's function; a task's lifetime is an async event (`b`/`e`) under its id, so the gaps are its waiting; each `epoll_wait` that blocked is an `idle` slice. Timer and descriptor waits appear as instant events with what was waited on.
  - **`pool`:** each job is a slice on its worker, with the deque it was stolen from in `args`; spare threads appear as threads.
  - **`alloc`:** sampled allocations as instant events on their thread: the size, the type's name (from `--profile`'s extra argument; without it, the size only) and the stack as frame names in `args` (walked from frame pointers where a build keeps them, `backtrace` otherwise), plus a counter event (`C`) with live objects and bytes, so Perfetto draws memory over time. Stacks go in `args`, which Perfetto's SQL aggregates; the legacy `stackFrames` form isn't written.
  - **Threads** are named with metadata events (`main`, `loop 2`, `worker 3`, `helper`, `spare 1`).
- **Sampling:** one allocation sample per 64 KB allocated, with a Poisson-distributed interval (as heapprofd samples), `ZS_TRACE_SAMPLE=<bytes>` to change it (`1` samples every allocation, for short runs). *Unresolved questions* 2.
- **Writing:** a 64 KB buffer per thread, appended to the file under a lock when full and at exit; names resolved from `.symtab` at exit by the panic path's reader, lines added with `llvm-symbolizer` when on PATH. A trace event costs about 100 bytes and two clock reads (an estimate): trace seconds, not hours.

### Order of implementation

1. **Panics and `-g` at any level:** the symbol reader in `rt.c`, Z# names and lines in backtraces, `-O1`/`-O2` accepted with `-g`, `#dbg_value` at those levels; `ZS_STATS=1` over the runtime's counters; `--profile` and `zs profile` (debugging items 3 and 5, profiling items 2 and 3).
2. **`--stats`:** the three counters in compiled code, measured on `bench/host` before anything turns them on by default.
3. **DWARF for every value** and the printers, embedded for gdb: variant parts, cells, arrays, closures, spans, `Map`, `Set`, `HashMap`; `tests/debug/gdb.sh` grows to the exit test (`list<Map<string, int>>` and a closure's captures, in an `-O2 -g` build too).
4. **After phase 11,** in the roadmap's order: lldb with [0022](0022-targets-macos-windows.md)'s macOS CI, `zs debug --config` for Zed, `zs tasks`, the rr test, microcontroller debugging, allocation hints once [0012](0012-interrupts-noalloc-intrinsics.md)'s analysis exists, `ZS_TRACE`, SWO sampling.

Each step keeps `./test.sh` green. Scripts under `tests/debug/` are wired in `test.sh` and skip
when the tool is absent, as `gdb.sh` does (`test.sh` about line 128, facts sheet §14).

## Drawbacks

- **Python in the debugger.** The printers need a gdb or lldb built with Python, which distributions ship but minimal images may not; without it, DWARF still shows every value except the five the printers draw.
- **A symbol reader in the runtime:** about 100 lines of C for ELF (an estimate), and another path for Mach-O ([0022](0022-targets-macos-windows.md)). The alternative, `-rdynamic` for every Z# function, puts thousands of symbols in the dynamic table and keeps none of them from being stripped.
- **Build variants multiply:** `-g` at four levels, `--profile`, `--stats`, each a key in the object cache. A profiled binary differs from the release one (frame pointers, the extra allocation argument), so what it measures is close to the release build, not identical.
- **Traces are large,** and sampling hides rare allocations. The counter events and `ZS_TRACE_SAMPLE=1` cover short runs.
- **Hints depend on the back half** running in the server, which is more work per edit than checking; they're off until asked for.
- **Variant parts depend on the debugger.** gdb's reader builds them for any language; its C value printer and lldb's support are newer than its Rust one (*Unresolved questions* 4). The union half of a printer is the fallback, and it's generic over the DWARF, so no per-type script either way.

## Alternatives

- **A debugger of Z#'s own,** as OCaml's `ocamldebug`. A debugger is a second runtime (ptrace, DWARF, expression evaluation, an editor protocol) and gdb and lldb already show C frames, which a Z# program has as well. Not chosen: wrapping is the track's rule, and nothing here needs a feature the two lack.
- **DWARF alone, no printers.** A `Map<string, int>` is a balanced tree of cells; gdb prints its root and the programmer follows pointers. Not chosen: a map as a tree is unreadable, and five printers are a page of Python.
- **Printers for everything, no DWARF work,** as many languages do. Not chosen: a script must be loaded and differs per debugger, and rr, core dumps, lldb and `perf` read DWARF only; the DWARF is the record of the layout and the printers draw on it.
- **Switching the compile unit's language to Rust** so gdb's Rust printer draws enums. Not chosen: gdb would then parse expressions as Rust, and `print range.lo` or a cast would mean the wrong thing.
- **Perfetto's SDK or protobuf format.** Not chosen: the runtime is one C file and the SDK is C++; the JSON form is a dozen `fprintf`s and Perfetto reads both.
- **A trace format and viewer of Z#'s own.** Not chosen: a viewer is a program to maintain; Perfetto's shows threads, slices, counters and SQL over `args`.
- **eBPF or uprobes for allocations.** Not chosen: root and Linux only, and the pool hides objects from the system allocator; the runtime knows every allocation and samples them itself.
- **heaptrack or massif.** They see `malloc`, so `ZS_NO_POOL=1` shows them each object, with `malloc`'s costs in the numbers. Kept as a fallback, not chosen as the design: the trace sees the pool's objects with their Z# types.
- **A SIGPROF sampler in the runtime,** as Go's pprof. Not chosen: perf and samply exist, see C and kernel frames too, and need only frame pointers and symbols from the binary.
- **A DAP adapter of Z#'s own.** Not chosen: gdb 14 and lldb ship theirs, and a launch configuration is a file `zs` writes once.
- **Counting reuse, copies and marks in every build.** Not chosen: an add at every reuse site in release code for numbers read once a month; the split keeps a release build's code as it is, and the diagnostic names the flag.

## Compatibility

- **Not a breaking change.** `-g` keeps building at `-O0`; `ZS_BACKTRACE=0`, `ZS_ABORT=1`, `ZS_LEAKCHECK=1` and `ZS_NO_POOL=1` keep their meanings; `Runtime.ticks` and `Runtime.allocations` stay.
- **No new source:** nothing here is syntax. An older compiler builds the same program and doesn't know `--profile`, `--stats` or `zs profile`, printing its usage (`Main.fs`, facts sheet).
- **Compiled binaries:** none to consider; packages are source (decision 27). A binary built by this compiler carries more DWARF, a `.debug_gdb_scripts` section and its symbol table; nothing in it runs differently.
- **The library:** unchanged. `Runtime.ticks` and `Runtime.allocations` are built-ins already (`Typer.fs` about lines 277 and 283).
- **`tests/debug/gdb.expected`** changes where a union prints: `{case = Large, Large = {0 = 14, 1 = 7}}` in place of today's flat form. It's the one test that reads the format.
- **Microcontrollers:** the DWARF and the printers come along in the ELF; `--stats` writes to the exit line; `-g` builds for QEMU and the board as today.

## Pragmatics

### Diagnostics

| Situation | Error |
|---|---|
| `zs profile` with neither tool | `zs profile: neither samply nor perf is on PATH; install samply (cargo install samply) or perf` |
| `zs debug` without a debugger | `zs debug: gdb not found; --lldb uses lldb` |
| `zs debug --config` with an old gdb | `zs debug --config: gdb 12.1 has no DAP adapter; gdb 14 or later, or lldb-dap` |
| `zs debug --config` outside a project | `zs debug --config writes .zed/debug.json next to zs.toml; there is no project here (zs new makes one)` |
| `zs debug --target cortex-m4` without QEMU | `zs debug: qemu-system-arm not found; --probe runs on a board through probe-rs` |
| `--stats` with `--no-heap` | `--stats counts heap operations and a --no-heap program has none; drop one of them` |
| `ZS_STATS=1` on a binary built without `--stats` | at exit, `reuse hits, copy-on-write copies, atomic marks: not counted (build with zs build --stats)` |
| `ZS_TRACE` names a file the program can't write | at start, `trace: cannot write /var/trace.json (Permission denied); tracing off`, and the program runs |
| `ZS_TRACE_KINDS` with an unknown kind | `trace: unknown kind 'allocs' (alloc, tasks, pool)` |
| a panic in a build whose symbols were stripped | the backtrace prints addresses with `(no symbols: the binary was stripped)` once |
| a panic with `-g` and no symbolizer on PATH | names without lines, and one line `(install llvm-symbolizer for file:line)` |

### Tooling

- **`zs lsp`:** hover, completion, definition, references and diagnostics while editing are unchanged (the editor gets the checker's types with no build run); the allocation hints are a new inlay-hint kind behind a setting, with tooltips. Nothing in the grammar: the tree-sitter grammar gains nothing, since no syntax changes.
- **`zs mcp`:** `check` returns the verdicts on request; `run` passes `ZS_STATS=1` on request and returns the counters, so an agent can measure a change it made.
- **Commands:** `zs profile`, `zs debug` (`--lldb`, `--config zed|vscode`, `--target`, `--probe`); `zs build` gains `-O1`, `-O2`, `--profile`, `--stats`; `zs test --debug <path>` ([0009](0009-tests-as-values.md)) runs one leaf under `zs debug`.
- **Debuggers:** gdb 14 and later for DAP (any gdb with Python for the printers), lldb from LLVM's release (the container's 23.1), rr, samply, perf, probe-rs, OpenOCD, QEMU, all unmodified.
- **The guide:** [10-tools.md](../guide/10-tools.md)'s Debugging section grows by the flags, the env vars and a `zs tasks` example.

### Performance

- **Existing code:** none. A build without the flags emits what it emits today; the symbol table was there already.
- **`-g` at `-O2`:** no run-time cost (debug sections aren't loaded); a larger binary. `--profile`'s frame pointers cost a register and a push per call, 0–2% on `bench/host` (an estimate, to be measured in step 1).
- **`--stats`:** one add per reuse hit, copy and mark; measured on `bench/host` before any default changes.
- **A panic:** the symbol reader runs once, at the panic, over `.symtab` (tens of thousands of symbols in milliseconds, an estimate).
- **`ZS_TRACE`:** two clock reads and about 100 bytes per event; allocation samples one per 64 KB; the file is written from buffers under a lock.
- **Hints:** the back half's passes for the open document's program, only while hints are on; cached per module.
- **Printers:** cost in the debugger only.

### Scaling

| Dimension | Typical | Upper bound |
|---|---|---|
| frames in a panic backtrace | 5–30 | 256 (today 64, `backtrace(frames, 64)`, `rt.c` about line 63) |
| symbols read at a panic | 2,000–20,000 | 500,000 (the self-hosted compiler), read once |
| elements a printer shows | 10–100 | gdb's `print elements` limit (200 by default), then `...` |
| tasks `zs tasks` lists per loop | 1–100 | 10,000 (the echo server's connections, DESIGN §6), a line each |
| trace events per second | 1,000–100,000 | 1,000,000 under load, about 100 MB per second of trace: a 1 GB file still opens in Perfetto |
| allocation samples | 1 per 64 KB allocated | every allocation (`ZS_TRACE_SAMPLE=1`), for runs of seconds |
| size classes counted | 32 (8 to 256 bytes) and `malloc` | fixed |
| hints per module | 10–200 | 10,000 (a module of the compiler), in the module's cache entry |

### Culture-aware formatting and parsing

Everything here is invariant: counters and sizes print as plain digits with no grouping and
`.` as the decimal point, as `Show` does; the trace is JSON; names are UTF-8 as the source
wrote them. gdb and lldb format values by their own settings.

## Unresolved questions

1. **lldb's auto-load:** `zs debug --lldb` and the launch configuration import the script (this proposal). The alternatives: a `.lldbinit` in the project (lldb refuses local ones unless `target.load-cwd-lldbinit` is set), or a line in `~/.lldbinit` that `zs` offers to add.
2. **The sampling interval:** one sample per 64 KB allocated with a Poisson interval (this proposal), against every Nth allocation (simpler, biased toward small objects) or a time-based sample.
3. **`--stats` in debug builds:** `-g` leaves the counters out (this proposal: a debug build is for stepping, and `-O0` already changes what Perceus's choices cost), against `-g` implying `--stats` so that the numbers are there whenever someone is looking.
4. **The debuggers' variant parts:** whether gdb's C value printer and lldb print only the live case from a variant part, as gdb's Rust printer does; step 3 tests both and the union printer is the fallback.
5. **Kinds and sampling in `ZS_TRACE`'s value** (`ZS_TRACE=trace.json:alloc,tasks`) against the two extra variables here.

## History

- **2026-10-22:** drafted from track D's profiling and debugging items, DESIGN §12 and the debug-info code in `Codegen.fs`.
