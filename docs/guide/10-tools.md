# 10. Tools

## The zs command

| Command | Does |
|---|---|
| `zs new <name>` | create a project |
| `zs build [file.zs] [-o out]` | build an executable (the project's, without a file) |
| `zs run [file.zs [--]] [args…]` | build and run |
| `zs check <file.zs>` | type-check only, reporting every error and warning |
| `zs test [file.zs] [paths…] [--update] [--summary]` | run `[<Tests>]` values, each test in its own process; `--update` rewrites failing `expect` literals |
| `zs fmt [--check] <files…>` | format files in place (`--check`: list unformatted ones; `--stdin`: standard input to standard output) |
| `zs doc <file.zs>` | print a Markdown reference of a file's documented items |
| `zs fetch` / `zs update` | check out / update git dependencies |
| `zs lsp` | the language server (stdio) |
| `zs mcp` | the MCP server for AI agents (stdio) |

**Build options:**

| Option | Does |
|---|---|
| `-g` | debug info, unoptimized ([Debugging](#debugging)) |
| `-Os` | optimize for size instead of speed ([Microcontrollers](11-microcontrollers.md)) |
| `--target <triple>` | cross-compile ([C interop](09-c-interop.md#cross-compiling)) |
| `--lib` | a static library plus a C header |
| `--sanitize` | AddressSanitizer and UndefinedBehaviorSanitizer |
| `--sanitize=thread` | ThreadSanitizer, for data races between threads |
| `--emit-llvm` | keep the LLVM IR (`out.ll`) |
| `--cpu <name>` | compile for a processor ([SIMD](15-simd.md)) |
| `--profile-generate` | a program that writes a profile of its run ([below](#profile-guided-optimization)) |
| `--profile-use <file>` | optimize with a profile |
| `--time` | how long each compiler phase took |
| `--strict` | warnings fail the command, as errors do (for CI; `zs build`, `run`, `check`, `test`) |

**Environment variables:**
- `ZS_BACKTRACE=0` leaves backtraces out of panic output.
- `ZS_ABORT=1` makes a panic a real `abort()`, with a core dump for a debugger.
- `ZS_LEAKCHECK=1` reports heap objects still allocated at exit.
- `ZS_NO_CACHE=1` checks the library and every module again. Otherwise builds, `zs check` and `zs test` keep the checked library, and the checked modules a main file uses, in `~/.cache/zs/checked` (or under `$XDG_CACHE_HOME`). The next build checks only the main file, or the modules too when one of them changed.
- `ZS_NO_LTO=1` links without ThinLTO (below).
- `ZS_NO_POOL=1`, at build time, makes the program allocate every object with `malloc` instead of the runtime's pool, so valgrind sees each one (`./test.sh --valgrind` sets it).

**Rebuilds:** a program of several files is compiled one module per file, in parallel. Builds keep each compiled module in `~/.cache/zs/modules`, under a key of what its code is made from, so a rebuild generates and compiles only the modules whose code changed. `--time` shows how many came from the cache, and how many objects clang compiled.

**Linking:** the modules and the runtime are compiled to LLVM bitcode and optimized together when they're linked (ThinLTO, with lld), so the runtime's allocation functions inline into the program.

## Warnings

A warning is about code that's probably wrong and may be right: the build goes on, and the
warning is printed with its kind in brackets.

```text
main.zs:11:3: warning: this statement's value (int) is discarded: use it, or pipe it to ignore [unused-value]
 11 |   twice 3
    |   ^
```

| Kind | Warns about |
|---|---|
| `unused-value` | a statement whose value isn't `unit` is dropped; `x \|> ignore` says it's on purpose |

- **Silencing:** `[<NoWarn "unused-value">]` on a declaration silences that kind in it; a name that isn't a kind is an error.
- **`--strict`** makes warnings errors: `2 warnings, errors under --strict`, exit code 1. CI passes it, and `./test.sh` does for the repository's own code; a build on your machine doesn't stop for one.
- **Editors** underline a warning in the warning color with its kind as the code.

## Profile-guided optimization

A profile of a typical run tells LLVM which branches are taken and which calls are hot:

```sh
zs build app.zs --profile-generate -o app   # a program that records its run
./app typical input                         # writes default.profraw (or $LLVM_PROFILE_FILE)
llvm-profdata merge -o app.profdata default.profraw
zs build app.zs --profile-use app.profdata -o app
```

On the host benchmarks it gains a few percent (6% on `binarytrees`); a profile from a run unlike the real ones can lose as much.

## Formatting

**What `zs fmt` does:** it applies the one canonical layout, with no options:
- two-space indentation;
- consistent spacing around operators and punctuation;
- trimmed trailing whitespace;
- at most one blank line in a row;
- lines over 100 columns broken, outermost construct first: after a binding's `=` or a lambda's `->`, at an `if`'s branches, before each `|>` of a pipeline, between a match's clauses, and between a list's, a tuple's or a record's items when each line then fits.

```zsharp
type Item = { name: string; price: int }

let report (items: list<Item>) = items |> List.filter (fun i -> i.price > 100) |> List.map (fun i -> i.name) // the expensive ones
```

becomes

```zsharp
type Item = { name: string; price: int }

let report (items: list<Item>) =
  items
  |> List.filter (fun i -> i.price > 100)
  |> List.map (fun i -> i.name) // the expensive ones
```

**What it keeps:** the line breaks you wrote, and comments where they are. A string literal or a comment never breaks, so a line long because of one stays long, and so does a call with many arguments outside brackets, since its arguments can't continue on the next line.

**Safety:** the formatter checks that the result parses to the same program (the same syntax tree, but for layout), so formatting can't change a program's meaning. A file that doesn't parse is left alone, with its error. Zed runs it on save, and formats a selection (range formatting).

## Documentation comments

`///` comments above a declaration document it. They work on functions, types, union cases, traits and their methods, and members.
- **Where they show:** in hover and completion in the editor, in the MCP `docs` tool, and in `zs doc`'s Markdown output.
- **The library:** it's fully documented this way. [Its reference](../reference/README.md) is generated with `zs doc`, one page per module.

```zsharp
/// A point on the screen, in pixels.
type Point = { x: int; y: int }

/// The distance between two points, moving only along the axes.
let manhattan (a: Point) (b: Point) = Math.abs (a.x - b.x) + Math.abs (a.y - b.y)

let main () =
  println $"{manhattan { x = 1; y = 1 } { x = 4; y = 5 }}"
  0
```

```text
7
```

## Debugging

`zs build -g` builds without optimization and with DWARF debug info, so gdb works with the Z# source:
- **Breakpoints and stepping:** break on a function (`break square`) or a line (`break prog.zs:12`), then step with `next` and `step`.
- **Backtraces:** `bt` shows Z# files and lines.
- **Values:** arguments and local variables are shown when they are numbers, bools or chars, strings (as their text), or tuples, records and unions of those. A union shows its case and every case's fields; a string inside a record is a pointer to its object, which `print *r.name` shows.

```
Breakpoint 1, square (n=1) at prog.zs:9
9	  let result = n * n
(gdb) bt
#0  square (n=1) at prog.zs:9
#1  main () at prog.zs:17
(gdb) print name
$1 = 0x405260 "squares"
(gdb) print range
$2 = {lo = 1, hi = 3}
(gdb) print summary
$3 = {case = Large, Small = 0, Large.0 = 14, Large.1 = 7}
```

**Memory checking:** `--sanitize` builds with AddressSanitizer and UndefinedBehaviorSanitizer, and valgrind works on any build. `--sanitize=thread` builds with ThreadSanitizer instead, which finds data races (in C code: code without `unsafe` has none).

## Editors

### Zed

`editors/zed` is a Zed extension. Install it with **Extensions → Install Dev Extension** and choose that folder. It needs Rust, with the `wasm32-wasip2` target installed through rustup.

**What it gives:**
- tree-sitter highlighting and outline;
- the `zs lsp` language server: errors as you type, hover with types (effects included) and docs, go to definition, references, completion, inlay hints (types, and a function's inferred effects before its `=`), document symbols and formatting;
- the `zs mcp` context server, so Zed's agent can check, build and run code and look up documentation.

The extension finds `zs` on your `PATH`. Or set the path in Zed's settings:

```json
"lsp": { "zs": { "binary": { "path": "/path/to/zs", "arguments": ["lsp"] } } },
"context_servers": { "zs": { "command": "/path/to/zs", "args": ["mcp"] } }
```

### Other editors

Run `zs lsp` over stdio as the language server for `.zs` files. The tree-sitter grammar is in `editors/tree-sitter-zsharp`, with highlight, indent and outline queries. `zs mcp` works with any MCP client.
