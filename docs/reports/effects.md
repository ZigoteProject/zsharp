# Effect handlers: phase 10's measurements

Phase 10 built effect handlers (DESIGN §6.1, [proposal 0002](../proposals/0002-effect-handlers.md)):
effect rows on function types, compiled by evidence passing with yield bubbling. Three questions
were left to measurement: whether pure code is untouched, what generators cost, and whether
`Task` should move onto an `Async` effect. Release builds on the dev container's host (x86-64),
`Runtime.allocations` counting objects.

## Pure code

The phase's exit test: a function without effects compiles to the IR it had before. The 106
programs without effects (those with expected output in `tests/`, the benchmarks in `bench/` and
the programs in `examples/`) were built by the compiler before the phase (commit `fcfad3c`) and
after it: their LLVM IR (`--emit-llvm`, the whole program), their debug binaries and their release
binaries were all byte-identical, the echo server's included. Two things made the binaries so: the
yield state is defined by the programs that have effects, not by the runtime, and a function
generic only in its effects (`let apply (f: int -> int) x = f x`) is, as its pure instance, its
module's own, as a non-generic function is. After the soak's fix (below), the four that end a task
with `return!` differ (the echo server and client, `tests/task/cancel.zs` and `awaits.zs`); the
other 102 are still byte-identical. (`tests/lambda_block.zs` named a record field `handle`, a reserved word now, as DESIGN
§6.1 always said; renamed, it's the same program to both compilers.) A pure instance of an
effect-polymorphic function has the name it always had: an empty row isn't part of it.

## `Task` on an `Async` effect

`bench/effects/async.zs` runs the same work both ways: a million rounds of a wait for a ready
task (`Task.ret`) and one for a task that suspends (`Task.yield`, a turn of the event loop).
The `Async` handler resumes a ready task's result where `await` is performed (that clause's path
resumes last), and gives a pending task's work the resumption.

| | allocations, 10 rounds | allocations, 1,000,000 rounds | time, 1,000,000 rounds |
|---|---|---|---|
| `task { }` (phase 9's state machines) | 7 | 7 | 24 ms |
| `Async` effect | 80 | 7,000,010 | 61 ms |

- **A ready wait** costs neither anything: the effect's clause runs in place.
- **A wait that suspends** costs the effect 7 objects: the closures of the two functions waiting (the round of the `for` loop and its driver), the clause's closure and the first continuation, the resumption with its one-shot cell, and the callback given to the pending task. A coroutine's frame is allocated once per task, and a wait passes the frame itself.
- **Against the phase 6 spike** ([its report](effects-spike.md): 2 objects per suspending await): the spike's loop was one tail-recursive function written by hand, with a list of closures for a handler; here two functions wait, and the resumption is one-shot, through a cell.

**Decided (decision 72):** `Task` stays on state machines. Its benchmarks and
`tests/task/awaits.zs` (7 allocations for 10 and for 200,000 waits) are unchanged; a wait stays in
a task's own body.

## Generators

`bench/effects/seq.zs`: a million naturals from a `seq { }` through `Seq.filter`, `Seq.map` and
`Seq.sum`, against `List.init` through the same stages (which Mono fuses into one loop) and the
loop by hand, the best of 5 runs.

| | allocations | time |
|---|---|---|
| `seq { }` pipeline | 11 (none per element) | 2.96 ms |
| list pipeline, fused | 0 | 0.62 ms |
| loop by hand | 0 | 0.29 ms |

Each stage's clause resumes last, so it runs where the generator yields: nothing is captured, and
the 11 objects are the frames and clauses, once per pipeline. What a stage costs is an indirect
call through its frame per element, about 1 ns. `Seq.take 10` of the same million stops the
generator after the tenth element (56 allocations: the ten elements' list and the stages).
Fusing such a pipeline into one loop, as lists are, is ROADMAP track S's item 9.

## Microcontrollers

`tests/mcu/effects.zs` (a generator through `Seq.take` and `Seq.sum`, a `Throw` caught from inside
`Seq.fold`) on a Cortex-M0+ and M4 under QEMU: 39 allocations, a heap peak of 184 bytes, nothing
live at exit, 200 to 272 bytes of stack. The yield state is a global there (no threads).

## The benchmarks at the end of phase 10

Every program without effects compiles to the binary the compiler before the phase made (the
yield state lives in the programs that have effects, not in the runtime), so these measure the
same code as before, on the same machine (an AMD Ryzen 7 PRO 8840U laptop).

- **Host** (`bench/host`): Z# at 1.04 s on `fib` (2.14× C; the previous compiler's identical binary takes the same 1.03–1.04 s today, where phase 9's report has 0.86 s: the machine's state, not the code), `binarytrees` 0.34 s (0.31×), `nbody` 1.03 s (0.88×), `spectralnorm` 0.64 s (0.97×), `rbtree` 0.52 s (0.91×), with the same peak memory as phase 9's report. The instruction counts are within 5% of `bench/host/baseline.txt` (`./test.sh`).
- **SIMD** (`bench/simd`): Z# / C at 0.96, 0.98 and 1.00 on x86-64 (`dot`, `nbody`, `blur`), 1.00, 1.03 and 1.04 on aarch64 under qemu: within phase 8's 10%.
- **Parallel** (`bench/parallel`): mandelbrot 10.8× faster on 16 threads (C 10.5×), nbody 6.5× (C 6.5×); ThreadSanitizer reports nothing.
- **Microcontrollers** (`bench/mcu`, Cortex-M4 and M0+ at `-O2`): every instruction count, flash and heap figure is [the report's](microcontrollers.md).
- **Compile time** (`bench/compile/run.sh`, 10 modules and a main file, the median of two runs each):

| build | before (s) | after (s) | checking before (ms) | checking after (ms) |
|---|---:|---:|---:|---:|
| first (nothing cached) | 1.17 | 1.24 | | |
| unchanged | 0.22 | 0.22 | 78 | 78 |
| a body changed in the main file | 0.42 | 0.43 | 171 | 181 |
| a body changed in a module | 0.57 | 0.59 | 204 | 218 |
| a module's interface changed | 0.53 | 0.55 | 208 | 218 |
| without the cache | 0.91 | 0.95 | 341 | 373 |

  Checking a module takes 2–9% longer (a row on every function type, unified at every call), and
  the library has two modules more (`Seq`, `Throw`); a rebuild after a change, 1–4%.
- **The echo soak** (`bench/echo/soak.sh`): 10,000 connections for an hour, 33,141,097 round
  trips with none failed, and the server's memory the same 26,428 KB from the first minute to the
  last. The first run for the release found the server growing 170 MB a minute: since phase 9's
  state machines, a `return!` that ends a task waited for the task it names, so each connection
  kept a state machine per round trip. `return!` last now gives that task what waits for this one
  (DESIGN §6), as phase 6's builder did.
