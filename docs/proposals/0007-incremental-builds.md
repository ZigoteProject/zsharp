# Proposal 0007: incremental builds by module

| | |
|---|---|
| **Status** | Approved in principle; implementation in progress (phase 9.5) |
| **Decided at** | the phase 9.5 plan ([ROADMAP](../../ROADMAP.md#phase-95-incremental-builds-and-threads)) |
| **Builds** | phase 9.5 |
| **Rests on** | decisions 27 (source packages, checked modules cached), 32 (editor support through `zs lsp` and `zs mcp`) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §9](../../DESIGN.md#9-compiler) |
| **Related** | [0001 type providers](0001-type-providers.md) (a provided module is a module here), [0019 the syntax tree](0019-syntax-tree.md), [0020 the compiler in Z#](0020-self-hosting.md) (carries this design over) |

- [x] Approved in principle
- [ ] Discussion
- [x] Implementation (in progress; this document records the design as the working tree builds it)

## Summary

Each module's checked result is cached under a key made of its own source and of what it sees
of the modules it uses, so a change to a function's body re-checks one module, and a change to
a signature re-checks the modules that use it. The passes after checking keep their results
per module too, keyed by the Core they read. One cache serves the CLI, `zs lsp`, `zs mcp`
and `zs doc`: in memory in a running server and in `~/.cache/zs` between runs. It replaces the
two snapshot layers (after the library, after the main file's other modules) that phase 5
introduced.

## Motivation

- **A rebuild follows the size of the change today only in its last third.** Phase 9's module cache keeps each module's reference counting, LLVM IR and object, but checking is cached in two layers (a change in one module re-checks every module after it), and monomorphization through lambda lifting and borrow inference run over the whole program: 0.29 s of the 0.61 s a one-function change costs in a 2,600-line program of 30 modules.
- **Editors check everything.** A keystroke in a 2,000-line file re-checks the program; track E's exit test wants it within 100 ms, and [0001](0001-type-providers.md) wants a changed sample to re-check only the provided module and its users.
- **Phase 11's compiler** is a large program whose authors will edit one module at a time; the design carries over to it as is.

## Detailed design

### Keys

A module's key hashes everything its checked result can depend on:

| Part of the key | Why |
|---|---|
| the compiler's hash and its settings | a new compiler or `--target` changes what a check produces |
| the program key: the names of the program's modules and their explicit impls | what's in scope by name |
| the module's source, and the saved results of its `import c` (and provided modules, 0001) | its own text |
| the interface hashes of the modules it uses (all of the library's) | a changed signature in a used module re-checks this one |
| the global hashes of the other modules before it: impls, members of others' types, what's seen without naming a module | a new impl elsewhere can change which impl a call resolves to |

A checked result carries its own interface hash (what others see by name), its global hash,
and its parts: what it added to the type checker's state, its hovers, and its functions' Core.
A module with errors has no result saved.

### Checking

- **Order:** the library's modules, then the program's in dependency order. For each, the key is computed from the results of what it sees; a hit restores the result into the checker's state (a few milliseconds per module, from the binary form `Snapshot` writes without reflection); a miss checks the module and saves the result.
- **What a change costs:** a body: that module. A signature: that module and those whose keys include its interface hash, which is exactly the modules that use it. A new impl or member of another module's type: the modules after it that see such things, conservatively, since the global hash can't say who would have used the impl.
- **Hovers** are part of the result, so an editor restoring a module has its hovers without re-checking.

### After checking

- **Per module, keyed by what it reads:** monomorphization, fusion, inlining, simplification, decision trees and lambda lifting run for a module when the hash of its checked Core and of the Core it inlines or instantiates from other modules (their functions' bodies, not only signatures) changes. Results are kept in the same store.
- **Borrow inference** is a fixpoint over the call graph. Per module it takes the borrowed-parameter summaries of callees as input; a module whose callees' summaries didn't change reuses its own; a changed summary re-runs the callers, until nothing changes. The whole-program rounds that phase 9 runs become this propagation.
- **Then phase 9's module cache** (reference counting, IR, objects) as it is, keyed by the lifted functions and their borrowed parameters.

### One cache

- **In memory,** in a running server: the results by key, newest last, at most 512 (what typing changes is one module's; the others stay).
- **On disk:** `~/.cache/zs/checked` for checked results, `objects/` and `modules/` as before. The CLI, `zs lsp`, `zs mcp` and `zs doc` share them. Eviction on disk is by age with a size cap (*Unresolved questions*).
- **Editors:** a keystroke re-checks the edited module; the others restore. Diagnostics are published for the edited module and for any whose key changed with it. `Driver.overlay` keeps the unsaved text that the key hashes.
- **`ZS_NO_CACHE=1`** checks everything, for comparison and for the tests.

### Correctness

- **Deterministic:** a build from the cache produces the same binary as a build from nothing, checked by `tests/cache.sh` over every test program, which also lists which modules each change checks again.
- **Conservative keys:** anything a check reads is in its key; the global hash makes the conservative case (an impl added elsewhere) re-check more rather than less.
- **The compiler's own hash** is in every key, so a new compiler sees an empty cache.

### Order of implementation

1. Per-module keys and results for checking, replacing the two layers; `tests/cache.sh` extended to say which modules were checked.
2. The passes after checking per module, and borrow inference by propagation.
3. The editor's path: diagnostics and hovers from restored results; the 100 ms exit test in Zed.

## Drawbacks

- **The global hash is coarse:** adding an impl re-checks every later module that could see it. Finer tracking (which impls a module resolved) is more bookkeeping for a change that's rare.
- **Hashing is work:** every build hashes every module's source and interfaces, linear in the program, which is small next to checking but not nothing.
- **`Snapshot` is written by hand:** a new field of the checker's state or a new Core case needs its place, and `tests/cache.sh` fails until it has one. Phase 11's `Binary` derive ([0020](0020-self-hosting.md)) generates it.
- **Disk use** grows with every variant of every module until eviction.

## Alternatives

- **Query-based incremental compilation** (rustc's queries, Salsa): fine-grained dependency tracking per query, with memoization of everything. More precise, and a framework the whole compiler is written against; modules are the grain Z# already has, and phase 11 may revisit.
- **Declaration-level keys:** a key per function and type rather than per module; fewer re-checks after a signature change in a module with many declarations, at the cost of tracking dependencies within a module. Later, if measurements ask.
- **Whole-program checking with the two layers:** what phase 5 built; the numbers above are its cost.
- **A build server that keeps state:** what the language server is; the on-disk cache gives the CLI the same without a daemon.

## Compatibility

- **No change to the language.** The cache directory's layout changes; an old cache is ignored (the compiler's hash differs).
- **`tests/cache.sh`'s expectations** change with the modules a change re-checks.

## Pragmatics

### Diagnostics

None new. `zs build --time` reports the modules restored and the modules checked, with times, so a rebuild that checks more than expected can be seen.

### Tooling

- **`zs build --time`** shows restored against checked per phase.
- **The language server** publishes diagnostics for what changed; a module restored from the cache keeps its last diagnostics (it had none, or it wouldn't be cached).
- **`zs doc` and `zs mcp`** read the same results.

### Performance

- **Target:** in the 2,600-line, 30-module program, a body change rebuilds in under 0.2 s and re-checks one module; a signature change re-checks exactly the users. In Zed, a 2,000-line file re-checks within 100 ms.
- **Restoring:** milliseconds per module from the binary form.
- **First builds:** unchanged, plus the writing of results.

### Scaling

| Dimension | Typical | Upper bound |
|---|---|---|
| modules per program | 10–50 | 2,000 (phase 11's compiler is a few hundred) |
| lines per module | 100–500 | 20,000 |
| results in memory (a server) | 50 | 512 (the cap) |
| results on disk | 1,000 | capped by size (below) |

Checking stays linear in the modules changed; restoring is linear in the program's size, and
the per-module hashing too.

### Culture-aware formatting and parsing

None.

## Unresolved questions

1. **Disk eviction:** by age with a size cap (2 GB), or a `zs cache clean`. Both are cheap; the cap keeps a machine's disk bounded without a command to remember.
2. **The global hash's grain:** whether a module's key should record which impls it resolved, so an added impl re-checks only modules that would resolve differently. Measured after phase 11's compiler exercises it.
3. **Hovers:** cached with the result (as here) or computed on request from the restored state. Caching costs disk and saves the editor a re-check.

## History

- **2026-10-22:** drafted from phase 9.5's plan and the working tree's per-module cache.
