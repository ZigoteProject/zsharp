# Proposals

A proposal is the design document for a feature that isn't designed yet, written before the
design review that decides it, in the form of [F#'s RFCs](https://github.com/fsharp/fslang-design)
and [C#'s language proposals](https://github.com/dotnet/csharplang/tree/main/proposals): the
questions those ask (compatibility, diagnostics, tooling, performance, scaling) are answered
before any code is. [DESIGN.md](../../DESIGN.md) describes the language as designed; a
proposal describes a change to it, and [ROADMAP.md](../../ROADMAP.md) says when it's built.

| # | Proposal | Status | Decided at |
|---|---|---|---|
| 0001 | [Type providers](0001-type-providers.md) | Approved in principle, after 0.1 | the third design review |
| 0002 | [Effect handlers](0002-effect-handlers.md) | Implemented (phase 10) | the phase 6 gate; open questions at the third design review |
| 0003 | [Spans and slices](0003-spans-and-slices.md) | Approved in principle | the phase 9.6 design review |
| 0004 | [C layout](0004-c-layout.md) | Approved in principle | phase 9.6 (`fixed`); the third design review (unions, layout facts) |
| 0005 | [Ergonomics](0005-ergonomics.md) | Approved in principle | the phase 9.6 design review |
| 0006 | [Anonymous records and top-level patterns](0006-anonymous-records.md) | Declined (anonymous records); approved (top-level patterns) | the third design review |
| 0007 | [Incremental builds](0007-incremental-builds.md) | Approved in principle | the phase 9.5 plan |
| 0008 | [Threads](0008-threads.md) | Approved in principle | the phase 9.5 plan |
| 0009 | [Tests as values](0009-tests-as-values.md) | Approved in principle | track D's plan |
| 0010 | [Properties and fuzzing](0010-properties-and-fuzzing.md) | Approved in principle, after phase 11 | track D's plan |
| 0011 | [Debug info, profiles and traces](0011-debug-info-profiles-traces.md) | Approved in principle | track D's plan |
| 0012 | [Interrupts, `[<NoAlloc>]` and intrinsics](0012-interrupts-noalloc-intrinsics.md) | Approved in principle; `noalloc<F>` declined | decision 42, track M's plan, the third design review |
| 0013 | [Bit fields](0013-bit-fields.md) | Approved in principle, after phase 11 | the third design review |
| 0014 | [Placement](0014-placement.md) | Approved in principle | track M's plan; the third design review (`[<Section>]`, `[<Align>]`) |
| 0015 | [Fixed-point numbers](0015-fixed-point.md) | Approved in principle as a library, after phase 11 | the third design review |
| 0016 | [Async on bare metal](0016-async-bare-metal.md) | Approved in principle | the third design review |
| 0017 | [Iteration](0017-iteration.md) | Approved in principle, before phase 11 | the third design review |
| 0018 | [Packages](0018-packages.md) | Approved in principle; the index is a draft | track K's plan |
| 0019 | [The lossless syntax tree](0019-syntax-tree.md) | Approved in principle | decision 33, track E's plan |
| 0020 | [The compiler in Z#](0020-self-hosting.md) | Approved in principle: go; questions settled | the third design review; the phase 11 review |
| 0021 | [Warnings](0021-warnings.md) | Approved in principle | phase 12's deferred features |
| 0022 | [Targets: macOS and Windows](0022-targets-macos-windows.md) | Approved in principle | decision 29, track T's plan |
| 0023 | [JSON in Core](0023-json-in-core.md) | Approved in principle | track S's plan |
| 0024 | [The library's API](0024-library-api.md) | Approved in principle | track S's plan |
| 0025 | [Reading effect rows](0025-reading-effects.md) | Draft | a design review with 0017, before phase 11 |

**Status:**
- **Draft:** written, with its open questions listed.
- **Approved in principle:** a design review took it. Its decision has a row in DESIGN §13, and the roadmap a phase or track item with exit tests. The unresolved questions are settled as the implementation starts.
- **Implemented:** the design text moves into DESIGN.md, and the proposal stays as the record of the alternatives and the reasons.
- **Declined:** stays, with the reason, so the question isn't reopened without new facts.

**Sections,** in this order: a status table and checklist; Summary; Motivation (the scenarios,
and what the alternative without the feature looks like); Detailed design (syntax, meaning,
examples, the order of implementation); Drawbacks; Alternatives (each with why it wasn't
chosen); Compatibility (breaking or not, older compilers, the library); Pragmatics
(diagnostics, tooling, performance, scaling, culture-aware formatting); Unresolved questions;
History.
