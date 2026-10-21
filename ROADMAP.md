# Z# roadmap

Every phase ends with an **exit test**: a program in `tests/` that must compile
to a native binary and produce the expected output. A phase is done when its
exit test passes and `./test.sh` passes. Design rationale: [DESIGN.md](DESIGN.md).

**Development** happens in a container (`.devcontainer/Containerfile`: Fedora 44, .NET 10, clang/LLVM, valgrind,
gdb, qemu-user, zig). `./dev ./test.sh` runs the suite inside it, plain `./dev` opens a shell, and
`./dev --rebuild` rebuilds the image.

```
 v1 (single-threaded)                                                         v2 (threads)                              v3
 0 ─ 1 ─ 2 core FP + RC ─ 3 traits/modules/C export ─┬─ 4 C import + tooling
                                                     ├─ 5 optimizer I ─────┐
                                                     └─ 6 CE + Task ───────┴─ 7 parallelism ─ 8 SIMD ─ 9 optimizer II ─ 10 effects ─ (11 self-host)
```

- **v1 (phases 0–6):** the complete single-threaded language. It is fast, memory-safe, has C interop, and runs async on one event loop.
- **v2 (phases 7–9):** threads, parallelism, SIMD and the final performance work.
- **v3 (phase 10+):** effect handlers.
- **Editor tooling (E1–E3)** is a parallel track, Zed first. It hooks into the main line where marked:

```
 E1 grammar + Zed extension (now) ─ E2a LSP diagnostics/hover (after 2) ─ E2b LSP navigation/completion (after 3) ─ E3 MCP (after E2a)
```

## Done

### Phase 0: skeleton ✅
- **Scope:** `int`, `let`, functions, `if`, `extern` (variadic too), `|>`, textual LLVM IR passed to clang.
- **Exit test:** `tests/fib.zs`, which prints `fib 30` via C `printf`.

### Phase 1: types and data ✅
- **Scope:**
  - Unification-based inference (int/eq kinds) and a typed Core IR.
  - Tuples, records (literal, `with` update, field access) and tagged unions.
  - Patterns: nesting, guards, or-patterns with bindings, `as`, and `let` destructuring.
  - An exhaustiveness and redundancy checker that names a missing case.
- **Exit test:** `tests/eval.zs`, an evaluator, simplifier and pretty-printer for a small expression language.
- **Known shortcuts:** marked in the code with `ponytail:` comments.
  - There is no let-polymorphism.
  - Union cells are never freed.
  - Every union is boxed.
  - Matches test clauses one after another.
  - Division by zero is unchecked.

### Phase 2: core FP and memory ✅
- **Scope:**
  - **Functions:** `fun` lambdas, closures, first-class and local functions, partial application, `>>`.
  - **Tail calls:** self tail calls and same-prototype tail calls use `musttail`.
  - **Generics:** let-polymorphism for top-level functions and monomorphization. Generic user types (`Tree<'a>`).
  - **Numbers:** `f32`/`f64`, all integer widths, and conversion functions.
  - **Mutation and loops:** `let mutable`, `for`/`while` (with steps), `ref<'a>`, and bounds-checked arrays.
  - **Panics:** bounds errors, divide by zero and `assert` print `panic:` plus a backtrace, then abort.
  - **Built-in types:** `string` (UTF-8, RC) and `$"…{x}…"` interpolation.
  - **Prelude in Z#:** `option`, `result`, and the `List`, `Option`, `Result` and `Array` functions.
  - **Memory:** Perceus RC (ownership-based dup/drop), drop specialization, and in-place reuse of unique cells.
  - **Leak checking:** `ZS_LEAKCHECK=1` reports leaked objects at exit, and `./test.sh` always sets it. `./test.sh --valgrind` runs everything under valgrind.
- **Exit tests:**
  - **`tests/rbtree.zs`:** 1M inserts and 1M lookups into a generic persistent red-black tree. Valgrind-clean, 1.75 s.
  - **`tests/binarytrees.zs`:** depth 16. Valgrind-clean, 0.30 s.
  - **Reuse check:** mapping a 100k list 10 times performs 200k allocations instead of 2.2M.
