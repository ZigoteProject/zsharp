# Z# on the host: performance and memory against C, Rust, Swift, Zig, OCaml and F#

**Question:** on a desktop x86-64 machine, how does Z# compare in speed and memory with C and
with the languages closest to it in design: Rust (no GC, monomorphization), Swift (reference
counting), Zig (C-level control), OCaml (ML semantics, a tracing GC) and F# (the syntax Z#
takes, on .NET's JIT and GC)?

**Answer:** Z# is in the group of languages compiled through LLVM. It is far ahead of Swift, the
other reference-counted language, and of F#, wherever a program allocates.
- **Arrays and floating point:** within 4% of C on `spectralnorm` and `nbody`, alongside Rust, Swift and Zig. F# ties on `nbody` and takes 1.26× on `spectralnorm`; OCaml takes 1.5–2.7×.
- **Allocation:** on the red-black tree, Z# is 1.07× C, 3.6× faster than Swift and 3.3× faster than F#, both running the same algorithm. On `binarytrees` it's 1.21× C, ahead of Rust (1.41×) and Swift (2.64×), and behind F# (1.07×), Zig's allocator (0.46×) and OCaml's GC (0.39×).
- **Calls with checked arithmetic:** `fib` is 2.04× C, like Swift (1.84×): these are the two languages that check integer overflow in release builds. C with the same checks (`-ftrapv`) takes 1.83×, so Z# is 1.12× of checked C. F# (1.44×) doesn't check.
- **Memory:** Z# uses C's peak memory on every program, `binarytrees` included. Swift's runtime adds 8 MB to every program, OCaml's GC uses about twice C's memory on the tree programs, and .NET starts at 26 MB and uses 2.7–4× C on them.

## Setup

