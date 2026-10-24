# Self-hosting: the Z# compiler against the F# compiler

**Question:** phase 11 (0020): can the compiler written in Z# (`src/`, `compiler/` before the
switch) replace the F# compiler? Every test passing under it, building itself to the same bytes,
and no slower and no bigger in memory than the F# compiler (0020's *Performance*).

**Answer:** yes. It passes everything the F# compiler did and builds itself to the same bytes. Built
from nothing it's faster than the F# compiler (the compiler itself: 14.90 s against 15.16 s debug,
45.60 s against 46.84 s release), and on every incremental build and every row of `bench/compile`,
with a quarter of the F# compiler's memory there and 57% of it debug and 88% release on itself. It
got there once its back half ran on every core (*From one thread to the pool*, below), and once
clang and code generation went as the F# compiler's had (*Closing the gap*): at the switch it took
2.4× the F# compiler's time on itself.

## Setup, 2026-10-24

| | |
|---|---|
| Machine | AMD Ryzen 7 PRO 8840U (8 cores, 16 threads), the dev container (`./dev`: Fedora 44, LLVM 23.1.4) |
| F# | the F# compiler of `v0.6`, published self-contained with ReadyToRun (`dotnet publish -c Release`), as 0020's targets name it |
| Z# | `src/` at the end of the phase, built `--release` by itself (gen 2), with its library and runtime beside it (`src/install.sh`) |
| Times | wall time of one run (`/usr/bin/time`), the two compilers measured in the same session; peak memory is the largest process's, clang's and the linker's included |

## Every test

| | F# | Z# |
|---|---:|---:|
| `./test.sh` (the Z# compiler: `--check-ir` on, `tests/bootstrap.sh` too) | 248 of 248 | 251 of 251 |
| `./test.sh --target aarch64-linux-musl` (qemu-user) | 201 of 201 | 201 of 201 |
| `bench/mcu` on a Cortex-M4 and a Cortex-M0+ (qemu-system-arm), 7 programs each | the same table | the same table |

Every result in `bench/mcu` is C's, and the two compilers' tables are the same bytes: the same
instruction counts, flash, heap and stack. Under the Z# compiler `tests/cache.sh` gives the F#
compiler's transcript (which modules a change checks again and compiles again, and each test
program's binary from the cache the same as from nothing), and `bench/host`'s instruction counts
are within 0.004% of the baseline the F# compiler set. `--check-ir` (`Core.Check` after each
pass: variables bound, join points and direct calls given their parameters' types, no type
variable after monomorphization) passes on every program. The last runs were in the container
without .NET, the F# compiler gone.

## The bootstrap

`src/` built `--release` from an empty cache, a module per source file (each module's own
functions and its copies of the library's as two LLVM modules, compiled in parallel, linked with
ThinLTO). At the switch, its back half on one thread:

