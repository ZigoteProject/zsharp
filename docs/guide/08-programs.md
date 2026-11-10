# 8. Programs

## Modules

**Each `.zs` file is a module named after the file:** `geometry.zs` is the module `Geometry`.
- **Using one:** another file uses it with qualified names (`Geometry.area`), or opens it with `open Geometry`. The compiler finds the files a program uses, next to the main file and in its dependencies, so there's nothing to list in a build file.
- **Private names:** `let private` and `type private` keep a name inside its module.
- **Renaming:** `module Name` on a file's first line gives it a different module name.
- **Folders:** a file in a folder is named by its path from the main file's folder: `Shapes/Square.zs` beside `main.zs` is `Shapes.Square` (the folder may be `shapes/` and the file `square.zs`).

```
src/
  main.zs        open Geometry … area (Circle 2.0)
  geometry.zs    type Shape = …   let area s = …   let private pi () = …
```

**Nested modules:** `module Inner =` followed by indented declarations defines a module inside a file.
- **Names:** its names are `Outer.Inner.name`, and code inside it sees the names of the modules it's in.
- **Privacy:** a `private` name is visible in its module and the modules nested in it. So are a
  `type private` record's fields, even where one of its values turns up (in a public record's field).
- **`open`:** inside a module, it lasts until the module ends.

```zsharp
module Geometry =
  let private pi3 = 3

  let area r = pi3 * r * r

  module Units =
    let toBig x = x * 100 * pi3

module Report =
  open Geometry

  let line r = $"radius {r}: area {area r}"

let main () =
  println $"{Geometry.area 2} {Geometry.Units.toBig 1}"
  println (Report.line 3)
  0
```

```text
12 300
radius 3: area 27
```

**Fields and traits belong to their module too.** A record literal, a record pattern, or `.name` on a value whose type isn't known yet, looks for the record among those in scope: the current module's first, then the opened modules'. So two modules can each have a record with a `name` field, or a trait called `Describe`. Elsewhere, open the module or annotate the literal:

```zsharp
module Shop =
  type Item = { name: string; price: int }
  let pen = { name = "pen"; price = 2 }

module Books =
  type Item = { name: string; price: int }
  let novel = { name = "Dune"; price = 9 }

open Shop

let main () =
  let mug = { name = "mug"; price = 3 } // a Shop.Item: Shop is open
  let book = ({ name = "Emma"; price = 7 } : Books.Item)
  println $"{mug.name} {Shop.pen.price} {book.name} {Books.novel.price}"
  0
```

```text
mug 2 Emma 9
```

## The library

**Three layers:**
- **Prelude:** the names every program has without qualification: the operator traits (`Eq`, `Ord`, `Show`, …), `option` and `result`, and functions such as `print`, `ignore`, `fst` and `min`.
- **Core:** what needs no operating system, so every target has it, microcontrollers included: lists, arrays, maps, sets, strings, characters, options and results.
- **Std:** what needs an operating system: the console, the environment, files, directories, paths, processes, timing, threads and sockets (TCP, UDP, Unix sockets and name lookup). On a microcontroller, using it is a compile error that says so, and a dependency that uses it is named as the build starts: `package 'logger' uses File, part of Std, which needs an operating system; a build for cortex-m4 has none, so it can't depend on this package`.

**Namespaces:** modules are grouped in namespaces, as in .NET.

| Namespace | Core | Std |
|---|---|---|
| `Collections` | `List`, `Array`, `Buffer`, `Map`, `Set`, `HashMap`, `Queue`, `Stack`, `PriorityQueue` | |
| `Text` | `String`, `Char`, `Utf8` | |
| `IO` | | `File`, `Directory`, `Path` |
| `Diagnostics` | | `Process`, `Stopwatch` |
| `Threading` | `Task`, `Atomic`, `Spsc`, `Signal` | `Mutex`, `Channel`, `Alt`, `Parallel` |
| `Net` | | `Tcp`, `Udp`, `Dns`, `Unix` |
| `Numerics` | `Random`, `Q7`, `Q15`, `Q31` | `Random.shared` |
| `Time` | `DateTime`, `Duration` | `DateTime.utcNow` |
| none | `Option`, `Result`, `Math`, `Int`, `Runtime`, `Mmio`, `Irq`, `Cpu`, `Bits`, `Ptr`, `Weak`, `Arena` | `Console`, `Environment` |

