# logstat: a Z# tour for F# developers

`logstat` summarises HTTP access logs: entries per level, the busiest routes, the slowest
requests, and every line it couldn't read. It's small, but it uses the parts of Z# that F#
doesn't have: effects, tasks that the compiler checks, parallelism that the compiler checks,
and traits.

```sh
cd examples/logstat
zs run -- [-v] [--top N] [--timeout MS] <file.log | dir>...
zs run -- -v logs
zs test                                  # unit, property and whole-program tests
../../dev examples/logstat/bench.sh      # size, time, memory on 1M generated lines
```

Exit codes: 0 on success, 1 if any file couldn't be read, 2 for a bad command line.

## If you know F#, you already know most of this

Records, unions, `match`, active patterns, `|>`, `option`, `result`, `$"..."` strings,
`let rec`, `module`, `open`: all of these work as they do in F#. The differences you'll meet
in this example are:

| F# | Z# | Note |
|---|---|---|
| `printfn "%s" x` | `println $"{x}"` | `eprintln` writes to stderr |
| `[<EntryPoint>] let main argv` | `let main () = ...` returning `int` | arguments come from `Environment.args ()` |
| `String.Split(',')` | `String.split "," s` | the string goes last, so it pipes |
| `failwith` / `try ... with` | `Throw.throw` / `Throw.catch` | the error shows in the function's type |
| `task { }` on .NET | `task { }`, compiled to a state machine | no .NET; it runs on Z#'s own event loop |
| `Array.Parallel.map` | `Array.Parallel.map` | the compiler checks what the function captures |
| `static member (+)` and `Zero` | `impl Add<T>` | a trait, resolved at compile time |
| a `.fsproj` listing the files | a `zs.toml` naming the package | each file is a module, found by its path |

## The files

```
logstat/
  zs.toml                 the package: its name and version
  bench.sh                size, time and memory on generated logs
  logs/                   sample input
  src/
    main.zs               main: App.run with the real terminal and disk
    App.zs                the whole program, arguments to exit code
    Cli/Args.zs           the command line                       Throw
    Domain/Entry.zs       one log line, parsed                   Throw
    Domain/Stats.zs       what lines add up to                   impl Add
    Domain/Chunk.zs       counting a file in pieces              pure, run on every core
    Input/Discover.zs     finding the log files                  Progress, Files
    Io/Effects.zs         the outside world                      Terminal, Files
    Io/Real.zs            ...as the terminal and disk            Task.all, Task.timeout
    Io/Memory.zs          ...in memory, for tests
    Output/Report.zs      the summary                            Terminal
  tests/
    Check.zs              a small property checker               Gen
    UnitTests.zs          each module on its own
    PropertyTests.zs      laws over random inputs
    AppTests.zs           the whole program, in memory
```

Each file is a module named by its path: `Domain/Stats.zs` is `Domain.Stats`. There's nothing
to import: `App.zs` calls `Cli.Args.parse` and the compiler finds `src/Cli/Args.zs`. Inside a
folder, files name each other without the folder (`Domain/Chunk.zs` writes `Stats.addEntry`).
`zs.toml` makes the folder a package, so `zs run` and `zs test` work without naming a file.

The folders are the layers. `Domain` is pure: it knows nothing of files, terminals or
threads. `Io` is the only place that touches the outside world. `Cli`, `Input` and `Output` sit
between them, and `App` wires them together.

**The tests live in `tests/`.** `zs test` runs every file with `[<Tests>]` in `src/` and
`tests/`, each built as a program of its own. In a package, a test names modules from the main
file's folder, as the program does, so `Domain.Stats` and `Io.Memory` mean the same in both. A
module that isn't found there is looked for beside the test, which is how the tests find
`Check`.

Data flows through the modules like this:

