# Proposal 0026: performance you can see: allocation sites in the editor, the controls Zig gives, and in-place functions

| | |
|---|---|
| **Status** | Draft |
| **Decided at** | a design review, with the flagship's first profiles (phase 12: "optimization waits for profiles of real programs") |
| **Builds** | track D (profiling 1, 3), track E (hints, code lenses, MCP), track M (`[<NoAlloc>]`, arenas on a chip); the optimizer items only after a measurement asks for them |
| **Rests on** | decisions 2 (Perceus), 4 (overflow traps), 20 (no comptime), 26 (from Zig: a checked opt-in, not explicit allocators), 42 (`[<NoAlloc>]`), 44 (arenas), 61 (warnings) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §5.2](../../DESIGN.md#52-perceus-reference-counting), [§9](../../DESIGN.md#9-optimizer), [§12](../../DESIGN.md#12-tooling) |
| **Related** | [0011 debug info, profiles and traces](0011-debug-info-profiles-traces.md) (the allocation hints, `--stats`, `--profile`), [0012 interrupts, `[<NoAlloc>]` and intrinsics](0012-interrupts-noalloc-intrinsics.md) (the allocation analysis), [0014 placement](0014-placement.md) (static objects with count 0), [0007 incremental builds](0007-incremental-builds.md) (per-module caches), [0021 warnings](0021-warnings.md) (hints aren't warnings), [0009 tests as values](0009-tests-as-values.md), [0017 iteration](0017-iteration.md) (fusion) |

- [ ] Discussion
- [ ] Approved in principle
- [ ] Implementation

## Summary

Zig makes the cost of code visible in the code: an allocator is a parameter, so a function that
may allocate says so in its signature, and `inline`, `noinline`, `@branchHint` and
`@setRuntimeSafety` sit in the source next to the code they change. Decision 26 took Zig's
cross-compilation and declined its explicit allocators; this proposal takes the rest of what
Zig is for, the knowledge and the control, in the form that fits a language whose
allocations are implicit: **the compiler says where they are, in the editor, and the
programmer says where they mustn't be.**

Four parts, in the order they're built:

1. **The allocation analysis, built** (0012 designed it, nothing implements it yet), with
   `[<NoAlloc>]` on top-level and local functions, and with a *reason* on every site: why this
   cell wasn't reused, who else holds the array that copied, what the closure captured.
2. **The editor, at three depths:** lints from the checker on every keystroke (a string built
   by `+` in a loop, `@` that makes a loop quadratic); verdicts from the back half on idle
   (0011's inlay hints, with the reasons, ownership on hover, inlining and fusion decisions, a
   code lens per function); and counts from the last run (`--stats=sites`, `zs profile`) on the
   same lines. Gopls's compiler optimization details and .NET's heap allocation analyzer are the
   models, not ZLS, which has nothing to show because Zig puts it in the source.
3. **Controls:** `[<Inline>]`, `[<NoInline>]` and `[<Cold>]` (Zig's `inline fn`, `noinline`,
   `@branchHint(.cold)`); `Testing.allocations` and a leak check per test (Zig's
   `std.testing.allocator`); `Arena.withLimit` (the bounded arena Zig gets from
   `FixedBufferAllocator`); and `[<InPlace>]` (Koka's `fip`), which no Zig program can say:
   this function, given unique arguments, rebuilds its input in its own memory.
4. **Optimizations, gated on a measurement:** stack environments for closures that don't escape,
   and `Array.getUnchecked` in `unsafe`. Each waits for the hints of part 2 to show it costs
   something in the flagship.

```fsharp
type Tree =
  | Leaf
  | Node of Tree * int * Tree

[<InPlace 1>]                                     // one new cell at most; the rest reuse t's
let rec insert (x: int) (t: Tree) : Tree =
  match t with
  | Leaf -> Node (Leaf, x, Leaf)                  ‹allocates: Node, 32 B›
  | Node (l, y, r) ->
    if x < y then Node (insert x l, y, r)         ‹reuses t›
    elif x > y then Node (l, y, insert x r)       ‹reuses t›
    else t

let report (items: list<Item>) =
  let mutable out = ""
  for it in items do
    out <- out + $"{it.name}: {it.qty}\n"         ‹allocates ×2: strings›  ┄ hint: quadratic: 'out' is copied on each iteration; build a list and String.concat it
  out                                             ‹last run: 1.2M allocations here, 41% of the program's›

[<NoAlloc>]
let step (s: State) (e: Event) : State = …        ⌜NoAlloc ✓ · borrows s, owns e · inlined into 2 callers⌝
```

(`‹…›` is an inlay hint, `┄` a hint-severity diagnostic, `⌜…⌝` a code lens. The markers are this
document's, not syntax.)

Approval adds a new decision row, numbered by the coordinator: the editor shows what the
compiler decided about memory, with reasons, and what the last run counted; controls are
attributes checked by the compiler, never switches that turn safety off for a whole program.

## Motivation

**Implicit allocation is the price of the syntax.** `x :: xs`, `$"…"`, a closure, a boxed union
case, a write to a shared array: each allocates, and nothing on the line says so. A Zig
programmer reads `try list.append(gpa, x)` and knows; a Z# programmer reads `x :: acc` and has
to know Perceus. Today the answer is `ZS_DUMP_CORE=name`, which prints Core after reference
counting (`src/Build/Compile.zs`), readable by the compiler's author and few others, and
`Runtime.allocations ()`, a count with no place attached (`runtime/rt.c`, `zs_allocations`).

**The analysis is designed and missing.** 0012 defines one allocation analysis after `Rc`, with a
verdict per site, as the base of `[<NoAlloc>]` and `--no-heap`; 0011 shows its verdicts as inlay
hints. Neither is built: `NoAlloc` appears nowhere in `src/`, and the flagship (a Nucleo-F401RE,
ROADMAP phase 12) wants its main loop `[<NoAlloc>]`. Building it is the first item here, and the
reasons are what turn it from a check into a tool: `reply -> describe -> String.concat allocates`
tells what failed; "`t` is borrowed here, so its cell can't be reused" tells what to change.

**What Perceus decided is the program's performance.** The difference between a tree insert that
allocates nothing and one that allocates a path of cells is whether the caller passed a unique
tree. Whether `List.map` reused its cells, whether a parameter was inferred borrowed, whether a
pipeline fused (`Mono.fuse`), whether a small function was inlined (`Inline`, by size alone:
`size f.body <= 60`, `src/Opt/Inline.zs`): each is decided, silently, by a pass a user doesn't see.
Known gap 5 in the roadmap is exactly this kind: a `Seq` pipeline is 4.8× a fused list pipeline,
and only the roadmap says so.

**Zig's answer, and why half of it doesn't transfer.**

| Zig | What it gives | Z# today | Here |
|---|---|---|---|
| an allocator parameter | the signature says *may allocate*; the caller picks the allocator | hidden; decision 26 declined the parameter | the editor says *where, what, how big, why*; `[<NoAlloc>]` says *must not*; `Arena.with` picks the allocator for a dynamic extent |
| `std.testing.allocator` | a test fails on a leak | `ZS_LEAKCHECK=1`, per process | a leak check per test, `Testing.allocations` for an allocation budget |
| `FixedBufferAllocator` | bounded memory, failure instead of growth | `Arena.with`, unbounded, hosted only (known gap 1) | `Arena.withLimit`, and arenas on a chip |
| `inline fn`, `noinline`, `@call(.always_inline, …)` | the inliner's decision, overridden | a size threshold | `[<Inline>]`, `[<NoInline>]` |
| `@branchHint(.cold)` | the unlikely path out of the hot one | panics are `noreturn` (`src/Gen/Prelude.zs`); COW copies are `cold` | `[<Cold>]` |
| `@setRuntimeSafety(false)`, `ReleaseFast` | checks off, per scope or per build | checks always; `[<Wrapping>]` per function; bounds checks hoisted out of loops (DESIGN §9) | a hint where a check stays in a loop; `Array.getUnchecked` in `unsafe` once one costs something |
| `comptime` | code run at compile time | declined (decision 20); constants in flash (0014), layout facts (0004) | nothing |
| `packed struct`, `extern struct`, `align` | layout | 0013, 0004, 0014 | nothing |

Zig's parameter tells a reader that a function *may* allocate, and nothing about which line, how
often, or how much: `ArrayList.append` in a loop of a million reads the same as one call. A
copy of a large struct by value is as invisible in Zig as a boxed case is in Z#. The editor can
do better than the signature for both, because the compiler knows the sites; what it can't do is
make the *caller* choose an allocator per call, and `Arena.with`'s dynamic extent is the answer
decision 44 already gave.

**What exists in other languages' tools:** gopls's "compiler optimization details" (escape
analysis, inlining, bounds checks shown as diagnostics from the compiler's own `-m` output);
the Clr Heap Allocation Analyzer, which marks boxing, closures and `params` arrays in Visual
Studio, the tool an F# or C# programmer already knows; LLVM's optimization remarks
(`-Rpass-missed`), in LLVM's terms rather than the source's; Clippy's `perf` lints; Koka's `fip`
check (Lorenzen, Leijen and Swierstra, ICFP 2023). ZLS shows types and parameter names only.

**Without the proposal:** a programmer tuning a Z# program reads Core dumps, sprinkles
`Runtime.allocations ()` around blocks, and finds a quadratic string build from a profile, after
the fact; firmware learns its heap use from the exit report's `heap_peak`.

## Detailed design

### 1. The allocation analysis, with reasons

0012's *`[<NoAlloc>]` and `--no-heap`* section is the design: one walk over Core after `Rc` and
before IR emission, a verdict per site, memoized over the call graph, the chain in the error. Its
verdict table stands. What this proposal adds:

- **A reason per site,** kept with the verdict (a short string and a position, so the cache
  holds it as text):

| Verdict | Reason, when the compiler has one |
|---|---|
| allocates | the object and its size: `a Node cell, 32 B`, `a string`, `a closure capturing n, xs (24 B)`, `boxed to dyn Show` |
| allocates (missed reuse) | why the matched cell wasn't reused: `t is borrowed in insert, so its cell isn't insert's to reuse`, `the cell is still used after this line (l)`, `Node has 3 fields, Pair 2: no cell of that size was consumed` |
| reuses | the cell: `reuses t (Node)` |
| copies on write | the other holder: `a is also held by b (line 12)`, `a is a parameter, and the caller keeps it` |
| frees | what goes: `drops old : list<Event>, which may free its cells` |
| atomic | `marks xs shared: it goes to Task.spawn` |
| static | `crcTable is a constant (in .rodata)` |

  The missed-reuse reasons come from `Rc`'s own decision: where it looks for a cell of a
  constructor's size among the variables dead at that point, it records the nearest candidate
  it turned down and why. This is the one new piece of analysis in part 1; the others are the
  verdict's own facts.
- **`[<NoAlloc>]` on a local function,** as on a top-level one: a hot loop's body is a local
  function, and `Lift` makes it a top-level one before `Rc`, so the check is the same.
  `let step = [<NoAlloc>] fun …` isn't proposed; a lambda is named first.
- **One summary per function,** from the memo: allocation sites by verdict, `NoAlloc` or the
  first chain, each parameter's ownership (borrowed or owned, from borrow inference), and
  whether `Inline` copied it and into how many callers. It's what hover and the code lens show.

### 2. The editor, at three depths

Three sources, each with its cost, all shown in the same places: inlay hints at the end of a line,
diagnostics at hint severity (LSP's `DiagnosticSeverity.Hint`, which editors draw as a faint
underline and don't count as problems), hover, and a code lens per function.

**Depth 1: lints from the checker, every keystroke.** Patterns the typed tree shows, no back half,
inside track E's 100 ms budget. Each has a name, as a warning kind does, so `[<NoWarn "name">]`
silences it in place; they never print in `zs build`, and `zs check --perf` prints them (for CI
or an agent). Only patterns with no plausible false positive go in:

| Name | Pattern | Message |
|---|---|---|
| `perf-string-loop` | a `mutable` string or a `ref<string>` assigned `x + …` or `$"{x}…"` inside a `for` or `while`, or a recursive function's string accumulator | `quadratic: 'out' is copied on each iteration; collect the parts in a list and String.concat them` |
| `perf-append-loop` | `acc @ [x]`, `List.append acc [x]` or `Array.append acc [|x|]` with `acc` the loop's or the recursion's accumulator | `quadratic: 'acc' is copied to add one element; cons onto it and List.rev once, or use a Buffer` |
| `perf-list-index` | `List.item`, `List.nth` or `List.length` on the same list inside a loop over an index | `List.item walks the list: this loop is quadratic; convert it to an array once` |
| `perf-seq-unfused` | a pipeline of two or more `Seq` stages (known gap 5) | `each Seq stage is an indirect call per element; over a list or an array the pipeline is one loop` |

  `perf-seq-unfused` goes away with track S item 9.

**Depth 2: verdicts from the back half, on idle.** 0011's *Allocation hints* is the design: the
server runs the passes to the analysis for the open document's program, after the check, keeps
the results per module in the cache beside the hovers (0007), and refreshes with
`workspace/inlayHint/refresh`. Hints are off unless `allocationHints: true` is in the
initialization options. What this proposal adds to it:

- **When:** 500 ms after the last edit with no newer one, cancelled by the next edit (the request
  runs on the loop thread, its passes on the pool, `src/Lsp/Server.zs`'s loop as it is). The
  checker's hints and diagnostics are never held back for it.
- **The reasons** from part 1 in each hint's tooltip, and a missed reuse or a copy on write also
  as a hint-severity diagnostic, with the reason as its message: those are the sites a change in
  the source can fix.
- **Hover** gains, under the type: on a parameter, `borrowed` or `owned (consumed at line 14)`;
  on a function name, the summary of part 1 (`allocates 3 sites · frees 1 · not inlined: 84 nodes,
  over 60`); on a pipeline, `fused into one loop` or `not fused: xs is used twice`; on a type,
  its representation from the layout facts (0004): `plain, 16 B, align 8`, `boxed: a 32-byte cell
  (8 B header, 3 fields)`, `one-case union: its field's size`.
- **A code lens** over each function, from the summary: `allocates 3 · NoAlloc ✓` or
  `allocates 3 · NoAlloc ✗ via describe → String.concat`, and for a generic one
  `3 instances · 4.1 KB` (Mono's instances and their emitted sizes, from the last build; absent
  before one). LSP's `textDocument/codeLens`, a new capability.
- **Code actions:** `Add [<NoAlloc>]` on a function whose verdict is clean (a guarantee for the
  next edit); `Show Core after reference counting` on a function, which opens
  `ZS_DUMP_CORE`'s text for it as a virtual document (`zs-core:` URI), and `Show LLVM IR` the
  same from the module's last `--emit-llvm`. rust-analyzer's "View MIR" and Compiler Explorer
  are the models; nothing new is computed for either.
- **Generic functions** show their instances' verdicts merged, naming the instance where they
  differ (0011). A module with no `main` (a library) is analyzed at the instances its own tests
  and examples reach: *Unresolved questions* 1.

**Depth 3: counts from the last run.** The static verdict says a line allocates; the run says how
often, which is what decides whether it matters.

- **`zs build --stats=sites`** extends 0011's `--stats`: each allocation call passes its site's
  number (one constant argument, as `--profile` passes the type's name), the runtime counts per
  site in a table, and at exit writes `.zs-cache/runs/<program>.json`: per site, allocations,
  bytes, reuse hits and copy-on-write copies, with the build's per-module hashes. Without
  `=sites`, `--stats` is 0011's.
- **`zs profile --save`** (0011) writes its samples beside it; the server folds them to lines
  through the line table.
- **In the editor,** when a run file exists for the open program: the line's hint gains the
  count (`‹allocates ×2: strings · 1.2M, 41%›`), and a line with over 5% of the samples gets
  `‹hot: 21%›`. A module whose hash differs from the run's shows no counts, and the code lens
  says `run is older than this file` once.
- **MCP:** `check` returns the verdicts on request (0011); a new tool `perf_sites` returns the
  sites of a file sorted by the last run's count, with reasons, so an agent asked to make a
  program allocate less starts at the top of the list.

### 3. Controls

**`[<Inline>]`, `[<NoInline>]`, `[<Cold>]`** on a top-level or local function.

- **`[<Inline>]`:** `Inline` copies the function into every call site whatever its size; its
  callers' reference counting then sees its constructors, which is what makes reuse across a
  call. A function that can reach itself, a `main`, or one whose address is taken (passed as a
  value; that copy stays) is an error at the attribute, as Zig's `inline fn` is for recursion:
  `'walk' is [<Inline>] but calls itself through visit; a recursive function can't be inlined`.
  The default stays size alone (the ponytail note in `src/Opt/Inline.zs`): an attribute where a
  profile says so is cheaper than a cost model nobody has measured.
- **`[<NoInline>]`:** excluded from `Inline` and given LLVM's `noinline`: the profiler's frame,
  and code size on a 64 KB flash.
- **`[<Cold>]`:** LLVM's `cold` on the function, so calls to it are unlikely branches and its code
  goes to `.text.unlikely`. An error path that isn't a panic (logging a malformed packet and
  going on) is the case; panics are cold already. A branch hint on an expression
  (`@branchHint`'s other form) isn't proposed: a call to a `[<Cold>]` function is the spelling,
  and LLVM propagates it.
- All three take `Decls.declare`'s path for code attributes (the list beside `Wrapping` and
  `FastMath`, `src/Infer/Decls.zs`), and the hover summary says which applied.

**`Testing.allocations` and leaks per test.**

- **`Testing.allocations : (unit -> 'a) -> 'a * int`** runs the function and returns its result
  and the heap objects it allocated on this thread, from the runtime's per-thread counter (`rt.c`
  keeps one per thread and `Runtime.allocations` sums them; this reads the caller's alone, so
  other threads' work doesn't leak into the number; a parallel path is counted in each job).
  `assert (snd (Testing.allocations (fun () -> step s e)) = 0)` is a regression test for an
  allocation-free path that keeps holding after `[<NoAlloc>]` would be too strict (the setup
  allocates, the steady state doesn't).
- **A leak check per test:** `zs test` already runs each test in its own process (0009), so it
  sets `ZS_LEAKCHECK=1` in each, and a test whose objects outlive it fails, naming them by type
  and allocation site when the build has `--stats=sites`:
  `leaks: 2 objects (a Node cell from tree.zs:14, a string from tree.zs:20); a cycle through 'parent'? see guide 12`.
  `zs test --no-leakcheck` turns it off. This is `std.testing.allocator`'s check, with the cycle
  hint a Zig program doesn't need.

**`Arena.withLimit`** *(with known gap 1, arenas on a chip)*.

- **`Arena.withLimit : int -> (unit -> 'a) -> 'a`:** `Arena.with` whose blocks total at most the
  given bytes; past it, a panic with the numbers:
  `panic: arena limit: 4096 bytes, 4064 in use, 48 asked (main.zs:31)`. Memory for one request
  or one frame, bounded and freed together, which is what Zig gets from a
  `FixedBufferAllocator` over a stack buffer.
- **On a chip** the arena's blocks come from the heap (track M's large-block list, M7); an arena
  over a `[<Section>]` buffer (0014) is *Unresolved questions* 4.
- An allocation that fails without a panic (Zig's `error.OutOfMemory`) isn't proposed: every
  Z# expression that allocates would need an error path, which is decision 26's reason.

**`[<InPlace>]`: functional but in place.** A Perceus-only guarantee: given unique arguments,
the function allocates nothing new, because every cell it builds reuses one it consumed.

- **The check:** the function's verdicts (part 1) have no *allocates* site and no *copies on
  write*, and no owned parameter is dup'ed (a dup would make a cell shared, and reuse would then
  fall back to allocating at run time). `[<InPlace n>]` allows up to `n` *allocates* sites
  executed at most once per call (not in a loop, not on a recursive path), as Koka's `fip(n)`
  does: a tree insert's one new leaf.
- **What it doesn't promise:** a caller passing a shared argument gets copies, as with any
  function; the guarantee is about the function, and `--stats=sites` counts its fallbacks at run
  time. Recursive calls count as in place when the callee is `[<InPlace>]` too.
- **The error** names the site and its reason: `insert is [<InPlace 1>], but line 9 allocates a
  Node: l is used after this line, so t's cell can't be reused yet`.
- **Why it's here and not just `[<NoAlloc>]`:** `NoAlloc` counts reuse as allocating (0012:
  reuse is a run-time choice), so a tree insert can never be `NoAlloc`. `InPlace` is the
  guarantee functional code can have, the one that makes a red-black tree as cheap as C's,
  and the one the hints alone can't hold against the next edit.

### 4. Optimizations, gated on a measurement

Each waits for the depth 2 and 3 hints on the flagship (or a host program a user reports) to show
it costs more than 5% of a run's time or allocations. Both are described so the hints collect the
right numbers.

- **Stack environments for closures that don't escape.** A closure passed to a parameter that
  the callee only calls (borrow inference already knows it's borrowed; this adds: never stored,
  captured, returned or passed on as owned, over the call graph, the memo of part 1) gets its
  environment in the caller's frame, with count 0: never freed, never unique, as 0014's static
  objects. `Array.iter (fun x -> total.Value <- total.Value + x * k) xs` then allocates nothing
  when `Array.iter` isn't inlined, and passes `[<NoAlloc>]`, which 0012 says counts a call
  through a closure parameter as allocating. The hint to measure first: `allocates: a closure`
  with its run count.
- **`Array.getUnchecked`, `Span.getUnchecked`, `Buffer.getUnchecked`** (and `set`), in `unsafe`
  only, as `ptr` is: Zig's `@setRuntimeSafety(false)` for one access, never for a scope or a
  build (decision 4 stands). The hint to measure first: Gen's loop versioning knows which loops
  it proved, so a loop it didn't gets `‹bounds checked per iteration: i + j isn't proved in
  range›` from the module's last build (a fourth source, read like the run file).

### Order of implementation

1. **The analysis and `[<NoAlloc>]`** (0012's item 3), with reasons, the per-function summary, and
   local functions. Tests: 0012's, and `tests/err_noalloc.zs` with each reason's message.
2. **Depth 2:** inlay hints, reasons, hover additions, the code lens, `Add [<NoAlloc>]`,
   `Show Core`. Test: `tests/lsp/hints.sh` on `examples/complex.zs`: the hints at fixed lines,
   none in a `[<NoAlloc>]` function; the exit test of track D's profiling 1.
3. **`Testing.allocations` and the leak check per test.** Test: a planted leak fails its test
   and only it.
4. **Depth 1 lints.** Test: `tests/lsp/perf.sh` with each pattern and a near miss of each (a
   string `+` outside a loop, `@` of two lists).
5. **`[<Inline>]`, `[<NoInline>]`, `[<Cold>]`.** Tests: Core dump shows the copy; the
   recursive error; `cold` in the IR.
6. **Depth 3:** `--stats=sites`, the run file, counts in hints, `perf_sites`. Test: the
   binary-trees benchmark's run file names `make`'s line with its count.
7. **`[<InPlace>]`.** Test: `bench/host/rbtree.zs`'s insert passes `[<InPlace 1>]`, and a planted
   use-after-match fails with its reason.
8. **`Arena.withLimit`,** with arenas on a chip (track M).
9. **Part 4,** each when its measurement asks.

## Drawbacks

- **The back half in the server** is more work per edit than checking, and a program's Mono runs
  from its entry points: for a large program it may take seconds. It runs on idle, cancelled by
  the next edit, cached per module, off by default; the checker's features never wait for it.
- **Hints change with the optimizer.** A change in inlining moves a hint or turns `NoAlloc` red.
  The reason says what changed; `[<InPlace>]` and `[<NoAlloc>]` are where it must not.
- **Reasons are a contract with `Rc`.** Each missed-reuse reason is a branch of `Rc`'s search
  recorded, and a reworded or wrong one misleads more than none. The test of each message keeps
  them honest.
- **More attributes.** Three code attributes and `InPlace` join `Wrapping`, `FastMath`, `Target`
  and `Multiversion`. Each is one line at a function, and each is checked; none changes meaning,
  only cost.
- **Lints with false positives** teach people to ignore them. Only four, each with a near-miss
  test, and each silenced by name.

## Alternatives

- **Zig's explicit allocators** (an allocator parameter on every function that allocates). Not
  chosen, as decision 26 found: in a language where `::`, `$"…"` and a closure allocate, every
  function would take one, and the parameter would carry no information. The editor shows more
  than the signature would (the line, the size, the count), and `Arena.with` chooses the
  allocator for a dynamic extent.
- **An `Alloc` effect in the row** (Koka's style: `f : int -> list<int> / <Alloc>`). Not chosen:
  the same argument, in the type system: nearly every row would hold it. The rare and useful
  fact is the inverse, *doesn't allocate*, which `[<NoAlloc>]` states where it matters.
- **Build modes as Zig's** (`ReleaseFast` with checks off). Not chosen: decision 4 keeps
  overflow and bounds checks in every build; `[<Wrapping>]` and part 4's unchecked reads are
  per function and per access, where a reader sees them.
- **LLVM's optimization remarks** as the editor's source (`-Rpass-missed=inline`, vectorization).
  Not chosen as the base: they speak LLVM IR after Z#'s lowering, where a reference count is a
  call and a reuse a branch, and most of a Z# program's cost is decided before LLVM. Kept for a
  later hint about vectorization in `[<FastMath>]` loops (*Unresolved questions* 5).
- **A separate linter,** as Clippy is to rustc. Not chosen: the lints need the checker's types,
  and the server already has them; one tool, `zs`, as for everything else.
- **`comptime`** for tables and specialization. Declined by decision 20; constants in flash and
  monomorphization cover what firmware needs.
- **A cost model for `Inline`** instead of `[<Inline>]`. Not now: the attribute is one line, the
  model a study, and the roadmap waits for profiles before optimization.

## Compatibility

- **Not breaking.** The attributes are errors today (`Decls.declare` admits `Wrapping`,
  `FastMath`, `Target`, `Multiversion` on functions); an older compiler stops at them with that
  message. `--stats=sites` and `zs check --perf` are new flags; `Testing.allocations` and
  `Arena.withLimit` are new functions in existing modules.
- **The leak check per test** fails tests that leak today and pass. That's the point, and the
  release notes say so; `--no-leakcheck` keeps the old behaviour.
- **Editors:** hints, code lenses and code actions are standard LSP; an editor without code
  lenses loses the summary and keeps it on hover. Zed, VS Code and Rider (track E) all show them.

## Pragmatics

**Diagnostics:**

| Situation | Message |
|---|---|
| `[<InPlace>]` violated | `insert is [<InPlace 1>], but line 9 allocates a Node: l is used after this line, so t's cell can't be reused yet` |
| `[<InPlace>]` and a dup | `rotate is [<InPlace>], but it uses 't' twice (lines 4 and 6), so its cells are shared and reuse would copy` |
| `[<Inline>]` on a recursive function | `'walk' is [<Inline>] but calls itself through visit; a recursive function can't be inlined` |
| `[<Inline>]` and `[<NoInline>]` together | `'f' is both [<Inline>] and [<NoInline>]` |
| `Arena.withLimit` exceeded | `panic: arena limit: 4096 bytes, 4064 in use, 48 asked (main.zs:31)` |
| a leak in a test | `parser/parses leaks: 2 objects (a Node cell from tree.zs:14, …)` |
| a lint | as in the depth 1 table, with its name in brackets: `[perf-string-loop]` |

**Tooling:** `zs lsp` gains code lenses, hint-severity diagnostics, three code actions and two
virtual documents; `zs mcp` gains `perf_sites`; `zs check --perf` prints the lints; the tree-sitter
grammar gains nothing (attributes are already parsed).

**Performance:** depth 1 is a walk of the typed tree the checker made, per keystroke, linear in
the module. Depth 2 is the back half to `Rc` with no IR, on idle, per module cached. Depth 3 adds
one constant argument per allocation call and a table add in `--stats=sites` builds only; a
release build is unchanged. `[<Cold>]` and `[<NoInline>]` cost nothing; `[<Inline>]` costs code
size the user asked for.

**Scaling:**

| Quantity | Typical | Limit |
|---|---|---|
| hints per module | 10–200 | 10,000 (a module of the compiler), in the module's cache entry (0011) |
| back half on idle | 50–500 ms for the flagship | seconds for the compiler itself; cancelled by each edit |
| sites in a `--stats=sites` table | 100–5,000 | one counter set per site, 32 B each |
| run files | one per program | the newest kept, by module hash |

## Unresolved questions

1. **Libraries:** a module without `main` has no instances to analyze. Its tests' and examples'
   instances (this document), or each generic function at a representative type (`int`, a boxed
   type), or no hints until something instantiates it.
2. **Depth 1 lints in `zs build`:** never (this document), or as warnings under `--strict`, which
   would make them 0021's kinds.
3. **`[<InPlace>]`'s name:** `InPlace` (this document) against Koka's `fip`, which says less to an
   F# reader.
4. **An arena over static memory** (a `[<Section>]` `Buffer`, 0014): objects that outlive it would
   pin a buffer the program means to reuse. Refused at the call when the buffer's last arena
   still has objects (a run-time check), or not offered.
5. **Vectorization hints** from LLVM's remarks in `[<FastMath>]` and SIMD loops: `‹vectorized ×8›`
   or `‹not vectorized: the loop calls f›`, as a fourth source. After this proposal.
6. **The 5% gate** for part 4: of time, of allocations, or either, and measured on what besides
   the flagship.

## History

- 2026-10-26: draft, from the question of what Z# should take from Zig beyond `zig cc`, with
  0011's hints and 0012's analysis brought into one plan.
