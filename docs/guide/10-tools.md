# 10. Tools

## The zs command

| Command | Does |
|---|---|
| `zs new <name>` | create a project |
| `zs build [file.zs] [-o out]` | build an executable (the project's, without a file) |
| `zs run [file.zs [--]] [args…]` | build and run |
| `zs check <file.zs>` | type-check only, reporting every error and warning |
| `zs test [file.zs] [paths…] [--update] [--summary]` | run `[<Tests>]` values, each test in its own process; `--update` rewrites failing `expect` literals |
| `zs test --doc [files…] [--update]` | run the examples in `///` comments (the project's files without any); `--update` rewrites their expectations |
| `zs add ../text`, `zs add https://…/json.git@1.2`, `zs add <url> --rev main` | write a dependency into `zs.toml`'s `[dependencies]` (a path, or a git URL at a release or a rev; the name from the package's `zs.toml`, or the URL's last part) and fetch it |
| `zs vendor`, `zs build --offline` | copy the git dependencies into `vendor/`, where the project reads them from with no network, their hashes checked against `zs.lock` (which hashes each dependency's files; an edited checkout is restored at the next fetch); `--offline` (or `ZS_OFFLINE=1`) is an error instead of a fetch |
| `[workspace] members = ["app", "libs/*"]` in a root `zs.toml` | a workspace: one `zs.lock`, one `.zs-cache/` and one `vendor/` at the root for every member (a lock inside a member is an error naming the root); `zs build`, `zs test`, `zs fetch`, `zs tree` and `zs vendor` at the root run over every member (a library member isn't built on its own); members refer to one another as path dependencies; `zs run`, `zs add` and `zs remove` are run in a member |
| `zs remove json`, `zs tree` | take a dependency out (the lock rewritten); show the dependencies as resolved, each with its version, where it comes from and its locked commit, its own under it |
| `zs test file.zs --target cortex-m4` | the file's tests built into one image and run on the chip's QEMU board (or a real board through probe-rs, `--target nucleo-f401`), every test in one process in order: `ok path` as each passes, a failing test's panic ending the run and naming it, its output shown |
| `zs bench file.zs [paths…] [--runs n]` | the file's `bench "name" (fun () -> …)` values, each timed in its own process after three warm-up runs: the median of 30 runs (or `--runs`) with its 95% confidence interval. The results are saved beside the file (`.zs-cache/bench/`), and a benchmark whose interval has moved past the saved one's by 10% or more is reported slower or faster; nothing is said of the rest. `testFaster "name" fast slow` is a test that passes when `fast` is faster with confidence (19 of 25 paired rounds), so a performance claim can't silently regress; `zs test` runs a `bench` once, as a test of its body |
| properties | `testProperty "reverse twice" (fun (xs: list<int>) -> List.rev (List.rev xs) = xs)` is a test over 100 generated cases, drawn with `Arbitrary` at the parameter's type (a tuple for several parameters; `[<Derive(Arbitrary)>]` gives a record or union its generator), growing in size. A case that returns `false` or an `Error` fails the property, and is shrunk to a smallest failing case, shown with the seed: `testPropertyWith { seed = Some (u64 42) } …` replays the run. `gen { let! n = Gen.range 0 99 … return … }` writes a generator, and `Gen.sample (u64 7) 5 g` shows what one makes. `prop { let! y = Gen.int … do! Prop.assume (y <> 0) … do! Prop.classify (y < 10) "small" … return … }` draws as it goes, discards and labels cases, and `Prop.model commands { init; step }` checks a system against a model by a sequence of derived commands, shrunk to the fewest that disagree. Under `zs test`, a case that panics is shrunk too, by replays of the test binary, and saved in `.zs-cache/failures/<file>/` beside the file: the next run replays it first, and deletes it once it passes |
| `zs fuzz file.zs path [--for 60] [-- flags]` | the property named run under libFuzzer (the tests built with its instrumentation and the sanitizers), each input the property's bytes: `prop { let! input = Gen.bytes () … }` takes an input whole, so a parser's property fuzzes the parser as it is. The corpus is kept in `.zs-cache/fuzz/<file>/<path>/` beside the file, so a run resumes; a crash is shrunk by replays, shown, and saved as the failure `zs test` replays first. Flags after `--` go to libFuzzer (`-max_len=64`, `-dict=words.txt`, `-runs=10000`), but for the ones that start other processes (`-jobs`, `-workers`, `-fork`, `-merge`): it runs in one |
| `zs test --coverage file.zs` | the test binary built with a counter per line of the file's directory's sources (not the library's), each test's process writing them at exit; then the lines run and not run per file (`cov.zs: 7 of 9 lines (77%), not run: 5, 7`) and `coverage.lcov` in the current directory, which `genhtml -o coverage coverage.lcov` renders and coverage services read. `zs build --coverage` and `zs run --coverage` write the counts to `<program>.zscov` the same way |
| `zs test --stress 10m [file.zs] [paths…]` | the tests at random on every core, over and over for that long (`30s`, `10m`, `1h`), each run its own process: a failure one run hides (a race, a leak on a rare path, a timeout under load) shows, each failing test shown once. With `ZS_LEAKCHECK=1`, a leak at a test's exit fails it, in one run too |
| `zs fmt [--check] <files…>` | format files in place (`--check`: list unformatted ones; `--stdin`: standard input to standard output) |
| `zs doc <file.zs>` | print a Markdown reference of a file's documented items |
| `zs fetch` / `zs update` | check out / update git dependencies |
| `zs doctor` | what builds need (clang, zig, libclang, and the tools some commands run), found or not, and how to get what's missing |
| `zs provide <provider> <file> [--option=value]…` | a module from a data source, printed to keep beside the program ([proposal 0001](../proposals/0001-type-providers.md)): `json` gives a document's records with the `Json` derive and `parse` and `print` (`--root`, `--types=temp:f64`), `csv` a `Row` record with `parse` and `print` from the header and the rows (`--separator`, `--hasHeaders`, `--types`); `--list` names the providers. The same module comes from an import in the program: `module Weather = import json "weather.json"`, or bare, `import csv ("stocks.csv", separator = ";")`, which opens it; it's written to `.zs-cache/providers/` and loaded as a module of the build |
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
| `cycle` | a type whose objects can form a reference cycle through a cell, at its declaration with the path ([memory](12-memory.md#cycles-and-weak-references)); `[<Cyclic>]` marks a type whose cycles the program breaks |

- **Silencing:** `[<NoWarn "unused-value">]` on a declaration silences that kind in it; a name that isn't a kind is an error.
- **Notes:** a warning about several places names the others under it (`note: 'Parent.kids: ref<list<Child>>' is on the cycle`), and an editor shows them as related places.
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

**Examples are tests:** a fenced `zsharp` block in a `///` comment is a program, the body of its `main`, with the documented module opened; its `// => text` lines are what it prints, in order. `zs test --doc` builds and runs each one and checks them, so an example can't go stale, and `zs test --doc --update` rewrites a failing block's `// =>` lines to what it printed (check them before committing).

````zsharp
/// The elements in lists of `size` (the last one shorter when they don't divide evenly).
///
/// ```zsharp
/// println $"{List.chunkBySize 2 [ 1; 2; 3; 4; 5 ]}"
/// // => [[1; 2]; [3; 4]; [5]]
/// ```
let chunkBySize (size: int) (xs: list<'a>) : list<list<'a>> = …
````

```text
$ zs test --doc lib/core/Collections/List.zs
ok   lib/core/Collections/List.zs:405 chunkBySize
1 passed, 0 failed
```

## Debugging

`zs build -g` builds without optimization and with DWARF debug info, so gdb, and lldb (the debugger on macOS), work with the Z# source (`-g --release`, or `-g` with an `-O` level, keeps the lines in an optimized build, for a crash that only shows there; stepping follows the optimizer's order, and an inlined call's lines are its caller's):
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

lldb shows the same, with its commands (`breakpoint set -n square`, `breakpoint set -f prog.zs -l 22`, `frame variable`, `finish`) and C's names for the types, since it reads DWARF through clang: a 64-bit `int` is a `long`, an `f64` a `double`.

```
(lldb) frame variable name range summary
(char *) name = 0x000000010000dfb0 "squares"
(Range) range = (lo = 1, hi = 3)
(Summary) summary = (case = Large, Small = 0, Large.0 = 14, Large.1 = 7)
```

A list, an array, a tree (a boxed union), a `ref` or a `Buffer` is a pointer to its object, and `print *xs` shows the object: a list cell's count, head and tail (`print *xs->tail` the next), an array's count, length and elements, a node's case where the cells carry one and each case's fields over the cell, a ref's value. An `option` over a string is the string's pointer (`None` the runtime's static), and a closure is an address.

**Memory checking:** `--sanitize` builds with AddressSanitizer and UndefinedBehaviorSanitizer, and valgrind works on any build. `--sanitize=thread` builds with ThreadSanitizer instead, which finds data races (in C code: code without `unsafe` has none).

## Editors

### Zed

`editors/zed` is a Zed extension. Install it with **Extensions → Install Dev Extension** and choose that folder. It needs Rust, with the `wasm32-wasip2` target installed through rustup.

**What it gives:**
- tree-sitter highlighting and outline;
- the `zs lsp` language server: errors as you type, hover with types (effects included) and docs, go to definition, references, completion, inlay hints (types, and a function's inferred effects before its `=`), document symbols and formatting;
- rename (a function, a type, a case, a local or a record field, in every open file's program), signature help inside a call, and code actions: add a missing match case, `open` the module an unknown name is in (or qualify it), write a binder's type;
- allocation hints, once turned on: what each line does to the heap (`allocates ×2`, `reuses t`, `copies on write`, with the objects and their sizes in the tooltip), and on hover what a function's own code allocates and whether `[<NoAlloc>]` would pass, or the chain to what doesn't;
- the `zs mcp` context server, so Zed's agent can check, build and run code and look up documentation.

The extension finds `zs` on your `PATH`. Or set the path in Zed's settings:

```json
"lsp": { "zs": { "binary": { "path": "/path/to/zs", "arguments": ["lsp"] } } },
"context_servers": { "zs": { "command": "/path/to/zs", "args": ["mcp"] } }
```

Allocation hints are off until the settings turn them on, since the server compiles the program's code for them after each change: `"lsp": { "zs": { "initialization_options": { "allocationHints": true } } }`. They come from the code the compiler makes, after inlining, so a small function's allocations show at the line that calls it too. A module of a project (a `zs.toml` above it naming another main file) gets them from the project's program, so opening any of its files shows them; code that no entry reaches (`main`, a test, an export) has none.

### VS Code

`editors/vscode` is a VS Code extension (1.101 or later). Package it with `npx @vscode/vsce package` in that folder and install the `.vsix`, or open the folder and press F5. It gives what the Zed extension does: TextMate highlighting, the language server's features, and the `zs mcp` server for the agent (Copilot's agent mode).

It finds `zs` on your `PATH`, or set `"zsharp.path": "/path/to/zs"`; `zsharp.lsp.arguments` and `zsharp.mcp.arguments` change the arguments, and `"zsharp.allocationHints": true` turns on the allocation hints. It stays off in an untrusted workspace, whose settings could point it at another program.

### Rider

`editors/rider` is a plugin for Rider and the other JetBrains IDEs, 2025.2 or later. Build it with `./gradlew buildPlugin` in that folder (it needs a JDK 25) and install `build/distributions/zsharp-rider-0.1.0.zip` from disk. It gives the same highlighting (the VS Code extension's grammar) and the language server through the IDE's LSP support, with the structure view, quick fixes and parameter info. **Settings → Tools → Z#** sets the path to `zs`.

JetBrains' AI Assistant and Junie take MCP servers from their own settings: add `zs` with the argument `mcp` there.

### Other editors

Run `zs lsp` over stdio as the language server for `.zs` files. The tree-sitter grammar is in `editors/tree-sitter-zsharp`, with highlight, indent and outline queries. `zs mcp` works with any MCP client.