```
Cli.Args ──Throw──▶ Options
                  │
Input.Discover ──Files, Progress──▶ file paths
                  │
Files.readAll ──(Io.Real: Task.all + timeout each)──▶ result<(path, text), error> list
                  │                                     └── errors to Terminal.err, exit 1
                  │
Domain.Chunk.cut ──256 KB pieces──▶ Array.Parallel.map Domain.Chunk.count ──▶ Array.sum ──▶ Stats
                  │
Output.Report ──Terminal.out──▶ stdout, or a test's list
```

## Effects: what a function may do is in its type

This is the biggest idea F# doesn't have. An **effect** declares operations. A function that
performs one has the effect in its type, and some caller must **handle** it, or the program
doesn't compile.

### `Throw`: exceptions you can see in the type

In F#, `int.Parse` can throw, but its type `string -> int` doesn't say so. In Z#,
`Entry.parse` has the type `string -> Entry / Throw<string>`. The part after the `/` lists its
effects. You don't write it: the compiler infers it, and the editor shows it on hover.

```fsharp
// Domain/Entry.zs
let private number (what: string) (s: string) =
  Throw.ofOption $"bad {what} '{s}'" (String.parseInt s)   // None becomes a throw

let parse (line: string) =
  match words line with
  | [ time; lv; meth; path; status; ms ] ->
    { time = time; level = level lv; meth = meth; path = path; status = number "status" status; ms = millis ms }
  | _ -> Throw.throw "expected 6 fields"
```

Compare this with F#'s `result { }`: there's no `let!` on every field, because the first
`Throw.throw` stops the whole parse. But unlike F# exceptions, a caller can't forget it.
`Throw.catch` turns the throw back into a plain `result`:

```fsharp
// Domain/Chunk.zs
match Throw.catch (fun () -> Entry.parse line) with
| Ok e -> addEntry s e
| Error why -> addBad s { file = file; line = n; why = why }
```

Rule of thumb: use `Throw` inside a parser or a long computation, and return a `result` at a
module's boundary.

### Your own effects: `Progress`

```fsharp
// Input/Discover.zs
effect Progress =
  abstract note : string -> unit
```

`Input.Discover.files` calls `Progress.note` without knowing where the messages go. `App`
decides:

```fsharp
// App.zs
let private discover (opts: Cli.Args.Options) =
  handle Input.Discover.files opts.inputs with
  | Input.Discover.Progress.note msg, k ->
    if opts.verbose then complain msg
    k ()          // carry on inside files, from just after Progress.note
```

The clause itself performs `Terminal.err` (through `complain`), which goes to the next handler
out. Handlers stack: `Progress` is a small, local effect, and `App` turns it into the
program-wide `Terminal`.

A clause gets the operation's arguments and `k`, the **resumption**: calling `k ()` continues
the code that performed the operation. Think of it as an interface given to the function at
the call site, without passing a logger parameter through every function in between, and with
the compiler checking that someone provides it. The next section uses this for the whole
program.

An effect in a clause that resumes at its end, as all of these do, compiles to a plain function
call: there's no allocation and no stack capture.

### Where effects must not go

Nothing can handle an effect once it leaves `main`, a `task { }` body, or a function run on
another thread. The compiler enforces this, and it shapes the design:
- `Domain.Chunk.count` runs on other threads, so it catches each line's `Throw` itself and is
  effect-free.
- The reading task lives inside `Io.Real.files`, a handler, and returns `result`s instead of
  logging.
- `App.run` handles `Throw` (arguments) and `Progress` (discovery); `main` handles `Terminal` and
  `Files`.

## Dependency injection with effects

In F# you'd inject the terminal and the filesystem as an interface (`IConsole`, `IFileSystem`)
or a record of functions, pass it down through every function that needs it, and give tests a
fake. In Z# the dependencies are effects, and the "container" is a stack of handlers.

**The dependencies** are declared once, in `Io/Effects.zs`:

```fsharp
effect Terminal =
  abstract out : string -> unit
  abstract err : string -> unit

effect Files =
  abstract isDirectory : string -> bool
  abstract listRecursive : string -> result<list<string>, string>     // full paths
  abstract readAll : int * list<string> -> list<result<string * string, string>>
```