| | |
|---|---|
| Machine | AMD Ryzen 7 PRO 8840U, 16 threads, 30 GB, Fedora 44 in the dev container (`./dev`) |
| Z# | `zs build` (default optimization), the compiler at the end of phase 5 |
| C | clang 22.1, `-O2`, and `-O2 -ftrapv` (signed overflow traps, as in Z#) |
| Rust | rustc 1.99.0, `--edition 2021 -C opt-level=3` |
| Swift | Swift 6.3.2, `-O` |
| Zig | Zig 0.16.0, `-O ReleaseFast` |
| OCaml | OCaml 5.4.0 with flambda, `ocamlopt -O3` |
| F# | F# 10 on .NET 10 (SDK 10.0.112), a `Release` build run with `dotnet`: tiered JIT and dynamic PGO, the default GC |
| Time | Wall clock, the best of 3 runs |
| Memory | Peak resident set size (GNU `time`), the lowest of the same 3 runs |
| Correctness | Each program's output at a small size must equal C's |
| Reproduce | `./dev bench/host/run.sh` |

## The programs

Each program is written as that language would normally write it (`bench/host/*`), and all of
them print the same result.

| Program | Size | Work | What it stresses |
|---|---|---|---|
| `fib` | 42 | recursive Fibonacci on 64-bit integers | calls, integer arithmetic |
| `binarytrees` | depth 18 | the Benchmarks Game: build and walk millions of small trees | allocating and freeing tiny objects |
| `nbody` | 20M steps | the Benchmarks Game: five bodies, arrays updated in place | float arithmetic, array writes |
| `spectralnorm` | 4000 | the Benchmarks Game: repeated matrix-vector products | float loops over arrays |
| `rbtree` | 1M keys | insert a million pseudo-random keys into a red-black tree, then look each up | tree updates, allocation, pointer chasing |

**How each language allocates:**

| Language | Allocation | Freeing | `rbtree` algorithm |
|---|---|---|---|
| Z# | unions on the RC heap | Perceus, at the last use | Okasaki's, persistent; unique nodes are reused in place |
| C | `malloc` | `free` | left-leaning red-black tree (Sedgewick), in place |
| Rust | `Box` (`malloc`) | at end of scope | left-leaning, in place |
| Swift | `indirect enum` (ARC) | ARC | Okasaki's, the same as Z# |
| Zig | `std.heap.smp_allocator` | `destroy` | left-leaning, in place |
| OCaml | GC minor heap | GC | Okasaki's, the same as Z# |
| F# | .NET's generational GC | GC | Okasaki's, the same as Z# |

## Results

**Time, seconds** (× C in parentheses; below 1, faster than C):

| Program | Z# | C | C `-ftrapv` | Rust | Swift | Zig | OCaml | F# |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fib | 0.953 (2.04×) | 0.467 | 0.853 (1.83×) | 0.486 (1.04×) | 0.860 (1.84×) | 0.559 (1.20×) | 1.147 (2.46×) | 0.673 (1.44×) |
| binarytrees | 1.374 (1.21×) | 1.137 | 1.173 (1.03×) | 1.604 (1.41×) | 3.006 (2.64×) | 0.524 (0.46×) | **0.443 (0.39×)** | 1.212 (1.07×) |
| nbody | 1.031 (0.96×) | 1.073 | 1.074 (1.00×) | **0.678 (0.63×)** | 1.294 (1.21×) | 1.253 (1.17×) | 1.633 (1.52×) | 1.044 (0.97×) |
| spectralnorm | **0.614 (0.97×)** | 0.631 | 0.644 (1.02×) | 0.674 (1.07×) | 0.644 (1.02×) | 0.640 (1.01×) | 1.720 (2.73×) | 0.792 (1.26×) |
| rbtree | 0.596 (1.07×) | 0.558 | 0.567 (1.02×) | 0.560 (1.00×) | 2.167 (3.88×) | **0.521 (0.93×)** | 0.984 (1.76×) | 1.959 (3.51×) |

**Peak memory, MB:**

| Program | Z# | C | C `-ftrapv` | Rust | Swift | Zig | OCaml | F# |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fib | 2.0 | 2.0 | 2.0 | 1.9 | 10.2 | 0.5 | 3.2 | 25.9 |
| binarytrees | 33.9 | 33.9 | 33.8 | 33.9 | 57.6 | 16.6 | 73.3 | 92.4 |
| nbody | 2.0 | 2.1 | 1.9 | 1.8 | 10.2 | 0.6 | 3.2 | 26.5 |
| spectralnorm | 1.9 | 2.1 | 2.1 | 1.9 | 10.3 | 0.6 | 5.4 | 27.5 |
| rbtree | 30.8 | 30.7 | 30.8 | 30.6 | 48.5 | 19.3 | 66.1 | 122.1 |

## What the numbers show

- **Reference counting, Z# against Swift:** the two languages run the same persistent red-black tree, and Z# is 3.6× faster with 37% less memory. On `binarytrees`, Z# is 2.2× faster. Several things combine here:
  - **Reuse:** Perceus writes a rebuilt node into the unique node it replaces, and inlining with re-matching lets it rebuild the whole path of an insert in place.
  - **Borrowing:** borrowed parameters and borrowed fields need no count traffic.
  - **Plain counts:** Z#'s reference counts are non-atomic, and Swift's are always atomic.
- **Against F#, the same programs on .NET:** F# is faster on `fib` (no overflow checks) and on `binarytrees`, where its trees die young and the GC frees them together. Where the data lives on, the GC pays more: the red-black tree keeps a million nodes alive, and each insert allocates a new path that the GC traces and moves into its older generations, while Z# rebuilds the path in place. Z# is 3.3× faster there, and needs a quarter of the memory. Plain loops are close: a tie on `nbody`, and Z# 1.29× faster on `spectralnorm`.
- **Against OCaml's GC:** OCaml is fastest on `binarytrees`. Its trees die young in the minor heap, so allocating is a pointer bump, and nothing is freed one by one. The cost is memory: OCaml has the highest peak on both tree programs after F#, at over twice Z#'s on both.
- **Allocators:** Zig's `smp_allocator` keeps no per-object header. That makes it fast and small on both tree programs, ahead of C and Rust, which both use `malloc`. Z# pays for `malloc` plus its own 8-byte count.
- **Smaller cells:** a union cell has a tag only when the union has more than one case with fields, and a case without fields is a static cell, not an allocation. A `binarytrees` node is the count and two pointers, 24 bytes, which `malloc` rounds up to the same 32 as C's 16-byte node. So Z# now needs exactly C's memory there (it needed 46% more), and runs 1.21× C instead of 1.31×.
- **Loops:** `spectralnorm` is a tie between the four LLVM languages (0.97–1.07×). On `nbody`, Z# is level with C, and copy-on-write arrays cost nothing because the writes are unique and the checks are hoisted.
- **Overflow checks:** `fib` is all calls and additions. Z# and Swift check every `+`, and Rust (release), Zig (`ReleaseFast`), OCaml and F# wrap silently. Plain C has no checks either, and with `-ftrapv` it takes 1.83× as long: the checks are the cost, and Z# is 1.12× of C that pays them too. The microcontroller suite shows the same ([microcontrollers.md](microcontrollers.md)). `-ftrapv` changes nothing on the other programs, whose time isn't in integer arithmetic.
- **Fixed memory cost:** .NET takes about 26 MB in every program and Swift's runtime libraries about 10 MB; Zig links no libc (0.6 MB), and Z#, C and Rust start at about 2 MB.

## What is left, and why

- **`fib`, 2.04× C:** these are overflow checks (DESIGN decision 4), which Swift pays too. `[<Wrapping>]` on the function removes them where wrapping is wanted. Against C with the same checks, it's 1.12×, which is what phase 5's exit test asks of it.
- **`binarytrees`, 1.21×:** this is `malloc` and `free` per node. `Arena.with` (phase V) would match Zig and OCaml for trees that die together.
- **`rbtree`, 1.07×:** the persistent algorithm against C's in-place one. Reuse already makes most inserts allocation-free.

## How the comparison could mislead

- **Different algorithms on `rbtree`:** Z#, Swift, OCaml and F# run Okasaki's persistent tree, and C, Rust and Zig update a left-leaning tree in place. Compare Z# with Swift, OCaml and F# for the language, and with C for the cost of writing it functionally.
- **Different allocators:** Zig's lead on the tree programs belongs to its allocator rather than to Zig. Zig with `std.heap.c_allocator` would allocate like C.
- **F# includes .NET's start:** each F# time includes starting the runtime and the JIT's warm-up, tens of milliseconds, which a long-running service pays once. Native AOT wasn't measured.
- **Optimization levels:** C is at `-O2`, and Rust is at `opt-level=3`, the default for a release build. Rust's lead on `nbody` (0.63×) may come partly from this. It hasn't been checked.
- **Overflow semantics differ:** Rust, Zig, OCaml and F# compute `fib` without overflow checks. Rust and Zig would trap only in debug or `ReleaseSafe` builds, F# only with `Checked` operators, and OCaml never does.
- **Wall-clock times:** the times come from a laptop CPU with frequency scaling, so differences under about 5% are noise, and absolute times move between runs (plain C's `fib` took 0.67 s in an earlier run and 0.47 s in this one). Compare columns within one table. For tracking Z# itself, `bench/host/run.sh --check` counts instructions, which is deterministic.
