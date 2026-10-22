# Proposal 0020: the compiler in Z#

| | |
|---|---|
| **Status** | Draft (phase 11 is optional: go or no-go at the third design review) |
| **Decided at** | the third design review ([ROADMAP](../../ROADMAP.md#third-design-review)) |
| **Builds** | phase 11 ([ROADMAP](../../ROADMAP.md#phase-11-self-hosting-optional)), after phase 10 and the tracks' *before phase 11* items |
| **Rests on** | decisions 20 (derive, no macros), 27 (source packages, no binary IR format), 39 ("Simple"), 47 (`share<F>`), 51 (textual IR stays) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §9](../../DESIGN.md#9-compiler) |
| **Related** | [0007 incremental builds](0007-incremental-builds.md) (carried over), [0019 the syntax tree](0019-syntax-tree.md), [0021 warnings](0021-warnings.md) (the diagnostic record), [0009 tests as values](0009-tests-as-values.md), [0023 JSON in Core](0023-json-in-core.md), [0018 packages](0018-packages.md), [0003 spans](0003-spans-and-slices.md), [0024 the library's API](0024-library-api.md), [0002 effect handlers](0002-effect-handlers.md) |

- [ ] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

The compiler is rewritten in Z#, compiles itself, and the second-generation build is
byte-identical. It is a redesign where that is simpler than a port: diagnostics are values and
positions sit in the nodes ([0019](0019-syntax-tree.md), [0021](0021-warnings.md)), a session
and an options record replace the module-level mutables, checking and lowering are two passes,
the cache's serialization is a `Binary` derive instead of `Snapshot.fs`'s hand-written lines,
and the passes run on Z#'s own thread pool with the type checker proving them race-free. The
backend stays textual LLVM IR (decision 51), and the language gains nothing for the compiler's
sake: what the compiler needs is what tracks S and K list. The F# compiler stays the stage-0
compiler until the Z# one passes `./test.sh` and builds itself byte-identically; then it is
deleted, and `./dev` downloads the previous release's binary, as Go and Rust do.

## Motivation

- **The toolchain's dependency.** Phase 12 installs "one native binary after phase 11, a self-contained .NET publish without it". A language that compiles to native code with no runtime of its own ships, without this phase, a compiler that needs .NET's ([ROADMAP](../../ROADMAP.md#phase-12-release-01)).
- **The language's largest program.** Nothing written in Z# is near the compiler's size (19,573 lines of F# at HEAD, 20,417 in the main checkout, `wc -l src/*.fs`). A compiler is trees and maps, the workload phase 9's one-word header and build-speed work are for, and what a 20,000-line program finds (in ergonomics, in Perceus on trees, in the editor on a real project) is found before users do.
- **What the F# compiler grew into.** About twenty module-level `mutable`s and tables, seven exception types behind about 120 `raise`/`failwith` and 85 `try`, 1,175 lines of serialization by hand at HEAD that fail `tests/cache.sh` until a new case gets its place, and one 3,568-line pass that infers and lowers at once, so the editor runs lowering it never needs. Each is a roadmap item below, and each is cheaper to fix in a rewrite than in place.
- **Without it:** 0.1 ships the .NET compiler, the third design review's other option. The tracks' *before phase 11* items are done either way; the rewrite follows 0.1 and its users meet the F# compiler's structure in every error that stops at the first per declaration.

## Detailed design

### Goals and non-goals

- **Goals:** a byte-identical second-generation build; a redesign where simpler, not a port; the suite as the contract (every `.out` and `.err` passes under both compilers before the F# one goes); the compiler as the first large user of phase 7's pool, 0007's cache, 0009's tests and the `Binary` derive.
- **Non-goals:** a new backend (textual IR, decision 51); new language features for the compiler's sake (it needs only what tracks S and K list, in the forms [0005](0005-ergonomics.md) brings); a plugin host (decision 20, [0001](0001-type-providers.md)); a compiler for microcontrollers (it is a host program on Std).

### The roadmap's items

Each row cites [phase 11](../../ROADMAP.md#phase-11-self-hosting-optional). Line numbers are the main checkout's and approximate; the tree is being edited.

| Roadmap item | What this proposal decides |
|---|---|
| **`libclang`** | `import c` reads headers through libclang's C API from the first-party `zsharp/libclang` package ([0018](0018-packages.md)): the translation unit's cursors replace `clang -ast-dump=json` (`CImport.fs:212-213`, parsed to a depth of 10,000), `clang_tokenize` over a macro's definition replaces the regular expressions that read macro bodies (`CImport.fs:142-159`), and the `-E -dD` pass goes. `CXCursor` is passed by value, so the package needs `fixed` ([0004](0004-c-layout.md)). The two regex uses left in `Driver.fs` are written as loops. |
| **`xxhash`** | cache keys (`Driver.fs:430-433`: SHA-256 cut to 32 hex characters) use XXH3's 128-bit hash from `zsharp/xxhash`, printed as the same 32 characters, so the cache's layout keeps its shape. The compiler's own hash (part of every key in [0007](0007-incremental-builds.md)) is the hash of its binary. |
| **Not needed: `llvm`, `git`, regex, TOML** | as the roadmap says: textual IR (decision 51); `git` stays a process; no regex package; the manifest's subset is parsed by hand as today. |
| **Processes** | `Process.start` with pipes for standard input, output and error, an exit code and an environment ([0024](0024-library-api.md), track S item 7): clang's errors arrive on standard error, and the MCP's `run` tool pipes both. |
| **IO** | 0024's `File.readAllBytes`, readers and writers over `Buffer<u8>`, `Path.getFullPath` and `getRelativePath`, `File.exists`, `move` and modification times, `Directory.exists`, temporary files. The lexer and the LSP's `Content-Length` framing read bytes as a `span<u8>` without copying ([0003](0003-spans-and-slices.md)). |
| **Numbers and text** | `Int.parse` in a radix and `Float.parse` for the lexer (track S item 3); format specifiers with widths (item 4) replace the `sprintf` calls (about 970 per the roadmap; 1,024 occurrences of the token in the main checkout), so IR is written by interpolation: `$"  %{name} = add i64 {a}, {b}"`. `DateTime.utcNow` (item 6) serves the cache's LRU only. |
| **JSON** | [0023](0023-json-in-core.md)'s `Json` carries LSP and MCP messages where `Rpc.fs` and `Lsp.fs` read `JsonNode` today. `import c` stops needing JSON with libclang. |
| **Collections** | `HashMap`, the mutable `HashSet` and `Buffer`'s `push`, `pop` and `clear` (0024, track S item 2) replace `Dictionary`, `HashSet` and `ResizeArray` (about 220 and 80 uses per the roadmap). The checker's state stays a record of tables, as `Typer.State` is (36 fields, `Typer.fs:457`). |
| **Exceptions** | none. The seven types (`CompileError`, `CompileErrorPos`, `CompileErrorAt`, `Syntax.fs:8-10`; `Unwritable`, `Snapshot.fs:17`; `Mismatch` and `NoImpl`, `Typer.fs:9-10`; `ToolError`, `Mcp.fs:29`) become: 0021's diagnostic for the first three and `NoImpl`; nothing for `Unwritable` (the derive serializes every type, or the compiler doesn't build); a `result` for `ToolError`; and for `Mismatch`, unification returns `result<unit, Mismatch>` and `?` carries it to the declaration that reports it (*Unresolved questions* 3). Panics stay for compiler bugs and name the pass. |
| **Identity hashing** | every node carries its `id` ([0019](0019-syntax-tree.md)): the file's index and the node's number in it, given by the parser. The tables keyed by identity today (`Syntax.positions`, `Syntax.fs:14`; the checker's hint tables, `Typer.fs:734-738`; the passes' memo tables, `Decide.fs:26`, `Simplify.fs:29,274`, `Codegen.fs:2055-2057`; 25 per the roadmap) key on the id. Z# gains no physical equality. |
| **Thread-local state** | each parallel job makes a context record (`{ counter: int; sizes: HashMap<NodeId, int>; lifted: Buffer<Fun> }`) and returns it with its result, instead of the eight `ThreadLocal`s (`Decide.fs:18,26`, `Lift.fs:36-38`, `Simplify.fs:21,29`, `Rc.fs:113`). Fresh names are the job's counter under the function's name, as phase 9's per-function naming does, so the output doesn't depend on which thread ran what. |
| **Speed** | the compiler is the workload; *Performance* sets the targets, measured on `bench/compile` and on the compiler building itself. |
| **Diagnostics are values** | 0021's record (severity, name, position, message, notes), carried over unchanged. Every pass returns its result with a `list<Diagnostic>`; the parser recovers into error nodes (0019), the checker into an error type that unifies with anything and is reported once, at the node that made it. A file shows all of its errors; the collect mode of `Driver.check` (`Driver.fs:947`) and the one-error-per-declaration rule (`Typer.fs:3572-3594`, facts sheet §3) go. |
| **Positions in the tree** | 0019: a span (file, offset, length) in every node; no `Syntax.positions`, nothing cleared per check (`Driver.fs:897`), nothing restored from the cache by hand. |
| **One lossless syntax tree** | 0019: the parser builds the concrete tree, the AST is a typed view, and `zs fmt`, rename and code actions work on it; `Format.fs`'s token pass goes. |
| **No global state** | *The session and the options record*, below. |
| **Incremental by module** | [0007](0007-incremental-builds.md) as is: keys, results, borrow inference by propagation, one cache on disk. The session holds the in-memory results (0007's 512), so the CLI, `zs lsp` and `zs mcp` are one binary with a session each, and several sessions run in one process. |
| **Parallel: the back half** | simplification, decision trees, lifting and reference counting run per function, and code generation per module, through `Array.Parallel.map`, each job with its context. A job is a `share<unit -> 'a>`: what it reads (the program's Core, its types, `Options`) is immutable, so Share by construction, and its result returns to the joining thread unmarked (DESIGN §7). |
| **Parallel: the front half** | files are parsed with `Array.Parallel.map` over the file list; modules are checked level by level in the dependency graph, one `Parallel.for` per level, each check reading the results of the levels before it, merged into the session on the driving thread before the next level starts. Monomorphization, inlining and fusion run per function once the Core they read is fixed (0007's "after checking"). |
| **Checked, not trusted** | a pass that wants a table across jobs takes a `Mutex` or merges per-job tables at the join, in sight of the reader. Nothing else is shared mutably: the checker refuses a job that captures a `ref` or a `Buffer`, so the passes are race-free by the type of their jobs. |
| **Measured** | the Core a job reads is marked shared at the crossing, so its counts are atomic and reuse copies instead of writing in place ([DESIGN §7.1](../../DESIGN.md#71-how-a-value-crosses-threads)). `zs build --stats` ([0011](0011-debug-info-profiles-traces.md)) on the compiler building itself reports atomic marks, copies and reuse hits per pass; that report decides whether the front half stays parallel (*Performance*). The output is byte-identical whatever `ZS_WORKERS` is: phase 9's naming per function, and diagnostics sorted by file and position before printing. |
| **SIMD only where profiled** | none in the first version. If the profile of the compiler building itself shows the lexer or the LSP's line index above 5% of the time (an estimate of where vectors would pay), that function scans bytes 32 at a time under `[<Multiversion>]` over a `span<u8>`; nothing else. |
| **Serialization by derive** | *The `Binary` derive*, below. |
| **Checking and lowering apart** | `Typer` (3,568 lines at HEAD) becomes two passes: `Infer` produces a typed tree (0019's tree with a type per node id and the resolved impls), and `Lower` turns it into Core. `zs lsp` and `zs mcp` run `Infer` only: hover, completion, definition and diagnostics come from the typed tree. 0007's checked result keeps the typed tree's tables and the Core, so a restored module runs neither. |
| **IR checks between passes** | in test builds (`zs build --check-ir`, on in `./test.sh`), `Check.core` runs after each pass: every expression's type matches its use, every owned variable is consumed once on every path after `Rc`, no type variable after `Mono`, every join point reached with the same types. A failure is an internal error naming the pass, the function and the node, and the test fails there, not in the binary. |
| **Bootstrap** | *The bootstrap chain*, below. |

### The session and the options record

```fsharp
type Options =
  { target: Target                    // Host | Cross of string | Mcu of Chip (was Codegen.target, Driver.mcu)
    cpu: option<string>               // --cpu (was Driver.cpu and Codegen.cpu)
    optimize: Optimize                // Speed | Size (was Driver.optLevel, Codegen.optimizeSize)
    sanitizer: option<Sanitizer>      // Address | Thread (was Driver.threadSanitizer)
    debugInfo: bool                   // -g (was Codegen.debugInfo)
    testBuild: bool                   // zs test's build (was Driver.testBuild)
    profile: Profile                  // Off | Generate | Use of string (was Driver.profileGenerate, profileUse)
    checkIr: bool }                   // the IR checks between passes

type Session =
  { options: Options
    overlay: HashMap<string, string>                    // unsaved editor text by full path (was Driver.overlay)
    checked: Cache                                      // 0007's results, the 512 most recent (was Lsp.results and the snapshot layers)
    diagnostics: HashMap<string, list<Diagnostic>> }    // per open document (was Lsp.problems)
```

- **One session** per CLI run or server, made by `Main` from the flags and passed to every entry point: `Build.run (s: Session) (main: string) : result<unit, list<Diagnostic>>`, `Infer.file s path : Typed * list<Diagnostic>`. The module-level `mutable`s go (`Driver.fs:14,388,951-959,1592-1614`, `Codegen.fs:416-442`, `Lsp.fs:75-77`, `Core.fs:160`), and `Core.nextVar`'s fresh type variables are `Infer`'s context's.
- **Hooks become parameters.** `Inline.kept` (`Inline.fs:95`) and `Typer.userImpl` (`Typer.fs:19`) are mutables because `Inline.fs` and `Typer.fs` come before `Driver.fs` in F#'s file order. Z# modules can't form a cycle either, and the fix is the same in both: `Inline.run (keep: string -> bool)` and `Infer.check (impls: ImplTable)`.
- **The session isn't Share:** it holds mutable tables and stays with the thread that drives the build (the CLI's main, the server's loop). A job receives `Options` and the immutable results it reads, and returns its own; the driving thread merges. So the checker, not a convention, keeps the passes off each other's tables.
- **Several at once:** the compiler's own tests (0009) run compilations in-process, a session each, under `Parallel.for`; `zs lsp` keeps one session for its open documents.

### The `Binary` derive

```fsharp
trait Binary<'a> =
  abstract write : Writer -> 'a -> unit
  abstract read  : Reader -> result<'a, string>

derive Binary =
  let write (w: Writer) (x: 'self) =
    match Shape.of x with
    | Record r -> for f in r.fields do write w f.value         // fields in declaration order
    | Union c ->
      Writer.string w c.name                                    // the case, interned: one number after the first time
      for f in c.fields do write w f.value
  let read (r: Reader) : result<'self, string> =
    match Shape.kind with
    | RecordKind -> Shape.build (fun f -> read r)
    | UnionKind ->
      let name = (Reader.string r)?
      match Shape.buildCase name (fun f -> read r) with
      | Some built -> built
      | None -> Error $"unknown case {name}"
```

- **What it replaces:** `Snapshot.fs`, 1,175 lines at HEAD (1,309 in the main checkout), written type by type (its header says why: no reflection, milliseconds to read back). With `[<Derive(Binary)>]` on the checked result's types, a new field or case is serialized without a change, and `tests/cache.sh` can't fail for a missing place. The `Binary` module (`Writer` over a `Buffer<u8>`, `Reader` over a `span<u8>`, impls for the numbers, `bool`, `string`, `list`, `array`, `option`, tuples, `Map` and `HashMap`) is about 150 lines, an estimate.
- **Sharing by number, not identity.** `Snapshot.fs` writes an object reached twice once (`ids`, `Snapshot.fs:549`, keyed by identity). Z# values have no identity, and nothing needs it: type variables are numbered in the checker's state, nodes carry ids, and the tables key on those numbers, so the derive writes plain values and what is shared stays shared. Strings are interned by the `Writer`, as `Snapshot.fs`'s `str` does.
- **No format version:** a cache file starts with the compiler's hash, which 0007's keys carry already; a new compiler reads none of the old files.
- **Placement:** `Binary` is Core's (no OS), owned by this proposal and usable by any program; 0024's tables don't list it. It is built in the F# compiler first, as the `Json` derive is, so the Z# compiler is written against it.

### The bootstrap chain

- **Stage 0** is the F# compiler, built by .NET 10 in the dev container as today. The Z# compiler is a project, `compiler/`, with a `zs.toml` naming `zsharp/libclang` and `zsharp/xxhash` as dependencies ([0018](0018-packages.md)), built by stage 0 into `bin/zs1`.
- **Generations:** gen 1 is `compiler/` built by stage 0; gen 2 by gen 1; gen 3 by gen 2. Gen 1 may differ from gen 2 (a different compiler made it). The pass is gen 2 and gen 3 byte-identical (`cmp`), and `./test.sh` green with gen 2 as `bin/zs`: every `.out` and `.err`, the LSP, MCP and cache scripts, and the benchmarks' performance contract.
- **Then** `src/*.fs`, `Zs.fsproj` and the .NET SDK leave the repository and the container; `compiler/` becomes `src/`; `./dev` downloads the previous release's archive for the container's target (phase 12's installing) as stage 0, pinned by version in `./dev`, as Go's bootstrap toolchain and Rust's stage-0 beta. The compiler's sources use only what that release has: a form added in one release is used in the compiler one release later.
- **From nothing:** check out the last commit with `src/*.fs`, build it with .NET 10, build that commit's `compiler/`, then each release in order. `CHANGELOG.md` records, per release, which release built it. The chain is documented, not kept working: CI builds each release with the previous one only (the roadmap's rule).

### Go or no-go

The third design review decides with its "before 0.1" list in hand ([ROADMAP](../../ROADMAP.md#third-design-review)). Go when all hold:

1. **Nothing to design first:** every replacement in the table exists or is scheduled before phase 11 in its track: 0019, 0021, 0009's items 1–3 and 7, 0023, the 0024 items named above, 0018's two packages, 0003. Up to two missing are the rewrite's own first steps; more is a no-go.
2. **The targets are reachable:** a Z# program of the compiler's shape (a parser and a type checker for a small language, about 1,000 lines, an estimate, written for the review) runs within 1.5× of the same program in F# on .NET, so *Performance*'s targets hold with the headroom parallelism gives.
3. **The time fits:** the rewrite (a program of the F# compiler's order, 19,573 lines at HEAD) plus the "before 0.1" list fits what the review gives to 0.1. Otherwise no-go: 0.1 ships the .NET compiler as a self-contained publish, and this proposal's design is unchanged, only later; phase 12 then follows phase 10 ([ordering](../../ROADMAP.md#ordering-rationale)).

Either way the tracks' *before phase 11* items stay first; they're useful on both paths.

### Order of implementation

1. **In the F# compiler, before the rewrite:** the tracks' items (0019, 0021, 0009, 0023, 0024, 0018, 0003) and the `Binary` derive, each tested on programs.
2. **`compiler/`: lexer, parser on 0019's tree, diagnostics as values, the session.** `zs1 fmt` and `zs1 check` pass the formatter's and the syntax `.err` tests.
3. **`Infer` and `Lower`,** the derives, the library's modules; every `.err` test green.
4. **The passes through `Rc`, textual IR, the driver with 0007's cache;** every `.out` test, `.same-ir`, `bench/host`'s contract.
5. **LSP, MCP, `zs doc`, `zs test`, the project commands;** the session scripts green.
6. **Parallel front and back halves, the IR checks, `--stats` on itself;** sequential first, parallel once sequential passes; *Performance*'s targets met.
7. **Gen 2 equals gen 3, `./test.sh` green, deletion, `./dev` downloads.**

## Drawbacks

- **Size and time:** a second compiler of the F# one's order, written while the language is frozen, before 0.1. The review's third criterion is this cost.
- **Two compilers during the rewrite:** a language change lands twice. Phases 9.6 and 10 come first and the language is frozen during the rewrite, so what lands twice is bug fixes.
- **Performance risk:** Perceus on trees and maps, with shared data paying atomic counts and copies (DESIGN §7.1). The targets may fail; the fallback is a sequential front half, measured, not assumed.
- **Losing .NET's tools for the compiler:** its debugger and profiler; Z#'s own (0011) are a smaller set.
- **The library grows for the compiler's sake:** track S's items, chosen because users need them too.
- **A build needs a downloaded binary,** and a build from nothing the documented chain.

## Alternatives

- **Keep the F# compiler.** The toolchain needs .NET or a self-contained publish, no large program exercises the language, and the structure above stays as it grew. Not chosen for the roadmap's reasons; it is the no-go path's shape until the rewrite.
- **Port rather than redesign.** Keeps the exceptions, the globals, the hand-written snapshot and the single pass, each with Z#'s costs on top of F#'s. Not chosen: each is a roadmap item, and a port would pay for the rewrite without them.
- **A different host language.** C: no types for a type checker, several times the code. Rust: a second language and toolchain for contributors, as .NET is today. Both leave Z# without its largest program. Not chosen.
- **Self-host after 0.1.** Delivers 0.1 sooner; its users get the .NET toolchain and meet the F# compiler's structure in its errors. Not chosen as the default; it is the review's no-go option, kept as the fallback.
- **An interpreter for bootstrapping,** as OCaml's bytecode: a third implementation to keep working. Not chosen; a downloaded binary and a documented chain cost nothing to maintain.
- **A query-based architecture** (rustc, Salsa) for the rewrite: 0007's alternative; modules are the grain Z# has, and the session carries 0007 over. Not chosen now; the rewrite may revisit with measurements.

## Compatibility

- **Not a breaking change for programs.** No syntax changes. The suite is the contract: every `.out` and `.err` passes under both compilers before the F# one goes, and 0021's record adds severity and a name without changing a message's text.
- **An older compiler** meets no new source from this proposal. The compiler's own sources are ordinary Z# and build with the previous release only, by the rule above.
- **Compiled binaries:** none to consider (decision 27). A cache written by the F# compiler is ignored: the compiler's hash is in every key (0007).
- **The library** is used, not changed: 0024's, 0023's and 0003's items. `Binary` is the one addition, in Core.
- **Microcontrollers:** unchanged targets; the compiler itself is a host program and is never built for a Cortex-M.
- **Contributors:** F# goes; the Z# code uses 0005's forms, and phase 12's "Z# for F# programmers" page is the bridge. The commands and flags stay; `./dev` downloads a binary instead of building .NET.

## Pragmatics

### Diagnostics

| Situation | Error |
|---|---|
| an IR check fails in a test build | `internal error after Rc in Parser.expr: x is consumed twice on the path through expr.zs:41; this is a compiler bug: run with ZS_DUMP_CORE=Parser.expr and report it` |
| a panic in the compiler | `panic: index out of range in Mono.instantiate`, the backtrace, and the same request; a program's own mistake is never a panic, only a diagnostic |
| libclang isn't installed | `import c needs libclang: run zs doctor for how to install it` (phase 12's `zs doctor`) |
| the stage-0 release is older than `./dev` pins | an older compiler stops at the first form it doesn't know, as any older compiler does; `./dev` names the version it downloads |
| gen 2 and gen 3 differ | not a compiler message: `tests/bootstrap.sh` names the first differing function from `ZS_DUMP_IR` of both, since IR differs before bytes do |
| errors from modules checked in parallel | the same text in the same order whatever the thread count: sorted by file and position before printing |

### Tooling

- **`zs lsp`** shows hover, completion, definition, references and inlay hints from `Infer`'s typed tree, with no lowering and no build run; diagnostics while editing are all of a file's errors (error nodes, the error type), not the first per declaration as today (facts sheet §1). One session per server holds 0007's cache. The compiler's own sources are the language server's largest test, edited in Zed.
- **`zs mcp`:** `check` returns 0021's records through 0023's `Json`.
- **The tree-sitter grammar** gains nothing: no syntax changes.
- **Commands:** `zs build --time` and `--stats` on the compiler itself; `zs test` runs the compiler's tests as values (0009) across cores; `zs build --check-ir` in `./test.sh`; `./dev` downloads instead of building .NET.
- **Debugging the compiler:** gdb through its own debug info (0011), where the .NET debugger was.

### Performance

Targets, measured in the dev container and by CI per commit:

- **`bench/compile`:** a build from nothing, a body change and a signature change, each no slower than the F# compiler (which is precompiled with ReadyToRun, `Zs.fsproj`).
- **Itself:** the compiler builds itself from nothing in no more than the time stage 0 takes to build it (the gen 1 build); a one-module change rebuilds it within 0007's 0.2 s plus that module's own time.
- **Startup:** a cold `zs check hello.zs` is bounded by loading the library's cache (milliseconds per module, 0007), not by a runtime's start.
- **Memory:** peak RSS at most the F# compiler's on `bench/compile`.
- **Shared data:** `--stats` on the compiler gives the first number for atomic marks and copies; the front half stays parallel only where it wins on four cores. Thread-local trees keep every optimization of DESIGN §5.2: the passes rebuild nodes in place when unique.
- **Byte-identical** whatever `ZS_WORKERS` is, checked by `tests/cache.sh` over thread counts.

### Scaling

| Dimension | Typical | Upper bound |
|---|---|---|
| the compiler's own modules | 60–120 (an estimate: 20 F# files, with `Typer` and `Codegen` split) | 2,000 (0007) |
| lines per module | 200–800 | 20,000 (0007) |
| functions per build after monomorphization | thousands | 100,000: linear passes, a job per function |
| IR per build | 8 MB for a program (DESIGN §9) | 100 MB (an estimate); the cache skips unchanged modules |
| threads | the cores (`ZS_WORKERS`) | spares at most twice the cores (DESIGN §7) |
| nesting depth of an expression | 10 | 1,000: a recursive parser on the stack, as today |
| diagnostics per file | 1–5 | every declaration: collected linearly, sorted once |
| sessions per process | 1 | one per test under `zs test`, bounded by memory |

### Culture-aware formatting and parsing

Invariant throughout: the lexer reads numbers with `.`, IR and diagnostics print `f64` as
`Show` does (shortest round-trip), identifiers compare by bytes, diagnostics sort by byte
offset. The F# compiler's `InvariantGlobalization` is the same rule. `DateTime.utcNow` is a
cache timestamp and is never shown.

## Unresolved questions

1. **Go or no-go:** this document chooses go when the three criteria hold, the rewrite before 0.1; the alternative is 0.1 on .NET with the rewrite after, the design unchanged.
2. **LSP and MCP at once:** chosen, one binary and one session, the F# compiler deleted whole; the alternative keeps the F# server during the transition, two binaries with two caches against 0007's one-cache rule.
3. **`Throw` for unification's backtracking:** this document chooses a local `result` with `?`, what the language has; the alternative is [0002](0002-effect-handlers.md)'s `Throw<Mismatch>` performed in `unify` and caught at the declaration, which reads as the F# code does and costs evidence passing on every call in between; decided when phase 10's cost is measured.
4. **Where the sources live during the rewrite:** `compiler/`, moved to `src/` at deletion, the F# compiler left to git history at a documented commit; the alternative keeps a `fsharp/` directory building, which the roadmap rules out.
5. **`Binary` at 0.1:** public in Core (chosen: binary formats want it); the alternative keeps it the compiler's until track S's freeze review.

## History

- **2026-10-22:** drafted from phase 11's roadmap text, the third design review's go/no-go, DESIGN §9 and decision 51, and the F# compiler at commit d6eb26d and in the working tree; a new decision row, numbered by the coordinator, when the review takes it.