**The program** uses them directly. Nothing is passed in: `Report.render` calls
`Terminal.out`, `Input.Discover.files` calls `Files.isDirectory`, and the types say so.
`App.run : list<string> -> int / <Terminal, Files>` is the whole program, and the type shows
everything it can do to the outside world. A function that tried to call `println` or
`File.readAllText` directly would still compile, so this is a convention you keep. But you can
check it in one place: no module outside `Io/` mentions `println`, `Directory` or `File`.

**Production** (`main.zs`) wraps it in the real handlers:

```fsharp
let main () = Io.Real.terminal (fun () -> Io.Real.files (fun () -> App.run (Environment.args ())))
```

`Real.files` is where the tasks are: its `readAll` clause runs `Task.all` over the reads, each
under `Task.timeout`, and resumes the program with the results.

**Tests** (`AppTests.zs`) wrap the same `App.run` in in-memory handlers:

```fsharp
let disk =
  [ ("logs/api.log", api)
    ("logs/old/web.log", "2025-12-08T22:10:01Z INFO GET /api/users 200 40ms")
    ("logs/notes.txt", "not a log") ]
  |> Map.ofList

let logstat args = Memory.terminal (fun () -> Memory.files disk (fun () -> App.run args))

test "a missing file is reported and fails the run" (fun () ->
  let (code, screen) = logstat [ "logs/api.log"; "nope.log" ]
  assert (code = 1)
  assert (screen.err = [ "logstat: cannot open nope.log: No such file or directory" ]))
```

`Memory.terminal` collects what's printed into a `Screen { out; err }` record, and
`Memory.files` serves a `Map` of path to contents. The tests run the real argument parsing,
discovery, parallel counting and report, with no disk, no stdout and no mocking library.

Why this is nicer than passing interfaces:
- **No plumbing.** `Stats` and `Entry` don't know a terminal exists, and `Report` doesn't take
  a console parameter. A new dependency doesn't change every signature on the way down.
- **Mix and match.** A `handle` takes clauses for one effect, so each handler supplies one
  dependency. `Memory.files disk` with `Real.terminal` runs against a fake disk but prints for
  real, with no new code.
- **Missing a handler is a compile error,** not a null reference at run time: `main` must
  handle everything `App.run` performs.
- **Test bodies must be effect-free** (`test : string -> (unit -> 'a / <>) -> Test`), so a test
  that forgot a fake doesn't compile, and can't touch the real disk by accident.
- **Cheap.** Every clause here resumes at its end, so each operation compiles to a plain
  function call.

## Tasks: reading every file at once

```fsharp
// Io/Real.zs
let private read (timeoutMs: int) (file: string) =
  task {
    let! r = Task.timeout timeoutMs (File.readAllTextAsync file)
    match r with
    | Some (Ok text) -> return Ok (file, text)
    | Some (Error e) -> return Error e
    | None -> return Error $"{file}: no data after {timeoutMs} ms"
  }

// in files, the handler for Files
| Files.readAll (ms, paths), k -> k (Task.run (Task.all (List.map (read ms) paths)))
```

This looks like F#'s `task { }`, with three differences:
- **Cold, like F#'s `async`.** Creating a task does nothing. `Task.run` in the handler starts it,
  and running a task twice does the work twice.
- **Structured.** `Task.all` waits for every task it started. `Task.timeout` gives `None` when
  time runs out and **cancels** the read: a cancelled task stops where it waits, and anything
  it bound with `use` is disposed. A stuck file can't hang the run or leak a handle.
- **Cheap.** The compiler turns the body into one state machine, allocated once, so each
  `let!` allocates nothing.

The two failure cases (read error, timeout) are values in the list. `App.run` prints them and
still reports on the files that did load.

## Parallelism the compiler checks

```fsharp
// App.zs
let private count (files: list<string * string>) =
  files
  |> List.collect (Domain.Chunk.cut chunkBytes)
  |> Array.ofList
  |> Array.Parallel.map Domain.Chunk.count
  |> Array.sum
```

