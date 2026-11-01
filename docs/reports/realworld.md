# Z# on real programs: word counts, JSON, an interpreter, shortest paths and hashing

**Question:** the host suite ([host.md](host.md)) measures kernels: recursion, tree allocation,
float loops. The programs people write spend their time elsewhere: in strings, hash tables, the
library's collections, parsing and building text. How does Z# do on small programs of that kind,
each written as that language would normally write it, against C and Rust?

**Answer:** slower than on the kernels, and slower for reasons the kernels couldn't show. With the
two compiler fixes below, `json` takes 1.2–1.3× C's time with less memory than C, `sha256` 1.5×,
`interp` 1.7–1.9×, `wordfreq` 2.9× and `pathfind` 3.4×. The gaps are mostly in the library's data
structures (a hash map of persistent chains, a persistent heap, a list merge sort) and in
reference counting on a tree that's only read. Writing the suite found two compiler bugs that
made ordinary code far slower, both fixed with it:
- **A copy per update** (`src/Opt/Rc.zs`): `m <- HashMap.add k (… HashMap.tryFind k m …) m`, the usual word count, copied the whole map on every update. `wordfreq` written that way took 84 s; it takes 0.23 s. Arrays had the same problem (`a <- Array.set a i (a.[i] + 1)`).
- **The pool lost to one library call** (`src/Build/Compile.zs`): a program with a SIMD vector anywhere had every object allocated by `aligned_alloc(64)` instead of the pool, and `Bytes.appendJsonString` has one. `json` took 3.5 s and 935 MB; it takes 1.4 s and 368 MB.

## Setup

