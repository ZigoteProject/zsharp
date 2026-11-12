# Proposals

A proposal is the design document for a feature that isn't designed yet, written before the
design review that decides it, in the form of [F#'s RFCs](https://github.com/fsharp/fslang-design)
and [C#'s language proposals](https://github.com/dotnet/csharplang/tree/main/proposals): the
questions those ask (compatibility, diagnostics, tooling, performance, scaling) are answered
before any code is. [DESIGN.md](../../DESIGN.md) describes the language as designed; a
proposal describes a change to it, and [ROADMAP.md](../../ROADMAP.md) says when it's built.

| # | Proposal | Status | Decided at |
|---|---|---|---|
| 0001 | [Type providers](0001-type-providers.md) | Implemented (0.7): `json`, `csv`, `sql` with typed queries (`queries = …`), `svd`, `import c` on the protocol, the `import` form, the editor's side, providers on PATH and from packages; a JSON Schema as `json`'s input and `rows = "sqlite"` after 0.7 | the third design review |
| 0002 | [Effect handlers](0002-effect-handlers.md) | Implemented (phase 10) | the phase 6 gate; open questions at the third design review |
| 0003 | [Spans and slices](0003-spans-and-slices.md) | Implemented (phase 9.6) | the phase 9.6 design review |
| 0004 | [C layout](0004-c-layout.md) | Implemented: `fixed` (phase 9.6); C unions and layout facts (phase 12) | phase 9.6 (`fixed`); the third design review (unions, layout facts) |
| 0005 | [Ergonomics](0005-ergonomics.md) | Implemented (phase 9.6; F#'s list and array ranges in 0.7) | the phase 9.6 design review |
| 0006 | [Anonymous records and top-level patterns](0006-anonymous-records.md) | Declined (anonymous records); implemented (top-level patterns, phase 12) | the third design review |
| 0007 | [Incremental builds](0007-incremental-builds.md) | Implemented (phase 9.5; the build server in phase 11) | the phase 9.5 plan |
| 0008 | [Threads](0008-threads.md) | Implemented (phases 9.5 and 11) | the phase 9.5 plan |
| 0009 | [Tests as values](0009-tests-as-values.md) | Implemented: items 1–3 and 7 before phase 11, doc tests (8) in phase 12; stress (4), benchmarks (9), coverage by lines (10) and tests on a chip (11) in 0.7; coverage through `llvm-cov`, `zs bench --instructions`, `zs test --debug` and the MCP `test` tool after 0.7 | track D's plan |
| 0010 | [Properties and fuzzing](0010-properties-and-fuzzing.md) | Implemented (0.7): properties, shrinking by replays, `Prop.model`, `zs fuzz` and properties on a chip; a property of curried parameters, `Arbitrary` for `Map`, `Set`, `HashMap`, `Buffer` and spans, `zs test --seed`, `shrinkTime` and the `HashMap`, `Channel` and pool models after 0.7 | track D's plan |
| 0011 | [Debug info, profiles and traces](0011-debug-info-profiles-traces.md) | Implemented in part: `ZS_STATS` (phase 11), lldb and the editor's allocation hints (phase 12); every value in gdb and lldb (heap values through their objects), `-g` on optimized builds and Z# names in a panic's backtrace on Linux (0.7); variant parts, pretty-printers, a backtrace's lines, `zs profile`, traces and the rest after 0.7 | track D's plan |
| 0012 | [Interrupts, `[<NoAlloc>]` and intrinsics](0012-interrupts-noalloc-intrinsics.md) | Implemented (phase 12); `noalloc<F>` declined | decision 42, track M's plan, the third design review |
| 0013 | [Bit fields](0013-bit-fields.md) | Implemented (phase 12) | the third design review |
| 0014 | [Placement](0014-placement.md) | Implemented in part: the heap's size and reuse (phase 12); constants in flash (arrays, lists, records, tuples and unions) and `[<Section>]` and `[<Align>]` on top-level values (0.7); `[<Align>]` on a type after 0.7 | track M's plan; the third design review (`[<Section>]`, `[<Align>]`) |
| 0015 | [Fixed-point numbers](0015-fixed-point.md) | Implemented (0.7): one-case unions without a tag, `Numerics.Fixed`, `ofFloat` folded on literals and the `q15` filter benchmark; C's view of a one-case union, the `raws` builtins and the vector forms after 0.7 | the third design review |
| 0016 | [Async on bare metal](0016-async-bare-metal.md) | Implemented (phase 12; `zs test --target` in 0.7); the `clock` key after 0.7 | the third design review |
| 0017 | [Iteration](0017-iteration.md) | Implemented (before phase 11; list expressions over any `Iter` pinned in 0.7); the versioning pass's `while` shape after 0.7 | the third design review |
| 0018 | [Packages](0018-packages.md) | Implemented in part: namespaced dependencies, versions (phase 12), the `[c]` section, the orphan rule; internal modules, targets, and `zs add`, `zs remove` and `zs tree`, the lock's hashes, `zs vendor`, `--offline` and workspaces (0.7); `zs add` by name and a second major's `v2/` directory after 0.7; the index is a draft | track K's plan |
| 0019 | [The lossless syntax tree](0019-syntax-tree.md) | Implemented (before phase 11, and the compiler's parser in phase 11) | decision 33, track E's plan |
| 0020 | [The compiler in Z#](0020-self-hosting.md) | Implemented (phase 11) | the third design review; the phase 11 review |
| 0021 | [Warnings](0021-warnings.md) | Implemented: `unused-value` (before phase 11), `cycle` (phase 12); `deprecated` at the 1.0 freeze | phase 12's deferred features |
| 0022 | [Targets: macOS and Windows](0022-targets-macos-windows.md) | Implemented (phase 11.5): every target builds; the suites on the platforms' own runners in CI don't pass yet | decision 29, track T's plan |
| 0023 | [JSON in Core](0023-json-in-core.md) | Implemented (before phase 11) | track S's plan |
| 0024 | [The library's API](0024-library-api.md) | Implemented in part: items 2–4 and 6–8 of track S, with the integers' checked, saturating and bit operations (item 3), ISO 8601 parsing (item 6) and UDP and name lookup (item 8) in 0.7; `Duration`'s functions, `DateTime`'s arithmetic and fields, and `Endpoint` after 0.7 | track S's plan |
| 0025 | [Reading effect rows](0025-reading-effects.md) | Implemented (before phase 11, decision 80) | a design review with 0017, before phase 11 |
| 0026 | [Performance you can see](0026-performance-you-can-see.md) | Implemented in part: the editor's allocation hints (phase 12), arenas on a chip and a leak failing its test under `ZS_LEAKCHECK=1` (0.7); atomic counts and the rest are a draft | a design review, with the flagship's first profiles |
| 0027 | [More microcontrollers](0027-more-microcontrollers.md) | Implemented in part (phase 12): the Nucleo-F401RE, RTT and probe-rs, not yet run on the board itself; the other boards are a draft | a design review, before phase 12's M4 (one real board) |
| 0028 | [Written constraints](0028-written-constraints.md) | Approved in principle; not built | track G's item 6, before packages publish signatures |
| 0029 | [Leaving a loop](0029-leaving-a-loop.md) | Implemented | track G's item 12 |
| 0030 | [Checking ahead](0030-checking-ahead.md) | Proposed; step 1 spiked and taken out (same bytes, no time) | after 0.7.1: the compiler's front half on the pool |
| 0031 | [Stability and support](0031-stability-and-support.md) | Draft | a design review, before the release after 0.7.1 |
| 0032 | [First-party packages: `sqlite`, `tls` and `http`](0032-first-party-packages.md) | Draft | a design review, with 0031 |

**Status:**
- **Draft:** written, with its open questions listed.
- **Approved in principle:** a design review took it. Its decision has a row in DESIGN §13, and the roadmap a phase or track item with exit tests. The unresolved questions are settled as the implementation starts.
- **Implemented:** the design text moves into DESIGN.md, and the proposal stays as the record of the alternatives and the reasons. **Implemented in part** names what's built and what waits, with the roadmap's marker (*after 0.7*, which was *after 0.6.2* until 0.7) for the rest.
- **Declined:** stays, with the reason, so the question isn't reopened without new facts.

**Sections,** in this order: a status table and checklist; Summary; Motivation (the scenarios,
and what the alternative without the feature looks like); Detailed design (syntax, meaning,
examples, the order of implementation); Drawbacks; Alternatives (each with why it wasn't
chosen); Compatibility (breaking or not, older compilers, the library); Pragmatics
(diagnostics, tooling, performance, scaling, culture-aware formatting); Unresolved questions;
History.
