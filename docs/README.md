# Z# documentation

Each set of documents answers one kind of question. A fact lives in one of them and the others
link to it ([which one](contributing/documentation.md#where-a-fact-lives)).

| Set | Answers | Kept current by |
|---|---|---|
| [Guide](guide/README.md) | how do I write this? 18 chapters of small, whole programs | `tests/docs.sh` compiles and runs every example |
| [Specification](spec/README.md) | what exactly does this construct mean? | hand, with each language change |
| [Library reference](reference/README.md) | what does this function do? | generated from `lib/`'s doc comments (`tests/reference.sh`) |
| [Proposals](proposals/README.md) | why is it designed this way, and what else was considered? | written before a feature, kept as its record |
| [Reports](reports/) | what was measured or reviewed, and when? | dated; not updated afterwards |
| [Posts](posts/) | a longer explanation of one idea | dated; not updated afterwards |
| [Contributing](contributing/README.md) | how do I work on Z# itself? | hand, with the process |

Outside `docs/`:

| Document | Answers |
|---|---|
| [README.md](../README.md) | what is Z#, for whom, and what state is it in? |
| [DESIGN.md](../DESIGN.md) | the language as designed, the reasons, and every decision (§13) |
| [ROADMAP.md](../ROADMAP.md) | what's built, what's next, and each phase's exit tests |
| [CHANGELOG.md](../CHANGELOG.md) | what each release changed, and what a program has to rewrite |
| [src/ARCHITECTURE.md](../src/ARCHITECTURE.md) | the compiler: its modules, passes and data flow |
| [AGENTS.md](../AGENTS.md) | the starting point for working on the repository: the map, the commands, the rules |
| [CONTRIBUTING.md](../CONTRIBUTING.md), [SECURITY.md](../SECURITY.md) | how to report a bug or send a change; how to report a vulnerability |
| `editors/*/README.md`, `examples/*/README.md` | each extension's setup; each example program |
