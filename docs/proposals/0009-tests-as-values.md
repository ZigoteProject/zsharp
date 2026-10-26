# Proposal 0009: tests as values

| | |
|---|---|
| **Status** | Approved; items 1–3 and 7 built before phase 11 (`tests/ztest/`), the rest after |
| **Decided at** | track D's plan ([ROADMAP](../../ROADMAP.md#testing-profiling-and-debugging-d)): items 1–3 and 7 before phase 11, the rest after |
| **Builds** | track D: testing |
| **Rests on** | decisions 5 (panics), 10 (structural printing), 20 (derive, no macros), 33 (the lossless syntax tree) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §12](../../DESIGN.md#12-tooling) |
| **Related** | [0010 properties and fuzzing](0010-properties-and-fuzzing.md), [0019 the syntax tree](0019-syntax-tree.md) (`--update` edits literals), [0011 debug info, profiles and traces](0011-debug-info-profiles-traces.md) (coverage) |

- [x] Approved in principle
- [x] Discussion
- [ ] Implementation: steps 1–3 (tests as values, the runner, assertions that explain with `Diff`, expect tests and `--update`); step 4 after phase 11

## Summary

Expecto's model, which F# programmers know: a test is a value, so tests compose with ordinary
code. `test "parses" (fun () -> …)` is a `Test`, `testList "parser" [ … ]` groups them, and a
top-level value marked `[<Tests>]` is found by `zs test` statically. Each test still runs in
its own process, picked by its path, so a panic fails only it. Around it: assertions that
print both sides and the first difference, inline expect tests that `zs test --update`
rewrites in place, doc tests, benchmarks as values, stress runs, coverage through `llvm-cov`,
and tests under QEMU for microcontrollers. `[<Test>]` goes.

```fsharp
open Testing

[<Tests>]
let parser =
  testList "parser" [
    test "parses numbers" (fun () -> assert (parse "42" = Ok (Num 42)))
    test "reads a file" (fun () -> task { let! text = File.readAllTextAsync "data.txt"; assert (text <> "") })
    testList "cases" [ for (input, expected) in cases -> test input (fun () -> assert (parse input = Ok expected)) ]
    testSequenced "uses port 8080" [ test "listens" (fun () -> …); test "connects" (fun () -> …) ]
  ]
```

## Motivation

- **Attributes don't compose.** A `[<Test>]` function can't be made from data, grouped, focused, skipped or sequenced without more attributes. A value can: `List.map` over cases is a parameterized test with no feature.
- **Assertions explain nothing.** `assert (parse s = Ok expected)` fails with a line number; the programmer adds `println`s. Printing both sides and the first differing field is what Expecto's `Expect.equal` does with a message, and the compiler can do it from the expression.
- **Expectations drift.** A pretty-printer's expected output lives in a `.out` file to find; an inline expect test keeps it next to the code and updates it in place, as ppx_expect and insta do.
- **Phase 11's compiler** needs its tests in this form before it's written, so it's written once.

## Detailed design

### The `Test` type

In Core, module `Testing` (no OS needed to define a test; running needs `zs`):

```fsharp
type Test =
  | Case of name: string * run: (unit -> unit) * focus: Focus * sequenced: bool
  | Group of name: string * tests: list<Test> * focus: Focus * sequenced: bool
```

- **`test name body`** makes a `Case`. `body: unit -> 'r` where `'r` implements `Outcome`: `unit` (a panic fails), `result<unit, 'e>` with `'e: Show` (an `Error` fails with it shown), `Task<unit>` and `Task<result<unit, 'e>>` (run on the event loop). So `test` serves what Expecto spells `test`, `testTask` and a result-returning body, with no overloading (DESIGN §2.2).
- **`testList name tests`** groups. **`testSequenced name tests`** runs a group one test at a time, for tests that share a file or a port; the default is parallel.
- **Focus and pending:** `ftest`/`ftestList` mark focus (only focused tests run while any exist), `ptest`/`ptestList` skip and say so. `zs test --fail-on-focused` fails a run with any focus left, for CI.
- **Generated tests:** cases are data; `[ for c in cases -> test c.name (fun () -> …) ]` needs nothing more.
- **Properties:** `testProperty` ([0010](0010-properties-and-fuzzing.md)) is a `Case` too.

### Discovery and running

- **`[<Tests>]`** marks a top-level value of type `Test` (or `list<Test>`); the checker lists them as it lists `[<Test>]` functions today, with no reflection. A test build needs no `main`.
- **Paths:** `parser/cases/42`, from the names; `zs test parser/` runs those whose path starts with it, `zs test parses` those containing it.
- **Processes:** the test binary, given a path, runs that one leaf; given `--list`, prints the tree. `zs test` lists, then runs the leaves in parallel (a process each, as many as cores), sequenced groups one at a time, each with a timeout (60 s; `testWithTimeout 5000 "name" …` for one). A hang fails the test and names it. Output is captured and shown on failure.
- **`--summary`** lists every test with its time, slowest first.
- **`[<Test>]` goes:** the five files that use it move to values, and the guide's chapter is rewritten.

### Assertions that explain

- **`assert (a = b)`,** and `<>`, `<`, `<=`, `>`, `>=`, `Ok e`/`Some e` comparisons: the compiler rewrites an `assert` whose expression is a comparison into code that evaluates both sides once and, on failure, prints them through `Show` and, for records, unions, lists, arrays and maps, the first place they differ, with its path (`at .items.[2].name: "a" vs "b"`). A `Diff` built-in derive walks both values with `Shape.pair` (DESIGN §3.1); an operand without `Show` is printed as its source text.
- **Everywhere,** not only in tests: a failed `assert` in a program prints the same, as part of the panic message. The message is built only on failure, so a passing assert costs the comparison.

### Expect tests

- **`expect value """…"""`** compares `string value` (through `Show`) with the literal and fails with a diff. **`zs test --update`** runs the tests and rewrites each failing literal in the source through the lossless syntax tree ([0019](0019-syntax-tree.md)): the test binary reports the new text with the literal's position, which `expect` knows as `assert` knows its line.
- **Only a literal** can be updated; an `expect` on an expression is an error.

### Doc tests *(built in phase 12)*

A fenced `zsharp` block in a `///` comment is a doc test: compiled as a module that opens the documented module, run under `zs test --doc`, with lines of the form `// => text` checked against the output as inline expectations, and `--update` rewriting them. The test's path is the declaration's.

Built as written, `// =>` lines settling *Unresolved questions* 3: the block is `main`'s body, its `// =>` lines the lines it prints, in order; the program is written beside the package's main (so the documented file's module is named as the program names it) and removed after; `--update` puts what was printed where the first `// =>` line was. The library's examples run in `./test.sh`.

### Benchmarks *(after phase 11)*

- **`bench "name" (fun () -> …)`** and `benchList` are values of type `Bench`, found by `[<Benches>]`. **`zs bench [filters]`** warms up, then runs until the median's confidence interval is within 2% or a time cap, and reports median and interval. Results are saved in `.zs-cache/bench/`; a run compares with the last saved one and reports only changes beyond the noise.
- **`testFaster "name" fast slow`** is a `Test` that passes when `fast`'s interval lies below `slow`'s, so a performance claim ("reuse beats copying") can't regress silently.
- **Instruction counts:** `zs bench --instructions` counts instructions (Linux `perf_event`) instead of time, deterministic as `bench/host/run.sh --check` is.

### Stress, coverage, microcontrollers *(after phase 11)*

- **`zs test --stress 10m`** runs the tests in random order on every core, over and over for that long; with `ZS_LEAKCHECK=1` and `--sanitize=thread` it finds a growing leak, a race, a deadlock.
- **`zs test --coverage`** builds with LLVM's source-based coverage: the compiler emits `llvm.instrprof.increment` per region (functions, match cases, branches) and the coverage mapping for Z#'s source, as `--profile-generate` already emits profiling; after the run, `llvm-profdata merge` and `llvm-cov report` print lines and branches, match cases included, and `--html` writes a report.
- **`zs test --target cortex-m4`** builds one test image, runs each test under QEMU with the test's path as a semihosting argument, and reads results over semihosting; `--probe` runs on a board through probe-rs with RTT or semihosting.

### Order of implementation

1. `Test`, `test`, `testList`, `[<Tests>]`, paths, processes, timeouts, focus and pending, `testSequenced`; `[<Test>]` removed.
2. Assertions that explain, with the `Diff` derive.
3. Expect tests, once [0019](0019-syntax-tree.md) can rewrite a literal.
4. After phase 11: stress, doc tests, benchmarks, coverage, microcontrollers, in the order the roadmap gives.

## Drawbacks

- **A process per test** costs a few milliseconds each and runs the program's startup values in every one; a suite of thousands takes seconds in parallel. It's what gives isolation Expecto can't, and `testSequenced` keeps shared state possible.
- **`assert`'s rewrite** means `assert` isn't a plain function; its meaning (a panic on false) is unchanged, only its message grows.
- **`--update` writes source,** which a programmer must review as any change; a wrong expectation can be accepted by habit. Diffs in review catch it.
- **Two value types** (`Test`, `Bench`) and their lists; one tree would mix runs with timings.

## Alternatives

- **Attributes with parameters** (`[<Test("name")>]`, `[<Sequential>]`, xUnit's theories): each feature is an attribute; composition stays impossible.
- **A test class model** (NUnit, xUnit): no classes in Z#.
- **In-process parallel tests** (Expecto's default): faster, but a panic takes the runner down and `ZS_LEAKCHECK` can't attribute leaks; processes it stays.
- **Snapshot files** (insta's `.snap`, the repository's `.out` files): a file to find; inline is the point, and `.out` files remain for whole-program output tests in `tests/`.
- **gcov-style coverage from the C side:** the runtime isn't the subject; LLVM's source coverage maps Z#'s own regions.

## Compatibility

- **`[<Test>]` is removed:** a breaking change for the five files that use it (all in the repository) and for the guide. There are no users yet; this is why it's before phase 11.
- **`assert`** keeps its type and meaning.
- **The `Testing` module** is new in Core; a program with its own `Testing` module shadows it.

## Pragmatics

### Diagnostics

| Situation | Error |
|---|---|
| `[<Tests>]` on a value that isn't a `Test` | `[<Tests>] needs a Test or a list<Test>; this is int` |
| two leaves with one path | `two tests named parser/parses: names in a testList must differ` |
| focus left in CI | `zs test --fail-on-focused: 2 focused tests (parser/parses, …)` |
| `expect` on an expression under `--update` | `expect needs a string literal to update; this is a call` |
| a timeout | `FAIL parser/slow: no result after 60 s` |
| a failed comparison | `assert failed at parser.zs:12: parse s = Ok expected` then `left: Ok (Num 41)`, `right: Ok (Num 42)`, `differs at .Ok.Num: 41 vs 42` |

### Tooling

- **`zs test`** gains `--list`, `--summary`, `--fail-on-focused`, `--update`, `--stress`, `--coverage`, `--doc`, `--target`, `--probe`; `zs bench` is new.
- **The language server:** a code lens "run" on a `[<Tests>]` value and each `test` (later, track E), running `zs test <path>`; the MCP server gets a `test` tool that returns the results, so an agent runs the tests it changed.
- **Debugging:** `zs test --debug <path>` runs one leaf under gdb.

### Performance

- **A leaf:** a process start (about a millisecond on Linux) plus the program's startup values; the suite runs on every core.
- **Assertions:** the comparison as before; the message only on failure.
- **Coverage builds** are slower, as instrumented builds are; they're not the default.

### Scaling

| Dimension | Typical | Upper bound |
|---|---|---|
| leaves per program | 50–500 | 20,000 (the self-hosted compiler's suite), listed once and run across cores |
| nesting depth | 2–3 | 10 |
| cases generated from data | 10–100 | 10,000 per list |
| an expect literal | 1–30 lines | 1,000 lines (a dump), rewritten in place |

The runner is linear in the leaves; `--list` is one process.

### Culture-aware formatting and parsing

Printed values go through `Show`, which is invariant (`1.5`, not `1,5`), so expect literals and diffs are the same on every machine.

## Unresolved questions

1. **Expecto's names:** `test` with the `Outcome` trait here, against `testTask` and `testResult` as separate names (the roadmap's wording). The trait is one name fewer to learn; the names are what Expecto users type.
2. **`assert`'s rewrite scope:** the comparison at the top of the expression only (here), or also inside `&&`.
3. **Doc test syntax:** `// =>` lines (here), or the guide's convention of a `text` block after the example.
4. **Benchmark statistics:** a bootstrap interval of the median here; whether `testFaster` should require a minimum effect size.

## History

- **2026-10-23:** steps 1–3 built before `compiler/`. A test's body is wrapped by `Outcome.finish` into the `Case`'s `unit -> unit`; the test binary's entry is a function the checker adds for a file's `[<Tests>]` values (`$tests`, calling `Testing.Runner.main`), and `--list` prints path, focus, time limit and sequenced group. `assert`'s rewrite covers the comparison at the top only (unresolved question 2), shows an operand without `Show` as its text (`Syntax.exprText`), and the first difference's path comes from `Diff` (`.y: 4 vs 5`, `.[2]`, `.Some`). An expect test reports `zs-expect file:line`, the text and an end line on standard error; `--update` replaces the call's literal token, a raw string on lines of its own for text with a line break.
- **2026-10-22:** drafted from track D's plan and Expecto's model.
