# Documentation

Which document holds what, how each is kept true, and how to write for them.

## Where a fact lives

Each fact has one home. The other documents link to it; they don't repeat it.

| Fact | Home | Not in |
|---|---|---|
| how to use a feature, by example | [the guide](../guide/README.md) | the spec, the README |
| what a construct means, exactly | [the specification](../spec/README.md) | the guide |
| what a library function does | its `///` comment in `lib/` | hand-written pages |
| why the language is this way; each decision | [DESIGN.md](../../DESIGN.md), §13 for decisions | proposals, once implemented |
| the alternatives considered for a feature | [its proposal](../proposals/README.md) | DESIGN.md |
| what's built, what's next, exit tests | [ROADMAP.md](../../ROADMAP.md) | proposals' status beyond a line |
| what a release changed, what to rewrite | [CHANGELOG.md](../../CHANGELOG.md) | the guide ("new in…") |
| how the compiler is built inside | [src/ARCHITECTURE.md](../../src/ARCHITECTURE.md) | DESIGN.md |
| a measurement or a review, on a date | [docs/reports](../reports/) | anywhere it would go stale |
| how to work on the repository | [AGENTS.md](../../AGENTS.md), [these pages](README.md) | ROADMAP.md, the README |

## What changes with what

| You changed | Update |
|---|---|
| syntax or semantics | the spec chapter and `13-grammar.md`; the guide; DESIGN.md; the tree-sitter grammar and its Zed pin; CHANGELOG |
| a library function | its doc comment; `./dev tests/reference.sh`; a new module's row in `docs/reference/README.md`; CHANGELOG |
| a `zs` command or flag | the guide's [Tools](../guide/10-tools.md) (and [Programs](../guide/08-programs.md) for projects); the README's tooling table if it's a new command |
| an error message | its `.err` test; the guide or spec where they quote it |
| the compiler's structure | ARCHITECTURE.md (an *As built* note where it departs from the plan) |
| a proposal's state | its status table, its row in `docs/proposals/README.md`, the ROADMAP item |
| the process, CI, a pin | these pages |

## How each set is checked

- **The guide.** Every ` ```zsharp ` block is a whole program the suite builds
  (`tests/docs.sh`); a block without `main` gets an empty one. A ` ```text ` block **directly
  after** it is the program's exact output, and ` ```text windows ` after that is Windows's
  where it differs. A fragment that can't compile alone, or an error shown on purpose, uses
  ` ```fsharp ` or another fence so it isn't run. Run the example and paste what it printed;
  don't write output by hand.
- **The reference** is generated: one page per file of `lib/`, by `zs doc`. The suite fails when
  it's stale, when a public name has no doc comment, or when a page isn't in the index. Fix the
  comment, never the page.
- **Doc comments.** A ` ```zsharp ` block in one is a doc test; `// => value` lines are what it
  must print.
- **The specification** is descriptive of the reference implementation. A paragraph marked
  *Note* is informative, *Implementation* describes what needn't be imitated, and *Deviation*
  records where the compiler differs from the design. When you find the compiler and the spec
  disagree, fix one or add a *Deviation*; don't leave it.
- **Links** are relative, so they work on GitHub and in a checkout. Check the ones you add.

## Proposals and decisions

A change to the language starts as `docs/proposals/NNNN-name.md`, in the section order
[the index](../proposals/README.md) gives: Summary, Motivation, Detailed design, Drawbacks,
Alternatives, Compatibility, Pragmatics, Unresolved questions, History.

1. **Draft:** written, with its open questions.
2. **Approved in principle:** a decision row in DESIGN §13, a roadmap item with exit tests.
3. **Implemented:** the design text moves into DESIGN.md; the proposal stays as the record of
   the alternatives. *Implemented in part* names what's built and what waits.
4. **Declined** proposals stay, with the reason, so the question isn't reopened without new
   facts.

Decision numbers in DESIGN §13 are permanent; code and docs cite them (`decision 74`).

## Writing

The reader is starting from zero, is reading to do something, and may be reading in a second
language or through a translator. They may also be a program.

- **Say what it does, then how, then why.** The first sentence of a page, a section and a doc
  comment stands alone.
- **Be specific.** The command, the file, the number, the exact message. `./dev ./test.sh`, not
  "run the tests". A date is absolute: `2026-11-11`, not "last week".
- **Show a program.** A small, whole example with its output teaches more than the paragraph
  describing it, and the suite keeps it true.
- **Plain words, short sentences, present tense.** One idea a sentence. Put the subject first.
  If a sentence needs reading twice, split it.
- **No selling and no hedging.** Not "powerful", "simply", "blazingly"; not "should probably".
  State what's true and what the limit is. Limitations go where the reader will meet them, as
  the README's *Status and limitations* does.
- **One name for one thing.** "stage 0" everywhere, not also "bootstrap compiler" and "seed".
  Define a term where it's first used.
- **Code is in backticks:** names, commands, paths, flags, literal messages.
- **Lists** for parallel items, each opening with its **term in bold** when it has one;
  **tables** for lookups; prose for reasoning. Don't nest lists more than once.
- **Don't write what will rot:** line counts, "currently", "new", "recently". If a number
  matters, give its date and how it was counted, or put it in a report.
- **Don't repeat another document.** Link to the home of the fact.

**Layout:** Markdown, wrapped at 100 columns where the file already wraps. One `#` title a
file, sentence-case headings, fenced code with its language (`zsharp` runs in the guide; `fsharp`
highlights without running; `sh`, `toml`, `text`). No HTML, no emoji in prose.

**Dated documents** (reports, posts, a release's changelog section) aren't edited to follow
later changes. Correct an error in them; put news in a new one.
