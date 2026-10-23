# Proposal 0019: the lossless syntax tree

| | |
|---|---|
| **Status** | Approved in principle |
| **Decided at** | decision 33 and track E's plan ([ROADMAP](../../ROADMAP.md#editor-tooling-e)): F2 first, then the rest of E2b; kept before phase 11 by phase 12's list ([ROADMAP](../../ROADMAP.md#phase-12-release-01)) |
| **Builds** | track E: F2 (the tree, reflow, `zs fmt --stdin`, range formatting) and E2b's rest (rename, code actions, signature help); the parser of phase 11 ([ROADMAP](../../ROADMAP.md#phase-11-self-hosting)) builds the same tree |
| **Rests on** | decisions 32 (editor support: tree-sitter, `zs lsp`, `zs mcp`, Zed first) and 33 (`zs fmt`: one style, no configuration; a lossless syntax tree for reflow) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §12](../../DESIGN.md#12-tooling) |
| **Related** | [0009 tests as values](0009-tests-as-values.md) (`zs test --update` edits literals), [0007 incremental builds](0007-incremental-builds.md) (the per-module cache keeps hovers, not trees), [0020 the compiler in Z#](0020-self-hosting.md) (phase 11's parser builds it), [0005 ergonomics](0005-ergonomics.md) (the `?` code action), [0021 warnings](0021-warnings.md) (the `[<Cyclic>]` code action), [0001 type providers](0001-type-providers.md) (rename refused on provided names) |

- [x] Approved in principle
- [ ] Discussion
- [ ] Implementation (steps 1 and 3 in the F# compiler: the tree, the printer, `--stdin`, range formatting)

## Summary

The parser builds a concrete syntax tree with full fidelity: every token with the whitespace,
newlines and comments around it, nodes by kind with their spans, and missing-token and error
nodes, so any text has a tree. The AST becomes a typed view over it: each AST node points at
its tree node, positions come from the tree, and the `Syntax.positions` table keyed by node
identity goes. One parser builds both (tree-sitter's grammar stays for highlighting). On the
tree: `zs fmt` as a pretty-printer that reflows to 100 columns and keeps comments where they
belong, `--stdin` and range formatting; rename across modules; code actions; signature help;
the literal rewriting `zs test --update` needs; and five LSP methods `zs lsp` doesn't offer
today. Decision 33 already names the tree; its row's "planned" becomes this proposal, and no
new decision row is needed.

```fsharp
let report (items: list<Item>) = items |> List.filter (fun i -> i.price > 100<usd>) |> List.map (fun i -> $"{i.name}: {i.price}") |> String.concat "\n" // the expensive ones
```

```fsharp
let report (items: list<Item>) =
  items
  |> List.filter (fun i -> i.price > 100<usd>)
  |> List.map (fun i -> $"{i.name}: {i.price}")
  |> String.concat "\n" // the expensive ones
```

## Motivation

- **The formatter can't reflow.** `zs fmt` works line by line on tokens (`src/Format.fs`, header lines 1–6 at HEAD, with the ponytail note that reflow needs a syntax tree): it re-indents, spaces operators and keeps at most one blank line, and checks that the output lexes to the same tokens (lines 226–229). It can't break a 150-column line because it doesn't know where a continuation is allowed or what the continuation's indentation is; only a tree knows that. Track E's exit test, "`zs fmt` reflows a 150-column line and keeps its comments", can't be met by it.
- **Positions live beside the tree.** `Syntax.positions` (Syntax.fs:12–14 at HEAD) maps AST nodes to `(line, column, length)` by object identity, for identifiers, binders, call heads and statements, filled by `mark` and `copyPos` (739–748), cleared at the start of every check and restored for cached modules through `Snapshot` (facts sheet §3). Phase 11 lists it among the 25 identity-keyed maps that Z# has no equivalent for, and wants positions in the nodes.
- **Comments aren't in the tree at all.** `lexComments` (Syntax.fs:316) returns them beside the tokens as `(line, column, text)`, and `Driver.docAbove` (Driver.fs:1634 in the main checkout) finds a declaration's `///` comment by scanning the lines above it. Each tool that needs a comment finds it its own way.
- **One error stops a file.** The parser raises at the first error (`Driver.parseText`, Driver.fs:22–30 in the main checkout), so in the editor a half-typed line loses the whole file: document symbols come from `Driver.parseFile` and are empty when it raises (Lsp.fs ~359), formatting returns nothing, and the checker never runs. Phase 11's "diagnostics are values" needs a tree that exists for every text.
- **Rename, code actions and signature help need edits,** and an edit is a token's text replaced with its trivia kept. Computing one from an AST without trivia means re-deriving where tokens are from line and column, for each feature.
- **What other compilers do.** Roslyn's red-green trees, SwiftSyntax and rust-analyzer's rowan all keep every byte of the source in the tree, with comments and whitespace as trivia on tokens, and build typed views over an untyped tree. Z# takes rowan's shape, a plain tree with the AST as a typed view, without the incremental reparse (*Alternatives*).

## Detailed design

### The tree

```fsharp
type Trivia =
  | Space of string      // spaces and tabs
  | Newline              // "\n"; a "\r\n" is read as one
  | Comment of string    // "// …", without its newline
  | DocComment of string // "/// …": what hover and zs doc show

type Token =
  { kind: Tok            // Syntax.Tok as today: KId, KInt, KStr, KSym, KNewline, KIndent, KDedent, …
    text: string         // "" for a layout token and for a missing one
    offset: int          // byte offset of the text in the file
    leading: Trivia list
    trailing: Trivia list
    missing: bool }      // expected here and not found

type Node =
  { kind: Kind           // one per AST case, plus the syntactic ones (below)
    children: Child list
    error: bool }        // tokens skipped while recovering, kept as they were

and Child = T of Token | N of Node
```

- **Full fidelity:** the tokens' leading trivia, text and trailing trivia, concatenated in order, give the file's text byte for byte. `tests/cst/roundtrip.sh` parses every `.zs` under `tests/` and `lib/` and compares.
- **Trivia ownership:** a token owns what follows it up to and including the end of its line (a trailing `// comment`, the spaces before it); everything else, including own-line comments, blank lines and `///` doc comments, is leading trivia of the next token (Roslyn's rule). So a comment at the end of a line moves with that line's last token, an own-line comment with the token below it (what `Format.fs` does at line 200 today), and a doc comment is the leading trivia of its declaration's first token: `Driver.docAbove`'s line scan becomes a read of that list.
- **Layout tokens:** the lexer keeps emitting `KNewline`, `KIndent` and `KDedent` from the offside rule (Syntax.fs:305–316), so the parser's grammar doesn't change. In the tree they have no text; the indentation they stand for is whitespace trivia, which the printer writes fresh.
- **Kinds:** one per AST case (39 expression and 16 declaration cases at HEAD, Syntax.fs:41–130) and one for each form that has no AST node: parentheses, a bracket pair, an indented block, a match clause (`|`, pattern, `when`, `->`, body), an attribute list, a type annotation, an interpolation hole. A node's span runs from its first token's text to its last token's, trivia excluded, and is computed when the node is built.
- **Missing tokens and error nodes:** where the parser expects a token and finds another, it records a missing token of the expected kind (zero width) and goes on. Where it can't go on, it skips tokens into an error node until a line at the same or a lower indentation (`KNewline`, `KDedent`) or a declaration keyword (`let`, `type`, `module`, `open`, `trait`, `impl`, `extern`), then continues. Every text gets a tree and a list of diagnostics, one per recovery, instead of an exception at the first.
- **Positions:** byte offsets in the tree; a per-file line index (the offsets of line starts) turns them into the `file:line:col` of diagnostics and the LSP's line and character. `Core.Hover`'s `hline`, `hcol` and `hlen` (Core.fs ~658) become a file, an offset and a length.

### The AST as a view

- **Now, in the F# compiler:** every AST case that `mark` positions today gains its tree node as a field, so `Typer.at` and `recordKey` (Typer.fs ~684–710 at HEAD; the main checkout differs) read the node's span, and `Syntax.positions`, `mark`, `copyPos` and `Snapshot`'s restore of the table go. The checker is otherwise untouched: an error node becomes a `CompileErrorPos` at its span when the view is built, so the checker keeps stopping at the first error until phase 11 gives it an error type that unifies with anything ([0020](0020-self-hosting.md)). Document symbols, formatting, rename and the code actions read the tree, so they work on a file that doesn't check.
- **In phase 11:** the AST is a view in rowan's sense, typed accessors over the node (`Call.head`, `Call.args`, `Let.binder`), with nothing copied. The tree's shape is the same, so the rewrite ports it.
- **One parser:** the compiler's parser is the reference, as `editors/tree-sitter-zsharp/grammar.js` says in its header. The tree-sitter grammar stays for highlighting, indentation and the outline, and `./test.sh` keeps parsing every test file with both.

### `zs fmt` as a pretty-printer

The printer turns the tree into a Wadler/Leijen document and lays it out at 100 columns:

```fsharp
type Doc =
  | Text of string
  | Line              // a space when its group fits on one line, else a newline at the nesting
  | HardLine          // always a newline
  | Nest of int * Doc // what follows a newline inside is indented this much more
  | Group of Doc      // on one line when it fits in the width, else its Lines break
  | Cat of Doc * Doc
```

- **One style, no options** (decision 33). The rules `Format.fs` has stay: 2 spaces a level, bracket contents one level past their opener's line, the same spacing around operators and punctuation everywhere, the `asWritten` cases (Format.fs:18: `f(x)` against `f (x)`, `-x`, `x?`, `list<int>`, `9.58<s>`) kept as written since spacing carries meaning there, trailing space trimmed, at most one blank line.
- **Where a line breaks,** by construct, when its group doesn't fit:

| Construct | Laid out as |
|---|---|
| a pipeline `a \|> f \|> g` | `a` on its line, then each `\|> stage` on its own line at `a`'s indentation (the summary's example) |
| a call `f a b c` | the head on its line, each argument below it one level in |
| an operator chain `a + b * c` | broken after an operator, the rest one level in |
| a list, array or record literal | one element per line, each one level past the opener's line, the closer after the last element |
| a lambda as the last argument | `(fun x ->` on the call's line, the body below one level in (today's "absorbed" bracket, Format.fs ~86) |
| `if c then a else b` | `then` and `else` branches on their own lines, one level in |
| match clauses | never joined: one clause per line, always |
| a function's parameters | one per line, one level in, when the signature doesn't fit |
| a string literal, a comment | never broken: a line that's long because of one stays long |

- **Comments move with their tokens.** A trailing `//` comment ends a line, so a token carrying one forces a newline after it and its group breaks there; the summary's comment stays after `"\n"` as that token moves to its own line. An own-line comment prints before its token at the token's new indentation. A `///` comment prints as written, above its declaration.
- **Verbatim:** the lines after the first of a string that spans lines, raw strings and interpolation holes print as written; a hole's column moves with the indentation, as today (Format.fs ~215).
- **Blank lines:** at most one is kept where the source has any; none are added (*Unresolved questions*).
- **Safety:** the output is lexed and compared with the input's tokens, as today, and also parsed and compared with the input's AST view, so a reflow that changed the offside structure is caught before the file is written; the message names it as a `zs fmt` bug and leaves the file alone.
- **Commands:** `zs fmt [--check] files…` as today; `zs fmt --stdin` reads standard input and writes the result to standard output, for editors and git filters, printing nothing and exiting 1 on an error so a pipe can't empty a buffer. `textDocument/rangeFormatting` formats the smallest declarations or statements whose spans cover the range and returns edits for them only. `textDocument/formatting` keeps returning one edit for the whole document (Lsp.fs:469–478). The MCP `format` tool returns the new layout.
- **A file with a parse error** isn't formatted: `zs fmt` prints the error and exits 1, as today. A range that contains an error node is left alone without an error, since editors ask on every save.
- **`Format.fs` goes:** 229 lines at HEAD, replaced by the printer.

### Rename

- **`textDocument/prepareRename`** answers with the identifier token under the cursor and its text when the checker gave it a `key` (`Core.Hover.key`: a local's unique name or a global's qualified name; what `references` already uses, Lsp.fs ~258–265). Anything else is refused with the reason (*Diagnostics*): a keyword or literal; a provided name, with [0001](0001-type-providers.md)'s message `temp is provided by json from weather.json; rename the key there`; a C name, which is declared in a header; a name defined outside the project (the library, a dependency under `.zs-cache/deps`); a module named by its file.
- **`textDocument/rename`** collects every hover with the same key, across modules, over the project's programs: the root program (`main` in `zs.toml`) and each file under the project root that no module of it imports (test files), as `zs test` finds them, each checked as a program from the cache ([0007](0007-incremental-builds.md): a cached module's hovers come back without a re-check). Each reference is a token: the server parses the files it edits, replaces the token's text and keeps its trivia, and answers a `WorkspaceEdit` with the edits per file, open or not. Rename never edits a file under `.zs-cache`, so a provided module, a dependency and `import c`'s cached declarations can't change under it.
- **What a key covers:** a local, a function, a type, a union case, a member, a trait, a module with a `module` header, and a record field at its declaration, in `r.field`, `{ field = v }`, `{ r with field = v }` and the pattern `{ field = p }`, which is track E's exit test ("renaming a record field updates every module that uses it").
- **The new name** must be an identifier and not a keyword; nothing else is checked. A name that now shadows or collides shows as an ordinary diagnostic after the edit, as it would when written by hand.

### Code actions

`textDocument/codeAction` is computed on request from the tree and the results the server already has; nothing is re-checked. Each action is a title, a kind and a `WorkspaceEdit`:

| Action | Offered when | Edit |
|---|---|---|
| **Add missing match cases** (`quickfix`) | the exhaustiveness error `match is not exhaustive; missing case: Circle _` (Match.fs:143); the diagnostic carries the example value's text in its `data` | a clause `\| Circle _ -> panic "todo: Circle"` after the last clause, at its indentation, once per missing case |
| **Add a type annotation** (`refactor`) | on a binder whose type wasn't written (the inlay-hint candidates, `Hover.inlay`) | `: int` after a `let` binder, `(x: int)` around a bare parameter, with the type as hover prints it |
| **Add an `open`** (`quickfix`) | `unknown value 'parse'` (Typer's `unknown`) and a module in the program or the library defines the name | `open Json` after the file's last `open` (or its `module` header), or `Json.parse` in place; both are offered |
| **Replace a `match` with `?`** (`refactor.rewrite`) | a `match x with \| Some v -> v \| None -> None` (either order), or the `Ok`/`Error` form, where [0005](0005-ergonomics.md)'s `?` applies | the match node's span becomes `x?` |
| **Add `[<Cyclic>]`** (`quickfix`) | the cycle warning of [0021](0021-warnings.md) | an attribute list inserted before the type's first token, after its `///` comment and at its indentation, so the doc comment stays above |

Phase 11's error type adds the actions that need a checked file with errors in it; these five work today because `zs lsp` checks in collect mode, which keeps one error per declaration and the hovers of the rest (facts sheet §3).

### Signature help

- **`textDocument/signatureHelp`,** triggered by `(`, `,` and space, answers when the cursor is inside a call node whose head the checker resolved: the head's type from its hover, split into parameters; the parameter names from the definition's tree (the binder tokens of its `Fun` node, through the hover with `isDef`); `activeParameter` is the number of argument children before the cursor's offset. For a member with named and optional arguments (DESIGN §2.3), the names and defaults come from the member's declaration.
- **Curried calls:** `add 1 |` shows `add : int -> int -> int` with the second parameter active; a pipeline's `|> f` counts the piped value as the last argument.

### Rewriting `expect` literals

[0009](0009-tests-as-values.md)'s `zs test --update` is this proposal's client: the test binary reports each failing `expect` with its new text and the literal's position. `zs test` parses each reported file once, finds the string token at the position (it must be the `expect` call's literal, else 0009's error), replaces its text (a literal gets `"""` quoting when the new text has a newline or a quote; a triple-quoted one keeps it), keeps the trivia, applies the edits from the last to the first so offsets stay valid, and writes the file. The new text is written as `Show` printed it, with no indentation added, since a triple-quoted literal's lines are its text (*Unresolved questions*). Nothing else in the file changes, and `zs fmt` isn't run.

### The checker and the cache

- **Hovers carry offsets,** and 0007's per-module cache keeps them as part of a module's result, so a module restored from the cache has its positions without a tree in memory. A tree exists only for the documents open in the editor and for the files a build parses; an unchanged file isn't parsed (DESIGN §9).
- **`Snapshot`** stops restoring `Syntax.positions` (Driver.fs ~803–806 at HEAD); the spans it needs are inside the nodes it writes, and phase 11's `Binary` derive writes them with the rest ([0020](0020-self-hosting.md)).
- **Diagnostics** keep their `file:line:col`, computed through the line index, so the `.err` tests pin that positions don't move.

### The language server

Today's `initialize` reply (Lsp.fs:416–430 at HEAD) advertises full text sync, hover, document symbols, inlay hints, document formatting, definition, references and completion triggered by `.`, with server info `zs` 0.4; it doesn't offer rename, signature help, code actions, semantic tokens, workspace symbols or pull diagnostics; it re-checks on every change with no debounce (the ponytail note at line 84), re-analyzes only the changed document, and watches no files (no `didChangeWatchedFiles`; facts sheet §1). Unsaved text goes through `Driver.overlay` (Driver.fs:14–19). With this proposal:

| Method | Reads | Answers |
|---|---|---|
| `textDocument/rename`, `prepareRename` (new) | hovers' keys, the tree of each edited file | a `WorkspaceEdit` of token replacements |
| `textDocument/codeAction` (new) | the diagnostics at the range, the hovers, the tree | the five actions above |
| `textDocument/signatureHelp` (new; triggers `(`, `,`, space) | the call node, the head's hover and definition | parameters, the active one |
| `textDocument/rangeFormatting` (new) | the tree | edits for the covered declarations or statements |
| `textDocument/formatting` | the tree | one whole-document edit, as today |
| `textDocument/documentSymbol` | the tree | the outline, on a file with parse errors too |
| hover, definition, references, inlay hints, completion | hovers, as today | as today, with ranges from the tree |
| `publishDiagnostics` | the parser's list and the checker's | every parse error in the file, then the checker's |

Full text sync stays: parsing a file is milliseconds, and incremental sync would buy an incremental reparse this proposal doesn't do. File watching stays absent; [0001](0001-type-providers.md) is the proposal that needs it.

### Order of implementation

1. **The tree and the view:** the lexer keeps trivia, the parser builds the tree and the AST from it, `Syntax.positions` goes, `tests/cst/roundtrip.sh` passes over `tests/` and `lib/` (wired into `./test.sh`'s host-only block, as every script is), and `./test.sh` stays green with no diagnostic moving (the `.err` tests pin them).
2. **Recovery:** missing tokens and error nodes; `tests/lsp/session.sh` gains a `didChange` with a parse error and a `documentSymbol` after it, answered with the outline.
3. **The printer:** `zs fmt` over the tree; `Format.fs` deleted; one commit reformats `tests/` and `lib/` where lines were over 100 columns, and `./test.sh`'s `zs fmt --check` (test.sh:160) keeps them so; `--stdin`; range formatting. Exit test: the 150-column line with its comments.
4. **Rename** and `prepareRename`; the record-field exit test, across modules.
5. **Code actions and signature help.**
6. **`expect` rewriting,** which 0009's step 3 waits for.

Phase 11 rewrites each step in Z# ([0020](0020-self-hosting.md)), on the same tree shape.

## Drawbacks

- **A bigger tree.** Every token is an object with its trivia; a 2,000-line file has on the order of 15,000 tokens (an estimate). Fine for a compiler, and only open documents and parsed files hold one; the cache holds hovers and Core.
- **Two parsers stay.** tree-sitter's for highlighting and the compiler's for everything else, kept in step by `./test.sh`. This proposal doesn't merge them; it stops the compiler's half from needing tree-sitter's.
- **One reformatting commit** touches every long line in `tests/` and `lib/`; `git blame` wants it in `.git-blame-ignore-revs`.
- **More opinions in the canonical layout:** where a pipeline breaks, how arguments wrap. Decision 33 means they're chosen once, here, and some won't like them.
- **A longer parser:** recovery and tree building add to a 2,500-line `Syntax.fs`, until phase 11 splits it.
- **Indirection in the F# compiler:** a node field on AST cases changes every pattern match on them once. The typed view pays off in phase 11, not before.

## Alternatives

- **Reuse tree-sitter's tree.** Its grammar (`grammar.js`, 389 lines, with a scanner for layout) already produces a lossless tree with error recovery, in a C library. It has no types, so rename and the code actions would need the checker's results mapped onto a second parser's nodes, and its recovery differs from the compiler's, so the two would disagree on broken text. Not chosen: the compiler's parser is the reference, and the grammar stays for highlighting.
- **Keep the token formatter and add heuristics** for long lines. A token pass can't tell a match clause's `|` from an operator, where a lambda's body ends, or what indentation a continuation must have to stay inside its construct under the offside rule. Not chosen: it can't reflow safely, which is the whole item.
- **Red-green trees as Roslyn's:** immutable green nodes with widths, red nodes with absolute positions built on demand, so an edit reparses only the changed region. Z# doesn't need the incremental reparse: parsing a file is milliseconds, and [0007](0007-incremental-builds.md) makes a keystroke cost one module's check. Not chosen; the split exists for incremental reparse and nothing else needs it.
- **Positions in the AST without a concrete tree,** phase 11's "positions in the tree" alone. Fixes the identity-keyed table, not the formatter, rename or `expect`. Not chosen: the concrete tree gives positions for free.
- **A formatter over the AST plus a trivia pass** that re-attaches comments, as Fantomas does for F#. Its history of lost comments is the cost of two sources of truth. Not chosen: one tree can't lose what it holds.
- **Rename by text search.** Can't tell `x` the local from `x` the field; the checker's keys can. Not chosen.
- **Configurable formatting** (a width, styles). Decision 33 settled it. Not chosen.

## Compatibility

- **Not a language change.** The parser accepts the same programs with the same meaning; no syntax is added or removed, so the tree-sitter grammar is unchanged.
- **The canonical layout changes** where a line was over 100 columns: `zs fmt --check` fails on such files until they're reformatted, once. An older compiler compiles the reflowed source as any; its `zs fmt` may re-indent a reflowed continuation differently where its rules differ, so a project pins one `zs` version for formatting, as with any formatter.
- **Diagnostics** keep their positions and messages; the exception types (`CompileError`, `CompileErrorPos`, `CompileErrorAt`) stay in the F# compiler until [0021](0021-warnings.md)'s diagnostic record and phase 11.
- **Compiled binaries:** none to consider; packages are source (decision 27), and nothing of the tree reaches a binary.
- **The library** is unchanged, reformatted once with the rest.
- **Microcontrollers:** unaffected; the tree is the compiler's.
- **Editors:** a client without `prepareRename`, code actions or signature help ignores the capabilities; Zed has all of them. The MCP `format` tool returns the new layout; `check`, `type_at` and `docs` are unchanged.

## Pragmatics

### Diagnostics

| Situation | Error |
|---|---|
| a parse error | `main.zs:12:18: expected ')'`, as today, and the rest of the file is parsed; the checker runs until phase 11 as it does now |
| several parse errors in one file | each printed once; after one, the parser skips to the next line at the same or a lower indentation, so a missing bracket gives one error, not a cascade |
| rename on a keyword, a literal or an operator | `nothing to rename here: 'match' is a keyword` |
| rename on a provided name | `temp is provided by json from weather.json; rename the key there` |
| rename on a C name | `point_add is declared in point.h; rename it there` |
| rename on a library or dependency name | `List.map is defined in lib/core/Collections/List.zs, outside this project` |
| rename to a keyword or a non-identifier | `'type' is a keyword; a name is a letter or _ followed by letters, digits, _ or '` |
| rename of a module named by its file | `Parser is named by its file parser.zs; rename the file` |
| `zs fmt` on a file with a parse error | the parse error; the file is left alone |
| `zs fmt` whose output would parse differently | `formatting would change the program (a zs fmt bug; the file was left alone)` |
| a formatting range with an error node | the range is left alone, with no error |
| `--update` at a position that isn't a string literal | [0009](0009-tests-as-values.md)'s `expect needs a string literal to update; this is a call` |
| a code action whose diagnostic is stale | the action isn't offered: actions come from the current tree and results only |

### Tooling

- **Hover, completion, definition and inlay hints** show what they show today, the checker's real types with no build run; their ranges are the tokens'. The editor keeps them while a file has a parse error elsewhere.
- **New in `zs lsp`:** rename with `prepareRename`, five code actions, signature help, range formatting (the table in *The language server*). Zed's rename, quick fixes and signature popup work through them.
- **Document symbols** come from the tree, so the outline survives a parse error.
- **Diagnostics while editing:** every parse error in the file, each at its token, then the checker's, pushed as today.
- **The tree-sitter grammar gains nothing:** no syntax changes. It keeps highlighting, indentation and the outline, pinned for Zed as grammar changes are.
- **Commands:** `zs fmt --stdin`, `zs fmt --check` in `./test.sh`, `zs test --update` through the tree. The MCP `format` tool uses the printer.

### Performance

- **Parsing** allocates a token object per token and a trivia list each; a file is parsed once per keystroke in the editor and once per build when its text changed (0007: an unchanged file isn't parsed). The estimate: a 2,000-line file parses in a few milliseconds, inside track E's 100 ms re-check budget, which checking dominates.
- **The printer** is linear in the document: Wadler's `fits` looks ahead at most one line width. The estimate: a 10,000-line file in well under a second.
- **Rename** reads hovers already in memory or restored from the cache and parses only the files it edits.
- **Code actions and signature help** read the current results; nothing is re-checked for them.
- **Memory:** a tree per open document and per file being built; none per cached module.
- **Compiled code and build time:** unchanged beyond parsing.

### Scaling

| Dimension | Typical | Upper bound |
|---|---|---|
| file size | 100–500 lines | 50,000 lines (a provided SVD module, 0001), parsed and printed in linear time |
| tokens per file | 1,000–5,000 | 500,000 |
| trivia on one token | 0–1 | a 1,000-line comment block before a declaration |
| line length before reflow | under 100 columns | 10,000 characters (a data literal, printed one element per line) |
| nesting depth | 5 | 200; the parser is recursive, and deeper nesting is reported as an error rather than overflowing the stack |
| parse errors in one file | 0–1 | one per line (a file pasted from another language): at most one error per recovery point |
| references in a rename | 10 | 10,000 across 500 files, one edit each |
| match cases added by one action | 1–3 | 100 (a large enum) |

### Culture-aware formatting and parsing

- **Bytes throughout.** Offsets are byte offsets into UTF-8 source (decision 28). The LSP's `character` is UTF-16 code units unless the client negotiates `positionEncoding: utf-8`; the line index converts either way.
- **Columns** for the 100-column width count Unicode scalar values, one per character; wide characters aren't measured, as most formatters don't.
- **Literals print as written:** `1_000`, `0xCF0`, `1.5e3`, strings and comments are copied byte for byte; the printer never reinterprets a token. No locale is read anywhere.

## Unresolved questions

1. **Trivia ownership.** This document: a token owns its line's end (trailing), and the next token owns the rest (Roslyn's rule). Alternative: SwiftSyntax's, where the newline itself is leading trivia of the next token, which makes "the last token on a line" a lookup rather than a property.
2. **Blank lines.** This document keeps at most one where the source has any and adds none, so a programmer's grouping survives. Alternative: exactly one blank line between top-level declarations always (rustfmt), which normalizes more and loses the grouping.
3. **Incremental reparse later.** This document stores absolute offsets, the simplest form for what positions are used for. Alternative: widths relative to the parent from the start, so a green/red split could come without changing the tree's shape, at the cost of a walk for every absolute position.
4. **How a pipeline breaks.** This document puts one stage per line when the pipeline doesn't fit. Alternative: fill the line with stages and break where the width runs out, which is shorter and harder to read.
5. **`expect` literal indentation.** This document writes the new text as `Show` printed it, with no indentation. Alternative: indent to the `expect` call and strip the common indentation when comparing (ppx_expect's rule), which reads better and makes a literal's text differ from its value; 0009 would own the comparison's half.
6. **The checker on error nodes before phase 11.** This document raises at the first error node when the AST view is built, so the checker doesn't change until phase 11's error type. Alternative: an error type in the F# checker now, touching the 3,600-line `Typer` twice.
7. **Signature help's triggers.** This document triggers on `(`, `,` and space, since calls are curried and `add 1 |` wants help. Alternative: `(` and `,` only, quieter and missing most Z# calls.

## History

- **2026-10-22:** drafted from track E's F2 and E2b items, phase 11's "One lossless syntax tree", DESIGN §12 and decision 33, and `src/Format.fs`, `src/Syntax.fs` and `src/Lsp.fs` as they stand.
