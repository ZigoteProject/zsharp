# 8. Programs

## Modules

**Each `.zs` file is a module named after the file:** `geometry.zs` is the module `Geometry`.
- **Using one:** another file uses it with qualified names (`Geometry.area`), or opens it with `open Geometry`. The compiler finds the files a program uses, next to the main file and in its dependencies, so there's nothing to list in a build file.
- **Private names:** `let private` and `type private` keep a name inside its module.
- **Renaming:** `module Name` on a file's first line gives it a different module name.

```
src/
  main.zs        open Geometry … area (Circle 2.0)
  geometry.zs    type Shape = …   let area s = …   let private pi () = …
```

**Nested modules:** `module Inner =` followed by indented declarations defines a module inside a file.
- **Names:** its names are `Outer.Inner.name`, and code inside it sees the names of the modules it's in.
- **Privacy:** a `private` name is visible in its module and the modules nested in it.
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

## The library

**Three layers:**
- **Prelude:** the names every program has without qualification: the operator traits (`Eq`, `Ord`, `Show`, …), `option` and `result`, and functions such as `print`, `ignore`, `fst` and `min`.
- **Core:** what needs no operating system, so every target has it, microcontrollers included: lists, arrays, maps, sets, strings, characters, options and results.
- **Std:** what needs an operating system: the console, the environment, files, directories, paths, processes and timing. On a microcontroller, using it is a compile error that says so.

**Namespaces:** modules are grouped in namespaces, as in .NET.

| Namespace | Core | Std |
|---|---|---|
| `Collections` | `List`, `Array`, `Buffer`, `Map`, `Set`, `HashMap` | |
| `Text` | `String`, `Char` | |
| `IO` | | `File`, `Directory`, `Path` |
| `Diagnostics` | | `Process`, `Stopwatch` |
| none | `Option`, `Result`, `Math`, `Int`, `Runtime`, `Mmio` | `Console`, `Environment` |

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
text = { path = "../text" }                                       # another project on disk
json = { git = "https://github.com/someone/json", rev = "v1.2" }  # tag, branch or commit
```

| Command | Does |
|---|---|
| `zs new <name>` | creates a project: `zs.toml`, `src/main.zs`, `.gitignore` |
| `zs build` | builds `build/<name>` |
| `zs run [args…]` | builds and runs, passing the arguments |
| `zs test [filters…]` | runs the `[<Test>]` functions in `src/` and `tests/` |
| `zs fetch` | checks out the git dependencies |
| `zs update` | moves git dependencies to the newest commit of their `rev` |

**Dependencies:**
- **Modules:** a dependency is another project, and its modules are found in the folder of its `main`.
- **Git dependencies:** they're checked out into `.zs-cache/deps/`. `zs.lock` records the exact commit of each, so builds are reproducible and need no network once fetched; commit `zs.lock` with your project. The builds and `zs test` fetch what's missing.

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
  println $"{Path.combine "src" "main.zs"} {Path.getExtension "main.zs"} {Path.changeExtension "notes.txt" "md"}"
  File.delete "notes.txt" |> ignore
  0
```

```text
0 arguments, HOME set: true
Ok [one; two]
Ok 14 true
Error cannot open missing.txt: No such file or directory
echo said hi there (code 0)
src/main.zs .zs notes.md
```

**More of Std:**
- **Directories:** `Directory.list`, `Directory.create` and `Directory.exists`.
- **Paths:** `Path.combine`, `getFileName`, `getDirectoryName`, `getExtension` and the others work on the text alone; they don't touch the file system.
- **The console:** `Console.readLine ()` and `Console.readLines ()` read standard input, and `Console.Error.writeLine` writes to standard error.
- **Exit codes:** `Environment.exit code` ends the program at once with that code. Returning a number from `main` sets the exit code too.
- **Processes:** `Process.run` starts the program directly, without a shell, so arguments are passed exactly as given.
- **Timing:** `let sw = Stopwatch.startNew ()`, then `sw.ElapsedMilliseconds`.

## Tests

A function marked `[<Test>]` is a test: a `unit -> unit` function that fails by panicking, usually through `assert`.
- **Separate processes:** `zs test` runs each test in its own process, so one failure doesn't stop the others.
- **Output:** a failure reports its message and output.
- **Where tests go:** they can live next to the code they test, since `main` isn't needed in a test build.

```zsharp
let wordCount (s: string) = String.split " " s |> List.filter (fun w -> w <> "") |> List.length

[<Test>]
let countsWords () =
  assert (wordCount "two words" = 2)
  assert (wordCount "  spaced   out  " = 2)

[<Test>]
let emptyHasNone () =
  assert (wordCount "" = 0)
```

```sh
$ zs test counter.zs
ok   countsWords
ok   emptyHasNone
2 passed, 0 failed
```

A failing assert names its location, e.g. `FAIL emptyHasNone` followed by `panic: assertion failed at counter.zs:10`.

## Units of measure

**Declaring units:** `[<Measure>] type m` declares a unit, and a number type can then carry it: `f64<m>`, `f64<m/s^2>`. A literal gets one with `9.81<m/s^2>`.

**What the compiler does:**
- **Checks:** it checks units through arithmetic. Adding meters to seconds is an error, and multiplying or dividing combines units.
- **No cost at run time:** units are erased after checking, so a program with units compiles to the same code as one without.

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
