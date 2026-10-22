# Proposals

A proposal is the design document for a feature that isn't designed yet, written before the
design review that decides it, in the form of [F#'s RFCs](https://github.com/fsharp/fslang-design)
and [C#'s language proposals](https://github.com/dotnet/csharplang/tree/main/proposals): the
questions those ask (compatibility, diagnostics, tooling, performance, scaling) are answered
before any code is. [DESIGN.md](../../DESIGN.md) describes the language as designed; a
proposal describes a change to it, and [ROADMAP.md](../../ROADMAP.md) says when it's built.

| # | Proposal | Status | Decided at |
|---|---|---|---|
| 0001 | [Type providers](0001-type-providers.md) | Draft | the third design review |

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
