# Glossary

The project's words, each with where it's defined in full. One name for one thing: use these
and no synonyms.

## The project

| Term | Means |
|---|---|
| **phase** | a numbered step of the main line in [ROADMAP.md](../../ROADMAP.md) (phase 11: self-hosting). A phase ends with its exit tests |
| **track** | work that runs beside the phases, by letter: **E** editors, **D** testing, profiling and debugging, **M** microcontrollers, **T** targets, **P** type providers, **S** the library, **K** packages, **G** the language's gaps. Items keep their numbers (`track S's item 6`) |
| **exit test** | a program or check in `tests/` that must pass for a phase or item to be done |
| **decision** | a numbered row in [DESIGN §13](../../DESIGN.md#13-decisions). Permanent; cited as `decision 74` |
| **proposal** | a design document written before a feature, `docs/proposals/NNNN-…`, cited by number (`0018`) |
| **design review** | where proposals are decided; the first, second and third are in the roadmap |
| **v1, v2, v3** | stages of the language (single-threaded; threads and SIMD; effects and self-hosting). Not release numbers |
| **flagship** | the Nucleo-F401RE firmware in `examples/nucleo`: the program that proves the microcontroller track |
| **deviation** | a place the compiler differs from the design, recorded in the specification |
| **after 0.7** | the roadmap's marker for what's designed but waits for a later release |

## Building the compiler

| Term | Means |
|---|---|
| **stage 0** | the earlier release that builds `src/`, pinned in `dev` ([development](development.md#stage-0)) |
| **generation** (gen 1, 2, 3) | the compiler built by stage 0, then by itself, then by that. Gen 2 and gen 3 must be the same bytes |
| **the bootstrap** | that check, `tests/bootstrap.sh` |
| **the suite** | everything `./test.sh` runs |
| **the dev container** | the podman image `./dev` runs commands in |
| **the build server** | a long-lived `zs` that builds reuse; `ZS_NO_SERVER=1` turns it off |
| **the pool** | the thread pool. In the compiler it runs parsing, checking and the passes; in a program, `Parallel` and `share` functions |
| **the driving thread** | the thread that owns the compiler's `Session` and merges the pool's results |
| **pin** | a version fixed in a file with a checksum or a commit: stage 0, LLVM, actions, the Zed grammar |

## The compiler's pipeline

In order ([src/ARCHITECTURE.md](../../src/ARCHITECTURE.md)):

| Term | Means |
|---|---|
| **Tree** | the lossless concrete syntax tree: every token, comments included. `zs fmt` and the editor work on it |
| **Ast** | the abstract tree the checker reads |
| **Infer** | type checking and inference, Hindley–Milner with effect rows |
| **Core** (the IR) | the compiler's typed intermediate language, between the checker and LLVM. Not the library tier of the same name |
| **Mono** | monomorphization: a copy of a generic function per type it's used at; the `Share` check runs here |
| **Evidence** | compiles effect handlers to evidence passing: a handler becomes a value passed to the code that performs |
| **Decide** | compiles `match` to decision trees |
| **Lift** | closure conversion and lambda lifting |
| **Rc** | inserts and optimizes reference counts (Perceus) |
| **Gen** | writes LLVM IR as text; clang compiles it, ThinLTO links |

## The language

| Term | Means |
|---|---|
| **Perceus** | the reference-counting scheme: counts inserted precisely, so a value is freed at its last use |
| **borrow** | a parameter the callee only reads, passed without touching its count |
| **reuse** | an object freed and allocated at once in the same shape is updated in place |
| **effect** | a set of operations a function may perform, declared with `effect`, shown in its type |
| **row** | the effects in a function's type, after `/`: `int -> string / Log` |
| **handler** | a `handle … with` that gives an effect's operations their meaning; `k` resumes the performer |
| **`Throw<E>`** | the effect for typed exceptions |
| **`Share`** | the trait of values that may cross threads: immutable, or `Atomic`, `Mutex`, `Channel` |
| **`share<F>`, `callback<F>`, `fnptr<F>`** | a function another thread may run; one C calls back; a C function pointer |
| **span** | a window onto an array's elements, without a copy |
| **`Buffer`** | the mutable array every name shares; an `array` is a value |
| **task** | a cold asynchronous computation, `task { }`, run on an event loop |
| **trait, impl, `dyn`** | type classes: the interface, its implementation for a type, a value of any implementing type |
| **the orphan rule** | an impl is written in its trait's package or its type's |
| **`unsafe`** | the expression form inside which raw pointers and unchecked operations compile |
| **panic** | the defined response to a bug: the program stops. Not catchable |
| **type provider** | a program the compiler runs to generate a module from a file: `import json "x.json"` |

## The library and targets

| Term | Means |
|---|---|
| **Prelude** | the names every program has unqualified (`lib/prelude.zs`) |
| **Core** (the library) | the tier that needs no operating system: on every target (`lib/core/`) |
| **Std** | the tier that needs one: files, processes, sockets, threads (`lib/std/`) |
| **host** | a target with an operating system; also the machine the compiler runs on |
| **chip** | a microcontroller target: `cortex-m4`, `cortex-m0plus` |
| **board** | a chip on a particular circuit board, with its memory map: `nucleo-f401` |
| **freestanding** | no operating system and no C library: the chips and `wasm32` |
| **semihosting, RTT** | how a chip's output reaches the developer: through the debugger's breakpoint (QEMU), or a ring in RAM a probe reads (a real board) |

## Packages and tools

| Term | Means |
|---|---|
| **package** | a folder with a `zs.toml`; a **project** is one you build |
| **`zs.lock`** | each git dependency's commit and file hash |
| **vendoring** | `zs vendor`: dependencies copied into `vendor/`, so builds need no network |
| **workspace** | several projects under a root `zs.toml`, sharing one lock |
| **`.zs-cache/`** | a project's build cache, checkouts (`deps/`), and what zs keeps per dependency (`pkgs/`) |
| **trust** (`--trust`) | permission for `zs lsp` or `zs mcp` to build and run a project's own code |
| **expect test** | a test whose expected value is a literal `zs test --update` can rewrite |
| **doc test** | an example in a `///` comment that the suite runs |
| **property** | a law checked over generated inputs; a failing case is **shrunk** to a small one and saved |
| **`.out`, `.err`, `.expected`** | a program's expected output; a compile error's expected text; a script's expected output |
