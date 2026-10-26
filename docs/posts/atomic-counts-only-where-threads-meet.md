# Atomic reference counts only where threads meet

Reference counting has a tax that tracing collectors don't: in a program with threads, a count
two threads can change at once must be changed atomically, and an atomic increment is a locked
instruction that costs many times a plain one. Swift pays it on every count, because any object
might be shared. Rust makes you choose per type, `Rc` or `Arc`. Z# does neither: a count is
plain until its object crosses to another thread, and the compiler knows where every crossing
is.

## What crosses is checked

A function another thread will run has the type `share<F>`: `Parallel.both`'s arguments,
`Array.Parallel.map`'s function, `Task.spawn`'s, a `Mutex`'s and a `Channel`'s values. What it
captures must be `Share`: numbers, strings, records, unions, lists and arrays of those, `Atomic`,
`Mutex`, `Channel`. A `ref` or a `Buffer` isn't, so a data race on one is a compile error, found
where the closure is made, through the local functions it calls, and after monomorphization
through every top-level value it reaches:

```text
this function crosses threads, but it uses the top-level value 'total' : ref<int>, which
threads can't share; pass it what it needs instead
```

## Marked once, counted atomically after

Every count starts plain. Where a value crosses (the compiler knows each place: a job, a spawn,
a send), the objects reachable from it are marked shared once, by a walk the compiler generates
per type, and from then on only those objects' counts are atomic: their count is negative, so the
generated increment and decrement test one sign bit to choose. Data a thread builds and keeps,
which is most data, never pays.

Crossings move, too (decision 75). A value given to another thread is consumed, and an object
only that value references isn't marked at all: it belongs to the receiving thread now, and
keeps Perceus's optimizations there (reuse in place, copy-on-write without a copy). `tests/parallel/move.zs`
maps 64 unique trees in parallel and then 64 trees the caller keeps using; it counts the
objects marked with `Runtime.marks ()`:

```text
7680 7680 0 true 64
```

The same work, the same sums: 0 objects marked when the trees move, some when they're kept.

## What it costs, and what it saves

**Scaling with C.** Phase 7's exit test runs two programs on 1, 8 and 16 threads next to C
versions with pthreads that do the same split:

| Program | 1 thread | 8 threads | ×8 | 16 threads | ×16 |
|---|---:|---:|---:|---:|---:|
| mandelbrot 8000×8000, Z# | 2213 ms | 319 ms | 6.94 | 243 ms | 9.11 |
| mandelbrot, C | 2070 ms | 304 ms | 6.81 | 245 ms | 8.45 |
| nbody, 6000 bodies, Z# | 1553 ms | 280 ms | 5.55 | 306 ms | 5.08 |
| nbody, C | 1556 ms | 269 ms | 5.78 | 300 ms | 5.19 |

Z# scales as C does, within 4%, on an 8-core laptop part whose clock drops as more cores run.

**Single-threaded speed stays.** A program without threads has no atomic count anywhere, and
the allocator's pool is only for it. On the host benchmarks (an AMD Ryzen 7 PRO 8840U), Z# runs
`binarytrees` in 0.26× C's time and a persistent red-black tree of a million keys in 0.89×. Swift,
the other reference-counted language, runs the same red-black tree algorithm 4.3× slower than
Z# and `binarytrees` 10× slower.

## How this could mislead

- **The Swift comparison isn't atomics alone.** Z# also reuses unique cells in place, borrows
  parameters without counting, and allocates from a pool where Swift calls `malloc`; atomic
  counts are one of four reasons ([docs/reports/host.md](../reports/host.md)).
- **Shared data pays.** A shared object's count is never 1, so it's copied where a unique one
  would be updated in place, and its counts are atomic. A design that funnels everything through
  one `Mutex` gets Swift's costs for that data.
- **Laptop timings.** Frequency scaling moves times by a few percent; compare columns, not runs.

Reproduce: `./dev bench/parallel/run.sh` and `./dev bench/host/run.sh`. The design is in
[DESIGN.md §7](../../DESIGN.md#7-parallelism) and its decisions 47 and 75.
