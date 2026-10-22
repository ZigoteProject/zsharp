# Proposal 0010: properties and fuzzing

| | |
|---|---|
| **Status** | Approved in principle |
| **Decided at** | track D's plan ([ROADMAP](../../ROADMAP.md#testing-profiling-and-debugging-d)): items 5 and 6, after phase 11 |
| **Builds** | track D: properties (item 5) and fuzzing (item 6) |
| **Rests on** | decisions 5 (panics), 10 (structural printing), 20 (derive, no macros) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §3.1](../../DESIGN.md#31-derive) |
| **Related** | [0009 tests as values](0009-tests-as-values.md) (`testProperty` is a `Case`), [0003 spans](0003-spans-and-slices.md) (`span<u8>` for raw bytes), [0011 debug info, profiles and traces](0011-debug-info-profiles-traces.md) (sanitizers), [0024 the library's API](0024-library-api.md) (`Random`) |

- [x] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

A property is a test over generated values: `testProperty "name" (fun (x: int) (xs: list<int>) -> …)`
is a `Test` ([0009](0009-tests-as-values.md)), run on 100 cases, and a failure is shrunk to a
smallest case, saved, and replayed first on the next run. One design carries all of it: a
generator reads its choices from a stream of bytes, so shrinking is shrinking the stream
(Hypothesis's design), every generator shrinks, mapped, bound and filtered ones included, and
their invariants hold; a saved stream replays a failure exactly; and under `zs fuzz` the same
property reads libFuzzer's bytes, guided by coverage, with no second harness.

```fsharp
open Testing

[<Derive(Arbitrary)>]
type Packet = { id: u16; flags: list<Flag>; payload: array<u8> }

[<Tests>]
let packets =
  testList "packet" [
    testProperty "round-trips" (fun (p: Packet) -> assert (Packet.parse (Packet.print p) = Ok p))
    testProperty "sort keeps length" (fun (xs: list<int>) -> List.length (List.sort xs) = List.length xs)
    testPropertyWith { runs = 1000 } "never panics" (fun (bytes: span<u8>) -> ignore (Packet.parse bytes))
  ]
```

```text
FAIL packet/round-trips: falsified after 12 runs, shrunk in 31 steps (seed 0x9c41e2a07b3d5f18)
       p = { id = 0; flags = []; payload = [| 0; 10 |] }
       assert failed at packet.zs:9: Packet.parse (Packet.print p) = Ok p
       left: Ok { id = 0; flags = []; payload = [| 0 |] }
       right: Ok { id = 0; flags = []; payload = [| 0; 10 |] }
       differs at .Ok.payload: [| 0 |] vs [| 0; 10 |]
       saved .zs-cache/failures/packet/round-trips; zs test replays it first
```

## Motivation

- **Example tests test the examples.** `tests/ztest/sample.zs` checks `double 21 = 42`. A property states what holds for every input (`parse (print p) = Ok p`), and the machine finds the input that breaks it; the bugs properties find (an empty list, a zero, a byte 10 in a payload, a key removed twice) are the ones nobody wrote an example for.
- **Shrinking is where libraries differ.** A failure on a 40-element list of 9-digit numbers is a puzzle; shrunk to `[0; 0]` it is a diagnosis. FsCheck shrinks by type, so a generator of even numbers can shrink to an odd one and its filter is lost (track D item 5); QuickCheck needs a shrinker written per type; the byte stream gives every generator a shrinker that keeps its invariants, with no shrinking code anywhere.
- **Replay has to be exact.** A seed replays a run as long as the generators don't change; the stream replays the case itself, and lives in `.zs-cache/failures` until the property passes it.
- **Fuzzing and properties are the same test.** A fuzz target is a function over bytes; a property is a function over typed values decoded from bytes. With one engine a `Packet` property is a fuzz target as written, and a crash the fuzzer finds is shrunk and replayed as a property failure is.
- **The library and the compiler need it.** Track D names `HashMap`, `Channel` and the runtime's pool as the first users of stateful testing, and phase 11's compiler ([0020](0020-self-hosting.md)) gets its parser's round-trip properties and the fuzzer's inputs.

## Detailed design

### One source of randomness

- **`Source`:** a stream of bytes with a cursor. A generator *draws* `n` bytes at a time; each draw is a *block*, and the draws of one generator's value form a *span* (nested: a list's span holds its elements' spans). The stream is recorded as it is read, with its block and span boundaries.
- **Where the bytes come from:** in a random run, from a `Random` seeded with a `u64` ([0024](0024-library-api.md): a PCG in Core, no OS needed), one seed per property per run, so the stream is as long as the case needs; in a replay, from a saved stream; under `zs fuzz`, from libFuzzer's input. A generator can't tell which. The run's seed comes from `zs test` (drawn from `Random.shared`, Std's), from `--seed`, or from the settings.
- **Running out:** a draw past the end of a saved or fuzzed stream is an *overrun*: the case is discarded, not failed. That is how a shrink candidate that is too short, or a fuzz input that is too short, is rejected without a generator knowing.
- **The encoding rule:** all-zero bytes mean the simplest value, and a lexicographically smaller block means a simpler one. Every generator in the table keeps it, and a hand-written one should (*Drawbacks*).

### Generators

`Gen<'a>` is `Gen of (Source -> 'a)`, a single-case union, as `Seq` is in
[0002](0002-effect-handlers.md). In Core's `Testing`:

| Generator | Type | Draws |
|---|---|---|
| `Gen.int`, `Gen.i8` … `Gen.u64` | `Gen<int>`, one per integer width | a magnitude bounded by the size (below), small first, then a sign; zero is all zeros |
| `Gen.float` | `Gen<f64>` | an integer-shaped value first (`0.0`, `1.0`, `-2.0`), then fractions, then the rest; NaN and the infinities with a small fixed weight |
| `Gen.bool`, `Gen.char`, `Gen.unit` | | one byte; `char` draws ASCII first, then any Unicode scalar |
| `Gen.range lo hi` | `int -> int -> Gen<int>` | the fewest bytes that cover `hi - lo`, big-endian, as an offset from `lo`: all zeros is `lo` |
| `Gen.constant x` | `'a -> Gen<'a>` | nothing |
| `Gen.elements xs` | `list<'a> -> Gen<'a>` | an index; the first element is the simplest |
| `Gen.frequency pairs` | `list<int * Gen<'a>> -> Gen<'a>` | a weighted index, then the chosen generator |
| `Gen.oneOf gens` | `list<Gen<'a>> -> Gen<'a>` | `frequency` with equal weights |
| `Gen.map f g` | `('a -> 'b) -> Gen<'a> -> Gen<'b>` | what `g` draws |
| `Gen.bind f g` | `('a -> Gen<'b>) -> Gen<'a> -> Gen<'b>` | `g`, then the generator chosen from its value |
| `Gen.filter p g` | `('a -> bool) -> Gen<'a> -> Gen<'a>` | `g` again, up to 100 times, until `p` holds; then the case is discarded |
| `Gen.list g`, `Gen.array g` | `Gen<'a> -> Gen<list<'a>>`, `Gen<'a> -> Gen<array<'a>>` | before each element one byte, "another?", then the element, each element a span; 0 stops, so the empty list is one zero byte |
| `Gen.listOfLength n g` | `int -> Gen<'a> -> Gen<list<'a>>` | `n` elements, no flags |
| `Gen.string` | `Gen<string>` | a `list` of `Gen.char` |
| `Gen.option g` | `Gen<'a> -> Gen<option<'a>>` | one byte, `None` first, then `g` |
| `Gen.sized f` | `(int -> Gen<'a>) -> Gen<'a>` | what `f size` draws |
| `Gen.scale f g` | `(int -> int) -> Gen<'a> -> Gen<'a>` | `g` at size `f size` |
| `Gen.draw g src` | `Gen<'a> -> Source -> 'a` | runs `g` on a source; what builders and derives call |
| `Gen.sample seed n g` | `u64 -> int -> Gen<'a> -> list<'a>` | `n` values from a seed, to look at a generator |

- **Size:** a property's cases grow from size 0 to `maxSize` (default 100) over its runs, as QuickCheck's do; `Gen.int`'s magnitude, a list's expected length and a string's are bounded by it, so the first cases are small and the later ones large. `Gen.sized` reads it; `Gen.scale` changes it for a sub-generator, which is how recursive types bound their depth.
- **`gen { }`** is `Gen.Builder` (decision 46): `bind`, `ret` and `delay`, so `let!` draws and `return` makes a value:

```fsharp
let email =
  gen {
    let! user = Gen.elements [ "ann"; "bob"; "cy" ]
    let! n = Gen.range 0 999
    let! host = Gen.elements [ "example.com"; "example.org" ]
    return Email $"{user}{n}@{host}"
  }
```

- **Shrinking needs nothing from a generator.** A mapped generator shrinks because its source shrinks and the map re-runs; a filtered one can't shrink to a value its predicate rejects, since the predicate re-runs too; `bind` shrinks the first draw, and the second re-generates from the smaller stream.

### `Arbitrary`

```fsharp
trait Arbitrary<'a> =
  abstract arbitrary : unit -> Gen<'a>
```

- **Impls in Core** for every integer type, `f64`, `f32`, `bool`, `char`, `string`, `unit`, `list`, `array`, `option`, `result`, `Map`, `Set`, `HashMap`, `Buffer`, tuples (structurally, as `Eq` on tuples is), and `span<u8>` and `array<u8>` as raw bytes: in a random run a block of up to `maxSize` bytes; under `zs fuzz` the rest of the input (*Fuzzing*).
- **`[<Derive(Arbitrary)>]`** for records and unions, written as a derive (DESIGN §3.1): a record draws each field with `arbitrary ()` at that field's type; a union draws a case with `Gen.elements`, then its fields. Each field is drawn at half the size (`Gen.scale`), and at size 0 a union chooses among its cases without fields when it has any, so a recursive union (`Tree`) ends in leaves: the size is what makes it terminate, and no case is marked by hand. A union whose every case holds a `'self` has no finite value; its generator spends the size and the case is discarded as an overrun, which the discard ratio then reports.
- **One addition to the derive API:** `Shape.cases`, the union's cases (`name`, `index`, `count`) with no value in hand. `Shape.of x` needs an `x`, and a generator has none; the shape constructs are listed at the head of `src/Derive.fs` (lines 1–9 in the main tree). Sketched:

```fsharp
derive Arbitrary =
  let arbitrary () : Gen<'self> =
    Gen (fun src ->
      let field f = Ok (Gen.draw (Gen.scale (fun n -> n / 2) (arbitrary ())) src)   // one copy per field, typed at it
      let built =
        match Shape.kind with
        | RecordKind -> Shape.build field
        | UnionKind ->
          let leaves = Shape.cases |> List.filter (fun c -> c.count = 0)
          let cases = if Source.size src = 0 && leaves <> [] then leaves else Shape.cases
          let c = Gen.draw (Gen.elements cases) src
          match Shape.buildCase c.name field with
          | Some r -> r
          | None -> Error "a case from Shape.cases"
      match built with
      | Ok v -> v
      | Error e -> panic e)
```

### Properties

```fsharp
testProperty     : string -> 'p -> Test                      when 'p : Outcome
testPropertyWith : PropertySettings -> string -> 'p -> Test  when 'p : Outcome
```

- **The parameters are the draws.** 0009's `Outcome` trait, which says what a test body may return (`unit`, `result<unit, 'e>`, `Task<unit>`, `Task<result<unit, 'e>>`), gains `bool` (`false` fails), `Prop` (below), and one structural rule: a function `'a -> 'r` is an `Outcome` when `'a : Arbitrary`, `'a : Show` and `'r : Outcome`; running it draws an `'a` from the current source and runs the result. So `fun (x: int) (xs: list<int>) -> …` is an `Outcome` by the rule twice, and any number of parameters works. The rule is built into `Typer.userImpl` next to the tuple rule (`src/Typer.fs:642–668` in the main tree; facts sheet §4), because an impl head must be a named type constructor and `->` isn't one.
- **Concrete types.** Generics are monomorphized, so a property's parameters must have concrete types: `fun x -> x + 0 = x` leaves `'a` with an `Arbitrary` requirement and nothing to resolve it, and the error says to annotate (*Diagnostics*). FsCheck substitutes `obj`; Z# has no equivalent.
- **A case:** `testProperty` is a `Case` of 0009's `Test`, so it has a path (`packet/round-trips`), runs in its own process, and is listed, filtered, focused and sequenced as any. Its body runs `runs` times (default 100) on fresh streams: `unit`, `true` or `Ok` passes the case; a panic (an `assert`, decision 5), `false` or an `Error` fails it, the `Error` shown through `Show` as 0009 says.
- **Settings** are a record with defaults ([DESIGN §2.3](../../DESIGN.md#23-default-fields-named-and-optional-arguments)), so `testPropertyWith { runs = 1000 } "name" …` names only what changes:

```fsharp
type PropertySettings =
  { runs: int = 100               // cases that must pass
    maxSize: int = 100            // the size the cases grow to
    maxDiscardRatio: int = 10     // discarded cases allowed per passing one, before the property fails
    seed: option<u64> = None      // None: a new seed per run, printed on failure
    shrink: bool = true
    shrinkTime: int = 10_000 }    // milliseconds the shrinker may spend on one failure
```

- **`Prop`:** `prop { }` is `Prop.Builder`; inside it `let!` draws a `Gen` and `do!` runs a check, so a property can draw as it goes, and discard, label and classify:

```fsharp
testProperty "division" (fun () ->
  prop {
    let! x = Gen.int
    let! y = Gen.int
    do! Prop.assume (y <> 0)                                   // discards the case; nothing after it runs
    do! Prop.classify (Math.abs y < 10) "small divisor"        // reported with the result
    return (x / y) * y + x % y = x
  })
```

| Function | Type | Meaning |
|---|---|---|
| `Prop.assume cond` | `bool -> Gen<unit>` | `false` discards the case; `Prop.Builder.bind` doesn't run the rest (FsCheck's `==>`) |
| `Prop.label name` | `string -> Gen<unit>` | names the case; a failure prints its labels |
| `Prop.classify cond name` | `bool -> string -> Gen<unit>` | counts the case under `name` when `cond` holds; the report prints the percentages |
| `Prop.collect value` | `'a -> Gen<unit>` when `'a : Show` | classifies by the value's text (`Prop.collect (List.length xs)`) |

`Prop` is `Prop of (Source -> Verdict)` with `Verdict = Passed | Failed of string | Discarded`.
`Prop.Builder.bind : Gen<'a> -> ('a -> Prop) -> Prop` draws, then checks the source's discard
flag before continuing, and `ret : 'r -> Prop when 'r : Outcome`. `fun () -> prop { … }` is an
`Outcome` by the function rule, since `unit` is `Arbitrary` and draws nothing. A passing
property reports its distribution: `ok   division (100 runs, 7 discarded; 23% small divisor)`,
so a generator that only makes trivial cases shows.

- **Discards:** `Gen.filter`'s retries and `Prop.assume` both discard; more than `maxDiscardRatio` discards per passing case fails the property with the ratio, which says to generate valid values instead of filtering invalid ones.

### Shrinking, failures and replay

Panics can't be caught (decision 5), and a case that panics ends the test's process, so the
shrinker lives in `zs test` and drives the test binary; the generators and the property stay
in the binary. The process budget is in *Performance*.

1. **The random phase,** in one process: `zs test` runs the leaf as 0009 does (`src/Main.fs:88–127` in the main tree: a temporary executable, `exe <i>` per test). The binary runs the cases with its seed; before each case it writes the case's index to `.zs-cache/failures/<path>.run`. A failure (a panic, `false`, an `Error`) ends the process with its message.
2. **Record:** the runner re-runs that one case (`--case 37 --record file`). Each case's stream is seeded from the property's seed and the case's index, so one case regenerates alone, and the binary appends each block, with its span boundaries, to the file as it draws it. The case fails again; the file holds the stream.
3. **Shrink:** the runner proposes candidate streams, shorter first, then lexicographically smaller (Hypothesis's order), and runs `exe <i> --replay candidate` for each: exit 134 (still fails) keeps it, exit 0 (passes) or an overrun (discarded) rejects it. The passes: delete a span (a list element, a field, a whole draw), zero a block, lower a block's bytes by binary search on its integer value, reorder two spans, replace a span with an earlier one; repeated until no pass makes progress or `shrinkTime` is spent. The shrinker never sees a value or a type, only blocks and spans, so it is written once (in `zs`, F# now and Z# after phase 11) and serves every generator and `Prop.model`'s command lists alike.
4. **Report:** the binary runs the final stream once more with `--show`: it prints each parameter as `name = value` through `Show` (a `Prop`'s labels too), the failure's message (an `assert`'s diff as 0009 prints it), the seed, the number of runs and shrink steps, and where the stream was saved.
5. **Save:** the stream is written to `.zs-cache/failures/<path>`, the property's path with characters outside letters, digits, `-`, `_` and `.` replaced by `-` (`packet/round-trips`), as a text file: one header line with the property's path, the seed, the compiler's version and the date, then the blocks in hex, one per line, span boundaries as indentation, so a failure is readable and diffable.
6. **Replay first:** `zs test` gives every property its saved streams before the random phase, one case each. One that fails again is reported as above (shrinking stops at once: the stream is already minimal). One that passes is deleted: the bug is fixed, or the generator changed and the bytes no longer mean the same case. The seed on a failure replays the whole run: `testPropertyWith { seed = Some 0x9c41e2a07b3d5f18 }`, or `zs test --seed 0x9c41e2a07b3d5f18`, which seeds every property from it and its path.
7. **Keeping a case for good:** `.zs-cache` isn't committed. A found case that should stay in the suite is a `test` next to the property, calling the same body: tests are values, and no `example` feature is needed.

### Stateful testing

`Prop.model` checks a system against a model with a sequence of commands: a union with a derived
`Arbitrary`, so the sequence is a `list<Command>` and shrinks as any list does, to the fewest
commands with the smallest arguments.

```fsharp
[<Derive(Arbitrary)>]
type Command = | Add of int * string | Remove of int | Find of int

let hashMapAgrees =
  testProperty "HashMap agrees with Map" (fun (commands: list<Command>) ->
    Prop.model commands
      { init = fun () -> (HashMap.empty, Map.empty)
        step = fun command (sys, model) ->
          match command with
          | Add (k, v) -> Ok (HashMap.add k v sys, Map.add k v model)
          | Remove k -> Ok (HashMap.remove k sys, Map.remove k model)
          | Find k ->
            let got, want = HashMap.tryFind k sys, Map.tryFind k model
            if got = want then Ok (sys, model) else Error $"Find {k}: HashMap gives {got}, the model {want}" })
```

- **`Prop.model : list<'c> -> Model<'c, 's, 'm> -> unit`,** with `Model` a record of `init : unit -> 's * 'm` and `step : 'c -> 's * 'm -> result<'s * 'm, string>`. It applies each command in turn; an `Error` fails the case (a panic with the message, decision 5) naming the commands so far, so the report reads `after [Add (1, "a"); Remove 1; Find 1]: Find 1: HashMap gives Some "a", the model None`.
- **Preconditions** are the generator's job (`Gen.filter`, or a `step` that returns `Ok` unchanged for a command that doesn't apply), not a flag per command.
- **First users** (track D): `HashMap` against `Map`; `Channel` against a queue, with `Channel.make n`'s capacity, `send`, `receive` and `close` as commands; the pool ([0008](0008-threads.md)'s spare threads) against a count of jobs that must complete, with commands that fork jobs and block them in channels.
- **The exit test:** a planted `HashMap` bug (a removal that leaves a stale entry) found and shrunk to the commands that show it.

### Fuzzing

`zs fuzz <path> [--time 60] [-- libFuzzer flags]` runs one property under libFuzzer. Nothing in
the property changes.

- **The build:** the test binary, built with `-fsanitize=fuzzer,address,undefined` through the host's clang. Host builds link with clang today (`src/Driver.fs:1877` in the main tree), and `--sanitize` adds `-fsanitize=address,undefined -g -DZS_NO_POOL` (lines 1786–1787; [guide: tools](../guide/10-tools.md)); the fuzz build adds `fuzzer`. libFuzzer brings `main`, so in place of the test `@main` (`src/Codegen.fs:3950–3958`, the switch over `zs_test_index()`) the compiler emits `LLVMFuzzerInitialize`, which runs the program's startup values once, and `LLVMFuzzerTestOneInput(data, size)`, which makes a `Source` over the bytes and runs the property's body once.
- **The bytes are the source.** Each draw reads from the input; an overrun returns, as a discarded case; `span<u8>`'s `Arbitrary` draws the rest of the input, so a property over raw bytes (`fun (bytes: span<u8>) -> ignore (Packet.parse bytes)`, [0003](0003-spans-and-slices.md)) is the parser fed the fuzzer's bytes with nothing in between. A typed property is structured fuzzing: libFuzzer mutates bytes, the generators decode them into `Packet`s that are always well-formed, and coverage guides the mutations toward the parser's branches (what Rust's `arbitrary` crate does for cargo-fuzz, here as the only generator there is).
- **A failure is a crash.** The fuzz build defines `ZS_FUZZ`, under which a panic takes the `abort()` path that `ZS_ABORT=1` takes today (`runtime/rt.c:44–47` in the main tree), so libFuzzer records it as a crash; `false` and `Error` abort the same way; the sanitizers report an out-of-bounds read or undefined behaviour as a crash too ([0011](0011-debug-info-profiles-traces.md)). libFuzzer writes `crash-<hash>` and stops.
- **Then the shrinker:** `zs fuzz` reads the crash's bytes, runs the property shrinker on them (*Shrinking*, with the sanitized test binary), saves the result under `.zs-cache/failures/<path>`, and prints the case as `zs test` would. `zs test` replays it first from then on, with no fuzzer. libFuzzer's own `-minimize_crash` works on bytes without the spans; the property shrinker is stronger and shared.
- **The corpus** lives in `.zs-cache/fuzz/<path>/`, so a second run resumes; `--time` is `-max_total_time`, and flags after `--` go to libFuzzer (`-max_len`, `-dict`, `-jobs`).
- **Host only.** libFuzzer and the sanitizer runtimes are clang's own for the host; `--target` (zig cc, `src/Driver.fs:1795`) is an error naming that.
- **The exit test:** a planted out-of-bounds read in a typed parser property, found within a minute.

### Order of implementation

1. **`Source`, `Gen`, `gen { }`, `Arbitrary`** with the Core impls and the derive (`Shape.cases` added to `Derive.fs`'s shape constructs), `testProperty` through the `Outcome` rule, the random phase in one process, `Gen.sample`. Needs 0009's `Test` and `Outcome`, and 0024's `Random`.
2. **Shrinking and replay:** record mode, the runner's shrinker over blocks and spans, `--replay`, `--show`, the failures directory, replay-first, the seed and `--seed`. Exit test: the planted even-number bug, shrunk to the smallest even case and reproduced from its file.
3. **`Prop`,** `prop { }`, `assume`, `label`, `classify`, `collect`, the distribution report and the discard ratio.
4. **`Prop.model`** and the `HashMap`, `Channel` and pool tests; the planted `HashMap` bug.
5. **`zs fuzz`:** the entry, the fuzz build, the corpus, crash to shrinker to failures; the planted out-of-bounds read.
6. **Microcontrollers,** once 0009's `zs test --target` runs tests under QEMU (*Compatibility*).

Each step keeps `./test.sh` green, with a test program per step under `tests/property/` (a
`.out` holding a planted failure's report, seed fixed) and a `tests/fuzz/` script wired into
`test.sh`'s host-only block, as facts sheet §14 describes for scripts.

## Drawbacks

- **A process per shrink step.** Decision 5 means the shrinker can't run in the failing process, so a failure costs a process start per candidate (about a millisecond on Linux, 0009, plus the program's startup values): hundreds of steps are a second or two, and `shrinkTime` caps the rest. A passing property pays nothing for it.
- **Shrinking is only as good as the encoding.** A generator that maps bytes carelessly (`Gen.map (fun n -> 1000 - n) (Gen.range 0 1000)`) shrinks toward 1000; "zero bytes mean the simplest value" is a convention to learn, with `Gen.sample` to check it. FsCheck's per-type shrinkers don't have this problem, and have the other one. Floats shrink by this encoding too: integers before fractions, which is the useful order most of the time, not Hypothesis's full treatment of floats.
- **Derived generators are naive.** `[<Derive(Arbitrary)>]` on `Email` makes random strings; a generator with the invariant is written by hand, as FsCheck users do. The derive covers the records and unions whose every value is valid, which is most of them.
- **More surface:** a trait, two builders, a settings record, a structural rule in `Outcome`, `Shape.cases`, a failures directory and a command. The rule and `Shape.cases` are the language's part; the rest is Core and `zs`.
- **Fuzzing needs clang's libFuzzer** on the host, and nothing is fuzzed under `--target`.

## Alternatives

- **FsCheck's type-directed shrinking:** `Arbitrary<'a>` carries `shrink : 'a -> seq<'a>`, so a value shrinks by its type regardless of the generator that made it: a filtered generator of even numbers shrinks to odd ones, a mapped one to values the map never produces, and `seq` is phase 10's. Not chosen: it loses invariants, which is the failure mode track D names.
- **QuickCheck's per-type `shrink` functions:** every hand-written generator wants a hand-written shrinker, and a mapped generator can't shrink unless the map is inverted by hand. Not chosen: the stream gives every generator its shrinker.
- **Hedgehog's rose trees** (integrated shrinking: a generator yields a value with a lazy tree of smaller ones): mapped and bound generators shrink with their invariants, as here, but `bind` re-generates the second draw from scratch at each step of the first, trees are lazy structures allocated per value and need `seq`, and a tree can't be saved, replayed or handed to a fuzzer. Not chosen: the stream does the same with a flat buffer, and that buffer is also the replay file and the fuzz input.
- **A separate fuzz harness** (cargo-fuzz's `fuzz_target!`, Go's `f.Fuzz`): a second kind of test with its own types and corpus, and no shrinking of its own. Not chosen: a property already is a function over bytes once its generators read bytes, so one engine serves both, and a crash becomes a property failure.
- **`Prop.model` as a trait** (FsCheck's `Command`, Hedgehog's `Machine`: `pre`, `run` and `post` per command type): more to write per command, for the same checks; a record of two functions covers the three first users. Not chosen for the first implementation; the API's final shape is an unresolved question.
- **`example` annotations** for found cases (Hypothesis's `@example`): the settings record would need the parameters' types. Not chosen: a `test` next to the property calling the same body does it with nothing new.
- **Doing nothing:** example tests only. The exit tests' planted bugs (an even-number case, a stale `HashMap` entry, an out-of-bounds read on a byte 10) are the bugs examples miss.

## Compatibility

- **Not a breaking change.** Everything is new, in Core's `Testing` (0009), which a program's own `Testing` module shadows; `gen { }` and `prop { }` are ordinary builders (decision 46).
- **An older compiler** has no `Testing`: `testProperty` is an unresolved name, `[<Derive(Arbitrary)>]` an unknown derive, and `Shape.cases` an unknown shape construct in a derive that uses it.
- **Compiled binaries:** none to consider; packages are source (decision 27). The test binary's `--case`, `--record`, `--replay` and `--show` arguments are between `zs test` and the binary it just built.
- **The library:** `Testing.Gen`, `Testing.Prop`, `Testing.Arbitrary` and `Testing.Source` in Core, as the ledger places them; `Random` as a type is Core's and `Random.shared` Std's (0024); `Outcome` gains `bool`, `Prop` and the function rule; the derive API gains `Shape.cases` (DESIGN §3.1's list grows by one line).
- **Microcontrollers:** a property is Core code and runs under 0009's `zs test --target cortex-m4` as any test: the random phase in one QEMU run, the failing case's index over semihosting, and shrinking as one QEMU run per candidate, so it is slower and `shrinkTime` matters more; `maxSize` is set lower where the heap is 8 KB (facts sheet §8). Fuzzing is host only.

## Pragmatics

### Diagnostics

| Situation | Error |
|---|---|
| a generic property | `testProperty "adds" needs concrete parameter types: 'a has no Arbitrary; annotate the parameter, as (fun (x: int) -> …)` |
| a parameter type without `Arbitrary` | `Email has no Arbitrary: write impl Arbitrary<Email>, or [<Derive(Arbitrary)>] on it` |
| a derive over a field without one | `Derive(Arbitrary) on Packet: field payload: Payload does not implement Arbitrary` |
| a parameter type without `Show` | `testProperty needs Show for Secret, to print a failing case: remove the opt-out, or impl Show<Secret>` |
| a body that isn't an `Outcome` | `testProperty's body must return unit, bool, a result, a Task or a Prop; this returns int` |
| a `prop { }` in a plain `test` | `prop { } needs testProperty: test runs its body once, with nothing to draw from` |
| a failure | `FAIL packet/round-trips: falsified after 12 runs, shrunk in 31 steps (seed 0x9c41e2a07b3d5f18)`, then `p = …`, the message, and `saved .zs-cache/failures/packet/round-trips; zs test replays it first` |
| too many discards | `FAIL division: 1,000 cases discarded for 90 passed (maxDiscardRatio 10): generate valid values instead of filtering them` |
| the shrinker's budget | after the report: `shrinking stopped after 10 s (shrinkTime); the case may not be the smallest` |
| a saved failure for a property that is gone | `.zs-cache/failures/packet/round-trips names no property; deleted` |
| a model's postcondition | `FAIL hashmap/model: after [Add (1, "a"); Remove 1; Find 1]: Find 1: HashMap gives Some "a", the model None` |
| `zs fuzz` on a plain test | `zs fuzz parser/parses: parser/parses is a test, not a property; zs fuzz takes a testProperty` |
| `zs fuzz` with `--target` | `zs fuzz runs on the host: libFuzzer and the sanitizers are clang's own; drop --target` |

### Tooling

- **`zs lsp`:** hover on `testProperty` shows its type with the requirements resolved at the call (`'p = int -> list<int> -> bool`, with `Arbitrary<int>` and `Arbitrary<list<int>>`); hover on a derived type lists its `Arbitrary` impl among the others; completion after `Gen.` and `Prop.` lists the tables above with their `///` docs; definition goes into Core's `Testing` sources, as it goes into `lib/core/Collections/List.zs` today (facts sheet §1). Diagnostics while editing: the "annotate" and "no Arbitrary" errors appear as the property is typed, since the checker resolves trait requirements with no build run.
- **Code lens:** 0009's "run" on a `testProperty` runs it; a "fuzz" lens isn't offered, since a fuzz run has no end.
- **Commands:** `zs test` gains `--seed`; `zs fuzz` is new. The MCP `test` tool (0009) returns a property's failure with the case and the seed, so an agent can replay it.
- **Debugging:** `zs test --debug <path>` (0009) on a property replays its saved failure under gdb, so the debugger stops in the one failing case.
- **The grammar:** nothing. `gen { }` and `prop { }` are computation expressions the tree-sitter grammar already has; there is no new syntax, and `zs fmt` and `zs doc` see nothing new.

### Performance

- **Existing code:** none. A program without properties has nothing of this in it, and `Testing` is linked only into test builds.
- **A passing property:** 100 cases in one process. A draw is a few bytes from the PCG and a copy into the record (estimate: tens of nanoseconds), so a case costs what its body costs; a list property's 100 cases run in milliseconds.
- **A failing one:** two extra processes (record and show) plus one per shrink step, 20–300 steps typically, capped by `shrinkTime`; in-process steps would need catchable panics, which decision 5 rules out.
- **The record:** a case's stream is hundreds of bytes, `maxSize` elements of a list at most, kept in a `Buffer<u8>`; the failures directory holds one file per failing property.
- **Fuzzing:** libFuzzer's loop (estimate: thousands of executions per second for a small parser under the sanitizers); the generators add one decode per execution.

### Scaling

Estimates for the dimensions that grow:

| Dimension | Typical | Upper bound |
|---|---|---|
| properties per program | 10–100 | 5,000 (the self-hosted compiler's suite), each a leaf of 0009's tree |
| runs per property | 100 | 1,000,000 (`runs`, under 0009's `--stress`) |
| bytes per case | 50–500 | 16 MB (a `span<u8>` under the fuzzer with `-max_len`) |
| draws per case | 10–1,000 | 100,000 (a list of records at `maxSize` 1,000); the record is linear in them |
| shrink steps per failure | 20–300 | what `shrinkTime` allows (estimate: 5,000 in 10 s) |
| commands in a model sequence | 10–100 | 1,000 |
| corpus files per fuzzed property | 100–1,000 | 100,000 (libFuzzer's, in `.zs-cache/fuzz`) |

### Culture-aware formatting and parsing

- **Invariant throughout.** Cases print through `Show` (decision 10): `1.5`, not `1,5`; strings with escapes for characters that don't print (`"\n"`, `"\u{1F600}"`), so a shrunk string is readable; seeds in hexadecimal; the failure file in hexadecimal, with no locale anywhere. `--seed` reads hexadecimal with or without `0x`.
- **`Gen.string` and `Gen.char`** draw Unicode scalars, ASCII first, so shrinking moves toward ASCII and a property over text meets `é`, `日` and `😀` without asking.

## Unresolved questions

1. **The shrinker's time budget:** 10 s per failure here (`shrinkTime`), spent on processes, then the best case so far with a note. The alternative is a step count (deterministic, the same on every machine), or no cap (Hypothesis has none, and runs in-process). A cap in time is what a programmer waiting at a terminal wants.
2. **`Prop.model`'s API:** a record of `init` and `step` here. The alternatives: a `Command` trait with `pre`, `run` and `post` per command type (FsCheck, Hedgehog), and parallel command sequences checked for a linearization (quickcheck-state-machine), which `Channel` and the pool would use. The record first; parallel sequences when the pool's tests ask for them.
3. **Coverage-guided generation without libFuzzer:** `zs test --guided`, keeping the cases that reach new regions of 0009's `--coverage` counters and mutating their streams, so guidance exists where libFuzzer doesn't (QEMU, and a CI without clang's runtimes). Not in the first implementation; `zs fuzz` on the host covers the exit test.
4. **`bool` bodies:** accepted here, since FsCheck's users write them; a `false` prints only the case, where an `assert` prints the diff. The alternative is to accept only `unit`, `result`, `Task` and `Prop`, and say so in the error.
5. **Generated functions** (QuickCheck's `Fun`): no `Arbitrary` for function types here; a property over a function takes a union of the functions it means. The alternative is a function generator built from a table over the argument's draws.

## History

- **2026-10-22:** drafted from track D's items 5 and 6, Hypothesis's byte-stream design, and Expecto's model as 0009 adopts it.
