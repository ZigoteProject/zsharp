# Editors and the grammar

Z# ships a tree-sitter grammar and extensions for Zed, VS Code and JetBrains IDEs. Several files
must agree, and the suite checks that they do. This page is the order to change them in. Each
extension's setup is in its own README.

## The parts

| Path | Is | Depends on |
|---|---|---|
| `editors/tree-sitter-zsharp/grammar.js`, `src/scanner.c` | the grammar and its scanner (the offside rule) | the language |
| `editors/tree-sitter-zsharp/src/parser.c` | **generated** by `tree-sitter generate`, and committed | `grammar.js` |
| `editors/tree-sitter-zsharp/queries/*.scm` | highlights, indents, outline, brackets | the grammar's node names |
| `editors/tree-sitter-zsharp/test/` | the grammar's corpus | |
| `editors/zed/languages/zsharp/*.scm` | **copies** of the queries | the queries |
| `editors/zed/extension.toml` | pins the commit Zed builds the grammar from (`rev`) | a commit containing the grammar |
| `editors/vscode/syntaxes/` | a TextMate grammar; Rider uses it too | the highlights' keywords |
| `editors/vscode`, `editors/rider` | the extensions: they start `zs lsp` | the `zs` binary |

Everything semantic (hover, completion, rename, diagnostics, formatting, allocation hints) comes
from `zs lsp`, the compiler itself, so the extensions stay thin. Don't put language knowledge in
an extension that the server could give.

## Changing the syntax

1. **`grammar.js`** (and `scanner.c` for layout), with a case in `test/`.
2. **Generate:** `./dev bash -c 'cd editors/tree-sitter-zsharp && tree-sitter generate'`. Commit
   the generated `src/parser.c`: Zed compiles it and doesn't run the generator.
3. **Queries:** a new keyword or node in `queries/highlights.scm` and the others it affects.
4. **Copy the queries** to `editors/zed/languages/zsharp/`.
5. **TextMate:** a new keyword in `editors/vscode/syntaxes/`.
6. **Check:** `./dev bash -c 'cd editors/tree-sitter-zsharp && tree-sitter test'`.
7. **Commit** all of that with the compiler's change.
8. **Pin:** set `rev` in `editors/zed/extension.toml` to that commit, and commit again
   (`Zed: the grammar pinned at the commit with …`).

The pin is a second commit because it names the first. Between the two, the suite fails on
purpose, and a Zed using the extension from this checkout can't build the grammar: do both
before stopping.

## What the suite checks

- the Zed queries are byte-for-byte the grammar's queries
- the TextMate grammar's keywords are the tree-sitter highlights' keywords
- `extension.toml`'s `rev` has the current `grammar.js` and `scanner.c` (CI checks out the whole
  history for this)
- the grammar parses every Z# program in the tree with no error node
  (`editors/tree-sitter-zsharp/script/errors.sh`), and its corpus passes

`errors.sh` is heavy: it parses every file in the tree. Run it through the suite, or `nice` it;
don't leave one running.

## The language server

- `zs lsp` and `zs mcp` are in `src/Lsp/` and share the compiler's front end: they stop after
  type checking, on the real checker, with no build.
- **A language feature isn't done until the editor has it:** hover shows its type, completion
  offers it, the formatter lays it out, and an error in it doesn't blank the rest of the file.
- **Tests are scripted sessions** in `tests/lsp/` and `tests/mcp/`: requests in, the transcript
  compared.
- **Trust.** The servers build and run a project's type providers only with `--trust`
  ([security](security.md#the-servers-zs-lsp-zs-mcp-the-build-server)). VS Code's extension
  passes it in a trusted workspace, Rider's for a trusted project, Zed's doesn't. An extension
  never passes it on its own judgment.

## The formatter

`zs fmt` works on the lossless syntax tree: comments kept, 100 columns, a file written whole or
not at all. New syntax needs its layout there and a case in `tests/fmt/`; the suite then holds
the whole repository to it.