`Domain.Chunk.cut` cuts each file at line ends into pieces of about 256 KB, so one big file
spreads over every core as well as many small ones do. A chunk is a record of the file's text
and a start and stop offset, so cutting copies nothing.

`Array.Parallel.map` runs `Domain.Chunk.count` once per chunk on a work-stealing thread pool. Its
type is `share<'a -> 'b> -> array<'a> -> array<'b>`, and the `share<…>` part is the
difference from F#: the function, and everything it captures, must be safe to share between
threads. Immutable values (numbers, strings, records, unions, lists, `Map`) are; `ref`,
`Buffer` and plain mutable state aren't. Had `Chunk.count` captured a `ref` counter, it would be a
compile error, not a data race.

So there are no locks here. Each job returns its own `Stats`, and the results are added
together afterwards.

## `impl Add`: counting is addition

F# lets a type define `static member (+)` and `static member Zero`, which is what
`List.sum` uses. Z# does the same with a trait:

```fsharp
// Domain/Stats.zs
impl Add<Route> =
  let add a b = { hits = a.hits + b.hits; totalMs = a.totalMs + b.totalMs; errors = a.errors + b.errors }
  let zero = { hits = 0; totalMs = 0; errors = 0 }
```

`Stats` gets one too. Then every level of the program is the same operation:
- one line → a `Stats` holding one entry (`ofEntry`);
- one chunk → the sum of its lines;
- the whole run → `Array.sum` of the chunks.

`+` on `Stats` is associative (and `Add.zero` adds nothing), so however the files are cut, the
parallel results add up to the same answer.

**Even line numbers add up.** A chunk doesn't know where in its file it starts, so it numbers
its lines from 1. `Stats` records how many lines it has seen in each file (`seen`), and `+`
shifts the right side's bad-line numbers past the lines the left side saw in that file. That's
still associative, so chunks need no numbering in advance, and cutting a file needs no pass
over it to count lines.

**The fast path is the same sum.** Building a one-entry `Stats` per line and adding it is
clear, but slow. `addEntry s e` adds an entry straight into `s`, and a property checks that it
always equals `s + ofEntry e`, so the faster code can't drift from the definition. The map merge is generic too: it relies only on
`+` and `Add.zero`, so the same `merge` adds up the `int`s in `levels` and the `Route`s in
`routes`.

```fsharp
let private merge a b = Map.fold (fun m k v -> Map.add k (v + Option.defaultValue Add.zero (Map.tryFind k m)) m) a b
```

Traits are resolved at compile time, so there's no virtual call, like an inlined F# SRTP
function but without the `inline` keyword.

## Tests

Three files in `tests/`, all run by `zs test`. Every test runs in its own process, and a test body must
be effect-free, so each test supplies the handlers it needs.

**`UnitTests.zs`: each module alone.**
- `Entry.parse` is tested from a table of lines and expected results:
  `for (line, expected) in parseCases -> test …` makes one test per case.
- `Args.parse`: defaults, flags in any position, and each error message.
- `Domain.Chunk.countFile` on a small file, and that it keeps only the five slowest requests.
- `Report.render` is an **expect test**. `expect actual """…"""` compares the value's text with
  a literal, and `zs test --update` writes the literal for you, so the expected report sits in
  the test. It runs under `Io.Memory.terminal`, so the report is captured, not printed.

**`PropertyTests.zs`: laws over random inputs.** Z# has no property-testing library, so
`Check.zs` is a small one, and the generator is an effect:

```fsharp
effect Gen =
  abstract below : int -> int          // a number from 0 up to n - 1

let genEntry () =
  { time = $"2025-12-{10 + Gen.below 20}T10:{10 + Gen.below 50}:00Z"
    level = pick [ Debug; Info; Warn; Err ]
    ... }
```

