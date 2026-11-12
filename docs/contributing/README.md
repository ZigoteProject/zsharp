# Contributing to Z#

How to work on the compiler, the library, the runtime, the tools and the documents. Start with
[AGENTS.md](../../AGENTS.md): the repository's map, the commands and the rules on one page.
These pages are each rule's detail and reasons.

| Page | Covers |
|---|---|
| [Z# for contributors](zsharp.md) | the language in ten minutes: what differs from F#, and the mistakes it prevents |
| [Development](development.md) | the container, stage 0, building, the test suite, adding a test, debugging |
| [Testing](testing.md) | the kinds of test, writing one, which tests a change needs, when one fails |
| [Code style](code-style.md) | Z#, the compiler's own rules, the library's, C, shell, commit messages |
| [Packages](packages.md) | what a package is, `zs.toml`, wrapping a C library, the packages in this repository |
| [Security](security.md) | the trust boundaries, what safe code guarantees, rules per component, a review checklist |
| [CI and releases](release.md) | what CI runs, version numbers, cutting a release, stage 0 |
| [Documentation](documentation.md) | which document holds what, how each is tested, writing style |
| [Diagnostics](diagnostics.md) | how an error or warning message is written and tested |
| [Performance](performance.md) | what's promised, the benchmark gate, measuring, writing an optimization |
| [Editors and the grammar](editors.md) | the grammar, queries, extensions and the Zed pin, in the order to change them |
| [Targets and boards](targets.md) | how a build reaches a platform; adding a board, a core, an operating system |
| [Glossary](glossary.md) | the project's words: stage 0, tracks, Core, Evidence, `Share`… |

**Before a change is done:**

- [ ] it has a test, and `./dev ./test.sh` passes
- [ ] a user-visible change is in `CHANGELOG.md`; a breaking one says what to rewrite
- [ ] the guide, the specification and `DESIGN.md` say what the code now does
- [ ] new public library names have doc comments, and `docs/reference/` is regenerated
- [ ] a grammar change has its Zed pin
