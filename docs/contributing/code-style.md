# Code style

The suite enforces formatting and warnings. The rest is here: what a reviewer would otherwise
have to say. When a rule and the surrounding code disagree, match the code and raise the
difference.

## Z#, everywhere

- **`zs fmt` decides layout.** Two spaces, 100 columns. Don't format by hand or argue with it;
  a commit that only reformats is listed in `.git-blame-ignore-revs`.
- **No warnings.** The repository builds `--strict`. Fix the cause; don't silence it.
- **Names:** `camelCase` for values, functions and fields; `PascalCase` for types, union cases,
  traits, effects and modules. A name says what the thing is, in whole words (`decode`, `digits`,
  `collect`), not how it's built.
- **Annotate public signatures.** Parameters and results of public functions carry their types;
  local bindings are inferred.
- **`let private`** for everything a module doesn't offer.
- **Errors are values.** A failure the caller can expect is an `option` or a `result`. `panic` is
  for a bug: a state the code's own logic says can't happen.
- **Immutable first.** `let mutable` and `while` are fine in a tight loop (see
  `lib/core/Text/Hex.zs`); keep the mutation inside one function.
- **Small `unsafe`.** One expression where possible, behind a safe function that checks its
  arguments. A comment says why it's sound.
- **No speculative code:** no option nobody sets, no abstraction with one user, no code kept
  "for later".

### Comments

- `///` is a doc comment: required on every public name in `lib/`, expected on the compiler's
  modules and their main types. It says what the thing gives and what its edge cases do, in a
  sentence or two.
- `//` explains what the code can't: why it's this way, what the constant means, which decision
  or proposal it follows (`decision 74`, `0021`). Lower case, no full stop, above the line.
- Don't narrate (`// loop over items`), and don't leave history (`// was X before`): git has it.

```fsharp
// a hex digit's value, either case, or -1
let private value (c: u8) : int = …

/// The bytes the hex digits (either case, two a byte) give, or `None` for an odd count or
/// anything that isn't a digit.
let decode (s: string) : option<array<u8>> = …
```

## The compiler (`src/`)

[src/ARCHITECTURE.md](../../src/ARCHITECTURE.md) is the design; these are its rules.

- **Stage 0's language only.** `src/` is compiled by the pinned earlier release
  ([development](development.md#stage-0)).
- **Modules form a DAG** in the directory order `Diag`, `Syntax`, `Types`, `Infer`, `Core`,
  `Opt`, `Gen`, `Build`, then the servers. A module uses only what's above it.
- **Nothing global.** No module-level `mutable`. State is a field of `Options`, of the `Session`,
  or of a job's context.
- **Diagnostics through `Report`.** A pass reports and goes on, so a file shows every error. The
  parser recovers into error nodes. Never `panic` on a user's mistake.
- **Pure work on the pool, waits as tasks, the session on the driving thread.** A job reads
  shared data, owns what moved into it and returns a value.
- **Deterministic output.** The same input gives the same bytes, with one worker or many. Don't
  let hash order, paths, time or scheduling reach the output.
- **Error messages** say what is wrong, where, and what to write instead, in the words of the
  language, not the compiler's (`a closure can't capture a let mutable`, not `EClosureCapture`).
  Each has a test with its exact text.
- **When the code goes another way than ARCHITECTURE.md says,** add an *As built* note there.

## The library (`lib/`)

- **Core uses no Std.** Core runs on a chip with no operating system.
- **The API's design** (the layers, and what each module holds and why) is
  [proposal 0024](../proposals/0024-library-api.md). Read it before adding a module.
- **Follow F#'s names** where the function exists there (`List.map`, `String.split`,
  `Option.defaultValue`), so F# programmers find it.
- **Every public name is documented,** with an example where the behavior isn't obvious. A
  `zsharp` block in a doc comment is a doc test; `// => value` is the output it must print.
- **Say what bad input does** in the doc comment: `None`, `Error`, or a panic, and test each.
- **Regenerate the reference** after changing a doc comment: `./dev tests/reference.sh`.
- **A new module** needs its row in `docs/reference/README.md`.
- **Wrap, don't rewrite.** HTTP, TLS, SQLite and their like are packages binding the robust C or
  Rust library ([packages](packages.md)), not Z# rewrites.

## C (`runtime/`, `src/host.c`, packages' C)

- Match the file: its naming, bracing and comment style.
- It builds with clang and gcc, for hosts and for both chip targets. Code for one platform is
  behind that platform's `#if`.
- Check every length, index and return value. Sizes are `size_t`; a size computed from input is
  checked for overflow before it's used.
- A runtime change is tested under `./test.sh --sanitize` and `--valgrind`.
- `rt-embedded.c` allocates nothing it doesn't have to and assumes no operating system.

## Shell (`dev`, `test.sh`, `tests/*.sh`, `src/*.sh`)

- `#!/usr/bin/env bash`, then a comment saying what the script does and how it's called.
- `set -eu` (`set -u` where a failing command is the test), `cd "$(dirname "$0")/.."`, temporary
  files under `mktemp -d` with a `trap` that removes them.
- Quote every expansion. A `&&` list hides failures from `set -e`: test and `exit` explicitly.
- It runs on Linux, macOS (BSD tools) and Git Bash on Windows: no GNU-only flags without a
  fallback.
- A test script prints only what's deterministic, and `test.sh` compares it to `.expected`.
- Before `rm -rf`, the script proves the directory is its own
  (`src/install.sh` refuses anything else).

## Commits

One sentence saying what the program now does, as a user or a reader of the code would put it.
No type prefix, no ticket, no trailers.

```
A literal outside its type's range is an error, 1e-3 is a float, compare orders a NaN
A header added beside a package's C file rebuilds it where zig cc builds (R3-3)
Zed: the grammar pinned at the commit with break and continue as one node
0.7.1: the version, the changelog with what a 0.7.0 program rewrites, the specification and the docs
```

- A prefix names an area only when the commit is about nothing else (`Zed:`, `ROADMAP:`,
  `fuzz.sh:`).
- One change a commit, with its test and its docs.
- The body, if any, says why, and what was measured.
- No personal names or addresses anywhere in the message.