- **Opened everywhere:** these namespaces are open in every module, so `List.map` is `Collections.List.map` and `File.readAllText` is `IO.File.readAllText`.
- **Your names come first:** the library's names have the lowest precedence. A program's own `List.top` or `Text.wrap` is found before them, and `List.map` still finds the library's.
- **Full names:** `Collections.Map.add` works too.

The [reference](../reference/README.md) documents every module.

## Projects

A project is a folder with a `zs.toml` manifest:

```toml
[package]
name = "wc"
version = "0.1.0"
main = "src/main.zs"        # the default

[dependencies]
text = { path = "../text" }                                         # another project on disk
json = { git = "https://github.com/someone/json", version = "1.2" } # its releases: v1.2.0 or later
yaml = { git = "https://github.com/someone/yaml", rev = "main" }    # a tag, branch or commit

[c]                                  # C code the package wraps (optional)
sources = ["c/shim.c"]               # compiled and linked with the program
include = ["c"]                      # where its `import c` and its sources find headers
link = ["m"]                         # libraries, as [<Link>] takes them
pkg-config = ["sqlite3"]             # a library's flags and libraries, from pkg-config

[c.cortex-m4]                        # added to [c] for one target: host, a chip, a triple
link = ["rust/target/thumbv7em-none-eabihf/release/libkit.a"]

[provider]                           # the package is a type provider: `import <its name> …` runs
main = "Provider.zs"                 # this program (the guide's chapter 18)
```

A project for a chip names it: `target = "cortex-m4"` under `[package]` makes `zs build` and `zs run`
build for it without `--target`, and `[target.cortex-m4]` sets what the chip's build takes, its
heap (`heap = "16K"`).

**Other languages:** a Rust crate or a Zig package built as a static library, with a C header for
it, is C to Z#: `examples/rust` and `examples/zig` use each both ways, on an OS and on a
microcontroller.

| Command | Does |
|---|---|
| `zs new <name>` | creates a project: `zs.toml`, `src/main.zs`, `.gitignore` |
| `zs build` | builds `build/<name>` (`--release` for an optimized one) |
| `zs run [args…]` | builds and runs, passing the arguments (a chip's image under QEMU, a WebAssembly module under Node) |
| `zs test [paths…]` | runs the `[<Tests>]` values in `src/` and `tests/` |
| `zs add ../text`, `zs add <git url>@1.2` | writes a dependency into `zs.toml`'s `[dependencies]` and fetches it: a path, or a git URL at a release (`@1.2`) or a rev (`@v1`, `--rev main`), named as its `zs.toml` names it, or after the URL's last part |
| `zs remove json` | takes a dependency out, the lock rewritten |
| `zs tree` | shows the dependencies as resolved: each one's version, where it comes from and its locked commit, its own under it |
| `zs fetch` | checks out the git dependencies |
| `zs update` | raises the project's `version`s to the newest releases, and moves `rev`s to their newest commits |
| `zs vendor` | copies the git dependencies into `vendor/`, where the project reads them from without fetching |

**Dependencies:**
- **Modules:** a dependency is another project, and its modules are behind its name. `json`'s main file is the module `Json` and its `Parser.zs` is `Json.Parser`: write `Json.Parser.parse`, or `open Json` and `Parser.parse`. So two dependencies may each have a `Util.zs`. Inside the dependency, its files name each other without the prefix, and its own dependencies are seen by its files only.
- **Internal modules:** a file under a directory named `internal` (at any depth) is for its own package's files. Naming it from another package is an error that lists the public ones: `Box.Internal.Secret is internal to box; use its public modules (Box, Box.Pub)`.
- **C code:** a package's `[c]` section is the build's when its modules are used: its sources are compiled (once, and again when one of them or a header it includes changes, wherever the header is, or a header is added beside one), its libraries linked, and its include directories and pkg-config's flags are its `import c`s'. pkg-config is asked on a host build only.
- **Git dependencies:** they're checked out into `.zs-cache/deps/`. `zs.lock` records the exact commit of each and a hash of its files, so builds are reproducible and need no network once fetched; commit `zs.lock` with your project. The builds and `zs test` fetch what's missing. A checkout edited by hand is restored from its commit at the next build or fetch, and files that still differ from the hash are an error naming the dependency (`zs update` accepts new ones); to change a dependency's code, make it a path dependency. A symbolic link in a dependency is hashed as the link it is and never followed, and a pipe or a device in one is an error. `zs.lock` keeps what the manifests ask for: a dependency you remove, or change from a `version` to a `rev`, leaves it at the next fetch.
- **Nothing written into a dependency:** what zs keeps for a dependency's files (its saved `import c`s, its provided modules, its type provider's program) is in the project's `.zs-cache/pkgs/<name>-<hash>/`, not in the dependency's directory, so a checkout or a vendored copy stays as its hash says; one whose `[package] name` isn't a directory's (`../x`) is kept in `package-<hash>/`. The directories of these caches, the project's as a dependency's (saved `import c`s, provided modules, providers' programs, and `zs provide c`'s), are made by zs, which refuses one that is a symbolic link (a repository can hold one pointing anywhere): `…/.zs-cache is a symbolic link, which zs doesn't write through`. Building or checking a dependency's own file (in `.zs-cache/deps/` or `vendor/`) fetches nothing: its dependencies are the project's.
- **Without the network:** `zs vendor` copies the git dependencies into `vendor/`, a copy kept in the project: they're read from there, their hashes checked, and never fetched. A symbolic link is copied as a link when it leads inside its package; one that leads out of it (to a file of your machine, which `vendor/` would commit) is an error naming it, and that dependency isn't vendored. `--offline` on `zs build`, `run`, `test`, `bench` or `fuzz` (or `ZS_OFFLINE=1`, for any command) makes a fetch an error instead, one that says `zs vendor` keeps a copy.
- **Versions:** `version = "1.2"` takes the repository's releases, its tags `v1.2.3`: 1.2.0 or later, below 2.0.0 (0.x and 1.x are one series, as in Go). When several packages ask for one, it gets the highest version asked for, not the newest there is: a diamond where `a` asks for `c` 1.1 and `b` for 1.3 builds with 1.3 on every machine, from the manifests alone, with no solver. Major version 2 is another package, with a key of its own (`json2 = { git = "…", version = "2.0" }`, the module `Json2`), so one program can use both.
- **Impls:** an impl is written in its trait's package or its type's, so two packages can't both write one that a program using both would have twice. The program's trait for a library type, or a library trait for the program's type, is the program's to write; the library's trait for a dependency's type isn't (wrap the type in a one-case union of your own).

