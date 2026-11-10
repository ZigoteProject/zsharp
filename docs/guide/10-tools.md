# 10. Tools

## The zs command

| Command | Does |
|---|---|
| `zs new <name>` | create a project |
| `zs build [file.zs] [-o out]` | build an executable (the project's, without a file) |
| `zs run [file.zs [--]] [args…]` | build and run |
| `zs check <file.zs>` | type-check only, reporting every error and warning; as a build, it fetches the project's git dependencies first, asks pkg-config for a `[c]` section's flags, and builds and runs a package's type provider ([Trust](#trust)) |
| `zs test [file.zs] [paths…] [--update] [--summary]` | run `[<Tests>]` values (tests, [properties](#properties) and benchmarks), each test in its own process; `--update` rewrites failing `expect` literals |
| `zs test --doc [files…] [--update]` | run the examples in `///` comments (the project's files without any); `--update` rewrites their expectations |
| `zs add ../text`, `zs add https://…/json.git@1.2`, `zs add <url> --rev main` | write a dependency into `zs.toml`'s `[dependencies]` (a path, or a git URL at a release or a rev; the name from the package's `zs.toml`, or the URL's last part) and fetch it |
| `zs vendor`, `zs build --offline` | copy the git dependencies into `vendor/`, where the project reads them from with no network, their hashes checked against `zs.lock` (which hashes each dependency's files; an edited checkout is restored at the next fetch); `--offline` (or `ZS_OFFLINE=1`) is an error instead of a fetch |
| `[workspace] members = ["app", "libs/*"]` in a root `zs.toml` | a workspace: one `zs.lock`, one `.zs-cache/` and one `vendor/` at the root for every member (a lock inside a member is an error naming the root); `zs build`, `zs test`, `zs fetch`, `zs tree` and `zs vendor` at the root run over every member (a library member isn't built on its own); members refer to one another as path dependencies; `zs run`, `zs add` and `zs remove` are run in a member |
| `zs remove json`, `zs tree` | take a dependency out (the lock rewritten); show the dependencies as resolved, each with its version, where it comes from and its locked commit, its own under it |
| `zs test file.zs --target cortex-m4` | the file's tests built into one image and run on the chip's QEMU board (or a real board through probe-rs, `--target nucleo-f401`), every test in one process in order: `ok path` as each passes and `skip path` for a pending one, a failing test's panic ending the run and naming it, its output shown. A property runs its cases there, nothing recorded or shrunk. Path filters aren't taken with `--target` yet: every test runs ([Microcontrollers](11-microcontrollers.md#tests-on-the-chip)) |
| `zs bench file.zs [paths…] [--runs n]` | the file's `bench "name" (fun () -> …)` values, each timed in its own process after three warm-up runs: the median of 30 runs (or `--runs`) with its 95% confidence interval. The results are saved beside the file (`.zs-cache/bench/`), and a benchmark whose interval doesn't overlap the saved one's, its median 10% or more away, is reported slower or faster; nothing is said of the rest. `testFaster "name" fast slow` is a test that passes when `fast` is faster with confidence (19 of 25 paired rounds), so a performance claim can't silently regress; `zs test` runs a `bench` once, as a test of its body |
| `zs fuzz file.zs path [--for 60] [-- flags]` | the property named run under libFuzzer (the tests built with its instrumentation and the sanitizers), each input the property's bytes: `prop { let! input = Gen.bytes () … }` takes an input whole, so a parser's property fuzzes the parser as it is. The corpus is kept in `.zs-cache/fuzz/<file>/<path>/` beside the file, so a run resumes; a crash is shrunk by replays, shown, and saved as the failure `zs test` replays first. Flags after `--` go to libFuzzer (`-max_len=64`, `-dict=words.txt`, `-runs=10000`), but for the ones that start other processes (`-jobs`, `-workers`, `-fork`, `-merge`): it runs in one |
| `zs test --coverage file.zs` | the test binary built with a counter per line of the file's directory's sources (not the library's), each test's process writing them at exit; then the lines run and not run per file (`cov.zs: 7 of 9 lines (77%), not run: 5, 7`) and `coverage.lcov` in the current directory, which `genhtml -o coverage coverage.lcov` renders and coverage services read. `zs build --coverage` and `zs run --coverage` write the counts to `<program>.zscov` the same way |
| `zs test --stress 10m [file.zs] [paths…]` | the tests at random on every core, over and over for that long (`30s`, `10m`, `1h`), each run its own process: a failure one run hides (a race, a leak on a rare path, a timeout under load) shows, each failing test shown once. With `ZS_LEAKCHECK=1`, a leak at a test's exit fails it, in one run too |
| `zs fmt [--check] <files…>` | format files in place (`--check`: list unformatted ones; `--stdin`: standard input to standard output) |
| `zs doc <file.zs>` | print a Markdown reference of a file's documented items; checking the file builds and runs a package's type provider, as `zs check` does ([Trust](#trust)) |
| `zs fetch` / `zs update` | check out / update git dependencies |
| `zs --version` | the compiler's release (`zs 0.7.0`), which the language and MCP servers report to an editor too |
| `zs doctor` | what builds need (clang, zig, libclang, and the tools some commands run), found or not, and how to get what's missing |
| `zs provide <provider> <file> [--option=value]…` | a module from a data source, printed to keep beside the program ([proposal 0001](../proposals/0001-type-providers.md)): `json` gives a document's records with the `Json` derive and `parse` and `print` (`--root`, `--types=temp:f64`), `csv` a `Row` record with `parse` and `print` from the header and the rows (`--separator`, `--hasHeaders`, `--types`), `sql` a record per table from a schema's `CREATE TABLE`s (`--types`, `--queries`), `svd` a module per peripheral from a chip's SVD file (`--only`), `c` a header's declarations as `import c` reads them, and another name runs `zs-provider-<name>` from PATH ([Type providers](18-type-providers.md#a-provider-of-your-own)); `--list` names the providers. The same module comes from an import in the program: `module Weather = import json "weather.json"`, or bare, `import csv ("stocks.csv", separator = ";")`, which opens it; it's written to `.zs-cache/providers/` and loaded as a module of the build |
| `zs lsp [--trust]` | the language server (stdio); `--trust` builds and runs the project's own type providers ([Trust](#trust)) |
| `zs mcp [--trust]` | the MCP server for AI agents (stdio), with the tools `check`, `type_at`, `definition` (where a name is defined, with the defining line), `explain` (a name's type with its constraints, its effects in words, where it's defined and its doc comment), `docs`, `build`, `run`, `emit_llvm` and `format`; `--trust` as for `zs lsp` |

**Build options:**

| Option | Does |
|---|---|
| `--release` | optimized (`-O2`) and inlined across files at the link ([Programs](08-programs.md#builds)) |
| `-O0`, `-O1`, `-O2`, `-O3` | clang's optimization level, for a debug or a release build |
| `-Os` | optimize for size instead of speed ([Microcontrollers](11-microcontrollers.md)) |
| `-g` | debug info: alone, an unoptimized build for stepping (on the Cortex-M0+ and wasm32, the optimized one with lines); with `--release` or a level, that optimized build with its lines ([Debugging](#debugging)) |
| `--target <triple>` | cross-compile ([C interop](09-c-interop.md#cross-compiling)) |
| `--lib` | a static library plus a C header |
| `--sanitize` | AddressSanitizer and UndefinedBehaviorSanitizer |
| `--sanitize=thread` | ThreadSanitizer, for data races between threads |
| `--coverage` | a counter per line of the program's own files, written to `<program>.zscov` at exit (`zs test --coverage` reports them) |
| `--no-heap` | the whole program checked as `[<NoAlloc>]`, and a chip's image built with no heap ([Microcontrollers](11-microcontrollers.md#code-that-doesnt-touch-the-heap)) |
| `--emit-llvm` | keep the LLVM IR (`out.ll`) |
| `--cpu <name>` | compile for a processor ([SIMD](15-simd.md)) |
| `--profile-generate` | a program that writes a profile of its run ([below](#profile-guided-optimization)) |
| `--profile-use <file>` | optimize with a profile |
| `--time` | how long each compiler phase took |
| `--strict` | warnings fail the command, as errors do (for CI; `zs build`, `run`, `check`, `test`) |

**Environment variables:**
- `ZS_BACKTRACE=0` leaves the backtrace out of a panic's output; otherwise, on Linux, it names the Z# functions the panic came through ([Errors](07-errors.md#panics)).
- `ZS_ABORT=1` makes a panic a real `abort()`, with a core dump for a debugger.
- `ZS_LEAKCHECK=1` reports heap objects still allocated at exit; under `zs test`, a test that leaks fails (`leak check: 2 object(s) still allocated`).
- `ZS_NO_CACHE=1` checks the library and every module again. Otherwise builds, `zs check` and `zs test` keep the checked library, and the checked modules a main file uses, in `~/.cache/zs/checked` (or under `$XDG_CACHE_HOME`). The next build checks only the main file, or the modules too when one of them changed.
- `ZS_NO_LTO=1` links without ThinLTO (below).
- `ZS_NO_POOL=1`, at build time, makes the program allocate every object with `malloc` instead of the runtime's pool, so valgrind sees each one (`./test.sh --valgrind` sets it).

**Rebuilds:** a program of several files is compiled one module per file, in parallel. Builds keep each compiled module in `~/.cache/zs/modules`, under a key of what its code is made from, so a rebuild generates and compiles only the modules whose code changed. `--time` shows how many came from the cache, and how many objects clang compiled.

**Linking:** a release build's modules and the runtime are compiled to LLVM bitcode and optimized together when they're linked (ThinLTO, with lld), so the runtime's allocation functions inline into the program.

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
| `stale-input` | a type provider that isn't on PATH, or a project's own that an editor's server started without `--trust` doesn't run ([Trust](#trust)), at its import: the module is the one an earlier build wrote, which an input changed since then would make stale ([Type providers](18-type-providers.md#a-provider-of-your-own)) |

- **Silencing:** `[<NoWarn "unused-value">]` on a declaration silences that kind in it; a name that isn't a kind is an error. `unused-value` and `cycle` are a declaration's; `stale-input` isn't, and goes once the provider is on PATH (or runs).
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

The profile is written by clang's profile runtime, which clang links for this machine on Linux and macOS; zig cc, which links a build for another target and Windows' builds (mingw-w64), has none, so `zs build` refuses the two flags there.

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

**Safety:** the formatter checks that the result parses to the same program (the same syntax tree, but for layout), so formatting can't change a program's meaning. A file that doesn't parse is left alone, with its error. A file is written whole or not at all: the new text goes to a file beside it, with the same permissions, which then takes its place, so a full disk leaves the file as it was. Zed runs it on save, and formats a selection (range formatting): the declarations and statements the selection touches, never a comment or blank line at its edges.

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

## Properties

A property is a test over generated cases. `testProperty "name" (fun (xs: list<int>) -> …)` runs
the function on 100 cases drawn with `Arbitrary` at its parameter's type (a tuple for several:
`fun (a: int, s: string) -> …`), growing from size 0 to 100. The type needs `Show` too, to show a
failing case: a list has it, an array doesn't. `unit`, `true` or an `Ok` passes a
case; `false` or an `Error` fails it, and the failing case is shrunk to a small one that still
fails, shown with the seed that replays the run:

```zsharp
open Testing

/// Drops repeated neighbours: [1; 1; 2] is [1; 2].
let rec dedup (xs: list<int>) =
  match xs with
  | a :: b :: rest when a = b -> dedup (b :: rest)
  | a :: rest -> a :: dedup rest
  | [] -> []

[<Tests>]
let tests =
  testList "dedup" [
    testProperty "is idempotent" (fun (xs: list<int>) -> dedup (dedup xs) = dedup xs)
    testProperty "keeps the length" (fun (xs: list<int>) -> List.length (dedup xs) = List.length xs)
  ]
```

The second property is the one that's wrong: a list with two equal neighbours gets shorter.

```text
$ zs test dedup.zs
ok   dedup/is idempotent
FAIL dedup/keeps the length
       panic: falsified after 6 cases (29 shrinks): [0; 0]
         false
         replay: testPropertyWith { seed = Some (u64 3566621387106) }
1 passed, 1 failed
```

- **Settings:** `testPropertyWith { runs = 1000 } "name" …` names what changes: `runs` (100), `maxSize` (100), `maxDiscardRatio` (10 discarded cases for each that passes), `seed` (`Some (u64 …)` replays a run) and `shrink` (`true`).
- **Shrinking:** a generator reads a stream of bytes, all zeros its simplest value, and a failing case is shrunk by making its bytes shorter, then smaller (as Hypothesis does). So every generator shrinks, the ones you write too.
- **Generators:** a `Gen<'a>`. `Gen.int ()`, the sized integers (`Gen.u8 ()`, …), `float`, `bool`, `char` and `string` (each a function of unit), `range lo hi`, `elements`, `oneOf`, `frequency`, `list`, `array`, `listOfLength`, `option`, `map`, `bind`, `filter`, `sized`, `scale` and `constant`, and the `gen { }` builder. `Gen.bytes ()` draws up to the size's number of bytes, and under `zs fuzz` takes the fuzzer's input whole, for a parser's property.
- **`Arbitrary`** has a generator for Core's types, lists, arrays, options, results and tuples, and `[<Derive(Arbitrary)>]` gives a record or a union one. A recursive union's values end when it has a case that ends one (a leaf, or a case that holds the type only through a list, an array or an option, which can be empty): the derive puts those cases first, leaves before the others, and at size 0 takes only the leaves with the fewest fields (with no leaf, the others with the fewest).

`Gen.sample seed n g` shows what a generator makes, at sizes growing to 100:

```zsharp
open Testing

[<Derive(Arbitrary)>]
type Command =
  | Push of int
  | Pop
  | Clear

let point = gen {
  let! x = Gen.range 0 9
  let! y = Gen.range 0 9
  return (x, y)
}

let main () =
  let commands : Gen<Command> = arbitrary ()
  println $"{Gen.sample (u64 7) 5 point}"
  println $"{Gen.sample (u64 3) 6 commands}"
  0
```

```text
[(5, 8); (3, 6); (8, 9); (2, 3); (5, 7)]
[Clear; Clear; Pop; Pop; Push 27; Pop]
```

- **Drawing as it goes:** `prop { let! y = Gen.int () … do! Prop.assume (y <> 0) … return … }` is a property that draws inside its body, so a draw can depend on the ones before it. `Prop.assume` discards a case. `Prop.label`, `classify` and `collect` label one: a failure shows the failing case's labels, and a property that passes prints how its cases were labelled (`division: 100 cases, 7 discarded; 28% small divisor`), which `zs test` doesn't show for a test that passes.
- **Models:** `Prop.model commands { init; step }` applies a list of commands (a derived union, drawn as any list is) to the system under test and to a model of it, and fails at the first answer they disagree on. It shrinks to the fewest commands with the smallest arguments: a stack that loses an element fails as `[Push 0; Push 0; Pop; Pop]` (`tests/property/model.zs`).
- **A case that panics** (an assert, an index out of range) ends the test's process, so `zs test` shrinks it by replaying the test binary on smaller cases, shows it, and saves it beside the file in `.zs-cache/failures/<file>/`. The next run replays it first, and deletes it once it passes. A panic the case doesn't reproduce on its own, and a run that gave up on its discards, are reported as they happened, nothing shrunk or saved; a smaller case that fails another way (another assert, a stack overflow) isn't taken.
- **Fuzzing:** `zs fuzz file.zs path` runs one property under libFuzzer, its coverage guiding the inputs ([the table above](#the-zs-command)); a crash it finds is shrunk the same way and saved as the failure `zs test` replays first.
- **On a chip,** `zs test --target` runs a property's cases with nothing recorded or shrunk.

## Debugging

`zs build -g` builds without optimization and with DWARF debug info, so gdb, and lldb (the debugger on macOS), work with the Z# source (`-g --release`, or `-g` with an `-O` level, keeps the lines in an optimized build, for a crash that only shows there; stepping follows the optimizer's order, and an inlined call's lines are its caller's):
- **Breakpoints and stepping:** break on a function (`break square`) or a line (`break prog.zs:12`), then step with `next` and `step`.
- **Backtraces:** `bt` shows Z# files and lines. A panic prints a backtrace of its own, on Linux the functions' names without their lines ([Errors](07-errors.md#panics)); for the lines, run the `-g` build in gdb with `ZS_ABORT=1`, which stops it at the panic.
- **Values:** every argument and local variable is shown, of any type but a SIMD vector or a mask, which have no type in the debug info yet: numbers, bools and chars, strings (as their text), and tuples, records and unions by their fields. A union shows its case and every case's fields; a string inside a record is a pointer to its object, which `print *r.name` shows, and so is a list, an array or a tree (below).

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

### Trust

Checking a program can run code of the project's own: a dependency with a `[provider]` section is a type provider the compiler builds and runs for its import ([Type providers](18-type-providers.md#a-provider-of-your-own)). `zs build`, `zs check`, `zs doc`, `zs test` and the other commands do that, since you run them on the project on purpose, as `cargo check` runs a package's build script: `zs check` and `zs doc` on a project you don't trust run its code. The provider is built with the project's checkouts of its dependencies, so it fetches nothing of its own. An editor opens whatever you open, so `zs lsp` and `zs mcp` don't, unless started with `--trust`: without it, such an import uses the module the last build wrote (with a `stale-input` warning), or is an error at the import, `provider shout not run: the project is not trusted (start the language server with --trust)`. zs's own providers (`json`, `csv`, `sql`, `svd`, `c`) and the `zs-provider-<name>` programs on your `PATH`, which you installed, run either way.

The VS Code extension passes `--trust`, as it runs only in a trusted workspace; the Rider plugin passes it in a trusted project; the Zed extension doesn't, and you add it to the arguments in Zed's settings ([Zed](#zed)). An MCP client starts `zs mcp` with the `args` you give it.

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

To have the servers run the project's own type providers ([Trust](#trust)), add `--trust` to both argument lists: `["lsp", "--trust"]` and `["mcp", "--trust"]`. The settings are yours, so that trusts every project you open in Zed.

Allocation hints are off until the settings turn them on, since the server compiles the program's code for them after each change: `"lsp": { "zs": { "initialization_options": { "allocationHints": true } } }`. They come from the code the compiler makes, after inlining, so a small function's allocations show at the line that calls it too. A module of a project (a `zs.toml` above it naming another main file) gets them from the project's program, so opening any of its files shows them; code that no entry reaches (`main`, a test, an export) has none.

### VS Code

`editors/vscode` is a VS Code extension (1.101 or later). Package it with `npx @vscode/vsce package` in that folder and install the `.vsix`, or open the folder and press F5. It gives what the Zed extension does: TextMate highlighting, the language server's features, and the `zs mcp` server for the agent (Copilot's agent mode).

It finds `zs` on your `PATH`, or set `"zsharp.path": "/path/to/zs"`; `zsharp.lsp.arguments` and `zsharp.mcp.arguments` change the arguments, and `"zsharp.allocationHints": true` turns on the allocation hints. It stays off in an untrusted workspace, whose settings could point it at another program, and in a trusted one starts both servers with `--trust`.

### Rider

`editors/rider` is a plugin for Rider and the other JetBrains IDEs, 2025.2 or later. Build it with `./gradlew buildPlugin` in that folder (it needs a JDK 25) and install `build/distributions/zsharp-rider-0.1.0.zip` from disk. It gives the same highlighting (the VS Code extension's grammar) and the language server through the IDE's LSP support, with the structure view, quick fixes and parameter info. **Settings → Tools → Z#** sets the path to `zs`. It starts the server with `--trust` in a trusted project, and without it in one opened in safe mode.

JetBrains' AI Assistant and Junie take MCP servers from their own settings: add `zs` with the argument `mcp` there (and `--trust` for projects you trust).

### Other editors

Run `zs lsp` over stdio as the language server for `.zs` files, with `--trust` when the editor trusts the project. The tree-sitter grammar is in `editors/tree-sitter-zsharp`, with highlight, indent and outline queries. `zs mcp` works with any MCP client.