Generators just call `Gen.below`. `check runs prop` handles `Gen` with a seeded 64-bit LCG
(so a failure happens again on every run) and gives back the first counterexample, which
`assert (check … = None)` prints when it fails. It's FsCheck's `Gen` without a monad: the
generator is ordinary code, and the effect supplies the randomness. The properties:
- `parse (format e) = Ok e` for any entry;
- `parse` never panics on junk, and rejects anything that isn't 6 fields;
- every non-blank line is either counted or reported as unreadable;
- `Add.zero` is the identity, and `+` is associative: the monoid laws that make the parallel
  merge correct;
- a file counted in two parts adds up to counting it whole, at any split point, bad lines'
  numbers included;
- `addEntry s e = s + ofEntry e`;
- a file cut into chunks of any size adds up to the whole file.

The third property found a real bug: a line of only spaces was reported as unreadable instead
of skipped as blank. `Domain.Chunk` now skips it. The two-parts property also caught a
mistake in a test once: joining the parts with `"\n"` drops the line break after an empty
first part, so the parts weren't the same file as the whole.

**`AppTests.zs`: the whole program**, under `Io.Memory`, as described above.

## Performance

`bench.sh` builds with `--release`, generates logs with awk (1 line in 100 is garbage), and
reports the best of 3 runs and the peak RSS on 1, 2, 4, 8 and 16 workers. Measured in the dev
container, on an AMD Ryzen 7 PRO 8840U laptop: 8 cores, 16 threads.

Binary: 394 KB, or 369 KB stripped. It's one self-contained file, with no runtime to install.

1,000,000 lines (50 MB):

| workers | 16 files | 1 file |
|---|---|---|
| 1 | 0.72 s, 55 MB | 0.77 s, 100 MB |
| 2 | 0.43 s | 0.48 s |
| 4 | 0.29 s | 0.33 s |
| 8 | 0.21 s | 0.25 s |
| 16 | 0.20 s, 60 MB | 0.23 s, 100 MB |

**What limits the scaling is the machine, mostly.** Pure compute with no allocation at all (a
parallel `fib`) gets 1.75× on 2 workers, 3.1× on 4, 4.4× on 8 and 5.6× on 16 here. The laptop
runs one core at 5.1 GHz but all of them much slower, and the second thread of a core adds
little. Counting alone gets 4.1× on 16 workers, about three-quarters of that ceiling; the whole
run gets 3.6×, because reading 50 MB takes about 36 ms that don't get faster with more workers.
Expect a desktop or server with more real cores to do better.

**One big file scales almost as well as many,** since files are cut into chunks.

**Memory stays flat with more workers:** 55 MB on 1, 60 MB on 16. That's the files' text plus a
little per chunk. One 50 MB file needs 100 MB because the text is read in one piece.

### How it got here

| Version | 1 worker | 16 workers | Peak memory (16 workers) | Speed-up |
|---|---|---|---|---|
| a list of every line's `Stats`, summed | 7.15 s | 1.49 s | 462 MB | 4.8× |
| no copy of the bad lines when there are none; a fold | 1.69 s | 0.42 s | 195 MB | 4.0× |
| 1 MB chunks, lazy lines, `addEntry` | 0.86 s | 0.24 s | 55 MB | 3.6× |
| chunks number their own lines; each copies its slice | 0.78 s | 0.21 s | 77 MB | 3.7× |
| a recursive line loop; 256 KB chunks | 0.72 s | 0.20 s | 60 MB | 3.6× |
| the same code in folders (see below) | 0.66 s | 0.15 s | 59 MB | 4.4× |

The last row's hot path is the same as the row above it. Another change to the compiler and
runtime was in the tree when it was measured, so part of that gain may be theirs, or a cooler
CPU; the tables above use the row before.

