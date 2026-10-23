# Proposal 0020: the compiler in Z#

| | |
|---|---|
| **Status** | Approved in principle: go (decision 65), the rewrite before 0.1; the unresolved questions settled at the phase 11 review (decisions 73–79) |
| **Decided at** | the third design review ([ROADMAP](../../ROADMAP.md#third-design-review-)): criteria 1 and 3 hold; criterion 2 (the 1,000-line program within 1.5× of F#) is phase 11's first step, and a miss is the no-go path |
| **Builds** | phase 11 ([ROADMAP](../../ROADMAP.md#phase-11-self-hosting)), after phase 10 and the tracks' *before phase 11* items |
| **Rests on** | decisions 20 (derive, no macros), 27 (source packages, no binary IR format), 39 ("Simple"), 47 (`share<F>`), 51 (textual IR stays) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §9](../../DESIGN.md#9-compiler) |
| **Related** | [the compiler's architecture](../../compiler/ARCHITECTURE.md) (modules, data flow, where each step runs, the passes); [0007 incremental builds](0007-incremental-builds.md) (carried over), [0019 the syntax tree](0019-syntax-tree.md), [0021 warnings](0021-warnings.md) (the diagnostic record), [0009 tests as values](0009-tests-as-values.md), [0023 JSON in Core](0023-json-in-core.md), [0018 packages](0018-packages.md), [0003 spans](0003-spans-and-slices.md), [0024 the library's API](0024-library-api.md), [0002 effect handlers](0002-effect-handlers.md) |

- [x] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

The compiler is rewritten in Z#, compiles itself, and the second-generation build is
byte-identical. It is a redesign where that is simpler than a port: diagnostics are values and
positions sit in the nodes ([0019](0019-syntax-tree.md), [0021](0021-warnings.md)), a session
and an options record replace the module-level mutables, checking and lowering are two passes,
the cache's serialization is a `Binary` derive instead of `Snapshot.fs`'s hand-written lines,
and the passes run on Z#'s own thread pool with the type checker proving them race-free, each job's data
moved to it rather than shared. Inside a pass, diagnostics are a `Report` effect and unification's
backtracking a `Throw<Mismatch>` under a trail; the compiler's waits (its servers, the processes a
build runs) are tasks on the driving thread's loop (decisions 73–79). The backend stays textual
LLVM IR (decision 51), and the language gains nothing for the compiler's
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

Each row cites [phase 11](../../ROADMAP.md#phase-11-self-hosting). Line numbers are the main checkout's and approximate; the tree is being edited.

| Roadmap item | What this proposal decides |
|---|---|
| **`libclang`** | `import c` reads headers through libclang's C API from the first-party `zsharp/libclang` package ([0018](0018-packages.md)): the translation unit's cursors replace `clang -ast-dump=json` (`CImport.fs:212-213`, parsed to a depth of 10,000), `clang_tokenize` over a macro's definition replaces the regular expressions that read macro bodies (`CImport.fs:142-159`), and the `-E -dD` pass goes. `CXCursor` is passed by value, so the package needs `fixed` ([0004](0004-c-layout.md)). The two regex uses left in `Driver.fs` are written as loops. |
| **`xxhash`** | cache keys (`Driver.fs:430-433`: SHA-256 cut to 32 hex characters) use XXH3's 128-bit hash from `zsharp/xxhash`, printed as the same 32 characters, so the cache's layout keeps its shape. The compiler's own hash (part of every key in [0007](0007-incremental-builds.md)) is the hash of its binary. |
| **Not needed: `llvm`, `git`, regex, TOML** | as the roadmap says: textual IR (decision 51); `git` stays a process; no regex package; the manifest's subset is parsed by hand as today. |
| **Processes** | `Process.start` with pipes for standard input, output and error, an exit code and an environment ([0024](0024-library-api.md), track S item 7): clang's errors arrive on standard error, and the MCP's `run` tool pipes both. `Process.wait : Task<int>`, so the driver's clang runs are `Task.all` over the modules (*The compiler's IO on tasks*). |
| **IO** | 0024's `File.readAllBytes`, readers and writers over `Buffer<u8>`, `Path.getFullPath` and `getRelativePath`, `File.exists`, `move` and modification times, `Directory.exists`, temporary files. The lexer and the LSP's `Content-Length` framing read bytes as a `span<u8>` without copying ([0003](0003-spans-and-slices.md)). `Net.Unix` (`listen`, `accept`, `connect` over a path), which the build server's socket needs and no item had: added to 0024 by this review. |
| **Numbers and text** | `Int.parse` in a radix and `Float.parse` for the lexer (track S item 3); format specifiers with widths (item 4) replace the `sprintf` calls (about 970 per the roadmap; 1,024 occurrences of the token in the main checkout), so IR is written by interpolation: `$"  %{name} = add i64 {a}, {b}"`. `DateTime.utcNow` (item 6) serves the cache's LRU only. |
| **JSON** | [0023](0023-json-in-core.md)'s `Json` carries LSP and MCP messages where `Rpc.fs` and `Lsp.fs` read `JsonNode` today. `import c` stops needing JSON with libclang. |
| **Collections** | `HashMap`, the mutable `HashSet` and `Buffer`'s `push`, `pop` and `clear` (0024, track S item 2) replace `Dictionary`, `HashSet` and `ResizeArray` (about 220 and 80 uses per the roadmap). The checker's state stays a record of tables, as `Typer.State` is (36 fields, `Typer.fs:457`). |
| **Exceptions** | none. The seven types (`CompileError`, `CompileErrorPos`, `CompileErrorAt`, `Syntax.fs:8-10`; `Unwritable`, `Snapshot.fs:17`; `Mismatch` and `NoImpl`, `Typer.fs:9-10`; `ToolError`, `Mcp.fs:29`) become: 0021's diagnostic for the first three and `NoImpl`; nothing for `Unwritable` (the derive serializes every type, or the compiler doesn't build); a `result` for `ToolError`; and for `Mismatch`, `unify` performs `Throw<Mismatch>`, caught by the expression under check (reported once, the error type) or by `Infer.attempt` at a trial, which rolls the trail back (*Unification and speculation*, decision 73). Panics stay for compiler bugs and name the pass. |
| **Identity hashing** | every node carries its `id` ([0019](0019-syntax-tree.md)): the file's index and the node's number in it, given by the parser. The tables keyed by identity today (`Syntax.positions`, `Syntax.fs:14`; the checker's hint tables, `Typer.fs:734-738`; the passes' memo tables, `Decide.fs:26`, `Simplify.fs:29,274`, `Codegen.fs:2055-2057`; 25 per the roadmap) key on the id. Z# gains no physical equality. |
| **Thread-local state** | each parallel job makes a context record (`{ counter: int; sizes: HashMap<NodeId, int>; lifted: Buffer<Fun> }`) and returns it with its result, instead of the eight `ThreadLocal`s (`Decide.fs:18,26`, `Lift.fs:36-38`, `Simplify.fs:21,29`, `Rc.fs:113`). Fresh names are the job's counter under the function's name, as phase 9's per-function naming does, so the output doesn't depend on which thread ran what. |
| **Speed** | the compiler is the workload; *Performance* sets the targets, measured on `bench/compile` and on the compiler building itself. |
| **Diagnostics are values** | 0021's record (severity, name, position, message, notes), carried over unchanged. Every pass returns its result with its diagnostics, collected at its boundary from the `Report` effect its functions perform (*Diagnostics as an effect*, decision 74); the parser recovers into error nodes (0019), the checker into an error type that unifies with anything and is reported once, at the node that made it. A file shows all of its errors; the collect mode of `Driver.check` (`Driver.fs:947`) and the one-error-per-declaration rule (`Typer.fs:3572-3594`, facts sheet §3) go. |
| **Positions in the tree** | 0019: a span (file, offset, length) in every node; no `Syntax.positions`, nothing cleared per check (`Driver.fs:897`), nothing restored from the cache by hand. |
| **One lossless syntax tree** | 0019: the parser builds the concrete tree, the AST is a typed view, and `zs fmt`, rename and code actions work on it; `Format.fs`'s token pass goes. |
| **No global state** | *The session and the options record*, below. |
| **Incremental by module** | [0007](0007-incremental-builds.md) as is: keys, results, borrow inference by propagation, one cache on disk. The session holds the in-memory results (0007's 512), so the CLI, `zs lsp` and `zs mcp` are one binary with a session each, and several sessions run in one process. |
| **Parallel: the back half** | simplification, decision trees, lifting and reference counting run per function, and code generation per module, through `Array.Parallel.map`, each job with its context. A job is a `share<unit -> 'a>` with an empty row: what it reads (the program's types, `Options`) is immutable, so Share by construction; its own function's Core moves into it (*Crossings move*); its effects are handled inside it; and its result returns to the joining thread unmarked (DESIGN §7). |
| **Parallel: the front half** | files are parsed with `Array.Parallel.map` over the file list; modules are checked level by level in the dependency graph, one `Parallel.for` per level, each check reading the results of the levels before it, merged into the session on the driving thread before the next level starts. `Mono.plan` and the `Share` check run on the driving thread over signatures, then instantiation, inlining and fusion per instance on the pool (*The front half in parallel*, decision 79). |
| **Checked, not trusted** | a pass that wants a table across jobs takes a `Mutex` or merges per-job tables at the join, in sight of the reader. Nothing else is shared mutably: the checker refuses a job that captures a `ref` or a `Buffer`, so the passes are race-free by the type of their jobs. |
| **Measured** | a crossing moves: what the moved value alone references keeps its count and only what another reference reaches is marked shared (*Crossings move*, decision 75; a refinement of [DESIGN §7.1](../../DESIGN.md#71-how-a-value-crosses-threads)), so a job's own tree is thread-local and the environment it reads is what pays atomic counts. `zs build --stats` ([0011](0011-debug-info-profiles-traces.md)) on the compiler building itself reports atomic marks, copies and reuse hits per pass: the phase's record of what sharing costs (*Performance*); both halves are parallel by decision 79, and a pass that dups the environment on a hot path is fixed in that pass. The output is byte-identical whatever `ZS_WORKERS` is (*Determinism*, decision 77). |
| **SIMD only where profiled** | none, decided (decision 78): a cached build never lexes an unchanged file, the editor's line index is built once per edit of one file, and the passes are trees and maps, which vectors don't help. The roadmap's item closes with no SIMD in the compiler. |
| **Serialization by derive** | *The `Binary` derive*, below. |
| **Checking and lowering apart** | `Typer` (3,568 lines at HEAD) becomes two passes: `Infer` produces a typed tree (0019's tree with a type per node id and the resolved impls), and `Lower` turns it into Core. `zs lsp` and `zs mcp` run `Infer` only: hover, completion, definition and diagnostics come from the typed tree. the typed tables and the Core are two cache files under one key (`checked/`, `lowered/`), so the editor never lowers, a build lowers a module once, and a restored module runs neither. |
| **IR checks between passes** | in test builds (`zs build --check-ir`, on in `./test.sh`), `Check.core` runs after each pass: every expression's type matches its use, every owned variable is consumed once on every path after `Rc`, no type variable after `Mono`, every join point reached with the same types. A failure is an internal error naming the pass, the function and the node, and the test fails there, not in the binary. |
| **Concurrency where the compiler waits** | the LSP and MCP loops, the build server and the processes a build runs are `task { }`s on the driving thread's loop; the passes are the pool's (*The compiler's IO on tasks*, decision 76). |
| **Hot paths stay plain** | tokens in an array over a `span<u8>`, not a `seq { }` (a parser looks ahead); IR written into a `Writer` by the pieces of an interpolation, as `print` prints them (DESIGN §9.1), so no 8 MB string is built; a file's `Tree` made under `Arena.with`, so it dies whole when the build or the editor drops it (ids leave it, nodes don't); everything else is the pool's (*What the compiler is made of*). |
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

### Unification and speculation

```fsharp
let unify (cx: Infer) (a: Ty) (b: Ty) : unit / Throw<Mismatch> = …    // binds through cx.vars, each binding pushed on cx.trail

let check cx e expected =                                               // where a mismatch is the program's mistake
  match Throw.catch (fun () -> unify cx (infer cx e) expected) with
  | Ok () -> ()
  | Error m -> Report.diagnostic (Mismatch.explain cx e.span m)         // once, at the node; the node's type is cx.error

let attempt cx (f: unit -> 'a / <Throw<Mismatch>, Report>) : option<'a> =   // a trial: an impl, an overload
  let mark = Trail.mark cx
  let reports = Buffer.create 0
  let r =
    handle Throw.catch f with
    | Report.diagnostic d, k -> Buffer.push reports d; k ()
  match r with
  | Ok x -> for d in Buffer.toArray reports do Report.diagnostic d; Some x
  | Error _ -> Trail.undo cx mark; None
```

- **Type variables are numbers** in the context (`cx.vars`, a union-find over indices with path compression), not cells compared by identity (`obj.ReferenceEquals(v1, v2)`, `Typer.fs:180`): the `Binary` derive writes them as they are, and node ids and variable numbers are the only identities the compiler has.
- **The trail** (`cx.trail : Buffer<int>`): every binding pushes its variable, and `attempt` records the length and unbinds back to it on a miss, as OCaml's `Btype.snapshot` and `backtrack` do. The F# checker's two copies of `tyvars` (`Typer.fs:2871, 4049`) and three `with Mismatch | NoImpl _` trials (1761, 2370, 3380) become `attempt`s; its other eight catches become `check`'s.
- **Why `Throw`, not `result`** (question 3): phase 10 measured a `Throw` whose clause stops as a call and one check after each call on the way, which is what `?` compiles to, so the cost is the same; `unify`'s recursion (13 `raise Mismatch` sites) carries no `?`; the row documents what the signature would hide; and `attempt` scopes the trial's diagnostics with the same handler. The frame costs one parameter on the functions between `check` and `unify`, which is one level. Track S's item 10 (`use` under effects) isn't needed: the checker holds no `use`.
- **The error type** (`cx.error`) unifies with anything, prints as `_` in hover, and a declaration with one still gets its generalized type for the rest of the file, so one mistake gives one diagnostic. Where the F# checker stops at a declaration's first error (`Typer.fs:3572-3594`), `Infer` goes on.
- **Scopes are persistent:** the names in scope are a `Map`, taken by value into a trial or a closure's body, so nothing is restored; the substitution is the checker's one mutable table, and the trail is its undo.

### Diagnostics as an effect

```fsharp
effect Report =
  abstract diagnostic : Diagnostic -> unit

let collect (f: unit -> 'a / Report) : 'a * array<Diagnostic> =         // at a pass's boundary
  let ds = Buffer.create 0
  let x = handle f () with | Report.diagnostic d, k -> Buffer.push ds d; k ()
  (x, Buffer.toArray ds)
```

- **In place:** the clause resumes last, so a report is a call through the frame (phase 10: about 1 ns) and nothing is captured; a pass that reports nothing has the row and no cost per node.
- **At boundaries:** a parallel job is a `share<unit -> 'a>` with an empty row, so it is `fun () -> collect (fun () -> Simplify.fn cx f)`, and the join concatenates; a `task { }` body has an empty row too, so a check inside one is a `collect`. Diagnostics are sorted by file and position once, before printing.
- **The parser too:** 0019's recoveries are `Report.diagnostic`s, not a list threaded through the parser.
- **Why not a `Buffer<Diagnostic>` in the context:** a trial that reports and then misses would have to truncate it (a second trail); `attempt`'s handler scopes it instead, and a row on a function's type says it may report, where a field in a record says nothing.

### Crossings move

[DESIGN §7.1](../../DESIGN.md#71-how-a-value-crosses-threads) marks the whole object graph of a
value shared at a crossing. For the passes that would put every node of every function under
atomic counts and copies, where the F# compiler's passes write in place; the roadmap's *Measured*
row was to measure that. Decision 75 designs it away:

- **Transfer for what the sender gives up:** the marking function walks in two modes. In transfer mode, an object whose count is 1 is referenced by the moved value alone: it keeps its count, and the walk goes into its fields in transfer mode. An object whose count is above 1 has another reference on the sending thread: it and everything under it are marked shared, as today (an object already shared or static stops the walk, as today). The receiving thread then owns the unique part outright, as it owns a job's result today.
- **A crossing consumes:** `Parallel.both`, `for`, `reduce`, `Array.Parallel.*`, `Task.spawn`, `Task.blocking`, `Channel.send` and `Mutex.create` take the crossing value owned, never borrowed (`Rc`'s borrow inference leaves their parameters alone), so a count of 1 at the crossing means the sender holds nothing.
- **`Array.Parallel.map` over a unique array moves its elements:** when the array's count is 1, the job for a part takes the part's elements out of it (the array is dead after the call and is freed without dropping them), each walked in transfer mode; a shared array is read as today. So `functions |> Array.Parallel.map (Simplify.fn cx)` gives each job its function's Core with every count positive, and the pass rebuilds it in place with every optimization of DESIGN §5.2.
- **Where sharing stays:** the environment the jobs read (the program's types, other functions' signatures, `Options`) is referenced by the driving thread too and is marked shared; `Rc`'s borrowing passes it without counting on most paths. `--stats` reports the marks and the atomic operations per pass.
- **Sound:** an object two threads can reach is reached, on the sender's side, through an object with a count above 1 (its other path) or through one already shared, and both are marked with everything under them; an object under a chain of counts of 1 from the moved root is reachable only through that root, which the sender no longer holds. A diamond inside the moved value (a count of 2 from two paths within it) is marked shared without need, which is conservative.
- **Cost and place:** DESIGN §7.1's walk with a mode bit, in Codegen's per-type marking functions, and a runtime change to `Array.Parallel.map`. Built in the F# compiler in step 1, before `compiler/` runs anything in parallel, and exercised by `tests/parallel`; `tests/parallel/move.zs` maps a unique array of trees and checks under `ZS_STATS=1` that nothing was marked.

### The compiler's IO on tasks

- **Three places wait:** `zs lsp` and `zs mcp` (framed messages on standard input and output), `zs server` (connections on a Unix socket in the cache: `Net.Unix`, added to 0024 and track S's item 8 by this review, since no item had it) and the driver's processes (clang per module, the linker, zig, git). Each is a `task { }` on the driving thread's event loop: `Console.openStandardInput` read under `Task.blocking`, `Unix.accept`, and `Process.start` with `Process.wait : Task<int>`; the clang runs are `Task.all` over the modules with the cores as the limit, where F# has `Parallel.For` over blocking `Process.Start`s.
- **The passes are the pool's:** a build forks its parallel passes onto the pool from the loop thread (any thread forks, [0008](0008-threads.md)), so a task that builds uses every core without tying the loop to them.
- **The session stays on the loop thread:** it isn't Share, so a job can't capture it, and the checker says so; the loop's tasks read and write it without a lock, since one thread runs them. A server with several clients serves one build at a time, in the order they arrive (one cache, 0007); an LSP request that arrives during a check is answered after it, as today.
- **Not `Task.spawn`:** nothing in the compiler runs on another thread's loop; cross-thread work is the pool's, with a value per job.

### Determinism

- **What reaches the output is ordered:** a `HashMap` is for lookups; whatever is iterated into IR, a cache file, `zs doc`'s pages or the diagnostics is a `Map` (ordered by key), an array sorted once, or a list in source order. The F# compiler leans on `Dictionary`'s insertion order, which parallel merges would break.
- **Names per function** (phase 9): a job's counter under its function's name, so a fresh name doesn't depend on which thread ran the job or when it finished.
- **Diagnostics** are sorted by file and position after the join, before printing.
- **Checked:** `tests/cache.sh` builds under `ZS_WORKERS=1` and under the cores and compares every object; `tests/bootstrap.sh` compares gen 2 and gen 3 the same way.

### What the compiler is made of

Decision 78 closes the choices the roadmap left to a profile. Each is the simpler one, and each is
also the fast one:

- **Names are strings.** No interner: it would be the design's one global table, under a lock across parallel parsing, and every printed name a lookup. Identifiers are short immutable strings; a `Map<string, _>` compare stops at the first differing byte, and a string is hashed where it is looked up.
- **Ids are dense, so tables are arrays.** A file's nodes are numbered by the parser and a function's Core nodes by the job's `Fresh`, from zero, so `Typed` is arrays indexed by node number and a pass's memo table an array indexed by a node's number; nothing hashes a node. A `HashMap` is for names.
- **A file's tree lives in an arena.** `Parser.parse` runs under `Arena.with`: the tree is made at once, nothing outside it references a node (ids leave it, nodes don't: `Ast`, `Typed` and `Core` carry numbers), and it dies whole, in a build after `Lower` and in the editor at the next parse: one free instead of one per node. Everything else is the pool's: `Typed` and `Core` live on in the cache, and the passes reuse cells in place.
- **Type variables are a union-find over numbers,** with path compression and levels, in the context's `Buffer`, and the trail is its undo. **Scopes are a persistent `Map`.**
- **Tokens are an array; IR is written by pieces,** as *Hot paths stay plain* says.
- **No SIMD.** A cached build never lexes an unchanged file, the editor's line index is built once per edit of one file, and the passes are trees and maps.
- **The cache holds a module's typed tables and its Core apart,** `checked/<key>` and `lowered/<key>`: the editor writes the first and never makes the second; a build makes the second once per key. `Typed` records each definition's span, so navigation into a module that isn't open needs no tree.

### The front half in parallel

Decision 79: both halves are parallel, and `--stats` reports what sharing costs rather than
deciding the structure.

- **Parsing** per file through `Array.Parallel.map`, each job returning its tree and diagnostics.
- **Checking by levels** of the dependency graph: one `Parallel.for` per level against the `Env` of the levels before it, immutable and Share; the results merge into the session on the driving thread between levels. Levels, not a dependency-driven scheduler: the graph is shallow and wide (the library is mostly one level), the merge points are fixed, and a `Parallel.for` is what the pool has.
- **`Mono.plan` on the driving thread:** the set of instances the program needs, by reachability from its roots over signatures only, and the `Share` check on that call graph. It reads signatures, not bodies, so it is cheap and sequential.
- **Instantiation per instance** on the pool: each instance a job with its context, the generic function's Core moved in at its last use and shared before it, fusion and inlining in the same job; then the per-function passes, the back half.
- **If a target fails:** `--stats` names the pass whose atomic operations are high, and the fix is in that pass (borrow the environment, or copy into the job the part it walks), as a fix in any pass is. The structure doesn't change.

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

1. **In the F# compiler, before the rewrite:** the tracks' items (0019, 0021, 0009, 0023, 0024 with `Net.Unix`, 0018's two packages, 0003), the `Binary` derive and the moving crossing (*Crossings move*), each tested on programs.
2. **`compiler/`: lexer and parser on 0019's tree, and criterion 2 measured on them** (against the F# compiler's, which build the same tree, over the compiler's sources) and on a checker for a subset of the language against `Typer`; then diagnostics as values and the session. `zs1 fmt` and `zs1 check` pass the formatter's and the syntax `.err` tests. A miss is the no-go path; the files are kept either way.
3. **`Infer` and `Lower`,** the derives, the library's modules; every `.err` test green.
4. **The passes through `Rc`, textual IR, the driver with 0007's cache and its processes as tasks;** every `.out` test, `.same-ir`, `bench/host`'s contract.
5. **LSP, MCP, `zs doc`, `zs test`, the project commands, the build server on `Net.Unix`;** the session scripts green.
6. **Parallel front and back halves, the IR checks, `--stats` on itself;** sequential first, parallel once sequential passes; *Performance*'s targets met.
7. **Gen 2 equals gen 3, `./test.sh` green, deletion, `./dev` downloads.**

## Drawbacks

- **Size and time:** a second compiler of the F# one's order, written while the language is frozen, before 0.1. The review's third criterion is this cost.
- **Two compilers during the rewrite:** a language change lands twice. Phases 9.6 and 10 come first and the language is frozen during the rewrite, so what lands twice is bug fixes.
- **Performance risk:** Perceus on trees and maps; the environment the jobs read pays atomic counts (*Crossings move* keeps a job's own tree off them). The targets may fail; `--stats` then names the pass that dups the environment on a hot path, and the fix is in that pass (borrow it, or copy into the job the part it walks), not in running it on one thread (decision 79).
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
- **Sharing at every crossing,** as DESIGN §7.1 had it, and measuring: every node of every function under atomic counts in the parallel passes, with no reuse in place. Not chosen: the moving walk costs a mode bit and keeps §5.2's optimizations for what a pass transforms (decision 75).
- **`result` from `unify` and a `Buffer<Diagnostic>` in the context,** what the language had before phase 10. Not chosen: the same cost as the effects (phase 10's measurement), with `?` on every call in `unify` and a second trail to truncate the buffer at a trial (decisions 73 and 74).
- **Processes on the pool,** `Parallel.for` over blocking runs as the F# compiler does. Not chosen: a process is a wait, and a loop of `Task.all` holds no worker while clang runs (decision 76).

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
| a trial misses (no impl or overload fits) | the diagnostic of the expression that needed it, once, with the candidates tried in a note; the trial's own reports are dropped |
| a `Session` captured by a job | the Share error, as for any `ref` or `Buffer`: `this function crosses threads, but it captures 'session' : Session, which can't be shared between threads …` |

### Tooling

- **`zs lsp`** shows hover, completion, definition, references and inlay hints from `Infer`'s typed tree, with no lowering and no build run; diagnostics while editing are all of a file's errors (error nodes, the error type), not the first per declaration as today (facts sheet §1). One session per server holds 0007's cache. `import c` goes through libclang in the server's process, so a C name has its type in Zed with no build run and no `clang` on PATH. The compiler's own sources are the language server's largest test, edited in Zed.
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
- **Shared data:** a job's own function crosses by moving, so `--stats` on the compiler building itself reports atomic marks on the environment only, and the per-function passes, summed over the jobs, take at most 10% longer than on one thread (no atomic counts and no copies on a job's own tree). Thread-local trees keep every optimization of DESIGN §5.2: the passes rebuild nodes in place when unique.
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

All settled at the phase 11 review (2026-10-23):

1. **Go or no-go:** go, the rewrite before 0.1 (the third design review); criterion 2 is measured on `compiler/Lexer.zs` and `Parser.zs` against the F# compiler's over the compiler's own sources, and on a subset checker, so the measurement is code the compiler keeps. A miss sends 0.1 out on .NET with the design unchanged.
2. **LSP and MCP at once:** one binary and one session each, the F# compiler deleted whole. Two binaries would be two caches against 0007's one-cache rule.
3. **`Throw` for unification's backtracking:** `Throw<Mismatch>` in `unify`, caught by `check` (a report and the error type) or by `attempt` (the trail undone, the trial's reports dropped), decision 73: phase 10 measured a stopping `Throw` at the cost `?` has, and the handler scopes the diagnostics too (*Unification and speculation*).
4. **Where the sources live during the rewrite:** `compiler/`, moved to `src/` at deletion, the F# compiler left to git history at a documented commit.
5. **`Binary` at 0.1:** public in Core; binary formats want it.

## History

- **2026-10-23:** the phase 11 review settled the five questions and added *Unification and speculation*, *Diagnostics as an effect*, *Crossings move*, *The compiler's IO on tasks* and *Determinism* (decisions 73–77); `Net.Unix` added to 0024 and track S; criterion 2 measured on the kept lexer and parser; the F# checker's `Mismatch` sites (13 raises, 11 catches, three of them trials with hand-copied `tyvars`) and its Unix-socket build server (`Main.fs:511-565`) read for it. The same review then closed what was left to a profile (decisions 78 and 79): names are strings, dense ids index arrays, a file's tree in an arena, no SIMD, the cache's `checked/` and `lowered/` files, `Mono.plan` then parallel instantiation, both halves parallel.
- **2026-10-23, later:** criterion 2 holds: `compiler/`'s lexer and parser, on 0019's tree, take 0.6× the F# compiler's time on the compiler's sources and 1.03× over the repository ([docs/reports/self-hosting.md](../reports/self-hosting.md)), after three fixes in the F# compiler the parser showed (`Mono.reaching` exponential on a recursive group, no copy propagation, borrowing stopping at records and join points). The tree is a few arrays indexed by ids, so it needs no arena.
- **2026-10-22:** drafted from phase 11's roadmap text, the third design review's go/no-go, DESIGN §9 and decision 51, and the F# compiler at commit d6eb26d and in the working tree; a new decision row, numbered by the coordinator, when the review takes it.
