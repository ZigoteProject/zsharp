# Self-hosting: the Z# compiler against the F# compiler

**Question:** phase 11 (0020): can the compiler written in Z# (`compiler/`) replace the F#
compiler? Every test passing under it, building itself to the same bytes, and no slower and no
bigger in memory than the F# compiler.

**Answer:** it passes everything the F# compiler does and builds itself to the same bytes. It's
faster wherever a build is incremental (the cache), at a third of the F# compiler's memory, and
starts in milliseconds where .NET takes a tenth of a second. Built from nothing it's slower:
2.4× on the compiler itself in a debug build. The F# compiler runs its passes and code generation
on every core, and the Z# one still one module after another: the parallel back half (0020's
"parallel on Z#'s own pool") is what closes that, and comes next (below).

## Setup, 2026-10-24

| | |
|---|---|
| Machine | AMD Ryzen 7 PRO 8840U (8 cores, 16 threads), the dev container (`./dev`: Fedora 44, LLVM 23.1.4) |
| F# | the F# compiler, `Release` on .NET 10 |
| Z# | `compiler/` built `--release` by itself, installed with its library and runtime beside it (`compiler/install.sh`; `./test.sh --zs <binary>` tests such a build) |
| Times | wall time of one run (`/usr/bin/time`); peak memory is the largest process's, clang's and the linker's included |

## Every test

| | F# | Z# |
|---|---:|---:|
| `./test.sh` (the Z# compiler: `--check-ir` on, `tests/bootstrap.sh` too) | 246 of 246 | 249 of 249 |
| `./test.sh --target aarch64-linux-musl` (qemu-user) | 201 of 201 | 201 of 201 |
| `bench/mcu` on a Cortex-M4 and a Cortex-M0+ (qemu-system-arm), 7 programs each | the same table | the same table |

Every result in `bench/mcu` is C's, and the two compilers' tables are the same bytes: the same
instruction counts, flash, heap and stack. Under the Z# compiler `tests/cache.sh` gives the F#
compiler's transcript (which modules a change checks again and compiles again, and each test
program's binary from the cache the same as from nothing), and `bench/host`'s instruction counts
are within 0.004% of the baseline the F# compiler set. `--check-ir` (`Core.Check` after each
pass: variables bound, join points and direct calls given their parameters' types, no type
variable after monomorphization) passes on every program.

## The bootstrap

`compiler/` built `--release` from an empty cache, a module per source file (each module's own
functions and its copies of the library's as two LLVM modules, compiled in parallel, linked with
ThinLTO):

| generation | built by | wall | peak memory |
|---|---|---:|---:|
| gen 2 | gen 1 (`compiler/` built by the F# compiler, a debug build) | 109 s | 1.15 GB |
| gen 3 | gen 2 | 81 s | 1.19 GB |
| gen 3, `ZS_WORKERS=1` | gen 2 | 123 s | 1.14 GB |

Gen 2, gen 3 and the one worker's gen 3 are the same bytes (`cmp`), and `tests/bootstrap.sh`
checks it in `./test.sh --zs`. Gen 3's build: parsing and checking 1.4 s, the passes 10 s
(lifting closures 2.2 s and borrowing 1.4 s the largest), LLVM IR 20 s, clang 21 s (125 objects,
in parallel), the ThinLTO link 26 s.

## Speed and memory

**The compiler building itself** (`compiler/`, 27,656 lines, with `packages/`; an empty cache, then
again, then after a function added to `Commands.zs`):

| build | F# s | F# MB | Z# s | Z# MB |
|---|---:|---:|---:|---:|
| debug, nothing cached | 17.95 | 1315 | 43.96 | 473 |
| debug, again | 0.59 | 127 | 0.36 | 128 |
| debug, a function added | 1.20 | 185 | 0.65 | 127 |
| release, nothing cached | 50.22 | 1346 | 86.32 | 1144 |
| release, again | 0.74 | 256 | 0.53 | 261 |

**`bench/compile`** (a generated program of modules; each timed build after a change of its own):

| build | 10 modules F# | 10 modules Z# | 40 modules F# | 40 modules Z# |
|---|---:|---:|---:|---:|
| first (nothing cached) | 1.641 | 0.926 | 2.800 | 2.519 |
| again, unchanged | 0.124 | 0.056 | 0.145 | 0.081 |
| a function's body changed in the main file | 0.144 | 0.073 | 0.169 | 0.104 |
| a function's body changed in a module | 0.203 | 0.119 | 0.229 | 0.151 |
| a module's interface changed | 0.169 | 0.097 | 0.199 | 0.130 |
| without the cache | 0.603 | 0.506 | 1.216 | 1.759 |

**The front end** (`zs check-time`: parsing and checking a program and the library, best of
ten): `examples/simple.zs` 129 ms F#, 81 ms Z#; `tests/json.zs` 117 and 90; `examples/complex.zs`
141 and 84; the compiler itself (`compiler/src/Main.zs`) 1,050 and 1,091.

**Where the time goes:** the Z# front end is as fast as the F# one, and its caches make every
incremental build faster. Built from nothing, the F# compiler's passes (`Decide`, `Lift`, `Rc`,
`Evidence`) map each function and its driver each module through `Array.Parallel.map` on .NET's
pool, and the Z# compiler does the same work on one thread: 20 s of LLVM IR in gen 3's build
alone, where the cores wait. Without the cache on 40 modules, the one row the F# compiler wins,
it's the same.

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