The speed-up column fell as the code got faster: less work per line leaves the fixed costs
(reading, the machine's shared resources) a bigger share. The time on 16 workers is what
improved, from 1.49 s to 0.20 s.

The bugs and bottlenecks found on the way:
- **Copying the bad lines on every line.** `+` ran `List.append a.bad b.bad` for every line,
  copying the running list of bad lines even when the new line had none: O(lines × bad lines).
- **A list of every line.** `String.splitLines` and then a `Stats` for each line kept the whole
  file in memory several times over. Lines are now cut one at a time.
- **One file, one core.** Jobs were whole files, so a single big file used one core. Files are
  now cut into chunks.
- **A shared string.** Every chunk of a file used the file's text, so 16 threads updated the
  same atomic reference count on every line. Each chunk now copies its slice once, and one
  50 MB file went from 2.4× to 3.1×.
- **Allocations per line.** About 45 objects a line at first. The worst were `Seq.unfold`'s
  tuples, `$"..."` interpolation (about 4.5 times the cost of `+` on strings) and filtering
  the words of every line.

Tried and dropped: reading each file on its own thread with `Task.spawn` (no faster), and 64 KB
chunks (slower than 256 KB).

What's left is in the runtime. In a profile, finding `"\n"` (`zs_str_index_of` and `memcmp`)
is about 16% of the time, as if it compared memory at every position instead of scanning for
one byte, and allocating and freeing is about 14%. Both would make every Z# program faster.

## Safe by design: a summary

- **Errors are values or typed effects.** Nothing throws an untyped exception. A missing
  file, a timeout and a bad line are each reported, and none of them stops the run.
- **Effects can't escape.** Every effect is handled in `main` or caught inside the function
  that crosses a thread, and the compiler checks both.
- **The outside world is behind two effects,** so the whole program runs in tests with no
  disk and no terminal.
- **No shared mutable state.** Parallel jobs return values; `share<…>` rules out the rest.
- **No leaked work.** Tasks are structured: `Task.all` and `Task.timeout` wait for or cancel
  what they started, and `use` disposes on cancellation.
- **Panics are bugs.** A panic (an index out of range, say) isn't an effect and can't be
  caught. It means the program is wrong, not the input.

## Things that will surprise you

- **Union cases can hide `result`'s.** A union with a case called `Error` hides
  `result`'s `Error` in every module that opens it. That's why `Level` has `Err`.
- **No tuple patterns in parameters.** `let f (a: string, b: string)` doesn't parse. Take the
  tuple and unpack it in the body, as `Domain.Chunk.cut` does.
- **`Directory.listRecursive` returns paths relative to the directory.** `Io.Real.files` joins
  each one back with `Path.combine`.
- **One effect per `handle`.** A handler with clauses for two effects is a compile error; nest
  two handlers, as `Io.Real.terminal` and `Io.Real.files` are.
- **Multi-line arguments.** `Map.ofList` followed by a list on the next, indented line doesn't
  parse. Put the list first and pipe it, as `AppTests.zs` does.
- **An opened module's names may win over a local one** (possibly a bug). In `UnitTests.zs`, with `open Entry`, a local `parse` was
  resolved to `Entry.parse`; the tests use `tryParse`.
- **A list on the line after `in` doesn't parse,** in `for … in` inside a list of tests. Give
  the cases a name first (`parseCases`).
- **No `[<Wrapping>]` on functions yet,** although the docs mention it; use
  `Int.wrappingMul` and `Int.wrappingAdd`. There's no `[a .. b]` list range either: use
  `List.init`.
- **No multi-line `if` as a record field's value.** Bind it first (`let slow = …`), as
  `Stats.addEntry` does.
- **Argument order.** Collection and string functions take the subject last, so they pipe
  (`String.split "," s`), but `String.replace s old new` takes it first.

## Where to read more

- Effects: [docs/guide/16-effects.md](../../docs/guide/16-effects.md)
- Tasks: [docs/guide/13-tasks.md](../../docs/guide/13-tasks.md)
- Parallelism: [docs/guide/14-parallel.md](../../docs/guide/14-parallel.md)
- Traits: [docs/guide/06-traits.md](../../docs/guide/06-traits.md)
- Modules and files: [docs/guide/08-programs.md](../../docs/guide/08-programs.md)