| generation | built by | wall | peak memory |
|---|---|---:|---:|
| gen 2 | gen 1 (`compiler/` built by the F# compiler, a debug build) | 109 s | 1.15 GB |
| gen 3 | gen 2 | 81 s | 1.19 GB |
| gen 3, `ZS_WORKERS=1` | gen 2 | 123 s | 1.14 GB |

Gen 2, gen 3 and the one worker's gen 3 are the same bytes (`cmp`); `tests/bootstrap.sh` checks it
in every `./test.sh`, builds every generation from one copy of the tree taken at its start, and
keeps each generation's IR to name the first module that differs. With the back half on the pool,
a generation takes 46 s.

**The one difference:** in one run of the suite, the one worker's gen 3 differed from gen 3 under
the cores (gen 2 = gen 3 held). Another session was adding a case to `Derive.expand`
(`src/Infer/Derive.zs`, nine lines of code) during that run: its change wasn't in the tree when the
suite started and was when it ended, and the one worker's gen 3, built last from the live tree,
compiled it. No build differed in 33 since (3 whole bootstraps among them, under the cores and one
worker), ThreadSanitizer finds no race in the compiler building a 40-module program on 4 and 16
threads, nor memcheck an uninitialized read. The bootstrap's copy of the tree now keeps an edit
made meanwhile out of it.

## Speed and memory

**The compiler building itself** (`src/`, 27,815 lines, with `packages/`; from an empty cache three
times, the two compilers taking turns, then again and after a function added to `Commands.zs`
three times each: the medians, and the peak memory; "at the switch" is the Z# compiler with its
back half on one thread, against the F# compiler's `Release` build of the time):

| build | F# s | F# MB | Z# s | Z# MB | Z# at the switch s | F# then s |
|---|---:|---:|---:|---:|---:|---:|
| debug, nothing cached | 15.16 | 1274 | 14.90 | 721 | 43.96 | 17.95 |
| debug, again | 0.34 | 128 | 0.29 | 128 | 0.36 | 0.59 |
| debug, a function added | 0.65 | 171 | 0.43 | 128 | 0.65 | 1.20 |
| release, nothing cached | 46.84 | 1257 | 45.60 | 1104 | 86.32 | 50.22 |
| release, again | 0.48 | 252 | 0.42 | 242 | 0.53 | 0.74 |

**`bench/compile`** (a generated program of modules; each timed build after a change of its own):

| build | 10 modules F# | 10 modules Z# | 40 modules F# | 40 modules Z# |
|---|---:|---:|---:|---:|
| first (nothing cached) | 1.192 | 0.752 | 2.207 | 1.846 |
| again, unchanged | 0.091 | 0.048 | 0.114 | 0.085 |
| a function's body changed in the main file | 0.110 | 0.068 | 0.140 | 0.108 |
| a function's body changed in a module | 0.168 | 0.104 | 0.181 | 0.156 |
| a module's interface changed | 0.130 | 0.082 | 0.155 | 0.134 |
| without the cache | 0.496 | 0.325 | 1.459 | 1.013 |

Peak memory building the 40 modules from nothing: 316 MB under the F# compiler, 81 MB under the Z#
one.

**The front end** (`zs check-time`: parsing and checking a program and the library, best of
ten): `examples/simple.zs` 130 ms F#, 73 ms Z#; `tests/json.zs` 112 and 79; `examples/complex.zs`
114 and 74; the compiler itself (`src/Main.zs`) 929 and 1,002.

**0020's targets:** no slower than the F# compiler, on `bench/compile` from nothing and after a body
or a signature change, and on itself: met, on every row. Memory at most the F# compiler's: met (a
quarter on `bench/compile`, 57% of it debug and 88% release on itself). Itself from nothing in no
more than stage 0's time: half of it (stage 0, the 0.6 release, takes 93 s). A one-module change:
0.43 s. Startup: a check is the library's cache, 73 ms with it. Byte-identical whatever `ZS_WORKERS`
is: met. The per-function passes summed over their jobs within 10% of one thread: met against one
thread under the same load, on 2, 4 and 8 workers (26% less to 6% more); against one thread on an
idle chip, jobs that share nothing miss it too on this laptop (*What sharing costs*, below).

## Closing the gap

The compiler at the end of step 7 built itself from nothing within 2% of the F# compiler's time on
a quiet machine; with the laptop's other programs running it was a quarter slower (18.9 s against
14.9 s), where the F# compiler kept its time. Phase by phase, the same build (debug, from nothing,
ms; "before" is that compiler, "now" this one):

| phase | F# | Z# before | Z# now |
|---|---:|---:|---:|
| parse and check | 3,234 | 1,261 | 1,179 |
| monomorphize, inline, simplify, effects, decision trees | 1,600 | 1,095 | 1,101 |
| lift closures | 820 | 1,199 | 1,201 |
| borrowed parameters | 362 | 954 | 937 |
| reference counting | 769 | 850 | 786 |
| LLVM IR | 3,000 | 4,363 | 3,708 |
| clang | 4,524 | 6,695 | 4,162 |
| the rest (between those, and the link) | 1,654 | 1,749 | 1,754 |
| total | 15,964 | 18,165 | 14,829 |