**Workspaces:** a `zs.toml` with a `[workspace]` section, in a folder above several projects, makes them one workspace:

```toml
[workspace]
members = ["app", "tool", "libs/*"]   # libs/*: each folder under libs/ with a zs.toml
```

- **One lock:** the members' dependencies resolve together, into one `zs.lock`, one `.zs-cache/` and one `vendor/` at the root. A `zs.lock` inside a member is an error naming the root.
- **Commands at the root:** `zs build`, `zs test`, `zs fetch`, `zs update`, `zs tree` and `zs vendor` run over every member (a library member isn't built on its own). `zs run`, `zs add` and `zs remove` are run in a member, and say so at the root.
- **Members** use one another as path dependencies: `text = { path = "../libs/text" }`.

## Builds

**Debug and release:**
- **Debug** (`zs build`, the default): the program's code isn't optimized (`-O0`), so a build after an edit takes a tenth of a second or two. Z#'s own work is the same in both: a debug build allocates what a release one does, and tail calls still run in constant stack.
- **Release** (`zs build --release`): optimized (`-O2`), and inlined across the program's files and the runtime at the link (ThinLTO), for measuring and shipping. `--profile-generate` and `--profile-use` are release builds.
- **Levels:** `-O0` to `-O3` and `-Os` set clang's level for either. A microcontroller's build is optimized either way (`-g` alone aside, below), since unoptimized code doesn't fit a chip.
- **Debug info:** `-g` adds it for a debugger. With `--release` or a level, it's that optimized build with its lines kept. Alone it's an `-O0` build, the code as written, for stepping, on a chip too, but for the Cortex-M0+ and WebAssembly, whose `-O0` can't lower Z#'s tail calls: there it stays the optimized build, with lines ([Tools](10-tools.md#debugging)).

**Rebuilds:** only what an edit reaches is checked and compiled again. A module whose code didn't change comes from the cache in `~/.cache/zs`, which the editor's language server shares. `zs build --time` names the modules it checked and the files it compiled.

**The build server:** `zs build` hands its work to a compiler that stays running between builds, so a rebuild skips starting it. The first build starts one and builds on its own; the server ends after ten idle minutes, or with `zs server stop`. Each cache directory and environment has its own, and `ZS_NO_SERVER=1` builds in the process instead. It builds one program at a time, in the order the builds ask: two `zs build`s at once take turns. A client that connects and sends nothing, or doesn't read its answer, is dropped after a few seconds, so it holds up no build after it.

## Arguments, files and processes

Std has what command-line tools need. Failures are `result`s with a readable message, such as `cannot open data.txt: No such file or directory`.

```zsharp
let main () =
  let args = Environment.args ()
  println $"{List.length args} arguments, HOME set: {Option.isSome (Environment.getVariable "HOME")}"
  match File.writeAllText "notes.txt" "one\ntwo\n" with
  | Ok () -> println $"{File.readAllLines "notes.txt"}"
  | Error e -> eprintln e
  File.appendAllText "notes.txt" "three\n" |> ignore
  println $"{File.readAllText "notes.txt" |> Result.map String.length} {File.exists "notes.txt"}"
  println $"{File.readAllText "missing.txt"}"
  match Process.run "echo" [ "hi"; "there" ] with
  | Ok r -> println $"echo said {String.trim r.output} (code {r.code})"
  | Error e -> eprintln e
  File.delete "notes.txt" |> ignore
  0
```

```text
0 arguments, HOME set: true
Ok [one; two]
Ok 14 true
Error cannot open missing.txt: No such file or directory
echo said hi there (code 0)
```

**Paths are text,** joined with `/`, and on Windows with `\` (which takes `/` as a separator too): this prints the first output on Linux and macOS, the second on Windows.

```zsharp
let main () =
  println $"{Path.combine "src" "main.zs"} {Path.getExtension "main.zs"} {Path.changeExtension "notes.txt" "md"}"
  0
```

```text
src/main.zs .zs notes.md
```

```text windows
src\main.zs .zs notes.md
```

**More of Std:**
- **Readers and writers:** `File.openRead path` gives a `Reader` (`Reader.readLine`, `readBytes`, `readExactly`, `readToEnd`) and `File.openWrite` a `Writer` (`Writer.write`, `writeText`, `flush`); `use` closes one. `Console.openStandardInput ()` and `openStandardOutput ()` give the standard streams as bytes.
- **Files:** `File.readAllBytes`, `copy`, `move`, `size`, `modifiedAt` (a `DateTime`), and `File.createTemp prefix` for a temporary file.
- **Directories:** `Directory.list`, `create`, `exists`, `delete`, `listRecursive`, `deleteRecursive`, `createTemp` and `temp ()`.
- **Paths:** `Path.combine`, `getFileName`, `getDirectoryName`, `getExtension` and the others work on the text alone; `getFullPath` and `getRelativePath` also read the working directory (`Environment.currentDirectory ()`).
- **Processes with pipes:** `Process.start { program = "clang"; args = [ "-c"; "a.c" ]; stderr = Piped }` gives a `Process` whose piped streams are a `Reader` or a `Writer`, and `Process.wait p` its exit code as a `Task<int>`.
- **Time:** `DateTime.utcNow ()` is the current moment; `string` prints a `DateTime` in ISO 8601, and `DateTime.parseIso "2026-11-04T08:30:00+02:00"` reads one back (an `option`), `DateTime.ofParts` makes one from its parts.
- **Unix sockets:** `Unix.listen path`, `Unix.accept` and `Unix.connect path` are `Tcp`'s calls over a path, for processes on one machine. `Unix.listen` replaces a socket an earlier run left at the path, one no server listens on; a file there, or a live server's socket, is an error. `Tcp`, `Udp` and `Dns.lookup` are in [Tasks](13-tasks.md#sockets).
- **The console:** `Console.readLine ()` and `Console.readLines ()` read standard input, and `Console.Error.writeLine` writes to standard error.
- **Exit codes:** `Environment.exit code` ends the program at once with that code. Returning a number from `main` sets the exit code too.
- **Processes:** `Process.run` starts the program directly, without a shell, so arguments are passed exactly as given (a Windows batch file runs in `cmd.exe`, its arguments quoted so it reads them as given; one with a line break is an `Error`). A write to a process's piped input once it has exited is an `Error`, not the end of the program; a program whose standard output is cut off (`| head`) still ends there, quietly.
- **Timing:** `let sw = Stopwatch.startNew ()`, then `sw.ElapsedMilliseconds`.

## Tests

Tests are values, as in Expecto: `test "name" (fun () -> …)` is a `Test`, `testList "name" [ … ]` groups them, and a top-level value marked `[<Tests>]` is what `zs test` runs. They're in the `Testing` module (`open Testing`).
- **A test fails** by panicking, usually through `assert`, or by returning an `Error`; a body may also be a `task { }`.
- **Separate processes:** each test runs in its own process, several at once, so one failure doesn't stop the others; `testSequenced` runs a group one at a time. A test has 60 s (`testWithTimeout ms` for another limit), and a hang fails it.
- **Data makes tests:** `[ for (input, expected) in cases -> test input (fun () -> …) ]` is a list of tests.
- **Focus:** `ftest` and `ftestList` run only the focused tests while any are; `ptest` skips one and says so.
- **Where tests go:** next to the code they test, since a test build needs no `main`.
- **In a project:** `zs test` runs the files with `[<Tests>]` in `src/` and `tests/`. Each names modules from the main file's folder, as the program does, so `tests/StatsTests.zs` writes `Domain.Stats` for `src/Domain/Stats.zs`; a module not found there is looked for beside the test file (a helper in `tests/`).

```zsharp
open Testing

let wordCount (s: string) = String.split " " s |> List.filter (fun w -> w <> "") |> List.length

[<Tests>]
let tests =
  testList "words" [
    test "counts words" (fun () -> assert (wordCount "  spaced   out  " = 2))
    test "empty has none" (fun () -> assert (wordCount "" = 0))
    test "splits" (fun () -> expect (String.split " " "a b") "[a; b]")
    testProperty "counts what it joined" (fun (n: u8) ->
      wordCount (String.join " " (List.init (int n) (fun _ -> "w"))) = int n)
  ]
```

```sh
$ zs test counter.zs
ok   words/counts words
ok   words/empty has none
ok   words/splits
ok   words/counts what it joined
4 passed, 0 failed
```

- **A failing comparison explains itself:** `assert (parse s = Ok expected)` prints both sides and, for records, unions and collections, where they first differ: `left: { x = 1; y = 4 }`, `right: { x = 1; y = 5 }`, `at .y: 4 vs 5`.
- **Expect tests:** `expect value "text"` compares the value's text with the literal, and `zs test --update` rewrites the literals of the ones that fail, so the expectation sits next to the code.
- **Running some:** `zs test counter.zs words/` runs the tests whose path starts with `words/`, `zs test counter.zs empty` those whose path contains it; `--summary` lists each test's time, slowest first, and `--fail-on-focused` fails a run with focused tests left (for CI).
- **Properties:** `testProperty "name" (fun (n: u8) -> …)` is a test over 100 cases drawn at the parameter's type, growing in size; a case that gives `false` or an `Error` fails it, and is shrunk to a smallest one, shown with the seed that replays the run. `bench "name" (fun () -> …)` is a benchmark among the tests, which `zs bench` times and `zs test` runs once. [Tools](10-tools.md#properties) has properties, and [its command table](10-tools.md#the-zs-command) `zs bench`, `zs fuzz`, `zs test --coverage` and `zs test --stress`.
- **Leaks:** with `ZS_LEAKCHECK=1`, a test that leaves objects allocated at its exit fails.

## Units of measure

**Declaring units:** `[<Measure>] type m` declares a unit, and a number type can then carry it: `f64<m>`, `f64<m/s^2>`. A literal gets one with `9.81<m/s^2>`. An exponent is at most a million either way, written or made (`(m^2)^3` is `m^6`).

**What the compiler does:**
- **Checks:** it checks units through arithmetic. Adding meters to seconds is an error, and multiplying or dividing combines units.
- **No cost at run time:** units are erased after checking, so a program with units compiles to the same code as one without.
- **Generic units:** `f64<'u>` takes any unit, and inference solves for units as it does for types: given `sq : f64<'u> -> f64<'u^2>` and `cube`, `same (sq x) (cube y)` needs no annotations, and makes x's unit some `'w^3` and y's `'w^2`.

```zsharp
[<Measure>] type m
[<Measure>] type s
[<Measure>] type kg

let speed (d: f64<m>) (t: f64<s>) = d / t
let force (mass: f64<kg>) (a: f64<m/s^2>) : f64<kg m/s^2> = mass * a

let main () =
  let v = speed 100.0<m> 9.58<s>
  let g = 9.81<m/s^2>
  println $"{v} {force 70.0<kg> g} {List.sum [ 1.0<m>; 2.5<m> ]}"
  0
```

```text
10.438413361169102 686.7 3.5
```

`speed 100.0<m> 9.58<s> + 1.0<s>` doesn't compile: the error explains that `m/s` and `s` don't match.
