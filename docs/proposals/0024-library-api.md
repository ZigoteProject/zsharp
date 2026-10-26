# Proposal 0024: the library's API

| | |
|---|---|
| **Status** | Approved in principle (track S items 2–4 and 6–8; the sub-items marked *after phase 11* stay so) |
| **Decided at** | track S's plan ([ROADMAP](../../ROADMAP.md#library-s)); the names at the 1.0 freeze review |
| **Builds** | track S: library, phase 11's "Library (track S)" list first ([ROADMAP](../../ROADMAP.md#phase-11-self-hosting)) |
| **Rests on** | decisions 3 (`int` is the machine word), 4 (overflow: checked by default, wrapping explicit; saturating added here), 28 (UTF-8 strings), 37 (prelude, Core and Std; .NET module names, F# function names) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §9](../../DESIGN.md#9-compiler) "The library" |
| **Related** | [0003 spans](0003-spans-and-slices.md) (`Bytes` over spans), [0017 iteration](0017-iteration.md) (the `ofIter` functions), [0023 JSON in Core](0023-json-in-core.md), [0020 self-hosting](0020-self-hosting.md) (what the compiler needs first), [0005 ergonomics](0005-ergonomics.md) (`Map.empty` as a value), [0015 fixed point](0015-fixed-point.md) (the saturating operations at `i16`), [0021 warnings](0021-warnings.md) (`deprecated` is a warning kind), [0022 macOS and Windows](0022-targets-macos-windows.md) (`Path` on Windows), [0016 async on bare metal](0016-async-bare-metal.md) (`Task` in Core), [0012 interrupts](0012-interrupts-noalloc-intrinsics.md) (`Atomic`, `Spsc`), [0009 tests as values](0009-tests-as-values.md) and [0010 properties](0010-properties-and-fuzzing.md) (`Testing`) |

- [x] Approved in principle
- [ ] Discussion
- [ ] Implementation (phase 11's list done; `Math`, `Random` and the collections in phase 12: `Random` in a namespace of its own, `Numerics`, as `DateTime` is in `Time`; `PriorityQueue` a leftist heap, not an array's, since `match dequeue q with Some(x, rest) -> q <- rest` keeps the old queue alive through the call and an array heap would copy at every step; the rest after phase 11)

## Summary

What the prelude, Core and Std grow into before 1.0, as tables of names, signatures, layers and
when: collections, numbers, text, time, IO, processes and the network, in DESIGN §9's layers and
decision 37's names. One language-level piece: format specifiers and widths in interpolation,
`$"{x:F2}"`, `{n:X8}` and `{name,-20}`, where the hole lowers to a `Format` trait call checked at
compile time. Everything is invariant: no culture parameter exists anywhere. Each addition brings
its `///` docs, a reference page, a test and, for Core, a microcontroller build. At 1.0 the names
freeze, and a rename afterwards is a `[<Deprecated "use X">]` warning for one release.

```fsharp
let report (name: string) (ratio: f64) (flags: u32) =
  $"{name,-20}{ratio:F2} {flags:X8}"      // "clang               0.97 000000CF"
```

## Motivation

- **Phase 11's compiler** is the first user: about 970 `sprintf` calls become holes with
  specifiers; about 220 `Dictionary`/`HashSet` and 80 `ResizeArray` uses become `HashMap`,
  `HashSet` and `Buffer`; `Process.run` captures only standard output and clang reports on
  standard error; the LSP reads N bytes from standard input; the cache needs modification times
  and `DateTime.utcNow`; the lexer and `import c` parse numbers in a radix (ROADMAP, phase 11).
- **The first day.** An F# programmer reaches for `List.groupBy`, `Math.floor`, `padLeft` and
  `Random` in the first hour and finds `Math` with `abs` and `sqrt` (facts sheet §12). Without
  the library each program writes them by hand, differently.
- **Track S's exit tests:** ten Advent of Code puzzles with only the prelude, Core and Std and no
  helper F#'s library already has; grep, a JSON pretty-printer and `tail -f` in `examples/`,
  each under 100 lines; every Core module builds for Cortex-M0+.

## Detailed design

### Layers and what other proposals own

- **Prelude:** `Format` joins `Show`; nothing else, since a name is global only if F# has it global.
- **Core** (no OS): everything below not marked Std, including `Random`, `DateTime` and `Duration` as types, so a microcontroller program has a generator, a time and a duration.
- **Std** (needs an OS): `Random.shared`, `DateTime.utcNow`, readers and writers, processes, the network; the loop primitives stay under `Native`.
- **Owned elsewhere, listed for the map:** `Task` in Core ([0016](0016-async-bare-metal.md)); `Atomic` and `Spsc` ([0012](0012-interrupts-noalloc-intrinsics.md)); `Testing` with `Gen`, `Prop` and `Arbitrary` ([0009](0009-tests-as-values.md), [0010](0010-properties-and-fuzzing.md)); `Json` ([0023](0023-json-in-core.md)); iteration and the `ofIter` functions ([0017](0017-iteration.md)); `Map.empty` and the other empty collections as values ([0005](0005-ergonomics.md)). This proposal adds nothing to those modules.
- **Values, as `HashMap` is one:** `HashMap` is a value like an array, updated in place when nothing else refers to it (`lib/core/Collections/HashMap.zs`). `HashSet`, `Queue`, `Stack` and `PriorityQueue` follow that contract; `Buffer` stays the shared, mutable reference it is.

### Collections

| Name | Signature | Layer | When |
|---|---|---|---|
| `HashSet<'a>` (`'a: Hash + Eq`) | `empty : HashSet<'a>`; `add : 'a -> HashSet<'a> -> HashSet<'a>`; `remove`; `contains : 'a -> HashSet<'a> -> bool`; `count`; `toList`; `ofList`; `union`, `intersect`, `difference : HashSet<'a> -> HashSet<'a> -> HashSet<'a>` | Core | before 11 |
| `Buffer.empty` | `Buffer<'a>`, a generic constant: a fresh empty buffer at each use, as `HashMap.empty` is | Core | before 11 |
| `Buffer.push`, `pop`, `clear`, `truncate` | `push : 'a -> Buffer<'a> -> unit`; `pop : Buffer<'a> -> option<'a>`; `clear : Buffer<'a> -> unit`; `truncate : int -> Buffer<'a> -> unit`; the length grows by doubling, so `push` is amortized constant | Core | before 11 |
| `List.groupBy`, `countBy` | `groupBy : ('a -> 'k) -> list<'a> -> list<'k * list<'a>>`; `countBy : ('a -> 'k) -> list<'a> -> list<'k * int>` (`'k: Hash + Eq`, first occurrence order) | Core | after 11 |
| `List.chunkBySize`, `windowed`, `pairwise` | `chunkBySize : int -> list<'a> -> list<list<'a>>`; `windowed : int -> list<'a> -> list<list<'a>>`; `pairwise : list<'a> -> list<'a * 'a>` | Core | after 11 |
| `List.scan`, `foldBack`, `tryFindIndex` | `scan : ('s -> 'a -> 's) -> 's -> list<'a> -> list<'s>`; `foldBack : ('a -> 's -> 's) -> list<'a> -> 's -> 's`; `tryFindIndex : ('a -> bool) -> list<'a> -> option<int>` | Core | after 11 |
| `Array.*` of the above | the same names over spans ([0003](0003-spans-and-slices.md)), returning arrays; `Array.binarySearch : 'a -> span<'a> -> option<int>` (`'a: Ord`, a sorted input) | Core | after 11 |
| `Map.change`, `Set.isSubset` | `change : 'k -> (option<'v> -> option<'v>) -> Map<'k, 'v> -> Map<'k, 'v>`; `isSubset : Set<'a> -> Set<'a> -> bool`; and `Set.isSuperset`, `Map.keys`, `Map.values` | Core | after 11 |
| `Queue<'a>`, `Stack<'a>` | `Queue.empty`; `enqueue : 'a -> Queue<'a> -> Queue<'a>`; `dequeue : Queue<'a> -> option<'a * Queue<'a>>`; `count`; `Stack.empty`, `push`, `pop : Stack<'a> -> option<'a * Stack<'a>>`, `peek`; a ring over an array and a list, in place when unique | Core | after 11 |
| `PriorityQueue<'a, 'p>` (`'p: Ord`) | `empty`; `enqueue : 'a -> 'p -> PriorityQueue<'a, 'p> -> PriorityQueue<'a, 'p>`; `dequeue : PriorityQueue<'a, 'p> -> option<('a * 'p) * PriorityQueue<'a, 'p>>`; `count`; a binary heap, lowest priority first, as .NET's | Core | after 11 |

### Numbers

| Name | Signature | Layer | When |
|---|---|---|---|
| `Int.parse`, `Int.parseRadix` | `parse : string -> option<'a>` and `parseRadix : int -> string -> option<'a>` for every integer type (the result's type decides the width and the range, `int` when nothing does, as a literal): an optional sign, then digits of the radix (2–36, letters in either case), nothing else: no `0x`, `_` or spaces; out of range is `None` | Core | before 11 |
| `Float.parse` | `string -> option<'a>` for `f32` and `f64`: a sign, digits, `.`, an exponent, `inf` and `nan`; `1,5` is `None` | Core | before 11 |
| `String.parseInt`, `parseFloat` | stay as the `int` and `f64` cases, one line each over `Int.parse` and `Float.parse` (the guide and DESIGN §2.2 use them); the freeze review decides whether they go | Core | before 11 |
| `Math.floor`, `ceil`, `round`, `trunc` | `'a -> 'a` for `f32` and `f64`, as `Math.sqrt` is (`Typer.fs:284`, main checkout); `round` is half to even, as F#'s `round` (`llvm.roundeven`) | Core | after 11 |
| `Math.pow`, `exp`, `log`, `log2`, `log10` | `pow : 'a -> 'a -> 'a`; the rest `'a -> 'a`; LLVM intrinsics | Core | after 11 |
| `Math.sin`, `cos`, `tan`, `atan2` | `'a -> 'a`; `atan2 : 'a -> 'a -> 'a`; LLVM intrinsics | Core | after 11 |
| `Math.clamp`, `pi`, `e` | `clamp : 'a -> 'a -> 'a -> 'a` (low, high, value) for every number with `Ord`; `pi` and `e` are constants that take the float type each use needs (DESIGN §2.1) | Core | after 11 |
| `Int.checkedAdd`, `checkedSub`, `checkedMul` | `'a -> 'a -> option<'a>` at every integer width, through `llvm.*.with.overflow` | Core | after 11 |
| `Int.saturatingAdd`, `saturatingSub`, `saturatingMul` | `'a -> 'a -> 'a` at every integer width, as `Int.wrappingAdd` is (`Typer.fs:274`, main checkout); `llvm.sadd.sat` and friends; `Mul` is `with.overflow` and a select. [0015](0015-fixed-point.md) uses them at `i16` | Core | after 11 |
| `Int.popCount`, `leadingZeros`, `trailingZeros` | `'a -> int` (`ctpop`, `ctlz`, `cttz`; the width for zero) | Core | after 11 |
| `Int.rotateLeft`, `rotateRight`, `byteSwap` | `rotateLeft : 'a -> int -> 'a` (`fshl`, `fshr`); `byteSwap : 'a -> 'a` (`bswap`), which `Bytes` uses | Core | after 11 |
| `Random` | PCG32: a `u64` state and stream behind a `ref`, so a `Random` isn't `Share` and each thread makes its own. `create : u64 -> Random`; `nextU32 : Random -> u32`; `nextInt : int -> int -> Random -> int` (low inclusive, high exclusive, unbiased); `nextFloat : Random -> f64` in `[0, 1)`; `nextBytes : Buffer<u8> -> Random -> unit`; `shuffle : array<'a> -> Random -> array<'a>` (in place when unique) | Core | after 11 |
| `Random.shared` | `unit -> Random`, seeded from the OS (`getrandom`, else `/dev/urandom`); a function, since a top-level value can't be shared across threads (DESIGN §7.1) | Std | after 11 |
| `Bytes.read*`, `Bytes.write*` | `read{U16,U32,U64,I16,I32,I64,F32,F64}{BE,LE} : span<u8> -> int -> <that type>` at an offset; `write… : Buffer<u8> -> int -> <that type> -> unit`; one bounds check, one unaligned load or store, and `byteSwap` where the order differs from the target's (never on the targets in DESIGN §10) | Core | after 11 |

### Text

| Name | Signature | Layer | When |
|---|---|---|---|
| `String.padLeft`, `padRight` | `int -> string -> string` with spaces; `padLeftWith`, `padRightWith : int -> char -> string -> string`; the width counts characters (`String.charCount`), not bytes, and never truncates | Core | before 11 |
| `String.trimStart`, `trimEnd` | `string -> string`, ASCII whitespace as `Char.isWhitespace`; `String.trim` exists | Core | before 11 |
| `String.splitLines` | `string -> list<string>`, at `\n` and `\r\n`, no empty last line, as `File.readAllLines` splits | Core | before 11 |
| `Text.Utf8` | `validate : span<u8> -> result<unit, int>` (the offset of the first malformed byte); `decode : span<u8> -> string` (malformed bytes become U+FFFD, decision 28); `tryDecode : span<u8> -> option<string>`; `encodeChar : char -> Buffer<u8> -> unit`. A string's bytes are `String.bytes` ([0003](0003-spans-and-slices.md)) | Core | after 11 |
| `Text.StringBuilder` | only if the measurement in *Performance* shows `s += x` in a loop isn't linear: `create`, `append : string -> StringBuilder -> unit`, `appendChar`, `length`, `clear`, `toString`, over a `Buffer<u8>` | Core | after 11 |

### Format specifiers in interpolation

The one subsection with syntax. It's F#'s own interpolation syntax, so decision 34 needs no discussion.

```
hole   :=  '{' expr [ ',' width ] [ ':' spec ] '}'
width  :=  [ '-' ] digits                 // positive pads on the left (right-aligned), negative on the right
spec   :=  letter [ digits ]              // at most two digits
```

- **Today** a hole lowers to `string e`, a `Show.show` call, and the pieces are joined with `+` (`interpolate`, `Syntax.fs:1772`, main checkout). A hole with `:F2` or `,10` after its expression is an error there.
- **`Format`** is a trait in the prelude next to `Show`, built in for the numeric types as `Show` is:

```fsharp
/// Text for a value under a format specifier: what `$"{x:F2}"` calls. Built in for numbers.
trait Format<'a> =
  /// The value as text, shaped by `spec` (`"F2"`, `"X8"`).
  abstract format : 'a -> string -> string
```

- **Lowering:** `{e:spec}` is `Format.format e "spec"`; `{e,w}` is `String.padLeft w (string e)` (`padRight` for a negative `w`); `{e,w:spec}` pads the formatted text. The specifier is a literal, so the built-in impls receive the letter and the digits already split and parse nothing at run time; `print $"…"` keeps printing the pieces without building the string (DESIGN §9.1).
- **Checked at compile time:** the specifier is parsed by the compiler; for a numeric hole the letter is checked against the table below, and an unknown one is an error. A string takes a width and no specifier. A type without a `Format` impl takes no specifier (`Json` has none: `{j:F2}` is the error in *Diagnostics*). In a generic function the hole adds a `Format<'a>` constraint, and the specifier is checked where the type is known.
- **The width is a literal,** so `{a,b}` isn't a tuple; a tuple in a hole is written `{(a, b)}`. No hole in the repository has a top-level comma today.
- **The subset** of .NET's standard numeric specifiers, with .NET's meaning and the invariant culture's text:

| Spec | Types | Text | Example |
|---|---|---|---|
| `F`, `Fn` | floats, integers | fixed-point with `n` decimals (default 2), half away from zero | `{3.14159:F2}` is `3.14` |
| `E`, `En` | floats | exponent, `n` decimals (default 6), `E+ddd` | `{1234.5:E2}` is `1.23E+003` |
| `G`, `Gn` | floats | `Show`'s shortest round-trip text; with `n`, that many significant digits | `{0.1:G3}` is `0.1` |
| `N`, `Nn` | floats, integers | `F` with commas every three digits | `{1234567:N0}` is `1,234,567` |
| `D`, `Dn` | integers | decimal, zero-padded to `n` digits | `{42:D5}` is `00042` |
| `X`, `Xn`, `x`, `xn` | integers | hex, upper or lower case, zero-padded to `n`; negatives as two's complement at the type's width | `{255:X8}` is `000000FF` |
| `B`, `Bn`, `b`, `bn` | integers | binary, zero-padded to `n` | `{5:B8}` is `00000101` |

- **A user impl** sees the text and decides what it takes; a letter it doesn't know is its own choice (its `Show` text, or a panic):

```fsharp
type Money = { cents: i64 }

impl Format<Money> =
  let format (m: Money) (spec: string) =
    if spec = "F" then string (m.cents / 100) + "." + Format.format (m.cents % 100) "D2"
    else string m.cents + "c"

let line (price: Money) = $"{price,10:F}"     // "     12.50"
```

### Time

| Name | Signature | Layer | When |
|---|---|---|---|
| `[<Measure>] type ns`; `Duration` | `type Duration = i64<ns>`: `i64`, not `int`, since `int` is 32 bits on a Cortex-M (decision 3) and 2.1 s of nanoseconds is too few; `+`, `-`, `*`, `/`, comparison, `Show` and hashing are `i64`'s, and the unit keeps a plain `i64` out of it (DESIGN §2.2) | Core | after 11 |
| `Duration.ns`, `us`, `ms`, `s` | `i64 -> Duration`; `toMilliseconds : Duration -> i64`; `toSeconds : Duration -> f64`; `toText : Duration -> string` (`1.5s`, `250ms`, `42us`, `7ns`: the largest unit that keeps three significant digits) | Core | after 11 |
| `DateTime` | `{ sinceEpoch: Duration }`: nanoseconds since 1970-01-01T00:00:00Z, UTC only, so equality, ordering and hashing are structural and the range is 1678–2262; `Show` prints ISO 8601 (`2026-10-22T08:00:00Z`, a fraction only when nonzero) | Core | before 11 |
| `DateTime.utcNow` | `unit -> DateTime`, `clock_gettime(CLOCK_REALTIME)` through a new `Native` builtin next to `Runtime.ticks` (`rt.c`, main checkout, about line 168) | Std | before 11 |
| `DateTime.add`, `diff` | `add : Duration -> DateTime -> DateTime`; `diff : DateTime -> DateTime -> Duration` (`Add` is homogeneous, so these are functions); `unixEpoch`; `ofUnixSeconds : i64 -> DateTime`; `toUnixSeconds` | Core | after 11 |
| `DateTime.parse`, fields | `parse : string -> option<DateTime>`: ISO 8601 `YYYY-MM-DD[THH:MM[:SS[.fraction]]][Z or ±HH:MM]`, an offset converted to UTC; `year`, `month`, `day`, `hour`, `minute`, `second : DateTime -> int` and `ofFields : int -> int -> int -> int -> int -> int -> option<DateTime>` (civil-from-days arithmetic, no tables) | Core | after 11 |
| `Stopwatch` | gains `sw.Elapsed : Duration`; `ElapsedMilliseconds` stays | Std | after 11 |
| time zones | a package (track K): the IANA database is data to ship and update | | |

### IO

| Name | Signature | Layer | When |
|---|---|---|---|
| `Reader`, `Writer` | types in `IO` with `Dispose` impls, so `use r = File.openRead "a.bin"?` closes them; buffered over `Native.fdRead`, `fdWrite` and `fdClose`, which `Tcp` uses today; blocking (a file is), so a task wraps a read in `Task.blocking` when it must not stall the loop | Std | before 11 |
| `File.openRead`, `openWrite`, `openAppend` | `string -> result<Reader, string>` and `string -> result<Writer, string>` | Std | before 11 |
| `Reader.readLine`, `readBytes`, `readExactly`, `readToEnd` | `readLine : Reader -> result<option<string>, string>` (`None` at the end); `readBytes : Reader -> Buffer<u8> -> result<int, string>` (up to the buffer's length; 0 at the end); `readExactly : Reader -> Buffer<u8> -> int -> result<unit, string>` (the LSP's `Content-Length` bytes); `readToEnd : Reader -> result<string, string>` | Std | before 11 |
| `Writer.write`, `writeText`, `flush` | `write : Writer -> span<u8> -> result<unit, string>` (an array, a `Buffer` or `String.bytes s`); `writeText : Writer -> string -> result<unit, string>`; `flush : Writer -> result<unit, string>`; `dispose` flushes | Std | before 11 |
| `Console.openStandardInput`, `openStandardOutput` | `unit -> Reader` and `unit -> Writer`, for binary framing; `Console.readLine` stays | Std | before 11 |
| `File.readAllBytes`, `writeAllBytes` | `readAllBytes : string -> result<array<u8>, string>`; `writeAllBytes : string -> span<u8> -> result<unit, string>` | Std | before 11 |
| `File.copy`, `move`, `modifiedAt`, `size` | `copy`, `move : string -> string -> result<unit, string>` (`rename`, then copy and delete across devices); `modifiedAt : string -> result<DateTime, string>`; `size : string -> result<i64, string>`; `File.exists` and `Directory.exists` are builtins today (`Typer.fs:353`, main checkout) | Std | before 11 |
| `File.createTemp`, `Directory.createTemp`, `Directory.temp` | `createTemp : string -> result<string, string>` (a prefix; `mkstemp`, mode 0600, the path returned); `Directory.createTemp` likewise (`mkdtemp`); `Directory.temp : unit -> string` (`$TMPDIR`, else `/tmp`) | Std | before 11 |
| `Directory.listRecursive`, `delete` | `listRecursive : string -> result<list<string>, string>` (relative paths, iterative, symlinks not followed); `delete : string -> result<unit, string>` (empty only); `deleteRecursive` | Std | before 11 |
| `Path.getFullPath`, `getRelativePath`, `separator`, `isAbsolute` | `getFullPath : string -> string`: `Environment.currentDirectory ()` joined and normalized lexically (`.`, `..`, repeated `/`), no symlink resolution, as .NET; `getRelativePath : string -> string -> string` (from, to); `separator : char`; `isAbsolute : string -> bool`. Specified on POSIX paths: `/`, case-sensitive; Windows's separator, drives and case are [0022](0022-targets-macos-windows.md)'s, and the separator is the target's at run time | Std | before 11 |
| `Environment.currentDirectory` | `unit -> string` (`getcwd`), which `getFullPath` needs | Std | before 11 |

### Processes

| Name | Signature | Layer | When |
|---|---|---|---|
| `ProcessStart` | `{ program: string; args: list<string> = []; environment: option<list<string * string>> = None; directory: option<string> = None; stdin: Pipe = Inherit; stdout: Pipe = Inherit; stderr: Pipe = Inherit }` with `type Pipe = Inherit \| Piped \| Null`, so a start names only what it changes (DESIGN §2.3) | Std | before 11 |
| `Process` | `{ pid: int; stdin: option<Writer>; stdout: option<Reader>; stderr: option<Reader> }` (a pipe for each `Piped` stream), with `Dispose` closing the pipes | Std | before 11 |
| `Process.start` | `ProcessStart -> result<Process, string>`: `posix_spawn` with file actions and the environment, as `zs_process_run` does today (`rt.c`, main checkout, about line 893), no shell, PATH lookup | Std | before 11 |
| `Process.wait`, `kill` | `wait : Process -> Task<int>` (the exit code, or 128 plus the signal, awaited through `Task.blocking` around `waitpid`); `kill : Process -> result<unit, string>` (`SIGKILL`) | Std | before 11 |
| `Process.run` | unchanged: `string -> list<string> -> result<ProcessResult, string>`, standard output captured, standard error inherited | Std | today |

### Net

| Name | Signature | Layer | When |
|---|---|---|---|
| `Endpoint` | `{ address: string; port: int }`, the address as text in dotted or colon form | Std | after 11 |
| `Unix.listen`, `accept`, `connect` | `listen : string -> result<Listener, string>` (a path; a stale socket file is removed first), `accept : Listener -> Task<result<Socket, string>>`, `connect : string -> Task<result<Socket, string>>`: `Tcp`'s functions over a path, giving `Tcp`'s socket type, so reads and writes are `Tcp`'s, on the event loop; the build server's socket ([0020](0020-self-hosting.md), decision 76) | Std | before 11 |
| `Udp.bind`, `sendTo`, `receiveFrom` | `bind : string -> int -> result<UdpSocket, string>`; `sendTo : UdpSocket -> Endpoint -> span<u8> -> Task<result<unit, string>>`; `receiveFrom : UdpSocket -> Buffer<u8> -> Task<result<int * Endpoint, string>>`; non-blocking sockets on the event loop, as `Tcp` | Std | after 11 |
| `Dns.resolve` | `string -> Task<result<list<string>, string>>`, `getaddrinfo` under `Task.blocking`, so the loop never waits on a resolver; `Tcp.connect` moves onto it | Std | after 11 |
| TLS, HTTP | packages (track K: `tls` over mbedTLS, `http` on `Net.Tcp` and llhttp) | | |

### Each addition's rule

- **Docs:** a `///` comment on every declaration, in the voice `lib/` has.
- **A reference page:** `zs doc` generates it; `tests/reference.sh` regenerates `docs/reference/` and fails when a page is stale.
- **A test:** a `tests/<name>.zs` with its `.out` (test.sh discovers the pair; facts sheet §14), and an `.err` for each diagnostic in *Diagnostics*.
- **A microcontroller build for Core:** `tests/mcu/core.zs` opens every Core module and builds for Cortex-M0+ (`Driver.mcus`), the exit test "every Core module builds for Cortex-M0+". `Math`'s intrinsics are libm calls there, which the build links.

### The freeze and `[<Deprecated>]`

- **Before 1.0** names change freely: packages are source (decision 27) and rebuild, and there are no users yet. `Map.empty ()` becoming a value is [0005](0005-ergonomics.md)'s example.
- **The 1.0 freeze review** checks every module name against .NET's and every function name against F#'s (decision 37), with a table of the differences and the reason for each kept one, in `docs/reports/`.
- **After it,** a rename keeps the old name for one release under `[<Deprecated "use Int.parse">]`, on a function, a type or a module. A use is a warning of kind `deprecated` with the message; `[<NoWarn "deprecated">]` silences it in a module. [0021](0021-warnings.md) owns the mechanism and the diagnostic record (severity, name, position, message, notes); this proposal adds the attribute and the kind, and `zs doc` marks a deprecated name with its replacement.

### Order of implementation

1. **Phase 11's list** (before phase 11, in the order the compiler meets it): `Int.parse`, `Float.parse`; format specifiers and widths; `HashSet`, `Buffer.push/pop/clear/truncate`; `padLeft`, `padRight`, `trimStart`, `trimEnd`, `splitLines`; `DateTime` and `utcNow`; readers and writers, `readAllBytes`, `move`, `modifiedAt`, temporary files, `getFullPath`, `getRelativePath`; `Process.start`; `Unix.listen`, `accept` and `connect` for the build server.
2. **After phase 11,** in track S's item order: the F# collection functions, `Queue`, `Stack`, `PriorityQueue`; `Math`, the integer operations, `Random`, `Bytes`; `Utf8` and the `StringBuilder` measurement; `Duration`, ISO 8601 and `DateTime`'s fields; `Udp` and `Dns`. The Advent of Code and `examples/` exit tests close it.
3. **Before 1.0:** the freeze review, then `[<Deprecated>]` once [0021](0021-warnings.md)'s warnings exist.

Each step keeps `./test.sh` green and follows *Each addition's rule*.

## Drawbacks

- **Surface.** About 120 names (an estimate from the tables), each with docs, a page and a test to keep; the freeze review is the check that each earns its place.
- **`Format` is a trait and a compiler table.** The specifier check lives in the compiler and the impls in the runtime (`rt.c` and `rt-embedded.c`), two places to keep aligned; `tests/` holds the table as `.out` files.
- **A subset of .NET's specifiers.** `{x:C}`, `{x:P}` and custom patterns (`0.00#`) are errors, which an F# programmer meets; the error lists what exists.
- **`{a,b}` changes meaning** from a tuple to a width; nothing in the repository writes one, and the error names the fix.
- **`Duration` as an abbreviation** has no `Show` of its own: `$"{d}"` prints nanoseconds, and `Duration.toText` is a call away.
- **Readers block,** where .NET has async streams; `Task.blocking` is the one escape, and files are what the readers are for.

## Alternatives

- **.NET's `IFormattable` surface wholesale:** `ToString(format, provider)`, culture providers, `C`, `P`, `R` and custom patterns. A provider is the culture parameter this design excludes, and custom patterns are a second language. Not chosen: the subset covers the compiler's `sprintf` uses and the exit tests, and a package can format money.
- **printf-style `%` formats** (`sprintf "%08x"`; F# has both): type-checked formats need the compiler to parse `%` strings as F# does, a mechanism beside the one holes already have. Not chosen: interpolation with .NET's specifiers is what F# programmers write first, and Z# has no `sprintf`.
- **A `String` module explosion** (`String.formatFixed 2 x`, `String.toHex 8 n`): each is a name to find and a call to nest. Not chosen: the hole is the one place, and `Format.format` is there for calls.
- **`Duration` as a record** with its own `Show`: a type to implement `Add`, `Ord` and `Hash` for. Not chosen: the unit costs nothing, arithmetic and ordering come from `i64`, and `toText` prints.
- **`Random` in Std only:** a microcontroller program needs a generator too, and PCG needs no OS. Not chosen; only the seed from the OS is Std's.
- **`DateTime` with civil fields** (year, month, day, …): comparison and arithmetic become algorithms. Not chosen: one integer compares, hashes and subtracts, and the fields are computed when asked.
- **Doing nothing:** each program writes `padLeft`, and the compiler's rewrite writes its own `HashSet`. The exit tests say no.

## Compatibility

- **Not a breaking change,** with two edges: a hole `{a, 3}` that printed a tuple pads `a` (none exists), and `Map.empty ()` is [0005](0005-ergonomics.md)'s. Everything else is new names.
- **An older compiler** stops at `{x:F2}` or `{x,10}` with its hole parse error, and at a new library name with "unknown name".
- **Compiled binaries:** none to consider; packages are source (decision 27).
- **The library:** additive. `String.parseInt` and `parseFloat` stay as the `int` and `f64` cases until the freeze review; `ProcessResult` and `Process.run` are unchanged; `Stopwatch` gains a member; `HashMap` and `Buffer.create` are untouched.
- **Microcontrollers:** every Core addition builds for Cortex-M0+ (the exit test); `Random`, `DateTime`, `Duration`, `Bytes` and `Format`'s number impls are plain code there, with the impls in `rt-embedded.c` (no `printf`); `Math`'s intrinsics are libm calls on a chip without the instruction.

## Pragmatics

### Diagnostics

| Situation | Error |
|---|---|
| an unknown specifier on a number | `unknown format specifier 'Q' for f64: F, E, G or N, with up to two digits (F2)` |
| an integer specifier on a float | `X is for integers: f64 takes F, E, G or N` |
| a specifier on a string | `a string takes no specifier: {name,-20} pads it` |
| a specifier on a type without `Format` | `Json doesn't implement Format: print it with Json.print, or format a number taken from it` |
| a width that isn't a literal | `a width is a number: {x,10} or {x,-10}; for a tuple write {(a, b)}` |
| three or more digits | `at most two digits in a specifier: F2, not F100` |
| a deprecated name (after the freeze) | `warning: String.parseInt is deprecated: use Int.parse` (kind `deprecated`) |
| a Std name in a microcontroller build | the existing error: `File.openRead is in Std, which needs an operating system; cortex-m0plus has none` |
| `Int.parseRadix 37 s` | at run time: `panic: radix 37: 2 to 36` |
| a read on a closed reader | at run time: `panic: read on a Reader closed by use` |

### Tooling

- **`zs lsp`:** hover on a hole's expression shows its type as today; hover on `:F2` shows `F2: fixed-point, 2 decimals`; completion after `:` in a hole lists the type's specifiers, and after `.` the new modules' functions; definition on `Format` opens the prelude; diagnostics above appear while editing, from the checker's real types with no build run (today's capabilities: hover, completion after `.`, definition, references, inlay hints, document symbols and formatting; facts sheet §1).
- **The tree-sitter grammar** gains the `,width` and `:spec` parts of a hole as nodes, highlighted apart from the expression.
- **`zs fmt`** leaves a hole's width and specifier as written. **`zs doc`** generates the new pages and marks deprecated names.

### Performance

- **Existing code:** none; a plain hole lowers as today.
- **Specifiers:** the letter and digits are split at compile time; the runtime's `zs_str_of_f64` (`rt.c`, main checkout, about line 570) gains fixed, exponent and grouped forms beside its shortest round-trip loop. `print $"{x:F2}"` prints the piece.
- **`Math`:** an instruction where the ISA has it (`roundsd`, `vrndm`), a libm call otherwise; `clamp` is two selects. **Integers:** `checkedAdd` is `+`'s own overflow check with the branch kept; the saturating and bit operations are single intrinsics.
- **`Bytes.readU32LE`:** one bounds check and one unaligned load; loop versioning (DESIGN §9.1) hoists the check out of a parser's loop.
- **`HashSet`:** `HashMap`'s table without values. **`Buffer.push`:** amortized constant by doubling.
- **`Random.nextU32`:** a multiply, an add, a shift and a rotate.
- **`DateTime.utcNow`:** one `clock_gettime`, no allocation.
- **The `StringBuilder` measurement:** a loop appending 100,000 short strings with `s += x` (an estimate of the compiler's largest IR emission), timed against the total length under `ZS_STATS=1`: linear with one allocation per growth means no `StringBuilder`.

### Scaling

Nothing in the library grows with the program; what grows with the data:

| Dimension | Typical | Upper bound |
|---|---|---|
| holes per interpolation | 1–5 | 100 |
| `Format` impls per program | the built-in ones and 0–2 | 100 |
| `HashSet` entries | 1,000 | memory (`int`-indexed buckets) |
| `Buffer` length | 1,000 | `int` elements, doubling |
| a line read by `readLine` | 100 bytes | memory; the buffer grows |
| `Directory.listRecursive` entries | 100 | 1,000,000, iterative |
| `Duration` | milliseconds to hours | ±292 years |
| `DateTime` | the present | 1678–2262 |
| `Int.parseRadix` | 10, 16 | 2–36 |

### Culture-aware formatting and parsing

- **Invariant throughout, no culture parameter anywhere.** `Show`, `Format`, `Int.parse`, `Float.parse` and `DateTime.parse` read and write `.` as the decimal point, `-` as the sign, ASCII digits only, and `N`'s grouping is commas every three digits. A program that must read `1,5` replaces the comma first, and localized output is a package's.
- **Time is UTC in ISO 8601,** read and written; zones and local formats are a package.
- **Text:** `padLeft` counts characters; `String.toUpper` and `Char.toUpper` stay ASCII (DESIGN §2.1), and string ordering is byte order, which is code point order in UTF-8, not collation.
- **`Json.print`** writes `JNumber` as `Show` writes `f64` (shortest round-trip, invariant) and `JInt` as the integer ([0023](0023-json-in-core.md)); `Json` is not a `Format` impl.

## Unresolved questions

1. **The specifier subset:** `F`, `E`, `G`, `N`, `D`, `X`/`x`, `B`/`b` here; `P` left out (the invariant culture writes `25.6 %` with a space, so Z#'s would be its own). The alternative adds `P` without the space.
2. **`N`'s default decimals:** .NET's 2 here (`{1234:N}` is `1,234.00`), so `N0` is the idiom; the alternative is 0 for integers.
3. **`Duration` as `i64<ns>`** (here) or a record with its own `Show`; the abbreviation prints a number and `toText` prints a duration.
4. **`Random` in Core with `shared` in Std:** yes here; the alternative keeps `Random` in Std, which leaves microcontrollers without one.
5. **`Random.shared` per call** (here) or a per-thread generator kept by the runtime; the latter needs thread-local state the runtime doesn't keep.
6. **`String.parseInt` and `parseFloat`:** kept as the `int` and `f64` cases until the freeze (here) or removed now, while there are no users.
7. **Readers blocking** (here) or returning `Task`s; `Task.blocking` wraps the former, and [0016](0016-async-bare-metal.md)'s `Task` in Core may change the answer.

## History

- **2026-10-22:** drafted from track S's plan, phase 11's "Library (track S)" list and DESIGN §9's "The library".
