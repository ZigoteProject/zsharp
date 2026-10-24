# The Z# compiler: architecture

The compiler written in Z# (phase 11, [proposal 0020](../docs/proposals/0020-self-hosting.md),
decisions 65 and 73–79 in [DESIGN §13](../DESIGN.md#13-decisions)). This document is the map of
`src/`: its modules, what flows between them, where each piece of work runs, the passes and
what each optimizes, and how the compiler keeps itself fast. The language it compiles is
[DESIGN.md](../DESIGN.md); when it is built, [ROADMAP.md](../ROADMAP.md#phase-11-self-hosting).
Line counts are estimates from the F# files they replace (`wc -l src/*.fs`: 23,700 at `v0.5`).

## 1. Shape

```
                 driving thread (the CLI's main, or a server's loop: owns the Session)
 .zs ──► Lexer ──► Parser ──► Tree ──► Ast ──► Infer ──► Typed ──► Lower ──► Core (per module)
  │  ▲   parsed in parallel (pool)     │        checked level by level (pool)    │
  │  └── cache: an unchanged file isn't parsed; an unchanged module isn't checked (0007)
  │                                    └── zs lsp / zs mcp stop here: hover, completion, …
  │
  │  per function, on the pool, a context per job, the function's Core moved into the job:
  └──► Mono ──► Inline ──► Simplify ──► Evidence ──► Decide ──► Lift ──► Rc ──► [Check after each]
                                                                          │
       per module, on the pool:  Codegen ──► LLVM IR (textual, a Writer)  ◄┘
       as tasks on the loop:     clang per module (Task.all) ──► ThinLTO link ──► binary
```

- **One binary, `zs`.** `Main` makes an `Options` record from the flags and a `Session`, and calls one entry point: `Build.run`, `Check.run`, `Fmt.run`, `Lsp.serve`, `Mcp.serve`, `Server.serve`, `Test.run`, `Doc.run`, `Project.fetch`/`update`.
- **Three ways work runs** (decisions 75 and 76):
  - **The driving thread** owns the `Session` (not Share) and merges every result into it.
  - **The pool** runs the pure work: parsing per file, checking per module (level by level), the passes per function, code generation per module. A job is a `share<unit -> 'a>` with an empty row: it reads Share data (the environment, `Options`), owns what moved into it, handles its own effects, and returns a value.
  - **Tasks** on the driving thread's loop run the waits: the LSP and MCP framing, the build server's socket, the processes a build runs.
- **Errors are values.** A pass reports through the `Report` effect and returns its diagnostics at its boundary (decision 74); the parser recovers into error nodes and the checker into an error type, so a file shows every error. `Throw<Mismatch>` is unification's one non-local exit, caught by the expression under check or by a trial (decision 73). IO returns `result`. A panic is a compiler bug and names the pass. *As built:* the checker recovers per statement: a failed statement is reported (`Fails.report`, through the handlers that place and word a failure), what it bound of the types before it is undone (`Vars.mark`/`undo`), and what it binds takes its declared type or a fresh one; the error type that unifies with anything is still to come, so a use of a failed binding can add an error of its own.
- **Nothing global.** No module-level `mutable`; the F# compiler's twenty become fields of `Options`, `Session` or a job's context, and its two file-order hooks (`Inline.kept`, `Typer.userImpl`) parameters.

## 2. Modules

Z# modules form a DAG, so the directories below are in dependency order: a module uses only
what is above it. About 20,000 lines in all.

### 2.1 `Diag/`: diagnostics

| Module | Lines | What it is |
|---|---|---|
| `Diagnostic` | 100 | [0021](../docs/proposals/0021-warnings.md)'s record: severity, name, span, message, notes. `Span` is a file index, an offset and a length. |
| `Report` | 50 | the effect (`Report.diagnostic : Diagnostic -> unit`) and `collect : (unit -> 'a / Report) -> 'a * array<Diagnostic>`, the handler every job and task boundary wraps its work in. |
| `Render` | 200 | text for the terminal (file, line and column from a `Source`'s line index), [0023](../docs/proposals/0023-json-in-core.md)'s `Json` for LSP and MCP; sorts by file and position. |

### 2.2 `Syntax/`: text to tree

| Module | Lines | What it is |
|---|---|---|
| `Source` | 150 | a file's text as `array<u8>`, its index in the build, and its line index (offset → line and column), built once. |
| `Token` | 100 | the token kinds; a token is a kind, an offset and a length into the source. |
| `Lexer` | 450 | `lex : Source -> array<Token>`, the offside rule included (indent and dedent tokens), over a `span<u8>`. Numbers through `Int.parse` and `Float.parse`. An array, not a `seq { }`: the parser looks ahead. |
| `Tree` | 350 | [0019](../docs/proposals/0019-syntax-tree.md)'s lossless concrete tree: every token (comments and blank lines are the text between them), each node with its id (its number in the file, in the order nodes end) and span, as a few arrays indexed by ids; `Tree.child`, `parents`, `tokenAt`. |
| `Parser` | 3,100 | `parse : Source -> array<Token> -> Tree * list<Decl> / Report`: recursive descent on the stack, missing tokens and error nodes as recovery, each a `Report.diagnostic`. It builds the tree and the AST together: tree nodes go into arrays as they end, so nothing outside references a node and the tree dies whole, in a few frees; an interpolated string's holes are lexed into the same token buffer and parsed by a parser of their own. |
| `Ast` | 200 | the AST the checker reads, in the F# compiler's shapes (`zs ast` prints it): `Expr`, `Pat`, `Decl`, `SType`, each node with its place, a token's index in the tree (-1: none of its own, the nearest one around it is meant). `Literal` turns literal tokens into values. |
| `Format` | 400 | `zs fmt` on the tree: reflow to 100 columns, comments kept, ranges, `--stdin`. Replaces `Format.fs`'s token pass. |

### 2.3 `Types/`: types, unification, traits

| Module | Lines | What it is |
|---|---|---|
| `Ty` | 230 | types as plain values: a variable is a number (`TVar i`), constructors, functions with effect rows (Leijen's scoped labels), tuples, a scheme's variables (`TGen`), units of measure; kinds (a literal's allowed types, the traits a variable needs, a trait's other parameters); the built-in names (numbers, SIMD vectors, the generic constructors), and `tcon`, `rowEmpty`, `mkRow`. |
| `Vars` | 90 | the context's variables: each one's binding and kind in `Buffer`s, by number, and the trail a trial undoes (`mark`, `undo`, `commit`). |
| `Norm` | 155 | types under their bindings: rows taken apart, measures in normal form, `substGen`, `resolve` (free variables defaulted by kind). |
| `Show` | 235 | types as text (0025's printer): the ambient row hidden, `/ <>` for an argument that must perform nothing; `explain`, a function's effects in words. |
| `Fail` | 30 | the checker's two effects: `Fails` (what it can't go on from in a declaration, with a place when known) and `Mismatched` (unification's one way out: the types differ, or one lacks an impl). |
| `Unify` | 220 | `unify v hooks c a b`: kinds met, occurs check, rows, units as Kennedy's; what it asks of the checker (a user impl, a trait's other parameters) through `Hooks<'c>`, which take the checker's context as an argument rather than capturing it. |
| `Repr` | 145 | how values are held: `needsRc`, plain unions, `unionRep` (plain, niche, boxed), `cellShape`, and `shareBlocker` (what keeps a type from crossing threads). |

### 2.4 `Infer/`: checking, to Core

The checker is the F# compiler's `Typer`, ported: it produces Core as it checks (as `Typer`
did), so there's no separate typed tree and `Lower` (§2.5 was the plan; one walk is less code, and
lowering is cheap next to checking, in the editor too). Its places are tokens: an error with no
place of its own takes the nearest expression's that has one (`located`), else its
declaration's line.

| Module | Lines | What it is |
|---|---|---|
| `Builtins` | 255 | the functions built into the compiler, by full name: their primitive, type scheme and arity. |
| `Cx` | 1,400 | the context, one heap cell (a union of one case, with a property per field: a closure that uses it holds a pointer, and a property reads its one field): the program so far (the F# `State`'s tables as maps in cells), what the declaration being checked is in, and the helpers that need nothing of expressions: names in scope (`resolveWith`, with privacy), written types to types (`toTy`, rows, aliases, `methodType`), `expect` and its messages for newcomers, `useRow`, generalization, records and constructors, hovers. Unification's hooks are here: a user impl, made the first time it's needed by a type's automatic derive (`Late`, what `Decls` defines). |
| `Patterns` | 265 | patterns to Core (`pattern`), and exhaustiveness and redundancy (Maranget's usefulness, `Match.fs`). |
| `Derive` | 250 | derive expansion by `Shape` ([DESIGN §3.1](../DESIGN.md#31-derive)), AST to AST before checking, with no places: an error in it is at the type declaration. |
| `Exprs` | 2,150 | expressions (`infer`): one recursive group, as `Typer.infer` is. The type expected of an expression is a parameter (`inferWith … hint`): it reaches what gives the value (branches, the tails of let and sequences, tuple, list and array elements) and gives a lambda its parameters' types, a record literal its record, a number with a unit its type, and makes a value the dyn, span or share expected of it. (`Typer` kept these in tables keyed by node; a parameter needs no node identity.) |
| `Decls` | 1,200 | declarations: function groups and generalization, members, C's boundary, traits, impls and derives, effects, constants and top-level values, modules, attributes; `declareOne`, the per-declaration recovery (a failure is the declaration's error; what it changed of the context is put back), and `check` and `finish` for a module and a program. |

An expression written elsewhere and checked here (a constant's body at a use, a field's or a
parameter's default) is *foreign*: it records no hovers and its places aren't used. A constant's
record literal keeps the record it built where it's defined (keyed by the constant and the
literal's first field name).

### 2.5 `Build/`'s checking half

| Module | Lines | What it is |
|---|---|---|
| `Modules` | 185 | the modules of a check: the library's (the prelude, Core, Std), then the program's (the main file and what it uses, dependencies first; an import cycle is an error). Packages (0018) are still the F# compiler's. |
| `Check` | 95 | `zs check`: the modules checked in order, the program's names added after the library's, and the report (with how many of each, `--strict`); `zs build` reports a failed check as F#'s does (its errors only). |

### 2.6 `Core/`: the intermediate language

| Module | Lines | What it is |
|---|---|---|
| `Core` | 500 | `Expr = { kind; ty }` with `Kind`: variables, literals, `let`, applications (known function or closure), lambdas, constructors, `match` on patterns (before `Decide`) or on tags with join points (after), fields, primitives, `handle` and `perform` (before `Evidence`), reference-count operations (after `Rc`). `FunDef`, `TypeInfo`, `UnionRep`, `Program`. |
| `Fresh` | 50 | a job's counter under its function's name: `fresh cx "x"` is `x.42` in `Parser.expr` whatever thread runs it (decision 77). |
| `Print` | 200 | `ZS_DUMP_CORE`'s text, and the per-function hash's input. |
| `Hash` | 100 | the content hash of a function's Core and of a module's IR (`zsharp/xxhash`): names, cache keys, the byte-identical test. |
| `Check` | 450 | the IR checks between passes in test builds (`--check-ir`): every expression's type matches its use, every owned variable consumed once on every path after `Rc`, no type variable after `Mono`, every join point reached with the same types. A failure is an internal error naming the pass, the function and the node. |

### 2.7 `Opt/`: the passes

| Module | Lines | What it is |
|---|---|---|
| `Cx` | 100 | a job's context: `Fresh`'s counter, memo tables keyed by node id, lifted functions, sizes. Returned with the job's result; never thread-local. |
| `Mono` | 900 | `plan`: the set of instances the program needs, by reachability from its roots over signatures, on the driving thread; `instantiate`: one instance per job, a generic or effect-polymorphic function at the program's types and rows, trait dispatch resolved, units erased, and fusion of list and array pipelines. |
| `Share` | 200 | after `Mono.plan`, on the driving thread, when every call has its target: follows each `share<F>` to the top-level values it reaches; one that isn't Share is an error. Marks the Share ones for startup. |
| `Inline` | 250 | uncurrying; inlining of small functions, with the `keep` predicate a parameter. |
| `Simplify` | 700 | known constructors, case of case, lambdas applied in place, `let` floating, dead `let`s, constant folding of what's safe. |
| `Evidence` | 900 | effect handlers to evidence passing with yield bubbling: frames per effect, clauses by path (in place when a clause resumes last or stops), loops with yielding calls through a driver, one-shot resumptions. Pure code untouched. |
| `Decide` | 600 | decision trees for matches, with join points; `ZS_NO_DECIDE=1` compiles clause by clause for comparison. |
| `Lift` | 200 | closure conversion and lambda lifting; a closure's description (drop function, arity, full entry). |
| `Rc` | 1,000 | Perceus: ownership, borrow inference per parameter (across modules through the ABI), moves out of mutables, drop specialization, reuse of dying cells, copy-on-write checks, re-matching; the crossing functions take their values owned (decision 75). |

*As built (step 4, first part):* `Mono` (with the share check and fusion), `Inline`, `Evidence`, `Lift` and `Rc` are the F# compiler's ported, one function at a time and no `Cx` yet: each pass takes and returns a list of `Core.Program.MFun`, and a pass's error is the `Stops` effect (`Evidence`'s collected and stopped at the end, so its own code stays pure). `Build/Compile.lower` runs them in the F# compiler's order. Their Core is the F# compiler's (`ZS_NO_SIMPLIFY=1 ZS_NO_DECIDE=1`): the same text after `Rc` on the 101 programs with an `.out` that don't import C (`ZS_DUMP_CORE='*'` in both compilers; `ZS_DUMP_STAGE=mono|inline|effects|lift` shows an earlier stage's). *Second part:* `Simplify` (without the F# compiler's set of finished nodes: moved code is simplified again) and `Decide` ported; a Core node has an `id` (`Ir.number`), so `Rc` caches free variables by node (`cachedFreeVars`), 3.5 times faster on the compiler. *Step 6:* `Lift`, `Simplify`, `Decide` and `Rc` run each function on the pool (`Array.Parallel.map`), each job with tables of its own (a `Vars`, its counters), `Rc` across the modules too, and `Gen` each LLVM module; borrowing's rounds stay on the driving thread, since each reads every function's code.

### 2.8 `Emit/`: Core to LLVM IR

| Module | Lines | What it is |
|---|---|---|
| `Target` | 200 | triples, the word size, CPUs and features (`--cpu`, `[<Target>]`), what a microcontroller target changes (an `i32` word, the embedded runtime, no Std). |
| `Layout` | 500 | representation: the one-word header, unions as plain values or cells, static cells for cases without fields, `option` of a pointer as the pointer, closures, strings, arrays, C structs by their ABI, SIMD alignment. |
| `Llvm` | 300 | the IR writer: a `Writer` over a `Buffer<u8>`, with names, types and constants written as pieces of an interpolation (no string per instruction), and the module's final text hashed by `Core.Hash`. |
| `Codegen` | 2,200 | functions to IR: calls and tail calls (`musttail`), matches as switches and phis, the reference-count operations against the inlined pool, bounds and overflow checks through intrinsics, `!range` and `inbounds nuw`, copy-on-write checks hoisted, loop versioning. Per module, on the pool. |
| `Runtime` | 200 | the built-in functions under their full names (`Text.String.length`), their runtime symbols and signatures. |
| `Simd` | 400 | vector types, lane operations, shuffles, masks, the target intrinsics, `[<Multiversion>]` dispatchers. |
| `Debug` | 400 | DWARF: lines, locals, unions as variant parts, Z# names in symbols. |

*As built:* `Gen/` (`Prelude`, `Emit`, `Layout`, `Helpers`, `Debug`, `Fun`, `Module`, 3,500 lines): the F# `Codegen` ported, its IR byte for byte the F# compiler's on every program of the suite (the module's text compared with `--emit-llvm`, with and without `Decide`).

### 2.9 `CImport/`: C headers

| Module | Lines | What it is |
|---|---|---|
| `Clang` | 250 | the translation unit and its cursors through `zsharp/libclang` (the one place `unsafe` is called from, inside the package). |
| `CTypes` | 300 | C declarations to Z# types: structs as `[<CLayout>]` records, unions as `[<CLayout>]` unions, enums, function pointers as `fnptr`, typedefs. |
| `Macros` | 100 | object-like macros through `clang_tokenize`: constants, no regular expressions. |

*As built:* one module, `Build/CImport` (650 lines): the translation unit's cursors through `zsharp/libclang`, C types as strings as the F# compiler read clang's JSON, a macro's body from `clang_tokenize` (no regular expressions); its declarations are the F# compiler's on every header in the repository (`.zs-cache/cimport`'s JSON the same). `zsharp/libclang` opens libclang at its first call (`dlopen`), so the compiler starts where libclang isn't installed and reads the saved import there.

### 2.10 `Build/`: from a project to a binary

| Module | Lines | What it is |
|---|---|---|
| `Options` | 100 | the record (target, cpu, optimize, sanitizer, debug info, test build, profile, check-ir): immutable, Share, given to every job. |
| `Session` | 150 | the overlay (unsaved editor text), the checked results in memory (0007's 512), the diagnostics per open document, the pool and loop handles. Not Share; lives on the driving thread. |
| `Project` | 400 | `zs.toml` and `zs.lock` (parsed by hand, the subset), path and git dependencies, namespaced ([0018](../docs/proposals/0018-packages.md)), `fetch` and `update` through `git` as a process. |
| `Graph` | 200 | the modules of a program, their dependencies from headers, the levels for parallel checking, and the cycle error. |
| `Checked`, `Lowered` | 150 | a module's checked result (its interface and its `Typed`) and its Core: two files under the same key, so the editor never lowers and a build lowers once; `[<Derive(Binary)>]`, so the cache's files are the derive's. |
| `Cache` | 500 | [0007](../docs/proposals/0007-incremental-builds.md)'s keys (`xxhash`, the compiler's own hash in each), the headers kept under a text hash, `~/.cache/zs/checked`, `worlds`, `modules`, `objects`, the LRU by modification time. |
| `Clang` | 300 | clang and `zig cc` as processes: a `Task<result<unit, Diagnostics>>` per module, `Task.all` with the cores as the limit, standard error read into diagnostics; the linker (lld, ThinLTO with its cache), PGO flags. |
| `Driver` | 700 | the build: parse, check, lower, the passes, emit, compile, link, in §4's order; `--time` and `--stats`. |
| `Server` | 250 | `zs server`: a `Net.Unix` listener in the cache directory, one build at a time, idle exit after ten minutes, `stop`. |

*As built:* `Options`, `Project` (with `Package`), `Tools` (processes, the cache's paths and keys, whole-file writes), `Modules` (loading, packages, `import c`), `Check` (the checked modules' cache: `Infer/Snapshot`'s `[<Derive(Binary)>]` interface, keyed as the F# compiler's), `Units` (the build by module: worlds, ABIs, the module and object caches, clang in parallel, ThinLTO), `Compile` (the one-module builds: a library, another target, a microcontroller, `--emit-llvm`, `-g`), `Make` (which of the two) and, at the top, `Server` (`zs server` on `Net.Unix`, a request's build run in the server with its output captured). `tests/cache.sh` gives the F# compiler's transcript line for line.

### 2.11 `Tools/`: the commands around the compiler

| Module | Lines | What it is |
|---|---|---|
| `Rpc` | 150 | JSON-RPC framing over `Console.openStandardInput` and `openStandardOutput`, `Content-Length` over bytes, messages as [0023](../docs/proposals/0023-json-in-core.md)'s `Json`. |
| `Lsp` | 900 | diagnostics, hover, completion, definition, references, rename, code actions, inlay hints, symbols, formatting, signature help: from `Typed` and the `Tree`, through the session's cache. Runs `Infer`, never `Lower`. |
| `Mcp` | 300 | `check`, `type_at`, `docs`, `build`, `run`, `emit_llvm`, `format` over the same session. |
| `Doc` | 300 | `zs doc`: reference pages from `///` comments and `Typed`'s signatures. |
| `Test` | 400 | `zs test`: finds `[<Tests>]` values ([0009](../docs/proposals/0009-tests-as-values.md)), builds the test binary, runs each test in its own process with a timeout, `--update` for inline expectations through the tree. |
| `Main` | 400 | the commands, flags to `Options`, exit codes. |

*As built:* `Lsp/Rpc` (framing, and JSON written as System.Text.Json wrote it, so the F# compiler's transcripts hold), `Lsp/Server`, `Lsp/Mcp`, `Build/Doc` (`docs/reference` byte for byte), `Commands` (build, run, test with `--update`, new, fetch, update, check) and `Main` (with protocol detection when started without arguments).

## 3. What flows between them

```
 Source ──lex──► array<Token> ──parse──► Tree ──view──► Ast ──check──► Typed ──lower──► Core
   (bytes)      (kind, offset, length)   (ids, spans,    (cases with   (per node id:   (per function,
                                          every token)    node ids)     type, impl,     owned by its
                                                                        name, hover)    job later)
 Checked = interface + Typed ──Binary derive──► ~/.cache/zs/checked/<key>;  Lowered = Core ──► lowered/<key>
 Core ──passes──► Core ──emit──► IR text (Writer) ──clang──► object ──link──► binary
```

- **Identity is a number.** A node's id (the file's index, the node's number), a type variable's number, a function's name and the hash of its Core are the only identities. Every table that F# keyed by object identity (`HashIdentity.Reference`, 25 of them) keys on one of these, so the `Binary` derive writes plain values and nothing needs physical equality. Ids are dense (a file's nodes from the parser, a function's Core nodes from `Fresh`), so every table keyed by one is an array indexed by it, and nothing hashes a node. Names are strings: an interner would be the design's one global, under a lock across parallel parsing, and identifiers are short (decision 78).
- **Positions live in the tree.** Every node has its span, every `Ast` and `Core` node its node id, so a diagnostic from any pass finds its position without a table, and nothing is cleared per check or restored from the cache. A file's `Tree` is made under `Arena.with`: nothing outside it references a node, so it dies whole, in a build after `Lower` and in the editor at the next parse.
- **The environment of a check** is the interfaces of the modules before it (its `Env`), immutable and Share, so one `Parallel.for` checks a whole level of the dependency graph against it; the results are merged into the session, and the next level's `Env` is built from them. *As built:* checking is one module after another (1.3 s of the compiler's own build, and the cache skips what didn't change); the library's files are parsed on the pool.
- **A function's Core is owned by its job** in the passes: `functions |> Array.Parallel.map (fun f -> collect (fun () -> Opt.run options env f))` moves each function into its job (decision 75), so the passes rebuild it in place with every optimization of [DESIGN §5.2](../DESIGN.md#52-perceus-reference-counting); the `env` (types, signatures, borrow summaries) is the one shared value, borrowed on most paths. *As built:* a pass gets its list as an argument (`Units.timedOn`), and the module build lets go of what a job takes, so lifting and code generation mark only the environment their jobs read (10 and 49 thousand objects on the compiler building itself); `Simplify`, `Decide` and `Rc` also mark what their jobs do share (a callee's body inlined at several call sites, a library instance in several modules' copies: about a million objects each). A code generation job decodes a copy of the types of its own (`Binary`): every job looks types up all the time.
- **Contexts, not globals.** `Infer.Cx` (one per module check), `Opt.Cx` (one per job), `Emit`'s (one per module). Each is a record of tables owned by the job that made it, returned with the result where the join needs it (the lifted functions, the sizes).

## 4. How a build runs

Where each step runs, for `zs build`:

| Step | Unit | Where | Reads | Writes |
|---|---|---|---|---|
| 1 project and graph | the program | driving thread | `zs.toml`, `zs.lock`, the headers (from the cache by text hash) | `Graph` |
| 2 parse | per file not in the cache | pool, `Array.Parallel.map` | its bytes | `Tree`, diagnostics |
| 3 check | per module not in the cache, level by level | pool, one `Parallel.for` per level | `Options`, the level's `Env` | `Checked`, diagnostics; merged into the session between levels |
| 4 restore | per module in the cache | driving thread | `~/.cache/zs/checked` (the `Binary` derive, milliseconds a module) | the session |
| 5 lower | per module whose Core isn't cached | pool | `Typed` | `Core`, kept as `lowered/<key>` |
| 6 plan | the program | driving thread | the modules' signatures | the instance set, the `Share` marks |
| 7 passes | per instance of the modules whose world changed | pool, the function moved in | `Options`, the program's environment | the function's Core, its `Opt.Cx` |
| 8 emit | per module | pool | the module's functions | IR text, hashed |
| 9 compile | per module whose IR hash is new | tasks, `Task.all` with the cores as the limit | the IR | an object in `~/.cache/zs/objects` |
| 10 link | the program | a task | the objects, the runtime | the binary |

- **Diagnostics stop a build after step 3** (a module with errors isn't kept, 0007) and are rendered sorted by file and position; steps 6 onward can report only the `Share` check's errors and internal ones.
- **Byte-identical whatever `ZS_WORKERS` is** (decision 77): fresh names per function, no `HashMap` iterated into output (a `Map`, a sorted array or source order instead), the join's results placed by index, diagnostics sorted once. `tests/cache.sh` checks it across thread counts.
- **A rebuild** after a body change in one module: step 1, step 2 for that file, step 3 for that module alone (the others restore), steps 5–8 for that module's own LLVM module (its copies of the library and the generic instances are unchanged and found by their keys), step 9 for it, step 10. The target is 0007's 0.2 s plus the module's own time, through the build server, which keeps the session warm.
- **`zs check`** is steps 1–4, and **`zs lsp`** the same per keystroke for the edited module, from the overlay, with the other open documents of the same program re-checked after it; both without `Lower`.

### 4.1 Effects in the compiler

| Effect | Performed by | Handled by | Cost (phase 10's measurements) |
|---|---|---|---|
| `Report` | the parser, the checker, the `Share` check, `Check` | `collect` at a job's or a task's boundary; `attempt` around a trial, which drops them on a miss | a call through the frame when a diagnostic is made; nothing otherwise |
| `Throw<Mismatch>` | `Unify` | `check` at the expression (a report, the error type), `attempt` at a trial (the trail undone) | a call to the clause and one check after each call on the way, the same as `?` |
| `Yield` (`seq { }`) | cold paths only: `zs doc`'s pages, listings | `Seq` | an indirect call per element: not in the lexer, the parser or the passes |

Nothing else: no `Task` on an effect (decision 72), no handlers of the compiler's own, no effect crosses a job (an empty row is required there and the checker enforces it).

### 4.2 Tasks in the compiler

- **`Lsp.serve` and `Mcp.serve`:** `task { while true do let! msg = Rpc.read stdin … }`, the read under `Task.blocking`; a request runs on the loop thread against the session, its parallel parts on the pool.
- **`Server.serve`:** `Unix.accept` in a loop, each connection a build request answered when its build ends; one at a time.
- **`Clang.compileAll`:** `Task.all` over the modules with the cores as the limit, each `Process.start` and `Process.wait`; standard error becomes diagnostics with the module's name.
- **Never `Task.spawn`:** a task never moves to another thread's loop; the session stays where it is.

## 5. The passes and what each optimizes

Every optimization in [DESIGN §9.1](../DESIGN.md#91-optimization-strategy) is carried over; this
table says where. The rewrite adds none until gen 2 equals gen 3: `.same-ir` tests and
`bench/host`'s contract pin the output while the compiler changes under it. New ones (track S's
generator fusion, item 9; `use` under effects, item 10) come after.

| Pass | In | Out | Optimizes | `Check` verifies after it |
|---|---|---|---|---|
| `Lower` | `Typed` | Core with generics, traits, effects | nothing; faithful, so `Infer` is the one place meaning is decided | types match their uses; every name bound |
| `Mono` | Core | Core, monomorphic | fusion: `map`/`filter` from `init`, a list or an array into `sum`/`fold`/`length`/`iter` as one loop (pure lambdas, decision 36); trait calls to known functions; units erased; a pure instance of an effect-polymorphic function under the name it always had | no type variable, no trait call, no row variable |
| `Share` | Core | Core, with the Share marks | the top-level values a thread may reach marked for startup, and only those | each `share<F>` reaches Share values only |
| `Inline` | Core | Core | uncurrying (a function whose body is a lambda takes its parameters; a closure applied to its arity calls its full entry); inlining of small functions, `keep` as a parameter | arities match the calls |
| `Simplify` | Core | Core | known constructors (a match on a value built or bound in sight takes its case); case of case with join points; a `let`-bound lambda only called is applied in place; so an inlined `Option.map` builds no `option` | no unreachable case left by a known constructor |
| `Evidence` | Core with `handle`/`perform` | Core without them | a clause that resumes last or stops runs where the operation is performed, nothing captured; other paths yield through closures per waiting function; loops with yielding calls run from a driver; pure functions untouched, so their IR is byte-identical to a compiler without effects | no `perform` left; every function's frames match its row |
| `Decide` | Core with patterns | Core with tag tests and join points | decision trees: no value tested twice, shared bodies as join points reuse tokens pass through | every join point reached with the same types |
| `Lift` | Core with lambdas | Core with closures | closure conversion; a top-level function's closure goes through a function of its maker's module, so borrowing is per function whatever makes closures of it | no free variable |
| `Rc` | Core | Core with `dup`, `drop`, `reuse`, `isUnique` | Perceus: ownership and borrowing (summaries in the ABI across modules), moves out of mutables, drop specialization (fields kept out of a dying cell), reuse of a dying cell for a new one of the same size, copy-on-write checks, re-matching | every owned variable consumed once on every path; a borrowed one never dropped |
| `Codegen` | Core | LLVM IR | representation (`Layout`): unions as plain values, static cells, `option` of a pointer as the pointer, the one-word header and the inlined pool; overflow through `llvm.*.with.overflow`; `!range` on lengths, `inbounds nuw`; copy-on-write checks hoisted out of loops; loop versioning for innermost call-free loops; `musttail` self-calls; `print` of an interpolation as pieces | none: clang parses the module (`-O0` in a debug build catches a malformed one at once) |
| `Clang`, link | IR | binary | `-O2`/`-Os` per module, ThinLTO with the runtime, PGO, `--cpu`, `[<Target>]`, `[<Multiversion>]` | `tests/*.same-ir` and `bench/host`'s instruction counts |

- **Why this order:** `Mono` first so every later pass sees concrete types and known calls; `Inline` and `Simplify` before `Evidence` so handlers are resolved on simplified code and a `Throw.catch` of a lambda is applied in place (no closure); `Decide` after `Simplify` so known constructors have removed what they can; `Lift` after `Evidence` since yielding makes closures; `Rc` last, on the final shape, so every reuse and borrow is decided on what runs.
- **Per function, except where it isn't:** `Mono.plan` picks the instances and `Share` follows calls across them on the driving thread, over signatures, then each instance is a job; `Lift` adds functions a job returns in its `Opt.Cx` for the join to place; `Codegen` is per module.
- **`Check` in test builds only:** `./test.sh` turns `--check-ir` on; a user's build skips it.

## 6. The compiler's own performance

The compiler is the largest Z# program and the workload phase 9's one-word header, pool and
build-speed work were for. The targets are 0020's: `bench/compile` no slower than the F#
compiler on a build from nothing, a body change and a signature change; the compiler builds
itself in no more than the gen 1 build takes; peak memory at most the F# compiler's; a cold
`zs check hello.zs` bounded by loading the library's cache.

| Lever | Where | Why it pays |
|---|---|---|
| **The cache** (0007) | `Build/Cache` | an unchanged file isn't parsed, an unchanged module isn't checked, an unchanged module's IR isn't made, an unchanged object isn't compiled; the `Binary` derive reads a module back in milliseconds |
| **Parallel halves** | §4's steps 2, 3, 5, 7–9 | parsing, checking by level, the passes per function and code generation per module on every core; clang as tasks |
| **Crossings move** (decision 75) | `Rc`, the runtime | a job's function keeps positive counts, so the passes write in place and reuse cells; only the environment pays atomic counts, and borrowing skips most of them |
| **Numbers, not identity** | `Types/Vars`, `Tree`, `Opt/Cx` | union-find over indices in a `Buffer`, path compression, levels; node ids dense per file and per function, so `Typed` and the memo tables are arrays; no cells compared by address, nothing hashes a node |
| **A trail, not copies** | `Types/Vars` | a trial undoes its bindings instead of copying the variable table (the F# checker copies `tyvars` twice) |
| **Persistent scopes** | `Infer/Scope` | a `Map` taken by value into a trial or a closure body: nothing to restore, and in-place update when unique |
| **Tokens as an array** | `Lexer` | the parser's lookahead is an index, not a resumption |
| **IR by pieces** | `Emit/Llvm` | `Writer.writeText w $"  {name} = add i64 {a}, {b}"` writes the pieces as `print` prints them, so an 8 MB module is never a string |
| **Hashing by content** | `Core/Hash`, `xxhash` | names per function and cache keys from one fast hash; byte-identical output is a property, not a test's luck |
| **A tree as arrays** | `Parser` | a node is its id in a few arrays, not an object: nothing outside the tree references a node, so a file's tree dies in a few frees after `Lower`, or at the editor's next parse |
| **Names are strings** | `Types`, `Infer` | short immutable strings, compared by bytes and hashed where looked up; an interner would be the design's one global, under a lock across parallel parsing |
| **No SIMD** | | a cached build never lexes an unchanged file, the line index is built once per edit, and the passes are trees and maps |

- **Measured by:** `zs build --time` (what was checked, made, compiled), `zs build --stats` (allocations by size class, reuse hits, copy-on-write copies, atomic marks and operations per pass), `bench/compile/run.sh`, and the compiler building itself in CI per commit.
- **If a target fails:** `--stats` names the pass whose atomic operations are high, and the fix is in that pass (borrow the environment, or copy into the job the part it walks); both halves stay parallel (decision 79).

## 7. The editor path

`zs lsp` is the same compiler to step 4, run per keystroke ([0019](../docs/proposals/0019-syntax-tree.md), 0007; the roadmap's rule that every feature's types are the checker's in the editor):

- **Per change:** the edited document's text from the overlay is parsed (one file), its module checked against the cached `Env` (the rest restore), and the other open documents of the program re-checked after it. The target is 100 ms for a 2,000-line file.
- **From `Typed` and the `Tree`:** hover (types with rows, constraints, doc comments), completion, definition and references (resolved names per node id), rename and code actions (edits on the lossless tree, so comments and layout survive), inlay hints (parameter types, inferred effects before `=`), document symbols, formatting, signature help.
- **All of a file's errors:** error nodes and the error type, so one mistake doesn't hide the next; sorted; the same list `zs check` prints. *As built:* every failed statement of each declaration, in the file's order (`tests/err_many.zs`; the same from `zs build` and `zs lsp`, `tests/lsp/many.sh`).
- **`import c` in the editor:** `CImport` runs libclang in the server's process, so a C name has its type in Zed with no build run and no `clang` on PATH; the header's result is cached under its text and flags.
- **One session, one cache:** the server's session holds the 512 most recent checked results and shares `~/.cache/zs/checked` with the CLI and the build server, so a build after editing restores what the editor checked.

## 8. Testing the compiler

- **The suite is the contract:** every `.out`, `.err`, `.same-ir`, session script and benchmark in `tests/` and `bench/` passed under the F# compiler and under this one before the F# one went ([the report](../docs/reports/self-hosting.md)); `tests/err_many.zs` adds a file with five errors in two declarations.
- **`--check-ir`** after every pass in `./test.sh`, so a pass's bug fails where it is made.
- **The compiler's own tests** are values ([0009](../docs/proposals/0009-tests-as-values.md)) in `src/tests/` (to come): a session per test, in-process, under `Parallel.for`; the lexer and parser on every `.zs` file in the repository (a parse, a print of the tree, byte-identical to the source); `Unify` on tables of pairs; `attempt`'s rollback; `Decide` against `ZS_NO_DECIDE=1`; `Binary` round trips of `Checked`.
- **Determinism:** `tests/cache.sh` across `ZS_WORKERS=1` and the cores; `tests/bootstrap.sh` comparing gen 2 and gen 3 and naming the first differing function from `ZS_DUMP_IR` when they differ.
- **Sanitizers and valgrind:** `./test.sh --valgrind` and `--sanitize=thread` over the parallel passes, as over the parallel tests today; `ZS_LEAKCHECK=1` on the compiler building itself.
- **Differential:** while both compilers exist, `tests/differential.sh` builds every test program with both and compares the `.out` and `.err` results and the benchmarks' instruction counts; the IR itself is allowed to differ (the rewrite lowers differently) until the F# compiler is gone.

## 9. Order and what is still measured

[0020](../docs/proposals/0020-self-hosting.md)'s order: the library's and tracks' items and the
moving crossing in the F# compiler; `Lexer`, `Parser` and the measurement; `Infer` and `Lower`;
the passes, `Emit` and `Build`; the tools; the parallel halves and `Check`; gen 2 equals gen 3
and the deletion. Decided above and in decisions 73–79: effects for diagnostics and unification's
backtracking, moving crossings, tasks for the waits, ordered output, strings for names, dense ids
indexing arrays, a tree per arena, no SIMD, the cache's two files, `Mono.plan` then instantiation
per instance, both halves parallel. One thing is measured, because it is the review's gate and not
a design choice: the 1.5× criterion on the kept lexer and parser.