Both compilers write the same IR (all 118 modules' files the same bytes), so clang's 2.2 s more
was how it ran: **in batches.** `Tools.runMany` started as many clangs as there are workers and
waited for the whole batch before the next, so a batch took as long as its biggest module (the
largest, `Infer/Exprs.zs`, is 14 MB of the 130) while the other cores idled. The F# compiler ran
them through `Array.Parallel.map`, a core taking the next module as soon as it's free; so does
the Z# compiler now, the biggest first.

**Code generation** wrote its text as the F# compiler's did, but without .NET's `StringBuilder`:
each instruction a string of its own (`" " + s + "\n"`), joined per function, per module and again
with the module's other parts, every join checking its UTF-8 again in `String.ofBytes`, and then the
word placeholders (`i_W`, `HDR1`) replaced by splitting the module into lines and replacing in each.
Under callgrind, building `bench/compile`'s 40 modules took 17.0 billion instructions: 8.5% of them
checking UTF-8 again, 12% replacing the placeholders. The code generator has a `StringBuilder` now
(each piece copied once, into storage that doubles), the placeholders are resolved in one pass that
copies what's between them whole, and `String.ofBytes` copies well-formed text whole after checking
it eight ASCII bytes at a time: 14.9 billion instructions after the placeholders, 12.6 billion with
the rest, and the IR the same bytes. Code generation is still 0.7 s behind the F# compiler's (its
jobs slow each other: *What sharing costs*), and lifting and borrowing 1.0 s together; the front
end's 2 s ahead makes up for them.

## From one thread to the pool

Step 6 put `Lift`, `Simplify`, `Decide` and `Rc` per function, code generation per LLVM module and
the library's parsing on the pool (`Array.Parallel.map`), each job with tables of its own. The
first run was slower than one thread: 38 s on 16 workers, 54 s on one, against 44 s at the switch.
Two things made it pay:

- **The runtime counted every allocation in three global counters**, an atomic add each, and a
  program with threads got its objects from malloc, not the pool: 600 million allocations from 16
  threads on one cache line, 314 s of CPU for a 38 s build. Each thread counts its own now (a
  cache line of its own, summed when read) and has a pool of its own (free lists and a chunk; an
  object goes on the list of the thread that frees it).

| workers | before: wall, CPU | after: wall, CPU | IR, after |
|---|---:|---:|---:|
| 1 | 54.2 s, 51 s | 43.3 s, 40 s | 13.7 s |
| 4 | | 27.7 s, 56 s | 6.6 s |
| 16 | 38.1 s, 314 s | 21.5 s, 112 s | 5.5 s |

