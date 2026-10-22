# Z# on the host: performance and memory against C, Rust, Swift, Zig, OCaml and F#

**Question:** on a desktop x86-64 machine, how does Z# compare in speed and memory with C and
with the languages closest to it in design: Rust (no GC, monomorphization), Swift (reference
counting), Zig (C-level control), OCaml (ML semantics, a tracing GC) and F# (the syntax Z#
takes, on .NET's JIT and GC)?

**Answer:** Z# is in the group of languages compiled through LLVM: at C's speed or better on
every program but `fib`, whose overflow checks C doesn't make, and the fastest here at
allocating small objects. It's far ahead of Swift, the other reference-counted language, and
of F#.
- **Arrays and floating point:** at C's speed or better on `spectralnorm` (0.96×) and `nbody` (0.88×), alongside Rust, Swift and Zig. F# ties on `nbody` and takes 1.20× on `spectralnorm`; OCaml takes 1.4–2.6×.
- **Allocation:** on `binarytrees` Z# takes 0.26× C's time, ahead of every language here, OCaml's GC (0.38×) and Zig's allocator (0.46×) included. On the red-black tree it's 0.89× C, 4.3× faster than Swift and 3.7× faster than F#, both running the same algorithm.
- **Calls with checked arithmetic:** `fib` is 1.76× C, like Swift (1.76×): these are the two languages that check integer overflow in release builds. C with the same checks (`-ftrapv`) takes the same time as Z#.
- **Memory:** Z# needs C's peak memory on the programs without trees, and less than C on the two with them (26 MB against 34 and 31). Swift's runtime adds 8 MB to every program, OCaml's GC uses 2.5–2.8 times Z#'s memory on the tree programs, and .NET starts at 26 MB and uses 3.6–4.7× Z#'s on them.

## Setup

