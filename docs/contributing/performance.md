# Performance

What Z# promises about speed and memory, how it's measured, and what a change must do before it
may make something slower.

## What's promised

- **Allocation is predictable.** Z#'s own optimizations (borrowing, reuse, unboxing, list
  fusion) run in every build, so a debug build allocates what a release build does, and
  `[<NoAlloc>]` doesn't depend on `-O`.
- **Tail calls run in constant stack,** in every build.
- **No hidden runtime cost:** no collector pauses, no startup work for constants (they're in the
  image).
- **The compiler is fast and deterministic:** incremental, parallel, and the same bytes with one
  worker or many.

A change that breaks one of these changes the language's contract, not only a number.

## The gate

`bench/host` holds each benchmark in Z# and in C, Rust, Swift, Zig and OCaml. The suite runs:

```sh
./dev bench/host/run.sh --check        # Z#'s instruction counts against bench/host/baseline.txt
```

Instructions are counted by valgrind's cachegrind at a small input size, which is deterministic,
so the gate doesn't flicker. **A program needing more than 5% over its baseline fails the
suite.** The baseline's counts are Linux x86-64's; the check runs only there.

```sh
./dev bench/host/run.sh                # times and peak memory, as Markdown tables, every language
./dev bench/host/run.sh --update fib   # write new counts for the programs named
```

**When to `--update`:**

- after an **improvement**, so the gain is kept: update the programs that improved, in the
  commit that improves them;
- after a **deliberate cost**, such as a safety check that was missing (a Buffer's bounds check
  in a loop, after the security review). The commit message says what the cost buys and how
  much it is.

Never update to make a failure go away. A regression nobody chose is a bug: find the pass that
changed.

## Other benchmarks

| Directory | Measures |
|---|---|
| `bench/host` | kernels and small real programs against five languages; the gate |
| `bench/parallel`, `bench/simd` | scaling over cores; vector code against C |
| `bench/effects`, `bench/alt` | effect handlers; channel selection |
| `bench/mcu` | cycles and code size on the chips, against C |
| `bench/compile` | the compiler's own build times |
| `bench/echo/soak.sh` | an echo server under load for a long time. **Run it alone:** nothing else in the container, never during a suite |

Results worth keeping go into a dated report in [docs/reports](../reports/), with the machine,
the commit and the command, and are not edited later.

## Measuring a change

1. **Say what should change and by how much** before measuring.
2. **Count instructions first** (`--check`'s numbers): they don't depend on the machine's load.
   Then times, best of several runs, on a quiet machine.
3. **Look at allocations.** `Runtime.mallocs` in a program, `ZS_LEAKCHECK=1` at exit, the
   editor's allocation hints, and `[<NoAlloc>]` as a test that a path stays off the heap.
4. **Look at the code.** `--emit-llvm` for the IR, `ZS_DUMP_CORE` with it for the compiler's own
   IR after its passes, `ZS_DUMP_IR=<dir>` to keep every module's.
5. **Compare with C** where a benchmark has a C twin: with `-ftrapv`, since Z# traps on
   overflow.
6. **Build as users do:** `--release` (ThinLTO). `--profile-generate` and `--profile-use` for
   profile-guided builds.

## Writing an optimization

- **It's a pass over Core** with a stated input and output form; `ZS_CHECK_IR=1` checks the IR
  after each pass, and the suite runs with it.
- **It proves what it removes.** A bounds check, an overflow check or a reference count goes
  only where the pass shows it's redundant, about the right value
  ([security](security.md#the-checker-and-the-optimizer)).
- **It has a switch** while it's young (`ZS_NO_DECIDE=1`, `ZS_NO_SIMPLIFY=1`), so a wrong result
  can be pinned on it and the two outputs compared.
- **It's deterministic** and works a function at a time, so it runs on the pool.
- **Tests:** a program whose output proves the result is the same where the optimization applies
  and where it just misses; `./test.sh --release`; a benchmark that shows the gain, and the
  baseline updated.
- **The compiler's speed counts too.** A pass that slows every build needs a gain that pays for
  it; `bench/compile` measures.

## In the library

- Core's functions say what they allocate when it isn't obvious, and a pipeline that should fuse
  has a test that it does (`tests/iter/loops.sh` checks what a `for` costs).
- Prefer a span to a copy, and a `Buffer` to rebuilding an array in a loop.
- Known gap: `Seq` pipelines aren't fused into one loop as list pipelines are.
