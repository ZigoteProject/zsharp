# Proposal 0038: the build graph, and `build.zs`

| | |
|---|---|
| **Status** | Draft |
| **Decided at** | not yet: a design review. It takes up the build script [0018](0018-packages.md#alternatives) declined, so it needs a decision row, numbered by the coordinator |
| **Builds** | [track K](../../ROADMAP.md#packages-k), in the steps under *Order of implementation*; step 6 (the repository's own scripts) waits for a stage 0 that has step 3 |
| **Rests on** | decisions 20 (derive; no macros, no comptime), 26 (from Zig: `zig cc`; comptime not adopted), 27 (source packages) and 56 (type providers: a program `zs` builds and runs) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §5.3](../../DESIGN.md#53-what-code-without-unsafe-guarantees) (what code without `unsafe` guarantees); [DESIGN §12](../../DESIGN.md#12-tooling) Projects; [the trust boundaries](../contributing/security.md#trust-boundaries) |
| **Related** | [0018 packages](0018-packages.md) (`[c]`, and *Alternatives*), [0001 type providers](0001-type-providers.md) (code that runs at build time, and trust), [0007 incremental builds](0007-incremental-builds.md) (the cache), [0022 macOS and Windows](0022-targets-macos-windows.md) (C per target), [0023 JSON in Core](0023-json-in-core.md) (the graph's form), [0031 stability](0031-stability-and-support.md) (a new public API before 1.0), [0034 C calls inside `unsafe`](0034-c-calls-in-unsafe.md) |
| **Changes** | DESIGN §12 and §13; the guide's chapters on programs (Projects) and tools (Trust); `docs/contributing/packages.md` and `security.md`; `src/Build/Project.zs`, `Modules.zs`, `Make.zs` and `Commands.zs`; a library namespace `Build`, seen by build scripts only. No syntax |

- [ ] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

`zs.toml` keeps saying what a package *is*: its name, version and dependencies, which version
selection reads at a release's tag without running anything. A package may add a build script,
`build.zs`: a Z# function from the target and the package's options to a value that says what
the package *makes*. That value is a graph: C libraries (with patterns and defines), programs,
commands that other tools run (`cargo`, `zig build`), and named steps. `zs` is the one that
acts on it, as Zig's build system does since 0.17: the script only describes, it's cached by
what it was given, and `zs` makes what the command line asks for.

The script is held to a subset that can only compute: the prelude and Core's pure modules, no
Std, no `unsafe`, no `extern` or `import c`. So it reads no file, clock or environment. Its
result depends on its arguments alone, which is its cache key, with no list of files it looked
at. Promise 1 of [security](../contributing/security.md#two-promises) applies to it as to any
safe program, so a tool can run it where it can't run a project's code.

```toml
# packages/tls/zs.toml
[package]
name = "tls"
main = "src/Tls.zs"

[build]
script = "build.zs"
```

```fsharp
// packages/tls/build.zs: in place of 110 listed sources and two identical Windows sections
open Build

let build (cx: Context) : Package =
  { c =
      [ { sources = [ File "c/shim.c"; Glob "c/mbedtls/library/*.c" ]
          include = [ "c/config"; "c/mbedtls/include"; "c/mbedtls/library" ]
          link =
            match cx.target.os with
            | Windows -> [ Lib "bcrypt"; Lib "crypt32" ]
            | _ -> [] } ] }
```

```sh
zs build                    # what it built before: build/<name>, every program the script adds
zs build flash              # a step the script names
zs build -Dfts5=true        # an option the script declares
zs build --steps            # the steps, with their docs
zs build --graph            # the configured graph, as JSON, for tools
```

## Motivation

**A library of 110 C files.** `packages/tls/zs.toml` lists its sources one by one: `c/shim.c`
and the 109 files of `c/mbedtls/library/`, which is every `.c` there. An upgrade of Mbed TLS
that adds a file has to add it to the list as well, or the link fails with undefined symbols.
`[c]` has no pattern.

**An option is a `#define`.** `[c]` has no key for one
([packages](../contributing/packages.md#in-this-repository)). So `packages/sqlite` sets its
options in `c/shim.c` before it includes the amalgamation, and `packages/tls` puts a header
ahead of the library's own on the include path (`c/config`). A program that wants SQLite's
full-text search has to edit the package.

**One section, twice.** `[c.x86_64-windows-gnu]` and `[c.aarch64-windows-gnu]` in
`packages/tls/zs.toml` hold the same line. `[c.<target>]` keys by target, and Windows is two
targets.

**A library another tool builds.** `examples/rust/zs.toml` links
`textkit/target/release/libtextkit.a`, and `examples/zig/zs.toml` links two `zig-out` archives,
which nothing in the build makes. Their READMEs run the other tool by hand first, once per
target: two `cargo build`s for Rust, and for Zig four `zig build`s, a fetch and a patch. A
forgotten one is a link error about a missing file. After an edit to the Rust, `zs run` links
the old archive without a word. In the other direction Zig has no such gap:
`examples/zig/calls-zs/build.zig` runs `zs build shapes.zs --lib` as a step whose output is an
input of its link.

**What a package makes.** A package makes one program, its `main`. In a workspace, `zs build`
builds a member when its main file's text contains `let main` and skips it as a library
otherwise (`Commands.build`). A package can't say that it makes two programs (a firmware and
the host tool that talks to it), or a program and a library for C.

**The repository's own build is bash.** `test.sh` (1,021 lines), 55 scripts under `tests/`,
`src/install.sh`, `src/release.sh` and `dev`. None of them runs on Windows as a program:
`test.sh` skips its `zs doctor` check because "Windows starts no shell script as a program",
and `tests/release.sh` because "src/release.sh is Linux's and macOS's".

**Code already runs at build time.** A dependency with a `[provider]` section (0001,
decision 56) is a Z# program that `zs` builds into `.zs-cache/providers/bin` and runs during
the build. It's rebuilt when any file it's built from changes, stopped after 60 seconds, and
not run by an editor without `--trust`. 0018 declined a build script as "against the spirit of
decision 20, and more than a wrapper needs". Since then, providers have built the mechanism a
build script needs (a Z# program `zs` builds, caches and runs) and its trust rule. The
scenarios above are more than a wrapper. Decision 20 is about code generated *into a program*
(derive, no macros, no comptime). A build script generates no code: it's a program whose
result is data, as a provider's is.

**What exists, and what carries over.**

- **Zig.** In Zig 0.17, `build.zig` is a program that builds a graph of steps.
  - **Configure and make are separate** ([devlog, May 2026](https://ziglang.org/devlog/2026/)).
    The script runs in a small "configurer" process whose graph is serialized and cached. An
    optimized "maker" executes the graph.
  - **The maker is the long-lived parent.** It also does the package management (June 2026),
    so it survives a re-run of the configurer and serves a build protocol to editors.
  - **The configurer sees less.** Arguments after `--` were taken away from it
    (`addPassthruArgs`), so changing them doesn't run the script again.
  - **What doesn't carry over: the configurer has Zig's whole standard library.** So its cache
    has to know every file it looked at; adding the script's own file dependencies was still
    an open follow-up in June 2026. And every dependency's `build.zig` runs natively, even for
    `zig build -h`. Running it in a WebAssembly sandbox has been an open issue since 2023
    ([#14286](https://github.com/ziglang/zig/issues/14286)).
- **Cargo.** A `build.rs` has the whole machine. It prints directives, and it's run again on
  `rerun-if-changed` paths it names itself.
- **Go.** Go has no build scripts; `go generate` is run by hand.

Z# can take Zig's shape and close the gap Zig has with two things it already has. The checker
knows which modules a file names; 0018 item 5 uses that to reject a package that needs Std
from a chip's build by name. And there's a promise about code without `unsafe`.

## Detailed design

### The manifest and the script

- **`[build] script = "build.zs"`** in `zs.toml` names the script, a path inside the package, as `main` is. Without the section a package has no script and builds as it does today. The key is required, not inferred from the file being there: compiler 0.7.1 stops at a key in a section it doesn't know (`unknown section [build]`), but an empty section, or a `build.zs` on its own, would be ignored silently and the package built without what its script adds.
- **The script is one file,** a module of its own: no module opens it, and it opens only what the subset below allows, `Build` included. `zs fmt` formats it, the checker checks it, and the language server shows its errors as it does any file's.
- **Its entry is `build`:** `let build (cx: Context) : Package`, or `let build (cx: Context) (o: Options) : Package` when the package has options (*Options*, below). Anything else named `build`, or no `build`, is an error at the script.
- **`zs.toml` stays the data.** `[package]`, `[dependencies]`, `[target.<name>]` (a chip's heap) and `[workspace]` are read without running anything. Version selection (decision 83) reads a release's `zs.toml` at its tag and never runs its script. `[c]`, `[c.<target>]` and `[provider]` keep their meaning: `[c]` is the first entry of the graph's `c`, before the script's, with its `[c.<target>]` added as today.

### What a script can use

A script is checked with a rule a program doesn't have. The rule is read from what each module
names, as the summaries the cache keeps already record it for 0018 item 5:

- **Modules:** the prelude, `Option`, `Result`, `Iter`, `Collections`, `Text`, `Int`, `Float`, `Math`, `Bits`, `Bytes`, `Binary`, `Numerics.Fixed`, `Time.DateTime` (values; reading the clock is Std's `DateTime.utcNow`), and `Build`. This is an allow-list, so a module added to Core later isn't open to scripts until it's added here. Left out: Std entirely; `Runtime` (a cycle counter); `Threading`; `Cpu`, `Irq`, `Mmio`, `Ptr`, `Simd` and `Arena`, which reach the machine; `Weak`; `Testing` (a seed drawn per run).
- **Constructs:** no `unsafe`, `extern`, `import` (of `c` or any provider), `[<Link>]`, `[<Export>]`, `[<Section>]` or `[<Interrupt>]`. An `extern` call and an `Mmio` access are safe code today ([0034](0034-c-calls-in-unsafe.md)), so the rule names them; it doesn't wait for 0034.
- **What's left can't observe anything** but its arguments. It can't read a file, the environment, the clock or another thread, and it can't call C. Its result is a function of the script's text, the library and its arguments, which is exactly its cache key. A script that loops or allocates without end is stopped (*Configure and make*, below).
- **`println` is allowed.** The graph doesn't go through the standard output (*Configure and make*), so what a script prints is shown, under its package's name, as a provider's errors are.

### The `Build` namespace

Data, with `[<Derive(Json)>]` on each type (`zs` reads a script's result as JSON, *Configure
and make*). The records use default fields (DESIGN §2.3), so a script writes only what it
sets:

```fsharp
namespace Build

/// The target a build is for: --target's, or this machine's.
type Target =
  { /// What --target took ("cortex-m4", "x86_64-windows-gnu"), or "host" for this machine
    name: string
    os: Os
    arch: Arch
    /// LLVM's triple, which is Rust's too for the chips ("thumbv7em-none-eabihf")
    triple: string
    /// zig cc's -target and -mcpu for it ("thumb-freestanding-eabihf", "cortex_m4+vfp4d16sp")
    zig: string
    zigCpu: string }

/// An operating system, or none: a chip, or freestanding WebAssembly.
and Os =
  | Linux
  | MacOs
  | Windows
  | Freestanding

/// A processor's architecture.
and Arch =
  | X86_64
  | Aarch64
  | Arm
  | Wasm32

/// What the command line asked for: the target, and whether the build is --release.
type Context = { target: Target; release: bool }

/// Files of the package: one path, or each path a pattern matches (`*` within a directory, `**`
/// across directories), found by zs when it builds, in byte order.
type Files =
  | File of string
  | Glob of string

/// A library to link: a name (-l) or a file of the package, or a file a command of this package
/// writes (the command's name, and the path under its output directory).
type Link =
  | Lib of string
  | Built of string * string

/// C compiled for the target and linked with the package: what a [c] section says, and defines.
type C =
  { sources: list<Files> = []
    include: list<string> = []
    defines: list<string * string> = []
    link: list<Link> = []
    pkgConfig: list<string> = [] }

/// A program built from a main file into build/<name> (with lib, an archive and its header, as
/// zs build --lib makes); for another target than the build's when target names one.
type Program = { name: string; main: string; lib: bool = false; target: option<string> = None }

/// What a command runs: a program on PATH, or one of this package's programs, built for this
/// machine.
type Exe =
  | Tool of string
  | Made of string

/// One of a command's arguments: text; a file of the package (an input); the file one of this
/// package's programs is built to; the directory the command writes into; or the arguments that
/// follow -- on zs build's command line.
type Arg =
  | Text of string
  | In of string
  | Program of string
  | OutDir
  | Rest

/// A program the build runs, in a directory of the package. A command that names its inputs is
/// run again only when they, its arguments or its program change; one that names none is run
/// each time it's asked for.
type Command =
  { name: string
    exe: Exe
    args: list<Arg> = []
    dir: string = "."
    inputs: list<Files> = [] }

/// What a step does: a program made, a command run, another step.
type Action =
  | Make of string
  | Run of string
  | Step of string

/// A step zs build <name> runs, its actions in order.
type Step = { name: string; doc: string; does: list<Action> }

/// What a package makes, besides its main program: its C, more programs, commands, and steps.
type Package =
  { c: list<C> = []
    programs: list<Program> = []
    commands: list<Command> = []
    steps: list<Step> = [] }
```

- **Values, not a builder.** Zig's `b.addExecutable` returns a pointer that later calls hang steps on. A Z# script returns one value, and one node names another by its name (`Built("textkit", …)`, `Run "flash"`). `zs` checks the names: each is unique within the package, and each reference resolves.
- **Paths are the package's.** Every path in the graph is relative to the package's directory and stays inside it, the rule `main` and `[provider] main` have. `..` that leaves the package, an absolute path, and a symbolic link out of it are errors.
- **A pattern is the build's,** not the script's: the script can't list a directory, so `Glob "c/mbedtls/library/*.c"` is a value that `zs` expands when it builds. The files it matches are part of what the C is cached by. A pattern that matches nothing is an error.

A library another tool builds, with `examples/rust`'s two README lines as one command:

```fsharp
open Build

/// The crate as a static library for the target, by cargo; a chip's without the standard library
let textkit (t: Target) : Command =
  let forChip =
    match t.os with
    | Freestanding -> [ Text "--no-default-features"; Text "--target"; Text t.triple ]
    | _ -> []
  { name = "textkit"
    exe = Tool "cargo"
    args = List.append [ Text "build"; Text "--release"; Text "--manifest-path"; In "textkit/Cargo.toml"; Text "--target-dir"; OutDir ] forChip
    inputs = [ Glob "textkit/src/**/*.rs"; File "textkit/Cargo.toml"; File "textkit/Cargo.lock" ] }

let build (cx: Context) : Package =
  let archive =
    match cx.target.os with
    | Freestanding -> cx.target.triple + "/release/libtextkit.a"
    | _ -> "release/libtextkit.a"
  { commands = [ textkit cx.target ]
    c = [ { link = [ Built("textkit", archive) ] } ] }
```

`zs run` and `zs run --target cortex-m4` then run `cargo` when the crate changed, and link what
it wrote. `[target.cortex-m4] heap = "512K"` stays in `zs.toml`.

### Options

- **Declared as a record,** the second parameter of `build`, with defaults and doc comments:

```fsharp
/// What -D sets for this package
[<Derive(Json)>]
type Options =
  { /// SQLite's full-text search (SQLITE_ENABLE_FTS5)
    fts5: bool = false }

let build (_: Context) (o: Options) : Package =
  { c =
      [ { sources = [ File "c/shim.c" ]
          include = [ "c" ]
          defines = if o.fts5 then [ ("SQLITE_ENABLE_FTS5", "1") ] else [] } ] }
```

- **A field is `bool`, an integer type, `string`, or a union whose cases have no fields** (`-Dlevel=fast`). `zs` reads the record's type from the checker, so `zs build --options` lists the fields, their types, defaults and docs without running the script, and an unknown or ill-typed `-D` is an error before anything runs.
- **Set** for the project's own package by `-D<field>=<value>` (`-D<field>` alone is `true`), and for a dependency in the project's `zs.toml`: `[options.sqlite] fts5 = "true"`. Only the project sets a dependency's options, so a package has one configuration in a build, as "a key names one package throughout a build" (0018) needs. A field not set has its default.
- **What follows `--`** on `zs build`'s command line goes to a command's `Rest`, never to the script, as Zig 0.17 decided for the same reason: changing those arguments doesn't run the script again.

### Steps and commands

- **`zs build`** with no step makes what it makes today, `build/<name>` from the package's `main`, plus every program in `programs`, each into `build/<its name>`. A `[workspace]` member is built when it makes a program: its `main` has a `let main`, or its script lists one. That replaces the text search for `let main`.
- **`zs build <step>`** runs a step's actions in order. Each action's prerequisites come first: the C a program links, and the commands whose files it links. A word that doesn't end in `.zs` is a step's name. Independent work runs at once, up to the cores, as `zs test` runs tests. What a step prints is in the order of its actions, whatever order they finished in.
- **`zs run`, `zs test`, `zs bench` and `zs fuzz`** are unchanged. They build the package's `main` and whatever it needs from the graph: its C, and the commands that C links.
- **A command's output directory** is `.zs-cache/build/out/<package>/<command>-<key>/`, its key being its program, its arguments and the hashes of its inputs. A command's files are never written into the package's own directory by `zs`. The tool `zs` runs may do so anyway: `cargo` writes `Cargo.lock`, which is one reason a command's cache counts only the inputs it names.
- **A program made for another target** (`target = Some "cortex-m4"`) configures the package, and its dependencies, for that target too, so a firmware and its host tool come from one `zs build`:

```fsharp
let build (_: Context) : Package =
  { programs = [ { name = "firmware"; main = "firmware/main.zs"; target = Some "nucleo-f401" } ]
    commands = [ { name = "flash"; exe = Tool "probe-rs"; args = [ Text "download"; Text "--chip"; Text "STM32F401RETx"; Program "firmware" ] } ]
    steps = [ { name = "flash"; doc = "the firmware onto the board"; does = [ Make "firmware"; Run "flash" ] } ] }
```

### Configure and make

How `zs build` gets from manifests to files:

1. **Read and fetch,** as today: `zs.toml` and `zs.lock`, the checkouts. No script runs.
2. **Configure** each package that has a script, for each target the build reaches (independent packages at once):
   - **The configurer** is the script and an entry `zs` writes. The entry reads the context and the options as JSON from its arguments, calls `build`, and writes the result as JSON to a file `zs` names. The entry is `zs`'s, so it may use Std; the script may not.
   - **It's built as a provider is:** `zs build --no-server --deps-of`, into `.zs-cache/build/bin/`, keyed by the compiler, the script's text and the library's and runtime's files.
   - **It's run in a process of its own,** stopped after 60 seconds (a provider's limit), with a memory limit (question 6).
   - **Its result is cached** in `.zs-cache/build/` by the configurer's key, the target's name, `release` and the options' JSON. A hit reads the file and runs nothing.
3. **Check the graph:**
   - every name unique and every reference resolved;
   - no cycle among steps and commands;
   - every path inside its package;
   - every pattern expanded, in byte order, and matching something.

   The graph's JSON is read with `Build.Package`'s derived `fromJson`, so a result that isn't
   one is an error naming the package, not a crash.
4. **Make** what the command line asked for (*Steps and commands*). The C, Z# and link steps are the ones `Make` and `Compile` run today, so a package without a script builds to the same bytes.

The build server keeps the graphs it has configured, as it keeps checked modules, and is the
long-lived maker Zig's 0.17 made its own (a parent that survives a re-configure).

### Trust

[The trust boundaries](../contributing/security.md#trust-boundaries) get one row, and the rows
of a project's own code and of the editor change as follows:

| | `zs build`, `run`, `test` | the same with `--no-trust` | `zs lsp`, `zs mcp` | the same with `--trust` |
|---|---|---|---|---|
| configure (a script, the subset) | runs | runs | runs (question 1) | runs |
| C compiled, Z# compiled, linked | yes | yes | checks only, as today | checks only |
| a command (`Tool`, `Made`) | runs | not run: an error naming the step | not run | when a tool asks (MCP's `build`) |

- **Configure runs where a project's code doesn't,** because the subset can do nothing but compute. Running it doesn't give the script anything it could use. The bet is that the compiler keeps promise 1, which it already makes for every safe program, and a break in it is a security bug already. Question 1 is whether that's enough for the editor.
- **A command is the project's code,** as a provider is: anything on PATH, with the project's arguments. It's trusted exactly where a provider is.
- **A dependency's script** configures that dependency only. Its commands run only when that dependency's C needs them, and only where commands run at all.

### Dependencies

- **A package's script describes that package.** Its paths are its own, and it can't name another package's files, programs or commands.
- **A dependent gets a dependency's modules and C,** with the commands that C links. It doesn't get the dependency's `programs` or `steps`.
- **Dependencies' scripts are configured independently,** in any order and at once. Each has its own key, so a package used by many projects is configured once per key.

### Order of implementation

1. **The manifest's growth, on its own.**
   - **What changes:** patterns in `[c] sources`, a `defines` key, and `[c.linux]`, `[c.macos]` and `[c.windows]` keyed by operating system, added to `[c]` before a `[c.<target>]`.
   - **Tests:** `packages/tls` becomes one pattern and one `[c.windows]`, with additions to `tests/project/pkgs.sh` and a project under `tests/project/`.
   - **Decided separately:** this helps whether or not the rest is taken.
2. **The graph inside `zs`.**
   - **What changes:** `src/Build/Graph.zs` holds the types above; `zs.toml` is lowered to them, and `Make` makes from them. `zs build --graph` prints the result.
   - **Exit test:** every project in `tests/project/`, `packages/` and `examples/` builds to the same bytes before and after.
3. **`build.zs`.**
   - **What changes:** `[build] script`, the `Build` namespace (`lib/build/`), the subset's check, and the configurer and its cache. Then options (`-D`, `[options.<key>]`, `--options`), programs, commands with their trust, steps, `zs build <step>` and `--steps`.
   - **Tests:** scripts under `tests/build/`, each with its `.expected`:
     - a second build configures nothing;
     - a change to the script or to an option configures again, and a change to `--` arguments doesn't;
     - every row of *Diagnostics*;
     - the trust table;
     - one script configured twice gives the same bytes.
4. **The examples and packages.**
   - `examples/rust` and `examples/zig` build their libraries by commands. The `cargo build` and `zig build` lines leave their READMEs; `zg`'s fetch and patch stay, since they edit Zig's package cache.
   - `packages/sqlite` gets the `fts5` option.
   - The guide's chapters change with them.
5. **The editors.**
   - The server reads the configured graph, so a package's `import c` gets the graph's include paths and defines.
   - A script's errors show as any file's.
   - MCP's `build` tool takes a step.
6. **The repository** (after a stage 0 that has step 3).
   - `src/build.zs` gets an `install` step in place of `src/install.sh`, and a `release` step in place of `src/release.sh`.
   - `test.sh` stays bash until the steps have proved themselves.

Each step keeps `./test.sh` green.

## Drawbacks

- **Two places to look:** `zs.toml` for what a package is, `build.zs` for what it makes.
- **A package's C is no longer readable without running its script.** Tools need the configured graph: the editor, `zs build --graph`'s readers, and anything that wants include paths.
- **A public API before 1.0.** `Build` will change, and scripts with it ([0031](0031-stability-and-support.md)). Zig's build API has broken in most releases.
- **A first build is slower:** the script is compiled once per change to it, the library or the compiler.
- **A second set of rules to learn and keep,** the subset. Its allow-list must be reviewed whenever Core gains a module.
- **The editor's safety rests on the compiler's,** if question 1 is answered yes. A soundness bug in the checker, the optimizer or the runtime becomes a way out of the script.
- **Commands make builds depend on tools:** `cargo` and `zig` on PATH, at versions the package doesn't pin.

## Alternatives

- **Grow `zs.toml` only.** Patterns, defines and operating-system sections (step 1), as a Cargo manifest would. **Not chosen as the whole answer:** it covers wrapping, but not steps, another tool's outputs, two programs, or the repository's scripts. It's kept as step 1, which stands alone.
- **Cargo's `build.rs`.** It has the whole machine, prints directives, and is re-run on paths it names itself. **Not chosen:** it's a native program from every dependency with access to everything, and its cache is as good as its `rerun-if-changed` lines.
- **Zig's `build.zig` as it is.** The configurer has the whole standard library. **Not chosen:** its cache has to track what it observed (an open item in June 2026), and its code runs natively from every dependency, `zig build -h` included. The subset gives the cache key with nothing to track.
- **A WebAssembly sandbox.** Compile the script to `wasm32`, which Z# targets, and run it in an interpreter inside `zs` (Zig's [#14286](https://github.com/ziglang/zig/issues/14286), open since 2023). **Not chosen now:** `zs` would carry a WebAssembly interpreter (a new dependency, rule 9), and the subset already takes away what a sandbox would. It stays the way to harden configure if question 1 asks for more.
- **Effects as capabilities.** `build : Context -> Package / <>`, or options as an effect that the entry handles. **Not chosen:** effect rows track algebraic effects, not the outside world. An `extern` call or `println` has no effect in its row, so a pure row promises nothing about IO. And options as a type are read without running anything.
- **Running the script inside the compiler,** as comptime would. **Not chosen:** Z# has no interpreter and decided against comptime (decisions 20, 26). A configurer is a program, as a provider is.
- **Another language:** Starlark (Bazel), Nix, CMake. **Not chosen:** that's one more language and tool for a Z# programmer to learn, without the checker or the editor.
- **A mutable builder,** as Zig's `*std.Build` is. **Not chosen:** a value returned is the graph, referred to by names, and needs no handles.
- **Keep shell for the repository.** **Not chosen for good:** it doesn't run on Windows as a program, it's untyped, and it has no cache. It's the state until step 6.

## Compatibility

- **Additive.** A package without `[build]` builds as before, to the same bytes (step 2's exit test). `[c]`, `[c.<target>]`, `[provider]` and `[target.<name>]` keep their meaning.
- **An older compiler** stops at `[build] script` with `unknown section [build]`. A key in a section it doesn't know is an error in 0.7.1's reader (`Project.parseManifest`), so a package with a script fails clearly on it. It doesn't build without the script's C and fail at the link.
- **`zs build <word>`.** Today `zs build` ignores a positional word that doesn't end in `.zs` (`Commands.build` keeps only those that do), so `zs build release` builds the project. With this, it's a step, and one the package doesn't have is an error.
- **Version selection** is unchanged. It reads `zs.toml` alone, and a release's script never runs to choose a version.
- **The compiler's own build:** `src/zs.toml` is what stage 0 reads, so `src/` uses no script until a stage 0 has step 3 (step 6).
- **Binaries:** none. The configurers and the graphs are cache, rebuilt from source.

## Pragmatics

### Diagnostics

| Situation | Error |
|---|---|
| a script naming Std | `build.zs:4:3: error: File is part of Std, which a build script can't use: a build script says what to build and zs builds it; name files with Glob, and run a program as a Command` |
| a Core module not open to scripts | `build.zs:2:6: error: Threading isn't open to a build script, which can use the prelude, Option, Result, Iter, Collections, Text, Int, Float, Math, Bits, Bytes, Binary, Numerics.Fixed, Time.DateTime and Build` |
| `unsafe`, `extern`, `import`, `[<Link>]` | `build.zs:9:5: error: extern in a build script: a build script can't call C; C to compile is a C entry of the result, and a library to link its link` |
| no `build`, or another shape | `build.zs: error: a build script's entry is build (cx: Context) : Package, or build (cx: Context) (o: Options) : Package` |
| `[build]` without a path | `zs.toml:9: [build] script: expected a quoted path such as "build.zs", found build.zs` |
| a path outside the package | `package tls, build.zs: "../common/x.c" isn't a path inside the package` |
| a pattern matching nothing | `package tls, build.zs: Glob "c/mbedtls/libary/*.c" matches no file` |
| a name used twice | `package app, build.zs: two programs are named app` |
| a reference to nothing | `package app, build.zs: step flash makes firmwre, which isn't one of the package's programs (app, firmware)` |
| a cycle | `package app, build.zs: step a runs step b, which runs step a` |
| an unknown step | `zs build relase: app has no step relase; did you mean release? (zs build --steps lists them)` |
| an unknown option | `-Dfts=true: sqlite's options are fts5 (bool); did you mean fts5?` |
| an option's value | `-Dfts5=yes: fts5 is a bool, true or false` |
| options for something that isn't a dependency | `zs.toml:12: [options.sqlit]: sqlit isn't a dependency (they are sqlite, text)` |
| a command not trusted | `step textkit runs cargo, and this build isn't trusted (--no-trust); build without --no-trust to run it` |
| a command's program not there | `step textkit runs cargo, which isn't on PATH` |
| a command failing | its output, then `in package app, command textkit (cargo, exit code 101)` |
| a script that doesn't finish | `package tls: build.zs was stopped after 60 seconds without a result` |
| a script that panics | `package tls: build.zs panicked: <the message>` |

Every manifest error carries `zs.toml:line`, as today. Errors in the script carry
`build.zs:line:col`. Errors in its result name the package and the node, since the result is a
value and has no line.

### Tooling

- **`zs lsp`:**
  - checks `build.zs` as any file, with `Build` in scope and the subset's errors as they're typed;
  - takes a package's `import c` include paths and defines from the configured graph;
  - configures again when a script is saved.
- **`zs mcp`:** `check` sees a script's errors, and `build` takes a step, whose commands run only with `--trust`.
- **`zs build`** gains three flags:
  - `--graph`: JSON, paths relative to the project, for other tools;
  - `--steps`: names and docs; configures but runs no command;
  - `--options`: read from the type, so it runs nothing.
- **`zs new`** writes no script: no script is the default. **`zs doc`** skips scripts. **`zs fmt`** formats them.
- **The tree-sitter grammar** gains nothing: a script is Z#.

### Performance

- **Without a script:** the manifest is lowered to a graph, a few hundred values at most. Nothing else changes.
- **With a script, nothing changed:** one hash of the key's inputs and one file read. The library's files are hashed already for the module cache.
- **A script changed:** one compile of a small program (estimate: under a second warm; measured at step 3), then one run of milliseconds.
- **An option changed:** no compile, one run. **An argument after `--` changed:** nothing.
- **Patterns:** one directory walk per pattern per build, and the matched files' hashes, which the C cache reads already. For `tls`'s 109 files that's well under the C compile it saves checking by hand.
- **Commands:** their inputs are hashed each build, as a provider's sources are. A crate of 1 MB hashes in about a millisecond with XXH3.

### Scaling

| Dimension | Typical | Upper bound |
|---|---|---|
| packages with a script in one build | 0–5 | 1,000 (each configured on its own, at once) |
| files a pattern matches | 100 (`tls`: 109) | 10,000 |
| programs, commands and steps in a package | 0–10 | 1,000 |
| options in a package | 0–5 | 100 |
| a configured graph's JSON | a few KB | 10 MB |
| a script's run | milliseconds | 60 seconds, then stopped |
| targets one build configures for | 1 | 5 (a firmware, its host tool, a few more) |

### Culture-aware formatting and parsing

Invariant throughout:

- **Paths** in the graph use `/` on every system.
- **Patterns** match bytes, case-sensitively, on every system, Windows and macOS included, so a script names the same files everywhere.
- **Expanded files** are sorted by their bytes, not by the locale.
- **An option's value** is parsed as JSON's is: `true` and `false`, ASCII digits, no grouping and no locale.
- **The graph's JSON** is UTF-8, its keys in a fixed order.

## Unresolved questions

1. **Whether configure runs untrusted** (`zs lsp`, `zs mcp`, `--no-trust`).
   - **This proposal: yes.** It rests on promise 1, in a process of its own with a time and a memory limit.
   - **The alternative:** the server uses the graph the last trusted build cached, as it uses a provider's last output. Until one exists, an `import c` whose include paths come from a script is an error.
   - **Either way,** an operating system's sandbox (seccomp on Linux, a job object on Windows) could be added to the configurer's process as defense in depth.
2. **The allow-list.** The one above is what a script needs. `Numerics.Random` (seeded, deterministic), `Sha256` and `Hmac` are pure too, and could be added when a script asks for them.
3. **The step command's spelling.**
   - **This proposal:** `zs build <step>`, which is Zig's.
   - **The alternative:** a command of its own, such as `zs step <name>`, which leaves `zs build`'s words alone.
4. **Who sets a dependency's options.**
   - **This proposal:** the project only, in `[options.<key>]`.
   - **The alternative, unification:** any dependent may ask, and the values are unified (a `bool` asked `true` by anyone is `true`), as Cargo's features are.
   - **Not possible:** Zig's way, one configuration per dependent, which would put two configurations of one package in a build.
5. **Shared build logic.** Whether a script may open a dependency's modules, as `build.zig` imports a dependency's. Not in the first version: a script opens the library and `Build` only.
6. **The memory limit,** and how it's kept: `setrlimit` on POSIX and a job object on Windows, or the runtime's own count of its heap.
7. **Whether `Build` is visible to programs.** This proposal: to scripts only, so it takes no name from a program, whose own `Build` module would otherwise meet a library namespace.
8. **The graph's form:** JSON through the derive (readable, and what `--graph` prints), or `Binary` if a measurement asks for it.
9. **`[c]` and `[provider]` in the long run:** shorthand kept for good (this proposal), or a script's `C` and a `Provider` node replacing them, with the keys deprecated.
10. **A workspace root's own script,** with steps over its members. Later.

## History

- **2026-11-17:** drafted from a review of the build as it is (`src/Build/Project.zs`, `Commands.build`, `packages/`, `examples/rust`, `examples/zig`, `test.sh` and the release scripts) and of Zig 0.17's build system (configure and make split in May 2026, package management moved into the maker in June 2026). The decision row is for the coordinator to number.
