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
                                                                         └─ F zs fmt (after 3) ─ LSP formatting
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

### Phase 3: traits, modules, members, derive, C export ✅
- **Scope:**
  - **Traits:** `trait`/`impl`. Impl requirements on type arguments are inferred. Operators are traits (`Add`, `Num`, `Eq`, `Ord`, `Show`, `Hash`), and `List.sum` uses `Add.zero`.
  - **Derive:** `derive` over `Shape.of`/`pair`/`kind`, with unrolled `for f in c.fields`, `Shape.build` and `Shape.buildCase`.
    - **Built-in derives:** `Eq`, `Ord`, `Hash` and `Show` are prelude derives, applied the first time a type needs them.
    - **Controls:** `[<Derive(X)>]`, `[<NoEquality>]`, `[<NoComparison>]`.
    - **Tuples:** structural traits.
  - **Members:** `member`, `static member` and `type T with` extensions. Dot resolution is type-directed, and `f(x).M()` binds tighter than juxtaposition. Named, optional and default arguments.
  - **Records and unions:** default field values, named union fields in construction and patterns.
  - **Modules:** a file is a module. `open`, qualified names, `private`, an import graph built from the main file, and import-cycle errors with the file named.
  - **Active patterns:** total, partial and parameterised, checked by the exhaustiveness checker.
  - **Units of measure:** Kennedy unification, erased before codegen.
  - **Errors:** `?` over `result`.
  - **C export:** `[<Export>]` plus a generated `.h`, `[<CLayout>]` with x86-64 System V lowering, `callback<A -> R>`, and `zs build --lib`.
  - **Stdlib core:** `List`, `Array`, `Option`, `Result`, `String` (runtime primitives plus Z#) and `Console`.
- **Exit tests:**
  - **`tests/cexport`:** a C program calls a Z# static library using structs of every ABI class, and Z# calls back into C with a closure that captures state. Valgrind-clean.
  - **`tests/units`:** mixing `m` and `s` fails to compile, and `physics.zs` compiles to LLVM IR identical to its unitless twin (`.same-ir`).
  - **`tests/json.zs`:** a `Json` derive written in Z# round-trips a record, a union and `Tree<int>`. `tests/err_derive.zs` shows that deriving it for a function field fails and names the field.
- **Known shortcuts:**
  - **`?` operator:** only `let p = e?` or a statement `e?`.
  - **Active patterns:** only at the top of a match case.
  - **Units:** Kennedy's general case, which introduces a fresh variable, isn't implemented. Unannotated `*` across different units needs annotations.
  - **C ABI:**
    - x86-64 System V only, and running out of argument registers isn't modelled.
    - Callbacks take scalar arguments and are synchronous, since the closure is borrowed for the call.
    - C function pointers can't be called from Z#.
  - **Modules:** record field names, traits and derives are global. There are no nested modules.
  - **Members:** generic members that are mutually recursive share type variables. Fine so far, but not principled.
  - **Syntax gaps:**
    - Strings are byte-based, and there's no `char` type yet.
    - No tuples without parentheses, no `(e: T)` annotations in expressions, no `let rec … and …`, and no top-level values.
    - Quotes aren't allowed inside interpolation holes.

## Next

**Who it's for first:** native libraries consumed from C, and CLI tools. Games over C
libraries come after. **The surface syntax is frozen** until Phases 4 and 5 are done: no new
syntax, only fixes. Both decisions came from the design review.

### Before Phase 4: design-review fixes (done)
- **Arrays are copy-on-write values** (DESIGN §5): `a.[i] <- x` needs `let mutable a`, writes in place when unique and copies otherwise. `Array.set a i x` returns the changed array. `Buffer<'a>` (`Buffer.create/length/ofArray/toArray`) is the shared mutable alternative.
- **Integer overflow traps** in every build (`llvm.*.with.overflow`; `MIN / -1` too). `Int.wrappingAdd/Sub/Mul` wrap on purpose, and the derived `Hash` uses them.
  - Deferred: `[<Wrapping>]` on a function. The explicit operations cover it until code needs many of them.
- **Compile time is measured:** `zs build --time` reports each phase, and `./test.sh` prints the totals for `tests/json.zs`. Parse and check dominate, since the prelude is re-checked on every build.
- **Exit tests:** `tests/cow.zs` checks aliasing, and that a unique array is updated with zero allocations. `tests/overflow.zs` and `tests/panic_div.zs` check traps and wrapping.
- **Panics** exit with status 134 without a core dump (`ZS_ABORT=1` restores `abort()`).

### Phase 4: C import and tooling
- **Scope:**
  - **Done:** `import c "header.h"`, via clang's JSON AST and macro listing, covering structs, enums, functions and `#define` constants. `[<Link "lib">]` links a library.
  - **Done:** DWARF debug info with `zs build -g` (`-O0`). gdb breaks on Z# functions and lines, steps, and shows backtraces with Z# files and lines.
    - Arguments and locals of number and bool types are shown, `for` variables included.
    - **Next:** strings, records and unions as gdb values (DWARF composite types).
  - `zs test` and better error messages (code snippets, carets). **Done:** `[<Test>]` functions, one process per test; a failed assert names its file and line.
  - **Cross-compilation (done):** `zs build --target <triple>`. clang compiles the IR for the target, and `zig cc` compiles the runtime and links against Zig's bundled musl, giving static binaries.
    - `./test.sh --target aarch64-linux-musl` runs the tests under qemu-user.
    - The C ABI follows AAPCS64 on aarch64: HFAs in float registers, structs up to 16 bytes in integer registers, larger ones by reference. `tests/cimport/abi.zs` checks each shape on both architectures.
  - **For C libraries:**
    - **Done:** the aarch64 AAPCS calling convention (HFAs, register rules).
    - Running out of argument registers, modelled on x86-64.
    - Headers that are better documented, with `const` where it applies.
    - A stable naming scheme for exported symbols.
  - **For CLI tools:**
    - **Stdlib (done):** `Env.args`, `Env.var`, exit codes, `File` (read, write, lines, exists), `Dir`, `Process.run`, stdin by line.
    - **Collections (done):** a persistent `Map`/`Set` and a `HashMap` (a CoW value). The tree is AVL, as in OCaml, because removal is much simpler than in a red-black tree.
      - `x <- f … x` moves `x`'s value into the call, so copy-on-write updates stay in place. 100k `HashMap.add` calls went from 7.1 s to 0.01 s.
  - **Projects:**
    - **Done:** a `zs.toml` manifest with name, version, entry point and path dependencies.
      - `zs build`, `zs run` and `zs test` with no file use it, and `zs new` creates a project.
      - Modules are found in dependencies for the CLI, the LSP and MCP alike.
    - **Done:** git dependencies (`{ git = "…", rev = "…" }`), with `zs.lock`, `zs fetch` and `zs update`.
- **Exit tests:**
  - A raylib window demo written only against `import c "raylib.h"`.
  - `tests/` cross-compiles to aarch64-linux-musl and passes under qemu-user. This includes `tests/cexport`, so the C ABI is checked on both architectures.
  - A CLI tool built from a `zs.toml` with a path dependency: a small `wc`/`grep` clone that reads files and arguments.

### Phase 5: optimizer I
- **Scope:**
  - **Core IR passes:** inlining of small higher-order functions, uncurrying, closure elimination, case-of-known-constructor, case-of-case.
  - **Matches:** decision trees.
  - **Representation:** unboxed small unions and tuples, `i8` enums, the null niche for `option<ref>`, pointer tagging for nullary constructors.
  - **Perceus:** borrow inference.
  - **LLVM hints:** `noalias`/`readonly`/`nonnull` metadata and hoisted bounds checks.
  - **Benchmark suite in CI**, run against C, OCaml and F#. A regression of more than 5% fails.
  - **Compile time:** moved here from Phase 9 because shipping Core IR and monomorphizing at the user is Rust's compile-time trap. The prelude and each module are cached as checked Core keyed by their content hash, and a one-function change rebuilds in under 1 second.
- **Exit test:** fib, binary-trees, nbody, spectral-norm and the red-black tree each run within **1.5× of C** (clang -O2).

### Phase 6: computation expressions and Task
- **Gate first** (DESIGN §6): a time-boxed spike of a single `Async` effect with evidence passing. Its result decides whether `Task` below is a library over effects (and Phase 10 moves up) or CPS as written.
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
  - **Build speed:** parallel module compilation (the cache arrives in Phase 5).
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

**Status (track E):**
- **`zs check`:** done.
- **Error messages:** done. They give `file:line:col`, the source line with a caret, and every error in one run.
- **E2a (`zs lsp`):** done. Diagnostics, hover with constraints, inlay hints, document symbols and formatting, tested by `tests/lsp/session.sh`.
- **E3 (`zs mcp`):** done. The `check`, `type_at`, `docs`, `build`, `run`, `emit_llvm` and `format` tools, tested by `tests/mcp/session.sh`.
- **F (`zs fmt`):** v1 done (token-based; see below).
- **E1 (grammar and Zed extension):** built.
  - **Grammar:** generates, passes its corpus test, parses every `.zs` file in the repository with no errors (checked by `./test.sh`), and parses the prelude in under 2 ms.
  - **Extension:** compiles to `wasm32-wasip1`. The self-contained `zs` runs inside Zed's Flatpak sandbox.
  - **Left to do:** install it in Zed (`zed: install dev extension`), which is a manual step.
- **E2b (navigation and completion):** partly done.
  - **Done:** go to definition (across modules and into the prelude), find references, and completion (members and fields after `.`, plus names and keywords), including names inside `$"…{x}…"`.
  - **Still to do:** signature help, rename and code actions.

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
  - Formatting (`textDocument/formatting` and range formatting), using `zs fmt` (F).
- **Zed integration:** the extension runs `zs lsp` through `language_server_command` and finds `zs` on `PATH` or from a configured path.
- **Exit tests:**
  - A scripted LSP session (JSON-RPC over stdio, run in `./test.sh`) checks diagnostics, hover and definition results against expected JSON.
  - In Zed, a 2,000-line file shows updated diagnostics within 100 ms of a keystroke.

### F: formatter (`zs fmt`)

**v1 (done):** works on tokens, so formatting can't change a program's tokens; every result is checked.
- **What it does:** re-indents from the block structure (2 spaces per level), spaces operators and punctuation the same way everywhere, and collapses blank lines. Comments are kept.
- **Where it runs:** `./test.sh` keeps the repository formatted, and the LSP and MCP formatting use it.
- **Still missing:** reflowing lines to 100 columns, which needs the lossless syntax tree described below.

- **Style:** one canonical style with no configuration, like `gofmt`, `zig fmt` and `rustfmt`. The default layout follows Fantomas/F# conventions:
  - 2-space indent.
  - Match cases aligned under `match`.
  - Pipelines broken one `|>` per line when they don't fit in 100 columns.
  - Record and list literals broken one item per line, with `;` dropped at line ends.
- **Compiler prerequisite:** a lossless syntax tree. The lexer keeps comments and blank lines as trivia attached to tokens, so formatting never drops a comment. The CLI error messages planned for Phase 4 benefit from the same spans.
- **Commands:**
  - `zs fmt <files…>` rewrites the files in place.
  - `zs fmt --check` lists unformatted files and exits non-zero, for CI.
  - `zs fmt --stdin` is for editors.
- **Integrations:** LSP document and range formatting (E2b), Zed's format-on-save through the extension, and an MCP `format` tool (E3).
- **Prerequisite:** Phase 3. The syntax is mostly stable after members and traits land, so the formatter doesn't have to chase it.
- **Exit tests:** run in `./test.sh` over `tests/*.zs` and `runtime/prelude.zs`.
  - **Idempotent:** `fmt (fmt x) = fmt x`.
  - **Meaning-preserving:** `parse (fmt x)` equals `parse x`, ignoring positions.
  - **Comments kept:** every comment survives.
  - **Repository formatted:** `zs fmt --check` passes on the repository's own `.zs` files.

### E3: MCP server (`zs mcp`) for AI agents
- **Purpose:** gives Zed's agent (and any MCP client) compiler-backed tools, so it doesn't have to guess types from text.
- **Tools:**
  - `check` (structured diagnostics for a file or project)
  - `type_at` and `definition` (shared with the LSP query index)
  - `build` and `run` (output, exit code, leak-check report, optional `--sanitize` or valgrind)
  - `emit_llvm`
  - `docs` (search prelude and stdlib signatures)
  - `explain` (long-form help for an error message)
  - `format` (`zs fmt` on a file or snippet)
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
- **F (formatter) waits for Phase 3** for the same reason, and it needs the lossless lexer first. Once it exists, `./test.sh` keeps the repository formatted.
- **Phase 10 (effects) comes last.** It needs Task's API to be stable and opaque, and it needs Perceus (the one-shot resumption rule depends on it). DESIGN §6.1 lists what must stay true until then.
