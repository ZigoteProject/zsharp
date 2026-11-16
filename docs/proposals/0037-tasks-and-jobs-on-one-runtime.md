# Proposal 0037: tasks and jobs on one runtime

| | |
|---|---|
| **Status** | Draft |
| **Decided at** | not yet: a design review |
| **Builds** | after 0.7, a step at a time: each step is its own change, with its measurement first |
| **Rests on** | decisions 21 (one cold `Task`), 22 and 48 (a loop per thread; tasks don't move), 47 (`share<F>`), 71 (the same `Task` on a chip), 72 (`Task` is a state machine, not an `Async` effect), 75 (crossings move) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §6](../../DESIGN.md#6-concurrency-task), [§7](../../DESIGN.md#7-parallelism) and §7.1 |
| **Related** | [0008 threads](0008-threads.md) (the pool any thread forks onto, spares, cancelling across threads); [0016](0016-async-bare-metal.md) (the chip's loop); [0002](0002-effect-handlers.md) and track G's item 4 (effects in a task); [0035](0035-contained-jobs.md) (a failure's boundary); track S's item 14 (completion-based I/O) |
| **Changes** | `runtime/rt.c` (the loop threads, `Task.blocking`'s helper, `Channel`'s waits); `lib/std/Threading/Channel.zs` and `Alt.zs`; DESIGN §6 and §7; the guide's chapters 13 and 14. No syntax, no new type, nothing on a chip |

- [ ] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

The draft this replaces ("lightweight fibers and a unified concurrency runtime") proposed a
`Fiber` type, a scheduler that steals suspended fibers between workers, a `select { }` form and
an effect context per fiber. Read against the code, most of what it proposed to add is there
already under other names, and the part that isn't, moving a suspended task to another thread,
is the one thing the memory model was designed not to need (decision 48). What's left is four
real gaps, each small, none of which needs a new abstraction:

1. **A spawned task is placed blindly.** `Task.spawn` gives each task to the next loop thread in
   turn (`zs_loop_spawn`: `T.next % T.n`), whatever that thread is doing. Fix: a task that hasn't
   started is still a `share<unit -> Task<'a>>`, which may go anywhere, so it waits in a deque an
   idle loop thread takes it from. Once started it stays (decision 48 holds).
2. **`Task.blocking` has one helper thread per loop,** so two blocking calls from one loop run
   one after the other. The compiler works around it itself (`src/Build/Tools.zs:107`: a
   `Task.spawn` around a `Task.blocking`, for a thread of its own). Fix: the calls run on the
   pool's spare workers, which exist for exactly this (a managed blocker).
3. **Nothing a task can wait for crosses threads but a spawn's result.** `Channel` is Share and
   blocks its thread: on a loop thread that stops every task of the loop. `Ch` waits as a task
   does and can't leave its loop. Fix: `Channel`'s operations as tasks, and as `Alt`s.
4. **Three sets of threads:** the loop threads (a thread per core), the pool's workers (a thread
   per core) and a helper per loop. A server that spawns its connections and forks its work runs
   twice the cores. Fix: after 1 and 2, measured, one count for both.

Not proposed, with the reasons under *Alternatives*: a `Fiber` type, tasks that move once
started, `select { }`, a fiber's effect context, parking `Mutex`, a `Failed` state.

## Motivation

### What the draft proposed that's there already

| The draft's | In the code |
|---|---|
| a hot `Fiber<'a>` beside the cold `Task<'a>` | a started task: `Task.start` in a `Task.scope` (`lib/core/Threading/Task.zs`). Its states are its `Cancel` and its `Promise`; there's nothing more a `Fiber` record would hold |
| `JoinHandle<'a>` | `Promise<'a>`: `Task.start` gives one, `Task.wait` waits for it, `Alt.wait` chooses on it |
| `Scope`, children that can't outlive it, cancellation flowing down, cleanup once | `Task.scope`, `start`, `cancel`; `both`, `all`, `race`, `timeout` wait for theirs; a `use` value is disposed on cancellation, newest first (`disposeOnCancel`, `disposed`) |
| stackless state machines, the frame allocated once, liveness at each wait | `task { }` is an LLVM coroutine behind a closure header; 7 allocations for 10 waits and for 200,000 (`tests/task/awaits.zs`) |
| a ready await taking no turn of the scheduler | `Task.ret`'s `ready`, and `resume`, which calls in place up to 64 deep |
| `Alt` as the one selection, with an atomic commit, over channels, timers, promises and cancellation | `lib/std/Threading/Alt.zs`: Concurrent ML's events. A sync's branches share a `Pick` that goes over exactly once; `Alt.after`, `Alt.wait`, `Ch.give`, `Ch.take`, `Mailbox.take`, `guard`, `withNack`. It isn't a "compatibility layer" to keep: it's the design |
| "channels park fibers, not threads"; rendezvous | `Ch` (capacity zero, between tasks of a loop). `Channel` with capacity 0 is a rendezvous between threads |
| blocked jobs don't take a worker | the pool's spares (0008): a job waiting in a `Channel` or for a `Mutex` starts one, up to twice the cores |
| a job from a thread outside the pool | a deque per forking thread (0008) |
| effect evidence kept across a wait | built in 0.7.1 (track G's item 4): a task's work captures the frames in scope where it's made (`tests/task/effects.zs`) |

### What the draft has wrong

- **"epoll / kqueue / IOCP."** Windows is wepoll, epoll's API over IOCP, so the loop is
  readiness-based on every host (0022). IOCP directly is a loop of another shape, and track S's
  item 14's question, not this proposal's.
- **"The existing managed-blocking mechanism can be reused" for `Task.blocking`.** They're two
  mechanisms today: the pool's spares are for jobs waiting in a `Channel` or a `Mutex`;
  `Task.blocking` is one helper thread per loop with a queue (`helper_main`). Reusing the first
  for the second is gap 2, and it's a change.
- **`Task.spawn` as "a structured child fiber".** `Task.spawn` is the crossing to another
  thread: it takes a `share<unit -> Task<'a>>` and its result must be Share. A child on the same
  loop is `Task.start`, which takes any task. Giving `spawn` the second meaning either drops the
  check (unsound) or puts it on every child (breaks every task that holds a `ref`).
- **`Task.start` as "a compatibility wrapper".** It takes its `Scope`, which is the whole of
  structured concurrency here: there's no unstructured start to wrap.
- **"The thread-local yield state needs reconsideration once fibers interleave."** Tasks
  interleave on a loop today. `zs_yield` is set only while a yield bubbles to its handler, on one
  stack, and a task's body is compiled with no yield points: a call that leaves it set panics
  (`src/ARCHITECTURE.md`, *In 0.7.1*). It's never set across a wait, so it has nothing to save.
  The draft's `EffectContext { frames: EffectFrame[] }` is a handler stack, which evidence
  passing replaced: frames are arguments, and a task's are in its closure already.
- **`Failed`, `Result<'a, Error>`, "child failure propagation".** A panic stops the program and
  can't be caught (decision 5), and an effect whose operation never resumes (`Throw`) is an
  error in a task's row. A task has no failure to propagate; an error is a `result` in its
  value. A panic's boundary is 0035's subject and needs its memory design, not a state here.
- **"A contended lock should suspend the fiber."** `Mutex` has `get`, `set` and `update`, whose
  function is plain: it can't wait, so no task holds a `Mutex` across a wait. There's no
  `Semaphore`.
- **"A CPU job must not monopolize a worker: add budgets and yield points."** A job is a plain
  function on a worker's stack, and `zs_par_join` runs other jobs on top of it. Taking it off
  its worker mid-run is stack switching, which the draft rules out two sections later.
- **`select { case! … }`, `100.ms`.** New syntax for what `Alt.choose` with `Alt.map` does, on
  the way to something else (the rules for a change, 5). `Task.sleep` takes milliseconds as an
  `int`.
- **`runtime/scheduler/*.c`, fifteen files.** `rt.c` is one file on purpose (one `_WIN32` part,
  no build system for the runtime, 0022). Not a design question, and not this proposal's.

### What moving a started task would cost

The draft's centre is that a suspended fiber is stolen by an idle worker. Decision 48 says a
task never moves, and the reason is §7.1's, not caution:

- **Counts.** A task's frame, and everything it reaches, has non-atomic counts. To resume on
  another thread, the frame's whole graph is marked shared at the move: atomic counts from then
  on, and a shared object's count is never 1, so reuse and in-place update (§5.2) stop for
  everything the task holds. "Crossings move" (decision 75) doesn't save it: the loop that
  suspended the task still references what its waits registered.
- **The library.** `Cancel` is a `ref<bool>` and a `Buffer`; `Promise`, `Scope`, a `Pick`, a
  `Ch`'s queues are `ref`s and `Buffer`s. `Alt.zs` says why that's sound: "the tasks of one loop
  take turns, so nothing here needs a lock." Tasks that move make each of them an `Atomic` or a
  `Mutex`, paid by the program that runs on one thread too (the echo server's 10,000
  connections in 26 MB on one loop).
- **What a task may hold.** Anything, today: a `ref`, a `Buffer`, a C pointer, the compiler's
  session (decision 76). A task that may move holds only Share values across a wait, which is
  Rust's `Send` bound on every `let!`, with its diagnostics, or a mobility analysis and a
  pinned kind beside it: two kinds of task where there's one.
- **Programs without threads.** A program that never starts a thread runs the code it always
  did (§7.1), and one without effects is byte-identical. A scheduler that owns `Task.run` starts
  workers for `Task.run (Task.sleep 10)`.
- **The chip.** `Task` is in Core and runs on a Cortex-M0, where an `Atomic` masks interrupts.
  An atomic state per task is a cost there for threads that don't exist.

What stealing buys is balance when load is skewed after placement: one loop with every busy
connection. Gap 1 removes skew at placement. Whether skew after it matters is a measurement
(*Unresolved questions*, 1), and the answer that keeps the model is the program's: a connection
that turns expensive forks its work onto the pool, which steals.

## Detailed design

### 1. A spawn waits where an idle loop finds it

- **Today:** `zs_loop_spawn` puts the work in the inbox of loop `T.next % T.n`. A loop busy
  with a long turn holds its spawns back while its neighbours sleep in `epoll_wait`.
- **Proposed:** the work goes on the spawning thread's deque (the pool's `par_deque`, which a
  loop thread takes the first time it forks already), and a loop thread with nothing ready takes
  one from its own or steals one before it waits. The work is a closure the compiler marked
  shared, as a job's is, so the deque's rules hold unchanged. Starting it is what `box_take`
  does with it now; from there the task is that loop's to the end.
- **Waking:** a sleeping loop is woken through its inbox's wake descriptor, as a fork wakes a
  sleeping worker: push, then read the count of sleeping loops, both sequentially consistent,
  so no wake is lost (`run_jobs`' argument).
- **Cancelling one not started:** `Task.spawn`'s state word has the case already (-1), and the
  thread that takes the work finds it.
- **Order:** spawns from one thread start oldest first when it's the thieves that take them
  (the deque's top). Today's order across loops is unspecified already.

### 2. `Task.blocking` on the pool's spares

- **Proposed:** `zs_loop_blocking` forks a pool job that announces itself blocked for its whole
  run (`par_block` before the call, `par_unblock` after), and fulfills a token on its loop
  (`zs_loop_expect`, which `Task.spawn` uses). The helper thread, its queue and its condition
  variable go.
- **Bound:** at most twice the cores run at once (the spares' cap); past it a call waits for a
  spare, where today it waits for the one helper. `Process.wait`, `File.readAllText` and the
  name lookups stop queueing behind one another.
- **What changes for a program:** two blocking calls from one loop may now run at once. A
  library that counted on the helper's order (*Unresolved questions*, 2) needs a `Mutex`, or a
  `Task.blockingInOrder` that keeps today's meaning.
- **Then:** `Tools.zs`' `Task.spawn (fun () -> Task.blocking …)` becomes `Task.blocking …`,
  once stage 0 is a release with this.

### 3. `Channel` for tasks

```fsharp
Channel.sending   : Channel<'a> -> 'a -> Task<unit>       // waits, as a task, while it's full
Channel.receiving : Channel<'a> -> Task<option<'a>>       // None once closed and empty
Channel.give      : Channel<'a> -> 'a -> Alt<unit>
Channel.take      : Channel<'a> -> Alt<option<'a>>
```

(Names to settle; `send` and `receive` keep blocking their thread, for jobs.)

- **A waiter** is a token on its loop (`zs_loop_expect`) in the channel's list, under the
  channel's lock. A sender on any thread that finds one moves its value into the token's slot
  and fulfills it; a cancelled task's waiter is taken out of the list on its own loop.
- **As a branch of a choice** is the hard part. A `Pick` goes over on its loop, without a lock;
  a sender on another thread can't know whether the waiter it found still wants the value.
  Giving a value back after another branch won breaks the order of the channel and the meaning
  of `Alt.choose` (it's `Task.race`'s defect). Two ways, to choose between by measuring:
  - **Reserve, then confirm:** the sender marks the head value reserved for the waiter and
    fulfills its token; the waiter's loop commits (takes it) or releases it, and the value never
    left the channel. Correct by construction; a busy loop holds the head for a turn.
  - **An atomic pick** for a sync with a branch on a `Channel`: `over` is a compare-and-swap,
    the sender commits it from its thread, and the loop's other branches lose to it. Faster,
    and it puts a second kind of `Pick` in `Alt.zs`, with every undo run on the owner's loop.
- **`Alt.waitFor fd write`,** a descriptor's readiness as a branch, belongs here too: on one
  loop, so it needs neither.

### 4. One count of threads

After 1 and 2 the loop threads and the workers share deques and spares, and what's left is the
count: `ZS_WORKERS` threads of each. Whether a loop thread with nothing ready should run jobs
(and how a long job then delays its descriptors), or the pool should run fewer workers while
loops are busy, is decided by `bench/echo` with `--threads` and a `Parallel.for` per request,
not here. Nothing is built for it before that number exists.

### What stays out

- **A handler installed inside a task around its waits,** and a stop across a wait: track G's
  item 4, with its own design (which clauses may resume after a wait, and what a stop cancels).
  This proposal doesn't change it and doesn't depend on it.
- **Completion-based I/O:** track S's item 14.
- **Failure:** 0035.

### Order of implementation

1. The measurements (*Performance*), on today's runtime: no code changes.
2. `Task.blocking` on spares (gap 2): the smallest, and it deletes code.
3. Spawns on deques (gap 1).
4. `Channel.sending` and `receiving`; then the `Alt`s, after the choice above.
5. The count (gap 4), if step 1's numbers ask for it.

## Drawbacks

- **Blocking calls at once** is a change of behaviour a test can miss (2 above).
- **A loop thread with a deque** is registered with the pool for as long as it lives; the
  `PAR_OTHERS` deques (1,024) bound the threads that fork, as now.
- **A second way to use a `Channel`,** and a second channel type still (`Ch`, for one loop,
  with no lock): the guide has to say which is for what.

## Alternatives

- **Tasks that move once started** (the draft; Go, Tokio's multi-thread runtime): the cost is
  above. Reopened only by a measurement gap 1 doesn't answer.
- **A `Fiber` type:** a name for a started task, with states `Cancel` and `Promise` hold
  already, and an `Atomic` a chip pays for.
- **`select { }`:** syntax for `Alt.choose`; a language change with no new meaning.
- **Tasks on an `Async` effect:** measured twice, seven allocations a wait against none
  (decision 72).
- **A blocking pool of its own:** a third set of threads, where the spares are that pool.
- **A global queue for spawns:** one contended queue; 0008 chose deques over it for forks.
- **Splitting `rt.c`:** not needed by any step here.

## Compatibility

- **Not breaking** in types or names: `Task`, `task { }`, `Alt`, `Ch`, `Parallel` and `Channel`
  keep theirs, and four functions are added.
- **Behaviour:** `Task.blocking`'s calls from one loop may overlap (2); a spawned task's loop
  isn't round-robin (it never was specified).
- **Stage 0:** the compiler uses `Task.blocking` and `Task.spawn`, built by 0.7.1's runtime
  until the pin moves; its code can't count on the new behaviour before then. Its output
  mustn't depend on which loop a spawn lands on (rule 7): today it reads pipes there, in order
  by `Task.all`.
- **A chip:** unchanged. `Task.spawn`, `Task.blocking` and `Channel` aren't there.
- **A program without threads:** unchanged, to the byte.

## Pragmatics

### Diagnostics

Compile time: none new (`Channel`'s values are checked Share where the channel is made). Run
time: none new; `Channel.sending` to a closed channel panics as `send` does.

### Tooling

`--sanitize=thread` over the new tests. `ZS_STATS=1` counts spawns stolen before they started,
blocking calls that waited for a spare, and channel waiters fulfilled across threads.

### Performance

Measured before each step and after, on `bench/host`'s machine:

| | Today | To hold or beat |
|---|---|---|
| allocations per wait (`tests/task/awaits.zs`) | 0 (7 for the task) | the same |
| `bench/alt` against Hopac | its report's | the same: a sync on one loop takes no lock |
| echo, one loop, 10,000 connections | 26 MB, flat (`bench/echo/soak.sh`) | the same |
| echo `--threads`, even and skewed load | to measure | no worse even; better skewed |
| eight `Task.blocking` calls of 100 ms from one loop | to measure (one helper: 800 ms expected) | about 100 ms |
| a `Channel` between a pool job and a task | a loop thread blocked | no thread blocked |

The draft's list (a million fibers, Go, Tokio, Eio) compares runtimes; these compare the
change. A cross-runtime table belongs in `docs/reports/host.md` if it's wanted.

### Scaling

| Dimension | Typical | Upper bound |
|---|---|---|
| spawns waiting to start | 0–100 | 100,000 (a listener's burst), a deque slot each |
| blocking calls at once | 1–8 | twice the cores, the rest waiting |
| waiters on a `Channel` | 1–10 | one per task: a list under the channel's lock |

### Culture-aware formatting and parsing

None.

## Unresolved questions

1. **Does skew after placement matter?** The measurement that would reopen moving tasks: echo
   with `--threads` under connections whose cost changes after they're accepted. If it does,
   the first answer to try is in the program (fork the work), not the runtime.
2. **`Task.blocking`'s order.** Does anything count on one helper per loop running calls in
   turn? `lib/std` and `packages/sqlite` are to be read for it before step 2; a C library with
   a handle that isn't thread-safe is the case.
3. **Reserve-and-confirm or an atomic pick** for a `Channel` in a choice (3).
4. **The names** of `Channel`'s four functions, against `Ch`'s `give`, `take`, `send` and
   `receive`.
5. **Should an idle loop thread run pool jobs** (4)? It ties a descriptor's latency to a job's
   length.
6. **A blocking call inside a pool job** (0008's question 2) is the same code after step 2;
   is it then simply allowed?

## History

- **2026-11-16:** rewritten from the draft "Lightweight fibers and a unified concurrency
  runtime", read against `Task.zs`, `Alt.zs`, `rt.c` and DESIGN §6 to §7.1.