- **Known shortcuts:**
  - **Tracked in the code:** `ponytail:` comments.
  - **Monomorphic local functions:** only top-level functions are generalized.
  - **Boxed unions:** every union is boxed, and match clauses are tested one after another.
  - **List building:** `List.map` and `List.filter` build a reversed list and then call `List.rev`, because there's no tail recursion modulo cons yet.
  - **Ownership:** every argument is owned (no borrow inference yet), and reuse requires an identical field layout.
  - **Compile time:** the RC pass recomputes free variables at every node, which is quadratic.
  - **Missing syntax:** loops over ranges only (no `for x in xs`). Multi-line lambda bodies inside parentheses aren't supported yet, because brackets suppress layout.
  - **Strings to C:** a `string` converts to `cstr` only as an `extern` argument.
  - **Overflow:** integers wrap. The debug-mode overflow trap needs a debug build mode.

## Next

### Phase 3: traits, modules, C export
- **Scope:**
  - **Traits:** monomorphized, with `Num`/`Ord`/`Eq`/`Hash`/`Show`. Operators become traits.
  - **Equality:** automatic structural `=`, `compare`, `hash` and `%A`, with `[<NoEquality>]`/`[<NoComparison>]`.
  - **Members:** `member`/`static member` on records and unions, with type-directed dot resolution.
  - **Units of measure:** `[<Measure>]` types and `f64<m/s>`, using Kennedy unification.
  - **Active patterns:** total, partial and parameterised, integrated into the exhaustiveness checker.
  - **Modules:** one file is one module, with `open`/`private`. The compiler follows imports from `zs build main.zs`.
  - **Errors:** the `?` operator over `result`.
  - **C export:** `[<CLayout>]` records with C ABI lowering, `[<Export>]` with a generated `.h`, and `fnptr` callbacks that can carry a closure.
  - **Derive:** `derive` definitions, `[<Derive(...)>]`, `Shape.of`/`build`/`buildCase` and per-field expansion. `Eq`/`Ord`/`Hash`/`Show` are written as prelude derives rather than as compiler special cases.
  - **Stdlib core:** `List`, `Array`, `String`, `Option`, `Result`, `Console`.
- **Exit tests:**
  - A C program links a Z# static library and calls into it, including a callback that captures state.
  - A physics snippet mixing `m` and `s` units fails to compile where it should and compiles to the same IR as unitless code.
  - A `Json` derive written in Z# round-trips a record, a union and a `Tree<int>`. Deriving it for a type with a function field fails with an error that names the field.