| | |
|---|---|
| Machine | a cloud VM: Intel Xeon @ 2.10 GHz, 4 vCPUs, 15 GB, Ubuntu 24.04 |
| Z# | `zs build` (default optimization: ThinLTO with the runtime), the compiler at `c6321e2` (both fixes in) |
| C | clang 23.1.4 (LLVM's release, as the dev container's), `-O2`, and `-O2 -ftrapv` (signed overflow traps, as in Z#) |
| Rust | rustc 1.97.0, `--edition 2021 -C opt-level=3`, no crates |
| Time | Wall clock, the best of 3 runs |
| Memory | Peak resident set size (GNU `time`), the lowest of the same 3 runs |
| Correctness | Each program's output at a small size must equal C's; at full size the three print the same too |
| Reproduce | `./dev bench/host/run.sh wordfreq json interp pathfind sha256` |

Swift, Zig and OCaml aren't here: these programs exist in Z#, C and Rust only, and the machine had
none of the three (`run.sh` shows `-` for a language without a source or a compiler).

## The programs

Each generates its input from a fixed seed (the same linear congruential generator in all three
languages), so no data files are needed and every run does the same work.

| Program | Size | Work | What it stresses |
|---|---|---|---|
| `wordfreq` | 1M words | generate a text of words with capitals, punctuation and line breaks; split it into lowercase words; count them in a hash table; sort by count, then word; print the top 10 | byte scanning, small strings, string hashing, sorting |
| `json` | 200k records (42 MB) | generate a JSON array of user records; parse it; decode it into typed records; sum and filter them; encode the active users back to JSON (25 MB) | parsing, many small allocations, floats, building text |
| `interp` | n = 300,000 | tokenize, parse (recursive descent, variables resolved to slots) and walk the tree of a 25-line program: the primes below n, the Collatz steps of every number below n/4 | matching on unions, recursion over a shared tree |
| `pathfind` | 2000 × 2000 grid | Dijkstra from a corner over cells costing 1–9, with a priority queue | a heap, array updates, index arithmetic |
| `sha256` | 64 MiB | SHA-256 of the whole buffer; then of each 4 KiB chunk, named by its hex digest as git names objects, the distinct names counted in a set; then of the chunk digests | 32-bit arithmetic, byte arrays and spans, hex strings |

**What each language uses:**

| Program | Z# | C | Rust |
|---|---|---|---|
| `wordfreq` | `Bytes` writer, `String.toLower`, `HashMap`, `List.sortWith` | a `realloc`ed buffer, open addressing (FNV-1a), `qsort` | `String`, `HashMap` (SipHash), `sort_by` |
| `json` | `Json.parse`, `[<Derive(Json)>]` records (`fromJson`, `toJson`), `Json.print` | a hand-written tree parser and printer, structs | the same as C, an enum tree (no serde) |
| `interp` | unions, `match`, a `Buffer` for the variables | tagged structs, `switch` | enums with `Box`, `match` |
| `pathfind` | `PriorityQueue` (the library's: a persistent leftist heap) | an array binary heap | `BinaryHeap` |
| `sha256` | Core's `Sha256`, `Hex.encode`, `HashSet` | written from FIPS 180-4, open addressing | written from FIPS 180-4, `HashSet` |

## Results

**Time, seconds** (best of 3; × C in parentheses):

| Program | Z# | C | C `-ftrapv` | Rust |
|---|---:|---:|---:|---:|
| wordfreq | 0.262 (2.98×) | 0.088 | 0.079 (0.90×) | 0.105 (1.19×) |
| json | 1.470 (1.29×) | 1.140 | 1.109 (0.97×) | **1.005 (0.88×)** |
| interp | 1.085 (1.69×) | **0.642** | 0.889 (1.38×) | 0.661 (1.03×) |
| pathfind | 1.242 (3.49×) | 0.356 | **0.352 (0.99×)** | 0.477 (1.34×) |
| sha256 | 1.021 (1.49×) | **0.686** | 0.733 (1.07×) | 0.692 (1.01×) |

A second run gave the same picture: Z# at 2.92×, 1.22×, 1.86×, 3.38× and 1.65× C.

**Peak memory, MB:**

| Program | Z# | C | C `-ftrapv` | Rust |
|---|---:|---:|---:|---:|
| wordfreq | 19.1 | 13.9 | 14.0 | 12.8 |
| json | **367.7** | 423.0 | 423.0 | 505.1 |
| interp | 1.8 | 2.2 | 2.1 | 2.1 |
| pathfind | 62.8 | 62.9 | 62.9 | 62.9 |
| sha256 | 66.2 | 66.5 | 66.5 | 66.4 |

**Before the two fixes,** the same programs on the same machine: `json` 3.51 s and 935 MB (2.5×
the time and memory it takes now); `wordfreq` with its count written as one expression,
`counts <- HashMap.add w (Option.defaultValue 0 (HashMap.tryFind w counts) + 1) counts`, 84 s.

**The kernels in the same run,** for calibration on this machine (the laptop's numbers are in
[host.md](host.md)): `fib` 1.48× C, `binarytrees` 0.46×, `nbody` 0.90×, `spectralnorm` 1.00×,
`rbtree` 0.89×. Z# keeps its lead on allocation-heavy kernels here, so the gaps above aren't the
machine's.

## What the numbers show

Where the time goes comes from cachegrind and callgrind at each program's counting size
(`bench/host/run.sh` lists them), Z# against C.

- **`json`, 1.2–1.3× and less memory than C:** after the pool fix, 98.8M instructions against C's
  82M, spread thinly: appending bytes, `Json.text`, field lookup by a linear search of the
  object's keys (as C's), building the output by joining strings. Z# needs 13% less memory than C
  and 27% less than Rust: a document node is a pooled object with a one-word header, where each
  of C's and Rust's strings and arrays is a `malloc` block.
- **`sha256`, 1.5×:** Core's `Sha256.compress` alone executes 1.45× the instructions of C's whole
  program (224M against 155M at 1 MiB), and is 93% of Z#'s. Its message
  schedule and state are `Buffer<u32>`s, objects reached through a pointer, where C's are a
  stack array and locals, and its round constants come from a 64-way `match` (a top-level array
  would need startup code, which a `--no-heap` program doesn't have).
- **`interp`, 1.7–1.9×, and 1.38× against checked C:** 3× C's instructions (983M against 331M at
  n = 30,000). `eval` takes its `Expr` owned: the borrowing pass (`Rc.borrowingWith`) makes a
  parameter owned when the function matches on it, so that Perceus can reuse a cell the function
  rebuilds, and so each call on the long-lived tree increments and decrements a count, with a
  test for the free path. A function that only reads its argument would be better off borrowing
  it, as Lean 4 decides (owned only where a reset/reuse applies). The rest is overflow checks:
  C with `-ftrapv` takes 1.38×.
- **`wordfreq`, 2.9×:** the sort is about a sixth of Z#'s instructions, string hashing a tenth.
  The rest is the hash table and building the text:
  - **`HashMap`** chains persistent lists: each update allocates a new pair and a new cell and
    filters the bucket's chain, and there's no single-lookup update (Rust's `entry`, F#'s
    `Map.change`), so a count hashes each word twice, once for `tryFind` and once for `add`.
    Hashing is SipHash-1-3, keyed, as Rust's: it isn't the gap.
  - **`List.sortWith`** (and `Array.sortWith`, which goes through it) is a top-down merge sort that
    takes, skips, reverses and appends lists at every level. A bottom-up merge sort over a
    `Buffer` saves only 16%: the compare dominates.
  - **The text** is built with `Bytes.append`, a call per word that isn't inlined (11% of the
    instructions).