| | |
|---|---|
| Machine | AMD Ryzen 7 PRO 8840U, 16 threads, 30 GB, Fedora 44 in the dev container (`./dev`) |
| Z# | `zs build` (default optimization: ThinLTO with the runtime), the compiler at the end of phase 9 |
| C | clang 23.1 (LLVM's release), `-O2`, and `-O2 -ftrapv` (signed overflow traps, as in Z#) |
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
| Z# | unions on the RC heap: the runtime's pool | Perceus, at the last use | Okasaki's, persistent; unique nodes are reused in place |
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
| fib | 0.856 (1.76×) | 0.486 | 0.855 (1.76×) | **0.480 (0.99×)** | 0.857 (1.76×) | 0.557 (1.15×) | 1.140 (2.35×) | 0.673 (1.38×) |
| binarytrees | **0.307 (0.26×)** | 1.161 | 1.153 (0.99×) | 1.605 (1.38×) | 3.075 (2.65×) | 0.531 (0.46×) | 0.446 (0.38×) | 1.194 (1.03×) |
| nbody | 1.022 (0.88×) | 1.163 | 1.162 (1.00×) | **0.687 (0.59×)** | 1.285 (1.10×) | 1.257 (1.08×) | 1.638 (1.41×) | 1.045 (0.90×) |
| spectralnorm | **0.633 (0.96×)** | 0.657 | 0.671 (1.02×) | 0.677 (1.03×) | 0.650 (0.99×) | 0.639 (0.97×) | 1.715 (2.61×) | 0.791 (1.20×) |
| rbtree | 0.515 (0.89×) | 0.578 | 0.573 (0.99×) | 0.562 (0.97×) | 2.238 (3.87×) | **0.439 (0.76×)** | 0.926 (1.60×) | 1.901 (3.29×) |

**Peak memory, MB:**

| Program | Z# | C | C `-ftrapv` | Rust | Swift | Zig | OCaml | F# |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fib | 2.0 | 2.0 | 2.0 | 1.8 | 10.2 | 0.6 | 3.2 | 25.9 |
| binarytrees | 26.0 | 33.9 | 34.0 | 33.7 | 57.5 | 16.4 | 73.3 | 92.7 |
| nbody | 2.1 | 2.0 | 1.8 | 1.8 | 10.2 | 0.6 | 3.1 | 26.5 |
| spectralnorm | 2.2 | 2.0 | 2.1 | 2.1 | 10.4 | 0.6 | 5.8 | 27.2 |
| rbtree | 26.0 | 30.9 | 30.7 | 30.8 | 48.6 | 19.7 | 66.0 | 122.0 |

**At the end of phase 5,** before the pool, ThinLTO and the one-word header (the same machine, clang 22): `fib` 2.04× C (1.12× of checked C), `binarytrees` 1.21×, `nbody` 0.96×, `spectralnorm` 0.97× and `rbtree` 1.07×, with C's peak memory on every program.

## What the numbers show

- **The pool** (phase 9): objects up to 256 bytes come from free lists of 8-byte size classes, carved from 64 KB chunks, and a freed object goes back on its list. ThinLTO inlines both into the program, so allocating and freeing a node take a few instructions and no call. That's most of `binarytrees`' change from 1.21× C to 0.26×, and `rbtree`'s from 1.07× to 0.89×: C, Rust and Swift call `malloc` and `free` for every node.
- **Smaller objects:** the header is one word, a 32-bit count with the tag of a union's case and the pool's size class beside it, so the pool needs no word of its own before each object (malloc does). A `binarytrees` node is that word and two pointers, 24 bytes, where `malloc` gives C's 16-byte node 32. So Z# now needs 23% less memory than C there, and 16% less on the red-black tree.
- **Reference counting, Z# against Swift:** the two languages run the same persistent red-black tree, and Z# is 4.3× faster with 46% less memory. On `binarytrees`, Z# is 10× faster. Several things combine here:
  - **Reuse:** Perceus writes a rebuilt node into the unique node it replaces, and inlining with re-matching lets it rebuild the whole path of an insert in place.
  - **Borrowing:** borrowed parameters and borrowed fields need no count traffic.
  - **Plain counts:** Z#'s reference counts are non-atomic (in a program without threads), and Swift's are always atomic.
  - **The pool,** where Swift calls `malloc`.
- **Against F#, the same programs on .NET:** F# is faster on `fib` (no overflow checks). Elsewhere Z# leads: 3.9× on `binarytrees`, whose trees die young and which .NET's GC handles well, and 3.7× on the red-black tree, which keeps a million nodes alive while each insert allocates a new path that the GC traces and moves into its older generations, where Z# rebuilds the path in place. F# needs 3.6–4.7× Z#'s memory on both. Plain loops are close: a tie on `nbody`, and Z# 1.25× faster on `spectralnorm`.
- **Against OCaml's GC:** OCaml's trees die young in the minor heap, so allocating is a pointer bump and nothing is freed one by one: it was the fastest on `binarytrees` until the pool. Z# is now 1.45× faster there, with 35% of OCaml's memory.
- **Allocators:** Zig's `smp_allocator` keeps no per-object header either, and is the smallest on both tree programs. On `rbtree` Zig runs C's in-place algorithm, the fastest here.
- **Loops:** `spectralnorm` is a tie between the four LLVM languages (0.96–1.03×). On `nbody`, Z# is ahead of C in this run, and copy-on-write arrays cost nothing because the writes are unique and the checks are hoisted.
- **Overflow checks:** `fib` is all calls and additions. Z# and Swift check every `+`, and Rust (release), Zig (`ReleaseFast`), OCaml and F# wrap silently. Plain C has no checks either, and with `-ftrapv` it takes exactly Z#'s time: the checks are the cost. The microcontroller suite shows the same ([microcontrollers.md](microcontrollers.md)). `-ftrapv` changes nothing on the other programs, whose time isn't in integer arithmetic.
- **Fixed memory cost:** .NET takes about 26 MB in every program and Swift's runtime libraries about 10 MB; Zig links no libc (0.6 MB), and Z#, C and Rust start at about 2 MB.

## What is left, and why

- **`fib`, 1.76× C:** these are overflow checks (DESIGN decision 4), which Swift pays too; C with them takes the same time. `[<Wrapping>]` on the function removes them where wrapping is wanted.

## How the comparison could mislead

- **Different algorithms on `rbtree`:** Z#, Swift, OCaml and F# run Okasaki's persistent tree, and C, Rust and Zig update a left-leaning tree in place. Compare Z# with Swift, OCaml and F# for the language, and with C for the cost of writing it functionally.
- **Different allocators:** Z#'s and Zig's leads on the tree programs belong to their allocators. Zig with `std.heap.c_allocator` would allocate like C, and so would Z# without its pool (`ZS_NO_POOL`, as under valgrind). The pool also keeps its chunks until the program ends, where `malloc` may give memory back.
- **Whole-program optimization:** Z# links with ThinLTO, which inlines the runtime's allocation functions into the program. The other languages are built as each would normally be, without LTO.
- **F# includes .NET's start:** each F# time includes starting the runtime and the JIT's warm-up, tens of milliseconds, which a long-running service pays once. Native AOT wasn't measured.
- **Optimization levels:** C is at `-O2`, and Rust is at `opt-level=3`, the default for a release build. Rust's lead on `nbody` (0.63×) may come partly from this. It hasn't been checked.
- **Overflow semantics differ:** Rust, Zig, OCaml and F# compute `fib` without overflow checks. Rust and Zig would trap only in debug or `ReleaseSafe` builds, F# only with `Checked` operators, and OCaml never does.
- **Wall-clock times:** the times come from a laptop CPU with frequency scaling, so differences under about 5% are noise, and absolute times move between runs (plain C's `fib` took 0.67 s in an earlier run and 0.49 s in this one, and C's `nbody` 1.07 s at the end of phase 5 and 1.16 s now). Compare columns within one table. For tracking Z# itself, `bench/host/run.sh --check` counts instructions, which is deterministic.