### Phase 4: C import and tooling
- **Scope:**
  - `import c "header.h"` via libclang, covering structs, enums, functions and `#define` constants.
  - DWARF debug info (gdb and lldb step through Z# lines).
  - `zs test` and better error messages (code snippets, carets).
  - **Cross-compilation:** `zs build --target <triple>` via `zig cc` and Zig's bundled libc.
- **Exit tests:**
  - A raylib window demo written only against `import c "raylib.h"`.
  - `tests/` cross-compiles to aarch64-linux-musl and passes under qemu-user.

### Phase 5: optimizer I
- **Scope:**
  - **Core IR passes:** inlining of small higher-order functions, uncurrying, closure elimination, case-of-known-constructor, case-of-case.
  - **Matches:** decision trees.
  - **Representation:** unboxed small unions and tuples, `i8` enums, the null niche for `option<ref>`, pointer tagging for nullary constructors.
  - **Perceus:** borrow inference.
  - **LLVM hints:** `noalias`/`readonly`/`nonnull` metadata and hoisted bounds checks.
  - **Benchmark suite in CI**, run against C, OCaml and F#. A regression of more than 5% fails.
- **Exit test:** fib, binary-trees, nbody, spectral-norm and the red-black tree each run within **1.5× of C** (clang -O2).

### Phase 6: computation expressions and Task
- **Scope:**
  - **CE syntax:** builders as modules plus a `Builder` trait, with `let!`, `do!`, `return`, `return!`, `use`, `for` and `if`.
  - **Libraries:** `result { }` and `option { }` builders.
  - **`Task<'a>`:**
    - Cold tasks with structured concurrency (`both`, `all`, `race`, `scope`) and implicit cancellation that runs `use` cleanup.
    - Continuations use `musttail`.
    - A single-threaded epoll/kqueue event loop in `rt.c`, plus `Task.blocking`.
  - **I/O and timing:** sockets, files and timers.
- **Exit test:** a TCP echo server holding 10k concurrent connections, flat memory over a 1-hour soak test, valgrind clean on shutdown.

### Phase 7: parallelism
- **Scope:**
  - **Thread pool:** work-stealing, Chase–Lev deques.
  - **Safety:** the `Share` auto-trait, checked at `Parallel.*` and channel boundaries.
  - **Shared RC:** marking a graph shared, with atomic RC only on shared objects.
  - **Parallel APIs:** `Parallel.both`, `for` and `reduce`, plus `Array.Parallel.map` and `init`.
  - **Sync primitives:** `Atomic`, `Mutex`, `Channel`.
  - **Scheduler:** the Task scheduler becomes multi-threaded.
- **Exit tests:**
  - Parallel mandelbrot and nbody scale to at least 0.8 × the core count (8 cores) and run clean under ThreadSanitizer.
  - A program that sends a `ref` to another thread is rejected at compile time.

### Phase 8: SIMD
- **Scope:**
  - **Vector types:** portable `f32x4`, `f32x8`, `f64x4`, `i32x8`, … with operators, `load`, `store`, `splat`, `shuffle`, `select` and reductions.
  - **Float control:** `[<FastMath>]`.
  - **Target control:** `--cpu`, `[<Target>]`, `[<Multiversion>]`.
  - **Intrinsics:** `Simd.X86` and `Simd.Arm`.
- **Exit test:** dot product, nbody and an image blur in SIMD Z# run within **10% of C written with intrinsics**. The same source builds for x86-64 and aarch64.

### Phase 9: optimizer II
- **Scope:**
  - **Task speed:** `task { }` lowered to stackless state machines, with no allocation per `let!`.
  - **Linking and profiling:** ThinLTO across modules and `rt.c`, plus `--pgo`.
  - **Backend:** switch to the LLVM C API.
  - **Build speed:** incremental per-module caching.
- **Exit tests:**
  - A Task microbenchmark makes zero allocations per await.
  - The Phase 5 suite reaches **1.2× of C**.
  - Rebuilding after a one-function change takes under 1 second.

### Phase 10: effect handlers (v3)
- **Scope:**
  - `effect` and `handle`, with inferred row-polymorphic effect types (`a -> b / E`).
  - One-shot resumptions, compiled by evidence passing with yield-bubbling (DESIGN §6.1).
  - The C-callback rule: closures passed to C must have an empty effect row.
  - Generators (`seq { }` over a `Yield` effect) and typed exceptions.
- **Exit tests:**
  - A generator-based pipeline and a typed-exception example both work.
  - Pure functions are unchanged by this phase (identical IR), shown by an IR diff test.

### Phase 11: self-hosting (optional)
- **Scope:** rewrite the compiler in Z#.
- **Exit test:** the compiler compiles itself, and the second-generation build produces byte-identical output.

## Editor tooling track (Zed first)

Zed is the primary editor. Everything below is plain tree-sitter, LSP and MCP,
so Neovim, Helix, VS Code and other agents get the same support with only a
thin extension each. The compiler is the single source of truth: the language
server and the MCP server are `zs` subcommands that reuse its lexer, parser and
type checker, so editor behaviour can't drift from the compiler's.

### E1: syntax highlighting and Zed extension
- **Scope:**
  - **Grammar:** `editors/tree-sitter-zsharp`, a tree-sitter grammar with an external scanner for the offside rule (INDENT/DEDENT/NEWLINE, as in tree-sitter-python).
  - **Queries:** `highlights.scm`, `indents.scm`, `brackets.scm`, `outline.scm` (functions, types, constructors) and `injections.scm` (expressions inside `$"…{x}…"`).
  - **Zed extension:** `editors/zed`, containing `extension.toml` and `languages/zsharp/config.toml` (`.zs` files, `//` comments, 2-space indent, bracket pairs). It also installs the grammar.
- **Prerequisite:** none, so it can start now.
- **Exit tests:**
  - `tree-sitter test` passes, and every `tests/*.zs` and `runtime/prelude.zs` parses with no `ERROR` nodes. This check runs in `./test.sh`, so the grammar can't drift from the parser.
  - Zed, with the extension installed as a dev extension, highlights and outlines the test files.

### E2: language server (`zs lsp`)
- **Compiler prerequisites:**
  - Source spans (line and column ranges) on tokens, the AST and Core.
  - Error recovery, so one pass reports every error instead of stopping at the first.
  - A query index mapping a position to its type and definition.
- **E2a, after Phase 2:**
  - Diagnostics as you type, debounced, with incremental re-check per file.
  - Hover showing inferred types, including generic schemes such as `List.map : ('a -> 'b) -> list<'a> -> list<'b>`.
  - Inlay hints for inferred `let` and parameter types, as in F#.
  - Document symbols.
- **E2b, after Phase 3 (modules, members, traits):**
  - Go to definition and find references, including into the prelude and stdlib.
  - Completion: locals, module members, record fields, constructors, members after `.`.
  - Signature help.
  - Rename.
  - Code actions: add the missing match cases named by the exhaustiveness checker, and add a type annotation.
  - Formatting, once a `zs fmt` formatter exists.
- **Zed integration:** the extension runs `zs lsp` through `language_server_command` and finds `zs` on `PATH` or from a configured path.
- **Exit tests:**
  - A scripted LSP session (JSON-RPC over stdio, run in `./test.sh`) checks diagnostics, hover and definition results against expected JSON.
  - In Zed, a 2,000-line file shows updated diagnostics within 100 ms of a keystroke.

### E3: MCP server (`zs mcp`) for AI agents
- **Purpose:** gives Zed's agent (and any MCP client) compiler-backed tools, so it doesn't have to guess types from text.
- **Tools:**
  - `check` (structured diagnostics for a file or project)
  - `type_at` and `definition` (shared with the LSP query index)
  - `build` and `run` (output, exit code, leak-check report, optional `--sanitize` or valgrind)
  - `emit_llvm`
  - `docs` (search prelude and stdlib signatures)
  - `explain` (long-form help for an error message)
- **Resources:** `DESIGN.md`, `ROADMAP.md`, and the language reference once it exists.
- **Safety:** `build`/`run` execute code. They are confined to the project directory, and Zed asks for approval before each call (tool permissions). The read-only tools never execute user code.
- **Zed integration:** the extension registers `zs mcp` as a context server.
- **Prerequisite:** E2a's query engine.
- **Exit tests:**
  - A scripted MCP session (`initialize`, `tools/list`, `check`, `type_at`, `run`) passes in `./test.sh`.
  - Given a file with a type error, Zed's agent fixes it using only these tools.

## Ordering rationale
- **Phase 2 comes before everything else.** Closures, generics and RC underpin every later feature, and async without RC would leak every continuation.
- **Phase 3 (traits) comes before 6 (CE).** Builders are checked through the `Builder` trait, and `Task.both` needs generics plus traits.
- **Phase 5 (optimizer) comes before 6 (CE/Task).** CPS-based tasks are only cheap once inlining and reuse work. Benchmarking first keeps that claim honest.
- **Phase 7 (parallelism) comes after 6.** The thread pool backs both `Task.blocking` and the multi-threaded scheduler.
- **Phase 8 (SIMD) comes after 5 and 7.** Vectorization relies on unboxed arrays and aliasing metadata from Phase 5, and parallel SIMD kernels are the real-world case.
- **Phases 4 and 5 can run in parallel with 6** if there are multiple contributors.
- **E1 can start now.** It depends only on syntax. The `./test.sh` parse check keeps it in step as the syntax grows.
- **E2a waits for Phase 2.** Hover is only useful once inference reports real generic types. It needs source spans and error recovery first, which also improve the command-line error messages planned for Phase 4.
- **E2b waits for Phase 3.** Most go-to-definition and completion targets (modules, members, traits) don't exist before then.
- **Phase 10 (effects) comes last.** It needs Task's API to be stable and opaque, and it needs Perceus (the one-shot resumption rule depends on it). DESIGN §6.1 lists what must stay true until then.
