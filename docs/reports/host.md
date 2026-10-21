# Z# on the host: performance and memory against C, Rust, Swift, Zig and OCaml

**Question:** on a desktop x86-64 machine, how does Z# compare in speed and memory with C and
with the languages closest to it in design: Rust (no GC, monomorphization), Swift (reference
counting), Zig (C-level control) and OCaml (ML syntax, a tracing GC)?

**Answer:** Z# is in the group of languages compiled through LLVM. It is far ahead of Swift, the
other reference-counted language, on allocation.
- **Arrays and floating point:** within 5% of C on `spectralnorm` and `nbody`, alongside Rust, Swift and Zig. OCaml is 1.6–2.9× C.
- **Allocation:** on the red-black tree, Z# is 1.11× C and 3.3× faster than Swift running the same algorithm. On `binarytrees` it's 1.49× C, ahead of Rust (1.64×) and Swift (3.05×), and behind OCaml's GC (0.45×) and Zig's allocator (0.68×).
- **Calls with checked arithmetic:** `fib` is 1.97× C, the same as Swift (1.92×). These are the two languages that check integer overflow in release builds.
- **Memory:** Z# uses the same peak memory as C, except with many tiny heap objects (`binarytrees`, +45%), where the 16-byte object header counts. Swift's runtime adds 8 MB to every program, and OCaml's GC uses about twice C's memory on the tree programs.

## Setup

| | |
|---|---|
| Machine | AMD Ryzen 7 PRO 8840U, 16 threads, 30 GB, Fedora 44 in the dev container (`./dev`) |
| Z# | `zs build` (default optimization), from the working tree at commit `8ca690c` |
| C | clang 22, `-O2` |
| Rust | rustc 1.99.0, `--edition 2021 -C opt-level=3` |
| Swift | Swift 6.3.2, `-O` |
| Zig | Zig 0.16.0, `-O ReleaseFast` |
| OCaml | OCaml 5.4.0 with flambda, `ocamlopt -O3` |
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

## Results

**Time, seconds** (× C in parentheses; below 1, faster than C):

| Program | Z# | C | Rust | Swift | Zig | OCaml |
|---|---:|---:|---:|---:|---:|---:|
| fib | 0.946 (1.97×) | 0.481 | 0.555 (1.15×) | 0.922 (1.92×) | 0.577 (1.20×) | 1.206 (2.51×) |
| binarytrees | 1.819 (1.49×) | 1.217 | 1.991 (1.64×) | 3.708 (3.05×) | 0.825 (0.68×) | **0.552 (0.45×)** |
| nbody | 1.178 (0.95×) | 1.235 | **0.775 (0.63×)** | 1.498 (1.21×) | 1.538 (1.25×) | 1.966 (1.59×) |
| spectralnorm | 0.750 (1.03×) | 0.730 | 0.783 (1.07×) | 0.760 (1.04×) | 0.749 (1.03×) | 2.099 (2.88×) |
| rbtree | 0.960 (1.11×) | 0.862 | 0.853 (0.99×) | 3.189 (3.70×) | **0.665 (0.77×)** | 1.216 (1.41×) |

**Peak memory, MB:**

| Program | Z# | C | Rust | Swift | Zig | OCaml |
|---|---:|---:|---:|---:|---:|---:|
| fib | 2.0 | 2.0 | 1.8 | 10.3 | 0.6 | 3.0 |
| binarytrees | 49.3 | 34.0 | 33.7 | 57.5 | 16.6 | 73.1 |
| nbody | 1.9 | 1.9 | 1.8 | 10.2 | 0.6 | 3.1 |
| spectralnorm | 2.1 | 2.0 | 1.9 | 10.2 | 0.6 | 5.6 |
| rbtree | 30.6 | 30.8 | 30.8 | 48.1 | 19.7 | 66.0 |

## What the numbers show

- **Reference counting, Z# against Swift:** the two languages run the same persistent red-black tree, and Z# is 3.3× faster with 36% less memory. On `binarytrees`, Z# is 2.0× faster. Several things combine here:
  - **Reuse:** Perceus writes a rebuilt node into the unique node it replaces.
  - **Borrowing:** borrowed parameters need no count traffic.
  - **Plain counts:** Z#'s reference counts are non-atomic, and Swift's are always atomic.
- **Against the GC:** OCaml is fastest on `binarytrees`. Its trees die young in the minor heap, so allocating is a pointer bump, and nothing is freed one by one. The cost is memory: OCaml has the highest peak on both tree programs, at 1.5× Z# on `binarytrees` and 2.2× on `rbtree`.
- **Allocators:** Zig's `smp_allocator` keeps no per-object header. That makes it the fastest and smallest on both tree programs, ahead of C and Rust, which both use `malloc`. Z# pays for `malloc` plus its own 16-byte header. A `binarytrees` node is 48 bytes for Z# against 32 for C, which is the +45% in peak memory.
- **Loops:** `spectralnorm` is a tie between the four LLVM languages (1.03–1.07×). On `nbody`, Z# is level with C, and copy-on-write arrays cost nothing because the writes are unique and the checks are hoisted.
- **Overflow checks:** `fib` is all calls and additions. Z# and Swift check every `+`, and Rust (release), Zig (`ReleaseFast`) and OCaml wrap silently. The checks roughly double the time. This matches the microcontroller measurement ([microcontrollers.md](microcontrollers.md)).
- **Fixed memory cost:** Swift's runtime libraries take about 10 MB in every program, Zig links no libc (0.6 MB), and Z#, C and Rust start at about 2 MB.

## What is left, and why

- **`fib`, 1.97×:** these are overflow checks (DESIGN decision 4), which Swift pays too. `[<Wrapping>]` on the function removes them where wrapping is wanted. Inlining at the Core level (phase 5) would cut the call overhead, but not the checks.
- **`binarytrees`, 1.49× and +45% memory:** this is `malloc` and free per node, plus the object header. Ways to close the gap:
  - **Smaller headers:** a header-free size class in the allocator, or a 32-bit count.
  - **Arenas:** `Arena.with` (planned) would match Zig and OCaml for trees that die together.
- **`rbtree`, 1.11×:** the persistent algorithm against C's in-place one. Reuse already makes most inserts allocation-free.

## How the comparison could mislead

- **Different algorithms on `rbtree`:** Z#, Swift and OCaml run Okasaki's persistent tree, and C, Rust and Zig update a left-leaning tree in place. Compare Z# with Swift and OCaml for the language, and with C for the cost of writing it functionally.
- **Different allocators:** Zig's lead on the tree programs belongs to its allocator rather than to Zig. Zig with `std.heap.c_allocator` would allocate like C.
- **Optimization levels:** C is at `-O2`, and Rust is at `opt-level=3`, the default for a release build. Rust's lead on `nbody` (0.63×) may come partly from this. It hasn't been checked.
- **Overflow semantics differ:** Rust, Zig and OCaml compute `fib` without overflow checks. Rust and Zig would trap only in debug or `ReleaseSafe` builds, and OCaml never does.
- **Wall-clock times:** the times come from a laptop CPU with frequency scaling, so differences under about 5% are noise. For tracking Z# itself, `bench/host/run.sh --check` counts instructions, which is deterministic.
- **The compiler in the working tree:** the run used the working tree at `8ca690c`, which included uncommitted changes to `src/Rc.fs`, `src/Driver.fs` and `src/Inline.fs`. Rerun on a clean tree before quoting the Z# column.