- **`pathfind`, 3.4×:** 76% of the instructions are `PriorityQueue`'s leftist-heap merges, a
  persistent structure that allocates on every operation, against C's array heap. Two more
  things, measured on a copy of the program:
  - **A hand-written binary heap in two `Buffer`s** brings it to 94M instructions from 170M (C:
    31.5M at the same size), so the data structure is most of the gap but not all of it.
  - **`for (nx, ny) in [ (x - 1, y); … ]`**, the four neighbours, allocates a list cell per
    element on every iteration: 4 million allocations here. Writing the four cases out saves
    13% with the library's heap and 25% with the hand-written one. Rust's `for … in [ … ]` is an
    array on the stack.

## What is left, and why

Each is a change to the library or the optimizer, measured here and not made:

| | Where | What it would save |
|---|---|---|
| Borrow a parameter a function only matches on and reads | `src/Opt/Rc.zs`, `borrowingWith` | most of `interp`'s 3× instructions |
| A `HashMap` that updates in place (open addressing), and `HashMap.change` | `lib/core/Collections/HashMap.zs` | an allocation and a second hash per update in `wordfreq` |
| A mutable array heap beside the persistent `PriorityQueue` | `lib/core/Collections` | most of `pathfind`'s gap |
| `for x in [ literal ]` without building the list | the optimizer's fusion | 13–25% of `pathfind` |
| `List.sortWith` over an array | `lib/core/Collections/List.zs` | 16% of a sort |

## How the comparison could mislead

- **Different data structures, on purpose:** each version uses what its language's programmers
  reach for. Z#'s `HashMap` chains persistent lists, its `PriorityQueue` is a persistent heap and
  its sort a merge sort over lists, where C has open addressing and an array heap. That's the
  point of the suite, what a program costs written the usual way, but a Z# program that writes
  its own array heap closes much of the gap (*pathfind*, above).
- **Hand-written C and Rust parsers:** `json`'s C and Rust parsers handle only what the documents
  contain (no `\u` escapes, no check of the grammar), where `Json.parse` is the complete RFC 8259
  parser with error positions, and the Z# version decodes through a generic `fromJson` where C and
  Rust read fields one by one. This favours C and Rust.
- **Overflow checks:** Z# checks every integer `+`, `-` and `*`; C and Rust (release) don't. The
  `C -ftrapv` column has the same checks.
- **Generating the input is timed:** each program builds its input as part of the run. For
  `wordfreq` that's a third of C's instructions.
- **A shared virtual machine:** wall-clock times on it moved by up to 10% between the two runs, and
  absolute times differ from the laptop's in [host.md](host.md) (its `binarytrees` is 0.31 s,
  0.67 s here). Compare within one table. The instruction counts in `bench/host/baseline.txt`
  are what `./test.sh` checks; those of these five were counted on this machine, whose glibc
  starts a program in about 117,000 more instructions than the dev container's, so they're
  slightly loose there (`./dev bench/host/run.sh --update wordfreq json interp pathfind sha256`
  tightens them).
