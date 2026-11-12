# Proposal 0030: checking ahead

| | |
|---|---|
| **Status** | Proposed (2026-11-12). Step 1 was built as a spike the same day and taken out again: it gives the same bytes and no time (*What the spike found*). Not to be built as written until where a derived impl lives is decided |
| **Decided at** | not yet; it changes how decision 79's "modules checked level by level" is built, not what it's for |
| **Builds** | after 0.7.1, in the steps under *Order of implementation* |
| **Rests on** | decisions 75 (crossings move), 76 (the session stays on the driving thread), 77 (the same output whatever the thread count), 79 (both halves parallel) in [DESIGN §13](../../DESIGN.md#13-decisions); [0007 incremental builds](0007-incremental-builds.md) (a module's key and its saved result) |
| **Related** | [0020 the compiler in Z#](0020-self-hosting.md) (*Checking by levels*, which this replaces); [the architecture](../../src/ARCHITECTURE.md) §1, §4 and §5, which describe the front half as parallel and are wrong today; [the self-hosting report](../reports/self-hosting.md) (*What sharing costs*) |
| **Changes** | `src/Build/Check.zs`, `src/Infer/Cx.zs`, `src/Infer/Snapshot.zs`; then `src/Opt/Inline.zs`, `Mono.zs`, `Evidence.zs`; ARCHITECTURE §1, §4, §5; decision 79's row; no change to the language, the library or any output |

- [ ] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

The compiler's back half runs on every core; its front half doesn't. Files are parsed on the
pool, and then every module is checked in order on one thread, and `Mono`, `Inline` and
`Evidence` run on one thread after it. 0020 and decision 79 say otherwise ("modules checked
level by level against an immutable `Env`"), and so does ARCHITECTURE: that part was designed
and not built.

This proposal builds it another way than 0020 drew it. The loop that checks modules in order
stays as it is and stays the only thing that decides a module's result. Beside it, modules whose
dependencies are done are **checked ahead** on the pool, each under the cache key it will have
if the modules still unchecked before it show nothing to modules that don't name them. When the
loop reaches a module, a result checked ahead under exactly its key is a cache hit like any
other, and is restored; under any other key it's dropped and the module is checked as today.

So nothing about a build's output depends on the pool, by construction: a result is used only
where the cache would already have used it.

## Motivation

A debug build of the compiler by itself, from an empty cache (`zs build src/Main.zs --time`,
the dev container, 16 cores, 2026-11-12, stage 0 at 0.7.1):

| phase | 16 workers ms | 1 worker ms |
|---|---:|---:|
| parse + check | 2,239 | 2,430 |
| monomorphize (two steps) | 545 | 636 |
| inline | 330 | 366 |
| effects | 241 | 242 |
| borrowed parameters | 663 | 767 |
| simplify, decision trees, lift, reference counting | 1,288 | 5,478 |
| LLVM IR | 1,328 | 4,173 |
| clang, link | 6,006 | 24,683 |
| total | 14,052 | 40,490 |

The passes that are on the pool take a quarter of their one-worker time. The ones that aren't
take the same, and together they're 4.0 s of the 14.1 s: with clang, the whole of what's left.
(Times on this machine move by a fifth between runs; the shape doesn't.)

Of `parse + check`, the library's 70 modules are 0.2 s (`tests/json.zs` from an empty cache:
214 ms), so the program's 73 are about 1.7 s. An estimate of what's there to take, from the
compiler's own module graph with a module's lines for its time: 38,578 lines, 6,977 on the
longest chain of dependencies (5.5× if nothing waited), 12,403 as the sum of each level's
largest module (3.1× by levels). So about 1.1 s of the 1.7 s on a build from nothing, and the
same share of an editor's re-check after a change to a module many others use.

What it isn't for: a build after a small change. There the cache restores what didn't change
and one module is checked; checking ahead must cost such a build nothing (*Pragmatics*).

## Detailed design

### What the cache already says

`checkModules` (`src/Build/Check.zs`) gives each module a key: the compiler, the target's word
and interrupt table, the module's path, name and text, and for every module before it either
its whole interface (`"I" + ifaceHash`, when this module uses it, directly or not) or only what
it shows to modules that don't name it (`"G" + seenHash`: its impls and derives for others'
traits and types, the members it gives others' types, its C functions). A result saved under a
key is restored whenever the key comes up again. That is already a statement of what checking a
module reads: the interfaces of what it uses, and `Seen` of the rest.

And `Infer.Snapshot` is already a statement of what checking a module writes: `written` takes
the tables' new entries since `marks` as an `Iface`, with the module's functions, hovers and
warnings, every type settled; `restore` puts an `Iface` into a context. A module restored and a
module checked leave the context the same for the modules after them, or the cache would be
wrong today.

Checking ahead is those two statements used once more: a job reads what the key names, and
gives back what `written` gives.

### The loop, and what's added

The loop is unchanged but for one line: where it asks the cache for a module's key, it asks the
results checked ahead as well (a `Map` from key to result, in memory, this run's).

When the loop comes to a module with no result under its key, in the cache or ahead, it
**checks ahead** before checking it:

1. **The base.** The interfaces of the modules the loop has merged (every module before this
   one), and of the results held ahead, each with its module's place in the order. A job takes
   the ones before its module, in order: what the loop will have when it gets there, less the
   modules not checked yet.
2. **The ready modules.** This module and every later one whose used modules are all in the
   base and whose **assumed key** is neither held, in the cache, nor tried. The assumed key is
   the module's key with an empty `Seen` for each module before it that isn't in the base (or
   the `Seen` it had the last time it was checked, kept beside its results by path). A result
   held under another key than the assumed one is dropped, and with it what was checked against
   it.
3. **The jobs.** One per ready module, `Array.Parallel.map` over them. A job makes a context of
   its own from the base (below), checks its module (`Infer.Decls.check`), and returns
   `Snapshot.written`'s result with the interface's two hashes, or nothing when the module has
   an error or its interface keeps a free type variable.
4. **Kept under the assumed key,** each result that came back, on the driving thread.

Then the loop goes on with the module it was at: its result is ahead now (its assumed key is
its key: nothing before it is unknown), unless it has an error, in which case it's checked
again in the loop's context, where its diagnostics are reported as today.

What makes a result checked ahead the right one, when the key matches:

- **What it used is what the loop has.** A module's used modules were all in the base, as
  results whose interface hashes are in the assumed key. If one of those is checked again by
  the loop and comes out different, the key differs.
- **What it didn't use is in the key as it was.** The modules before it in the base are in
  its context whole, as they are in the loop's, and in the key by the hashes they were held
  under. The ones that weren't in the base are in the key with an empty `Seen`; if one turns
  out to show something, the key differs. To the key, a module that's unused and shows nothing
  is a module that isn't there.
- **Nothing after it.** A job's context has no module that comes after its own.
- **Order.** `cx.records` is read in order (a record found by its fields); the base's is in the
  modules' order because the held results are restored in it. The other ordered lists
  (`exports`, `tests`, `valueList`, `funs`) are only appended to while a module is checked, or
  searched for the module's own entries.
- **Names.** Fresh names count from 0 in each module (`Decls.check` resets `cx.counter`), and a
  job's type variables are its own table's: neither reaches a settled result.

A module the loop restores from a result checked ahead is counted as checked (`checkedNames`,
`--time`'s `check (n of m)`), since it was: `tests/cache.sh`'s transcripts don't change. Its
result is written to the cache under its key as a checked module's is.

### A job's context

As the spike built it: a new context (`Infer.Cx.create`), then `Snapshot.restore` of each
interface of the base before the module, in order, with the program's names put in after the
library's as the loop does. No new type, and nothing that isn't what a build with a full cache
does; 2 to 4 ms a job on the compiler (120 interfaces). The `Env` below is the same thing
without the replay, for when that time matters.

A job can't have the loop's `Cx`: decision 76 keeps the session on the driving thread, and its
tables are `ref`s and `Buffer`s, which aren't Share. So:

- **`Infer.Cx.Env`**: the tables' values without their `ref`s (the persistent `Map`s and `Set`s
  as they are, the ordered lists as arrays), and the fixed settings. Immutable, Share, made
  from a context in a few dozen pointer copies. This is 0020's "immutable `Env`"; `Snapshot`'s
  `Marks` is nearly it already and becomes it.
- **`Infer.Cx.ofEnv`**: a context from an `Env`: fresh `ref`s and `Buffer`s around the same
  values, a type-variable table of its own, its own diagnostics. `create` becomes `ofEnv` of
  the empty `Env`.
- **The base has no type variables of the loop's.** A module checked (not restored) by the loop
  leaves types in its tables that point into the loop's variable table. The base is made from
  the modules' settled interfaces, as a restored context is; the loop keeps each module's
  `Iface` for it (it makes one for the cache already).
- **A job's row is empty:** the handlers checking needs are installed inside it, and its
  diagnostics are dropped with its context.

### Only the program's modules

The library's modules are checked in order, as today: 0.2 s of a build from nothing, restored
in milliseconds otherwise, and most of them show something to every module (their C functions),
which is what makes a module wait. Checking ahead starts at the first module of the program.

### One worker, no cache, the editor

- `ZS_WORKERS=1`, or one module left: no jobs; the loop is today's.
- `ZS_NO_CACHE=1`: results ahead are kept in memory under their keys all the same; nothing is
  written.
- `zs lsp` and `zs mcp` call the same loop (`programIn` with the open documents' texts), so a
  re-check after an edit runs the modules that use the edited one ahead, on the pool.

### `Mono`, `Inline`, `Evidence`

The same question for the three passes still on one thread (1.1 s together). Each gets its
answer in its step, measured first; what's known now:

- **`Inline`.** The small functions are finished first, callees before callers, on the driving
  thread, as today: they're what every copy is made of. Every other function's body is then a
  job that reads the finished small ones and their sizes and counts its fresh names itself
  (they're per function already). `kept` and `mayInline` become `share` closures, as `Lift`'s
  `external` is.
- **`Mono`.** Decision 79: the plan (which instances) on the driving thread over signatures,
  then an instance a job. To be read against what `Mono.runFrom` does today.
- **`Evidence`.** Writes the types it adds as it goes; whether a function's lowering reads
  another's is to be read first.
- **Borrowed parameters** stay on one thread: a round reads every function's code and the
  rounds are few (`Rc.borrowingWith`'s own note).

## What the spike found

Step 1, built in `src/Build/Check.zs` on 2026-11-12 with batches from the loop (step 2's rule,
without the last `Seen` by path), on the compiler checking itself from an empty cache, 16
workers. A switch (`ZS_NO_AHEAD=1`) gave the loop alone in the same binary.

- **It's right.** 69 of the program's 73 modules were restored from a result checked on the
  pool, the other four checked by the loop (nothing else was ready beside them), and the
  compiler built was the same bytes with it on and off, three times.
- **It isn't faster.** `parse + check`: 1,918 to 2,022 ms off, 2,231 to 2,422 ms on. 33 batches
  ran 302 jobs for the 73 modules; the batches' wall time summed was 1,190 ms.
- **Why: what a module shows.** 16 of the 73 show something to modules that don't name them,
  so each is in the key of every module after it, and a module checked ahead before one of them
  was known is checked again after it. Eleven show an `Eq` or `Ord` derived on demand for a
  type of another module (`Lexer` for `Syntax.Token.Kind`, `Core.Ir` for `Types.Ty.Ty`,
  `Infer.Exprs` for eight of `Syntax.Ast`'s), and five their C functions (`Tools`, `Project`,
  `Options`, `Xxhash`, `Server`). A derived impl lives in the first module, in order, that
  compares the type; that is what makes the order matter.
- **The ceiling without that.** With every `Seen` taken as empty (the output not to be trusted,
  the time is): 13 batches, 72 jobs, 692 ms of batches for what the loop does in about
  1,450 ms. About 2×, not the 3× the line counts promised: a batch waits for its largest
  module, and `Cx`, `Exprs`, `Decls` use each other in a row.
- **Sharing costs nothing here.** A job's maps are its own (restored into its context), so the
  jobs summed took what the loop takes for the same modules. The risk under *Drawbacks* didn't
  show.

So, as written, checking ahead is correct and useless on a program shaped like the compiler,
and worth at most 0.7 s of a 10 s build if a module stopped showing its derives. That is its
own question, and it comes first: **where a derive on demand lives** (in the module that first
needs it, as now; or in each module that needs it, as a function of its own that the linker
folds; or with the type). Today it also costs builds that aren't the first: a change to
`Lexer.zs` that stops comparing a `Kind` changes what `Lexer` shows, and every module after it
is checked again.

The spike was taken out of `src/` (it made no build faster, and a path nobody runs isn't
kept); the loop is as it was.

## Drawbacks

- **Work thrown away.** A module checked ahead under an assumption that fails is checked twice.
  It happens when a module turns out to show something (a new `extern`, an impl for others'
  types) that it didn't show the last time, or the first time anything is built. The second
  check is the one that counts, so nothing is wrong; it's time.
- **An error costs a second check** of the module that has it.
- **One more table to keep right:** `Env` beside `Cx`, `Marks` and `Iface`. A table added to
  `Cx` and not to `Env` is a module checked ahead against less than it should see. `Env` being
  what `Cx` is made of (`ofEnv`) is what keeps that from compiling.
- **What sharing costs.** Every job reads the base's maps, shared, so each read is an atomic
  count ([the report](../reports/self-hosting.md): code generation's jobs take twice as long on
  8 workers for it). The checker looks names up all the time. This is the design's one unknown,
  and step 1 measures it before anything else is built.

## Alternatives

- **Levels, the session merged between them** (0020, decision 79). The merge puts modules into
  the session in level order, not the modules' order, so everything ordered in it (`records`,
  the functions, the top-level values' startup order) has to be put back in order, and a module
  is checked against modules that come after it. Every one of those is a place where the output
  could come to depend on how checking was scheduled. Checking ahead never changes what the
  loop does, so there's nothing to put back.
- **Jobs that write the session under a lock.** Not Share, and the order of writes is the
  schedule's.
- **A scheduler driven by dependencies** (a module starts the moment its last dependency ends).
  More parallel than batches by perhaps a half on the compiler's graph (5.5× against about 3×),
  and it needs results merged out of the loop's order while jobs run. Batches from the loop
  need `Array.Parallel.map` and nothing else. If step 3's numbers ask for it, it's a later
  proposal over the same `Env` and the same rule for using a result.
- **Checking functions in parallel inside a module.** The big modules are where the time is,
  but inference inside a module is in order by design (a function's type is settled by the uses
  after it).
- **Nothing:** the cache makes every build but the first cheap. True of builds; the editor's
  re-check after an edit to `Ty.zs` and CI's build from nothing are the first build every time.

## Compatibility

Nothing a user can see changes: no syntax, no library name, no diagnostic, no output byte, no
cache format (one small file a module beside its results: its last `Seen`'s hash, by path; a
cache without them is read as today). A build with one worker is today's build.

## Pragmatics

- **A build after a small change must not get slower.** The assumed key is what makes that so:
  with each unchecked module's last `Seen` in it, a module that the change doesn't reach has
  the key it had, which is in the cache, and isn't checked ahead. `bench/compile`'s three
  incremental rows are the test: within noise of today's.
- **Determinism:** `tests/cache.sh` and `tests/bootstrap.sh` as they are, under one worker and
  the cores. A new script checks that the compiler's own modules come out the same bytes
  (`Saved`, hashed) checked ahead and checked in order.
- **Measured by** `--time` (a line for what was checked ahead and what of it was used) and
  `--stats` (the atomic operations of the jobs).
- **The editor:** the 100 ms target for a 2,000-line file is a one-module check and isn't
  touched; what moves is the re-check of the modules that use it.

## Order of implementation

1. **The spike: `Env`, `ofEnv`, and one batch.** The program's modules that use only the
   library, checked ahead in one `Array.Parallel.map`; the loop uses the results. Measured:
   the jobs' time summed on 1, 4 and 16 workers against the loop's for the same modules. **If
   the sum on 16 workers is more than twice the loop's, stop:** the base has to be copied into
   each job or borrowed, and that's a different design.
2. **Batches from the loop,** the assumed key, the last `Seen` kept by path, the count as
   checked. `tests/cache.sh` unchanged; the new same-bytes script.
3. **Measure:** the self-build from nothing and `bench/compile`'s rows, in a dated report. The
   target: `parse + check` of the self-build under half of today's on 16 workers; no
   incremental row slower.
4. **`Inline`** on the pool, then **`Mono`**, then **`Evidence`**, each measured before and
   after, each keeping `tests/bootstrap.sh` and the `.same-ir` tests as they are.
5. ARCHITECTURE §1, §4, §5 and decision 79's row say what was built.

## Unresolved questions

- Whether a held result that shows something should let the modules that *use* it go ahead
  (they see all of it anyway), keeping out only those that don't. It would matter for a program
  whose low modules declare C functions.
- Whether the jobs' diagnostics should be kept and reported from them, to save the second check
  of a module with errors. They'd have to come out in the loop's order and text.
- The last `Seen` by path is a guess kept in the cache directory; whether the build server
  should keep it in memory instead.

## History

- 2026-11-12, later: step 1 spiked with step 2's batches, measured, taken out; *What the spike
  found*. The base's rule and a job's context are written above as the spike had them.

- 2026-11-12: written, after measuring 0.7.1 building itself: the front half's 4 s of 14 s on
  one thread, and the levels the architecture describes not in the code.