- **The jobs share less** (0020's *Crossings move*): a code generation job owns the functions it
  defines, the module's others coming as signatures, and decodes a copy of the types of its own
  from one array of bytes (every job looks types up all the time: shared, their counts were
  atomic ones all the jobs waited on); a pass gets its list as an argument, not through a closure
  that keeps it; the module build walks each function's references once instead of once per
  module that reaches it. That took the build from 21.5 s to the 15.3 s above.

**What crosses shared** (`Runtime.marks ()` around each step of the compiler building itself):
lifting 10 thousand objects and code generation 49 thousand, the environment their jobs read;
`Simplify` 1.0 million, `Decide` 1.1 million and reference counting 0.8 million, which also mark
what their jobs do share (a callee's body inlined at several call sites, a library instance in
the copies of every module that uses it). Copying a job's input on its way in costs more than the
atomic counts it saves (tried on code generation: 1.3 s more).

## What sharing costs

0020's last target: the per-function passes, summed over their jobs, within 10% of one thread (no
atomic counts and no copies on a job's own tree). A probe build times each function's job and adds
it up per pass (a debug self-build, ms):

| | Lift | Simplify | Decide | Rc | code generation |
|---|---:|---:|---:|---:|---:|
| 1 worker | 1,235 | 440 | 306 | 3,169 | 7,528 |
| 2 workers | 1,310 (+6%) | 489 (+11%) | 349 (+14%) | 3,553 (+12%) | 9,053 (+20%) |
| 1 worker beside 1 load | 1,349 (+9%) | 490 (+11%) | 341 (+11%) | 3,523 (+11%) | 8,428 (+12%) |
| 2 workers against it | -3% | +0% | +2% | +1% | +7% |
| 4 workers | 1,419 (+15%) | 646 (+47%) | 437 (+43%) | 4,482 (+41%) | 14,254 (+89%) |
| 1 worker beside 3 loads | 1,684 (+36%) | 611 (+39%) | 426 (+39%) | 4,472 (+41%) | 10,598 (+41%) |
| 4 workers against it | -16% | +6% | +3% | +0% | +34% |
| 8 workers | 1,756 (+42%) | 875 (+99%) | 612 (+100%) | 6,487 (+105%) | 31,296 (+316%) |
| 1 worker beside 7 loads | 2,385 (+93%) | 896 (+104%) | 639 (+109%) | 6,364 (+101%) | 14,708 (+95%) |
| 8 workers against it | -26% | -2% | -4% | +2% | +113% |

Against one worker on an idle chip, two workers take 6–14% longer summed, but so does one worker
beside a single load that shares nothing (9–11%): the chip slows a job when its other cores are busy
(their clocks drop under all-core load, and they share the memory). One worker beside W−1 loads (a
core each, building and folding trees of its own, allocating as the passes do) is that same machine
with nothing shared, and against it the four passes summed on W workers take between 26% less and 6%
more, on 2, 4 and 8 workers: what the jobs share costs them nothing measurable, which is what the
target asks. As worded, against one worker on an idle chip, it can't hold on this laptop beyond one
worker: jobs that share nothing miss it too.

Code generation's jobs (per module, not per function, so outside the target) are the exception:
against the loaded worker they take 7%, 34% and 113% more on 2, 4 and 8 workers. They share the
environment (49 thousand objects marked) and write megabytes of text each; keeping big allocations
off `mmap` (each `munmap` interrupts every core the program runs on) changed nothing, so what does
cost them is the next thing to measure: it's the compiler's longest phase.

## What the port found

Running the same tests through a second implementation found bugs in the first, in the library
and in LLVM, all fixed:
- **`Map`, `Set` and `HashMap` equality** was the derived one, over the tree's shape and the
  buckets' order: two maps with the same entries added in another order compared unequal. They
  compare their entries now. The checked modules' cache found it: a restored module's sets
  differed from a checked one's.
- **`File.writeAllBytes`** wrote through `String.ofBytes`, which replaces each byte that isn't
  UTF-8 with U+FFFD, and `readAllBytes` read through text: binary files were corrupted.
- **A mutable variable assigned in an effectful lambda** lost its writes when Simplify didn't run
  (both compilers): it's boxed under a handler now when a lambda mentions it.
- **Range formatting** answered a no-op edit for a line already formatted: an F# slice was bound
  to `String.concat`'s result, not its argument. The session test meant to send a messy line never
  did (its `sed` missed the JSON-escaped quotes).
- **ThinLTO and `musttail`** (both compilers): LLVM 23 rejects a module after importing a callee
  from another module and inlining it at a `musttail` call, so neither compiler could build
  `compiler/` `--release`. A tail call into another LLVM module is a plain tail call in an
  optimized build now (LLVM makes it a sibling call all the same).
- **The object cache** (the Z# port): an object reused from the cache wasn't touched, so eviction,
  oldest first, could delete one the link was about to read.
- **`String.join`** was quadratic (writing the compiler's own IR took minutes), and a `--lib`
  header wrote a struct before the ones its fields hold.
- **The runtime's object counts** were global atomics every allocation of a program with threads
  waited on, and such a program had no pool (above).

## The front end and the checker (steps 2 and 3)

**Question:** 0020's second criterion, phase 11's gate: is a program of the compiler's shape,
written in Z#, within 1.5× of the F# compiler? It's measured on code the compiler keeps:
`compiler/src/Syntax/Lexer.zs` and `Parser.zs`, on 0019's tree, against the F# compiler's
lexer and parser over the same files; and the checker, `compiler/src/Infer/`, against `Typer` on
the same programs.

**Answer:** yes. The Z# lexer and parser, the AST included, take 0.6–0.9× the F# compiler's
time on the compiler's own sources and 1.0× over every `.zs` file in the repository. They make
the same tokens, the same tree and the same AST for all 303 files (`compiler/tests/lexer.sh`,
`parser.sh`, `ast.sh`), and the same first error for the files that have one.
- **First run:** 1.5× and 2.6×. The parser showed the F# compiler three inefficiencies, all
  fixed there (below), and with them the parser's state, a record of 22 fields passed to every
  function, stopped being copied field by field on each call.
- **The checker:** the whole of it (`Infer`, `Typer` ported, not a subset), checking a program
  and the library it uses, takes 0.8× the F# compiler's time (below). It gives the F# compiler's
  errors on 90 of the 93 `.err` tests (the other three are errors of passes after checking, and
  of `import c`) and checks 100 of the 105 programs with an `.out` cleanly (the other five import
  C): `compiler/tests/errors.sh`.

### Setup

| | |
|---|---|
| Machine | AMD Ryzen 7 PRO 8840U, 16 threads, Fedora 44 in the dev container (`./dev`) |
| Z# | `compiler/` built by the F# compiler (`zs build`: default optimization, ThinLTO with the runtime) |
| F# | the F# compiler's `Release` build on .NET 10, after one run for the JIT |
| What's timed | lexing and parsing, in process, after the files are read: the best of ten runs (`zs parse-time <files>` in both) |
| Files | `compiler/src` (20 files, 6,601 lines), and every `.zs` file under `tests`, `lib`, `examples`, `packages` and `compiler` that the F# parser takes (303 files, 17,289 lines; it stops at a file's first error) |

**What each makes:** the F# compiler's lexer and parser make tokens with their trivia, the AST,
the lossless tree (0019's F2) and the positions table. The Z# ones make tokens (a kind, an offset
and a length), the same lossless tree as a few arrays indexed by node ids, and the AST in the F#
compiler's shapes, its places token indices into the tree. Both parse each interpolated string's
holes, for their errors.

### Results

| Files | F# | Z# | Z# / F# |
|---|---|---|---|
| `compiler/src`, 6,601 lines | 47–69 ms | 42–43 ms | 0.6–0.9 |
| the repository, 17,289 lines | 115–121 ms | 117–121 ms | 1.0 |
| first run (the tree only), `compiler/src` | | | 1.5 |
| first run (the tree only), the repository | | | 2.6 |

With the tree only (the parser before it made the AST), the figures were 0.55–0.65 and 1.03.

### The checker

| Program (with the library, 6,600 lines) | F# | Z# | Z# / F# |
|---|---|---|---|
| `examples/simple.zs` | 107 ms | 84 ms | 0.79 |
| `tests/json.zs` | 105 ms | 87 ms | 0.83 |
| `examples/complex.zs` | 105 ms | 85 ms | 0.81 |
| `tests/modules/main.zs` | 97 ms | 83 ms | 0.85 |

`zs check-time file` in both: parsing and checking the library and the program, the best of ten
runs in process (the F# one after one for the JIT, with `ZS_NO_CACHE=1`).

The first build took 225–240 ms, 2.0–2.3×. Four changes brought it under the F# compiler's:
- **The built-in impls' sets were made at each use.** `hasBuiltinImpl`, which unification asks
  for every literal and trait, built the union of the number and vector types each time; the
  sets are values now.
- **The context was copied into closures.** A record of 74 fields captured by a lambda is 74
  words copied and as many counts incremented: the context is one heap cell now (a union of one
  case, with a property per field, so its uses read as before).
- **A field read through the cell copied the whole record.** `match c with Cx d -> d.globals`
  copies `d` out of the cell before reading the field; `Cx { globals = g } -> g` reads the one
  field. This was most of what was left (callgrind: 12% of instructions in the copy). The Z#
  code generator should read a field through the cell either way; until then, the pattern says
  which field.
- **Names were resolved again at each use.** `resolveName`, a dozen candidates tried against nine
  tables, runs several times per name; it's remembered for the declaration now.

### What the first run found

All three were in the F# compiler, which builds the first generation of `compiler/`; the Z#
compiler's passes take the same rules.
- **`Mono.reaching` was exponential on a large recursive group.** A walk that met a function it
  was inside of kept no answer for the functions it went through, so every walk went through the
  whole group again: the parser's expressions, one group of about 50 functions, didn't finish building in ten
  minutes. A walk now goes through a function once, and when it finds nothing, nothing is the
  answer for every function it went through. The build takes 5 seconds.
- **No copy propagation.** Inlining a call binds its parameters (`let p' = p`), and Simplify
  kept the alias, so a record parameter looked consumed and each caller dup'ed every field of
  the record to pass it. `let x = y` is now `y`.
- **Borrowing stopped at records and join points.** A record parameter whose uses are field
  reads is borrowed now (a read dups the field it reads), and so is a `ref` read and written
  through. A join point's parameter that every jump to it passes the same borrowed parameter of
  the function in is that parameter: Simplify and Decide give a join point all its body uses,
  the function's parameters too, and passing one there consumed it.

And one in the parser itself: its entry point is pure (`/ <>`). With an open row, its functions
were instances under the caller's `Report`, with a check after each call for an operation in
progress, though none performs one.

After the fixes, only the two functions that make a parser state own one; every other function
borrows it.
