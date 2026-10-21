# Z# on the host: performance and memory against C, Rust, Swift, Zig and OCaml

**Question:** on a desktop x86-64 machine, how does Z# compare in speed and memory with C and
with the languages closest to it in design: Rust (no GC, monomorphization), Swift (reference
counting), Zig (C-level control) and OCaml (ML syntax, a tracing GC)?

**Answer:** Z# is in the group of languages compiled through LLVM. It is far ahead of Swift, the
other reference-counted language, on allocation.
- **Arrays and floating point:** within 5% of C on `spectralnorm` and `nbody`, alongside Rust, Swift and Zig. OCaml is 1.5–2.7× C.
- **Allocation:** on the red-black tree, Z# is 1.10× C and 3.8× faster than Swift running the same algorithm. On `binarytrees` it's 1.31× C, ahead of Rust (1.41×) and Swift (2.71×), and behind OCaml's GC (0.37×) and Zig's allocator (0.45×).
- **Calls with checked arithmetic:** `fib` is 2.08× C, like Swift (1.88×): these are the two languages that check integer overflow in release builds. C with the same checks (`-ftrapv`) takes 1.87×, so Z# is 1.11× of checked C.
- **Memory:** Z# uses the same peak memory as C, except with many tiny heap objects (`binarytrees`, +46%), where the 16-byte object header counts. Swift's runtime adds 8 MB to every program, and OCaml's GC uses about twice C's memory on the tree programs.

## Setup

| | |
|---|---|
| Machine | AMD Ryzen 7 PRO 8840U, 16 threads, 30 GB, Fedora 44 in the dev container (`./dev`) |
| Z# | `zs build` (default optimization), the compiler at commit `63850ee` |
| C | clang 22.1, `-O2`, and `-O2 -ftrapv` (signed overflow traps, as in Z#) |
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

| Program | Z# | C | C `-ftrapv` | Rust | Swift | Zig | OCaml |
|---|---:|---:|---:|---:|---:|---:|---:|
| fib | 1.381 (2.08×) | 0.665 | 1.242 (1.87×) | 0.705 (1.06×) | 1.249 (1.88×) | 0.817 (1.23×) | 1.648 (2.48×) |
| binarytrees | 2.192 (1.31×) | 1.671 | 1.652 (0.99×) | 2.349 (1.41×) | 4.527 (2.71×) | 0.754 (0.45×) | **0.621 (0.37×)** |
| nbody | 1.486 (0.95×) | 1.571 | 1.572 (1.00×) | **1.005 (0.64×)** | 1.861 (1.18×) | 1.840 (1.17×) | 2.368 (1.51×) |
| spectralnorm | 0.916 (0.98×) | 0.930 | 0.926 (1.00×) | 0.982 (1.06×) | 0.949 (1.02×) | 0.938 (1.01×) | 2.470 (2.66×) |
| rbtree | 0.756 (1.10×) | 0.688 | 0.682 (0.99×) | 0.677 (0.98×) | 2.906 (4.22×) | **0.588 (0.85×)** | 1.148 (1.67×) |

**Peak memory, MB:**

| Program | Z# | C | C `-ftrapv` | Rust | Swift | Zig | OCaml |
|---|---:|---:|---:|---:|---:|---:|---:|
| fib | 1.9 | 2.0 | 2.0 | 1.9 | 10.2 | 0.5 | 3.2 |
| binarytrees | 49.5 | 33.8 | 33.9 | 33.8 | 57.5 | 16.6 | 73.3 |
| nbody | 1.8 | 2.0 | 1.9 | 1.8 | 10.1 | 0.6 | 3.1 |
| spectralnorm | 2.1 | 2.1 | 2.1 | 1.9 | 10.1 | 0.6 | 5.7 |
| rbtree | 30.8 | 31.1 | 30.9 | 30.7 | 48.8 | 19.6 | 66.0 |

## What the numbers show

- **Reference counting, Z# against Swift:** the two languages run the same persistent red-black tree, and Z# is 3.8× faster with 37% less memory. On `binarytrees`, Z# is 2.1× faster. Several things combine here:
  - **Reuse:** Perceus writes a rebuilt node into the unique node it replaces, and inlining with re-matching lets it rebuild the whole path of an insert in place.
  - **Borrowing:** borrowed parameters and borrowed fields need no count traffic.
  - **Plain counts:** Z#'s reference counts are non-atomic, and Swift's are always atomic.
- **Against the GC:** OCaml is fastest on `binarytrees`. Its trees die young in the minor heap, so allocating is a pointer bump, and nothing is freed one by one. The cost is memory: OCaml has the highest peak on both tree programs, at 1.5× Z# on `binarytrees` and 2.1× on `rbtree`.
- **Allocators:** Zig's `smp_allocator` keeps no per-object header. That makes it fast and small on both tree programs, ahead of C and Rust, which both use `malloc`. Z# pays for `malloc` plus its own 16-byte header. A `binarytrees` node is 48 bytes for Z# against 32 for C, which is the +46% in peak memory.
- **Loops:** `spectralnorm` is a tie between the four LLVM languages (0.98–1.06×). On `nbody`, Z# is level with C, and copy-on-write arrays cost nothing because the writes are unique and the checks are hoisted.
- **Overflow checks:** `fib` is all calls and additions. Z# and Swift check every `+`, and Rust (release), Zig (`ReleaseFast`) and OCaml wrap silently. Plain C has no checks either, and with `-ftrapv` it takes 1.87× as long: the checks are the cost, and Z# is 1.11× of C that pays them too. The microcontroller suite shows the same ([microcontrollers.md](microcontrollers.md)). `-ftrapv` changes nothing on the other programs, whose time isn't in integer arithmetic.
- **Fixed memory cost:** Swift's runtime libraries take about 10 MB in every program, Zig links no libc (0.6 MB), and Z#, C and Rust start at about 2 MB.

## What is left, and why

- **`fib`, 2.08× C:** these are overflow checks (DESIGN decision 4), which Swift pays too. `[<Wrapping>]` on the function removes them where wrapping is wanted. Against C with the same checks, it's 1.11×, which is what phase 5's exit test asks of it.
- **`binarytrees`, 1.31× and +46% memory:** this is `malloc` and free per node, plus the object header. Ways to close the gap:
  - **Arenas:** `Arena.with` (phase V) would match Zig and OCaml for trees that die together.
  - **Smaller headers:** one word instead of two (phase 9).
- **`rbtree`, 1.10×:** the persistent algorithm against C's in-place one. Reuse already makes most inserts allocation-free.

## How the comparison could mislead

- **Different algorithms on `rbtree`:** Z#, Swift and OCaml run Okasaki's persistent tree, and C, Rust and Zig update a left-leaning tree in place. Compare Z# with Swift and OCaml for the language, and with C for the cost of writing it functionally.
- **Different allocators:** Zig's lead on the tree programs belongs to its allocator rather than to Zig. Zig with `std.heap.c_allocator` would allocate like C.
- **Optimization levels:** C is at `-O2`, and Rust is at `opt-level=3`, the default for a release build. Rust's lead on `nbody` (0.64×) may come partly from this. It hasn't been checked.
- **Overflow semantics differ:** Rust, Zig and OCaml compute `fib` without overflow checks. Rust and Zig would trap only in debug or `ReleaseSafe` builds, and OCaml never does.
- **Wall-clock times:** the times come from a laptop CPU with frequency scaling, so differences under about 5% are noise, and absolute times move between runs (plain C's `fib` took 0.48 s in an earlier run and 0.67 s in this one). Compare columns within one table. For tracking Z# itself, `bench/host/run.sh --check` counts instructions, which is deterministic.
