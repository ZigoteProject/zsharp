# Testing

How Z# is tested, how to write a test that fits, and which tests a given change needs. Running
the suite and its modes: [development](development.md#the-test-suite).

## The idea

**A test is a program and what it must print.** There is no test framework for the compiler:
`test.sh` builds each program with the compiler under test, runs it, and compares the output,
byte for byte, with a file beside it. A feature is done when its **exit tests** pass
([ROADMAP](../../ROADMAP.md)), and a bug is fixed when a test that failed now passes.

Three properties make this work, and every test keeps them:

- **Exact.** The whole output is compared, so a test also catches what it wasn't written for.
- **Deterministic.** The same output on every run, machine and thread count.
- **Self-checking for memory.** The suite runs with `ZS_LEAKCHECK=1`: a leaked object is printed
  at exit, so a program that leaks fails its test.

## Kinds of test

| Kind | Files | Use it for |
|---|---|---|
| a program | `x.zs` + `x.out` | language and library behavior: the default |
| a compile error | `x.zs` + `x.err` | a diagnostic: its exact place and text |
| a script | `x.sh` + `x.expected` | a tool or anything with several steps: `zs fmt`, projects, the servers |
| a chip program | `tests/mcu/x.zs` + `x.expected` | bare metal, run under QEMU |
| a guide example | a `zsharp` block in `docs/guide` + the `text` block after it | what users are told works |
| a doc test | a `zsharp` block in a `///` comment, with `// => value` | a library function's example |
| a library test | `[<Tests>]` values run by `zs test` | the testing library itself, and projects' own tests |
| a property | `testProperty` with generators | laws over many inputs; a failing case is shrunk and saved |
| a fuzz target | `zs fuzz` (libFuzzer) | parsers and decoders of untrusted bytes |
| a benchmark gate | `bench/host` against `baseline.txt` | a performance regression ([performance](performance.md)) |

Prefer the first kind that can show the behavior. A script is slower and harder to read than a
program; a property is for a law, not for one example.

## Where tests live

```
tests/
  *.zs, *.out, *.err       the language and library, one behavior a file
  effects/ task/ parallel/ simd/ alt/ iter/ json/ units/ values/ modules/ nested/ cycle/
                           an area's programs
  cimport/ cexport/ chandle/ cthreads/   C interop, both ways
  mcu/                     programs for the chips (QEMU) and wasm32 (Node)
  project/                 projects and the package manager: fixtures and scripts
  lsp/ mcp/                scripted sessions against a transcript
  fmt/ cst/ debug/ backtrace/ stats/     zs fmt, the syntax tree, gdb and lldb, panics, build stats
  ztest/ property/ fuzz/ doctest/        zs test, properties, zs fuzz, doc tests
  providers/ security/ newcomer/         type providers, the review's regressions, first programs
  *.sh                     whole-tree checks: bootstrap, docs, reference, release, install, stress
```

Name a file for the behavior, not the bug number: `fold_edges.zs`, `err_neg_unsigned.zs`,
`process_wait.zs`. Compile-error tests start with `err_`.

## Writing a program test

```fsharp
// tests/hex_roundtrip.zs
let main () =
  let bytes = [| u8 0; u8 0xAB; u8 255 |]
  println (Hex.encode bytes)
  println (Hex.decode "00abff" = Some bytes)
  println (Hex.decode "0g")
  0
```

```sh
./dev bin/zs run tests/hex_roundtrip.zs          # read what it prints
./dev bash -c 'bin/zs run tests/hex_roundtrip.zs > tests/hex_roundtrip.out'
```

- **Small and whole.** One behavior, the fewest lines that show it, no helper modules unless
  modules are the point.
- **Print the edges,** not only the usual case: empty, one, the largest, the first invalid.
  What a function does on bad input is part of its behavior.
- **Read the output before saving it.** An expected file is a claim that the output is right.
  When a test fails after a change, read the difference and decide which side is wrong; never
  regenerate to make it pass.
- **Formatted and warning-free.** Tests are built `--strict` and checked by `zs fmt --check`
  (tests of parse errors aside).
- **No leaks,** or the leak report fails it. A test about a cycle on purpose says so.

## Writing a compile-error test

`x.err` is the compiler's message without the quoted source lines:

```
tests/err_neg_unsigned.zs:3:3: error: value of 'x': expected u8, got int: numbers don't convert on their own; write u8 x
```

One error a file unless the test is about reporting several. A new or changed rule needs both
sides: a program the rule rejects (`.err`) and the nearest program it accepts (`.out`).
Wording: [diagnostics](diagnostics.md).

## Writing a script test

For a tool, a project or a server. The script prints what it observed; `test.sh` compares that
with `.expected`.

- Work in `mktemp -d`, remove it in a `trap`; never write into the checkout.
- Print labelled, stable lines (`--- the archive`, then facts). Strip paths, times, process ids
  and addresses before printing.
- Put `timeout` on everything that could wait.
- Don't take a port from the range the system gives clients, and don't depend on the network:
  git dependencies are tested against a local repository (`tests/project/git.sh`).
- Add the check to `test.sh` beside its kind, with a comment saying what it proves, and a `skip`
  line with the reason where it can't run (Windows, a cross target). Don't edit `test.sh` while
  a suite runs.
- The servers are tested as sessions: requests sent, the transcript compared (`tests/lsp/`).

## Platform markers

A test that can't run in some mode has a marker file beside it holding the reason in one line,
which the `skip` message prints:

| Marker | Skipped |
|---|---|
| `x.host-only` | when cross-compiled and run under qemu-user or Wine |
| `x.plain-only` | under `--valgrind` and `--sanitize` (it measures the pool or the runtime's own counts) |
| `x.posix-only` | on Windows |
| `x.x86_64-only` | on other architectures |
| `x.windows.out` | not a skip: Windows's expected output, where it differs by design |

A marker is for a real limit of the platform. A test that fails somewhere for a reason nobody
understands is a bug to find, not a test to mark.

## What a change needs

| The change | Tests |
|---|---|
| a language feature | programs for each form; `.err` for each rule; the guide's examples; the grammar's corpus (`editors/tree-sitter-zsharp/test`); `zs fmt` on it |
| a checker rule or a safety check | the rejected and the accepted program; the same through generics, effects and tasks |
| an optimization | a program whose output proves the result unchanged, at the sizes where it applies and where it doesn't; `--release`; the benchmark gate |
| a library function | a program with its edges; a doc test; on Core, a run on a chip (`tests/mcu/`) when width or the heap matters |
| the C runtime | the program that reaches it; `--sanitize` and `--valgrind`; threads under `--sanitize=thread` |
| a parser of untrusted input | bounds (depth, length) as tests; a property or a fuzz target |
| a `zs` command, the package manager | a script under `tests/project/` or its tool's directory |
| the language server, MCP | a scripted session |
| a target or a board | its programs under QEMU or Node; the cross mode `--target` |
| a bug | the smallest program that showed it, failing before the fix |
| a security fix | the hostile input as a test, in `tests/security/` or beside its area |

## Whole-tree checks

Some properties belong to the tree, not to a program, and the suite checks them on every run:

- **The bootstrap** (`tests/bootstrap.sh`): `src/` built by the compiler under test, by that
  build, and by that one; the last two are the same bytes, with one worker and with every core.
- **Robustness:** programs broken at random give errors, never a crash, a panic or a hang of
  `zs check` or `zs fmt`. `tests/stress.sh` covers very long literals, long runs of statements
  and deep nesting.
- **Docs:** the guide's examples run; the reference is current; every public library name is
  documented.
- **Editors:** the grammar parses every program in the tree; the Zed queries and pin and the
  TextMate keywords agree with it ([editors](editors.md)).
- **Benchmarks:** instruction counts within 5% of the baseline (Linux x86-64).

## When a test fails

1. Run it alone and read the diff. The compiler prints every error, so read the first.
2. Is the new output right? Then the change is user-visible: update the expected file **and**
   the changelog, the guide and the spec with it.
3. Only in one mode? `--valgrind` and `--sanitize` failures are memory bugs even when the
   output is right. A failure on one platform is a platform difference to understand.
4. Now and then? It's a race or a time limit. Find it; don't retry it. Give a slow tool a
   bounded, generous time (`fuzz.sh` gives libFuzzer 300 s).
5. `bench/echo/soak.sh` runs alone: nothing else in the container, and not during a suite.

## Tests in Z# projects

What users write, and what `zs new` starts a project with:

```fsharp
open Testing

[<Tests>]
let tests =
  testList "greeting" [
    test "greets" (fun () -> assert (greeting "Z#" = "Hello, Z#!"))
  ]
```

`zs test` runs each test in a process of its own, so a panic fails one test. `--update` rewrites
a failing expect test's literal, `--coverage` and `--stress` do as named, `--target cortex-m4`
runs them on a chip under QEMU, and `zs bench` times the `bench` values among them. In full:
[the guide](../guide/10-tools.md) and [the Testing reference](../reference/Testing.md).
