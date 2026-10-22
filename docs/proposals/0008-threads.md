# Proposal 0008: threads: forking from any thread, waiting jobs, cancelling across threads, C on other threads

| | |
|---|---|
| **Status** | Approved in principle; implementation in progress (phase 9.5) |
| **Decided at** | the phase 9.5 plan ([ROADMAP](../../ROADMAP.md#phase-95-incremental-builds-and-threads)), closing known gap 1 |
| **Builds** | phase 9.5 |
| **Rests on** | decisions 22 (threads), 45 (Z# objects in C as handles), 47 (`share<F>`), 48 (a loop per thread) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §7](../../DESIGN.md#7-parallelism) and §7.1 |
| **Related** | [0002 effect handlers](0002-effect-handlers.md) (handlers are per thread), [0016 async on bare metal](0016-async-bare-metal.md) |

- [x] Approved in principle
- [ ] Discussion
- [x] Implementation (in progress: the pool's spare threads are in `rt.c` already; this document records the design as the working tree builds it)

## Summary

Four gaps phase 7 left, each closed where it sits in the runtime or the library:

| Gap today | After |
|---|---|
| parallel work started outside the pool (a spawned task, `Task.blocking`'s helper) runs on that thread alone | any thread forks onto the pool: it gets a deque the first time, workers steal from it, and it joins as a worker would |
| a pool job that waits on a channel holds its thread, so a channel between two jobs needs room for what one sends first | a worker that blocks tells the pool, which starts a spare thread until it wakes (Java's `ForkJoinPool.ManagedBlocker`), so a channel of capacity zero works between jobs |
| cancelling a task doesn't stop the tasks it spawned on other threads | the cancellation goes to each child's loop through that loop's inbox, and the child disposes its `use` values there |
| C calling Z# callbacks or handles from other threads isn't checked | a handle or callback over a `Share` value is marked shared when made and works from any thread; any other remembers its thread and panics when used from another, naming its type |

## Motivation

- **Parallel code inside a spawned task** is the normal shape of a server: `Task.spawn` runs a connection's task on another loop, and `Array.Parallel.map` inside it should use every core. Today it runs on that one thread.
- **Channels between jobs** are how pipelines are written (`Parallel.both` a producer and a consumer); a producer that fills the channel before the consumer is scheduled deadlocks the pool when every worker is a blocked producer.
- **Cancellation across threads** is what `Task.timeout` over spawned work means; today the children keep running and their results are dropped.
- **C hosts are multi-threaded:** a library exported with `--lib` is called from whatever thread the host likes, and a non-atomic count on a handle used from two threads is a use-after-free. A check with the handle's type in the panic finds it at once.

## Detailed design

### Forking from any thread

- **A deque per forking thread.** The pool's workers each own a Chase–Lev deque. A thread outside the pool (a loop thread, `Task.blocking`'s helper, a C host's thread calling an exported function that uses `Parallel`) gets a deque of its own the first time it forks, kept in a thread-local and registered with the pool so idle workers steal from it. Today such a thread runs the job itself (`zs_par_fork`'s `me < 0` branch).
- **Joining:** the forking thread pops its own deque, steals from others, and runs jobs while it waits, as a worker does. It isn't counted as a worker for `ZS_WORKERS`, and its deque is unregistered when the thread ends.
- **Results** come back to the joining thread unmarked, as today (DESIGN §7).

### Waiting jobs

- **Blocking is announced:** `Channel.receive` and `send` (when they must wait) and `Mutex.lock`'s slow path, run on a pool worker, call `zs_par_blocking(1)` before parking and `zs_par_blocking(0)` after. The pool counts active workers; when one blocks and no idle worker exists, it starts a spare thread (up to a cap, twice the core count), and a spare that finds the active count full when a blocked worker wakes parks itself and is reused later.
- **Why not run other jobs while waiting:** a job run on the waiting job's stack could wait for what the waiting job holds (a mutex, a channel slot), and deadlock; nested joins on a fork-join tree are safe, blocking on a channel isn't. The spare thread keeps the pool's throughput without nesting.
- **Short waits** (a mutex held for a few instructions) spin before announcing, so uncontended locks cost nothing more.

### Cancelling across threads

- **Registration:** `Task.spawn` registers the child's cancellation under the parent's as `both` and `race` do on one loop, with the child's loop thread recorded.
- **Delivery:** cancelling posts a message to the child's loop through its inbox (the pipe each loop's epoll watches, which `Task.spawn`'s result and `Task.blocking`'s completion use already). On that thread the child's `cancelNow` runs: its wait is dropped and its `use` values disposed, newest first, on the thread that owns them (tasks don't move, decision 48).
- **Results** of a cancelled child are dropped when they arrive; the parent's `Task.spawn` result completes with the cancellation, as a cancelled `both` does.

### C on other threads

- **Shared handles:** a `zs_handle` or a `callback` made from a value whose type is `Share` is marked shared when it's made (its object graph's counts turned negative, DESIGN §7.1), so `zs_retain`, `zs_release` and calls through it are atomic and valid from any thread.
- **Other handles** record the thread that made them (a word in the handle). Use from another thread panics: `panic: a handle of Tree used from another thread (make its type Share, or use it on the thread that made it)`. The check is one compare per use.
- **Callbacks** (`callback<F>`) are borrowed for the call (decision 31), and the same rule applies to the call: a non-Share closure called from another thread panics naming the function's type.

### Order of implementation

1. Deques for forking threads; the spawned-task `Parallel.for` exit test.
2. Blocking announcements and spare threads; the capacity-zero channel exit test.
3. Cancellation through inboxes; the `use`-disposal exit test.
4. Handle thread checks; the Helgrind exit test.

## Drawbacks

- **Spare threads** can grow to the cap under a flood of blocking jobs, and each costs a stack. The cap bounds it, and a program that blocks every worker is one that wants `Task` instead.
- **A word per handle** for the thread id, and a compare per use.
- **Cancellation is asynchronous:** a child on another thread stops at its next wait, not at once, as on one loop.

## Alternatives

- **A global injection queue** (Java's `ForkJoinPool` submissions): one contended queue for every outside thread; per-thread deques keep the stealing design uniform.
- **Running jobs while blocked:** deadlock-prone (above).
- **Atomic counts on every handle:** every handle pays for the rare multi-threaded host; the mark on creation costs once.
- **Cancellation by polling** (a flag the child checks): the child already has a loop to receive messages, so delivery is cheaper than a shared flag read per await.

## Compatibility

- **Not breaking:** every change takes effect where a program today runs alone, deadlocks or isn't checked. `ZS_WORKERS` keeps its meaning.
- **C hosts** that used a non-Share handle from two threads were racing already; they now panic with the type.

## Pragmatics

### Diagnostics

Compile time: none new. Run time: the handle panic above, and `panic: the pool's spare threads are exhausted (N blocked jobs)` when the cap is hit with every worker blocked, rather than a silent hang.

### Tooling

- **`--sanitize=thread`** runs the new tests; Helgrind runs the handle test under valgrind.
- **`ZS_STATS=1`** ([0011](0011-debug-info-profiles-traces.md)) counts spare threads started and jobs stolen from outside deques.

### Performance

- **Existing code:** fork and join on pool threads are unchanged; the blocking announcement is on the slow path of channels and mutexes only.
- **Outside threads:** a fork costs a deque push and a possible wake, as inside the pool.
- **Handles:** one compare per use.

### Scaling

| Dimension | Typical | Upper bound |
|---|---|---|
| threads forking from outside the pool | 1–8 (loop threads) | 1,000 (a C host's threads), each with a deque registered |
| spare threads | 0–2 | twice the core count |
| spawned tasks under one cancellation | 10 | 100,000 (the echo server's connections), one inbox message each on cancel |

### Culture-aware formatting and parsing

None.

## Unresolved questions

1. **The spare-thread cap:** twice the core count here; a `ZS_WORKERS_MAX` for programs that know better.
2. **Which waits announce:** channels and the mutex slow path here; `Task.blocking` inside a pool job (a job awaiting a task) is a shape to decide against or support.
3. **Cancellation of a child mid-C-call:** a `Task.blocking` child can't be interrupted; it's cancelled when it returns, as on one loop.

## History

- **2026-10-22:** drafted from phase 9.5's plan and DESIGN §7.
