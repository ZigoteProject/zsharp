# Proposal 0035: contained jobs: a panic's boundary inside a program

| | |
|---|---|
| **Status** | Implemented (after 0.7): `Contained.run` and `Contained.task`, as designed but for what *As built* lists |
| **Decided at** | the go-ahead to build it, 2026-11-14 ([decision 86](../../DESIGN.md#13-decisions)) |
| **Builds** | after 0.7 |
| **Rests on** | [DESIGN §2.1](../../DESIGN.md) and decision 5 (a panic stops the program: no unwinding, can't be caught); §5.2 and decision 44 (arenas); §7 and §7.1 (`Share`, `share<F>`, how a value crosses threads); §6 (tasks) |
| **Related** | [0033](0033-library-failure-and-typed-handles.md) (the same jump out of a panic, for a C host; its question 1); [0008 threads](0008-threads.md); [0036 snapshots](0036-snapshots.md) (the same copy of a value's objects); [ROADMAP.md](../../ROADMAP.md)'s review of errors ("a panic has no boundary below the process") |
| **Changes** | decision 5's row and DESIGN §2.1, §5.2 and §7.2; the specification's §10 (execution); the guide; a new `lib/std/Threading/Contained.zs`; `runtime/rt.c`; a copy function per type in the compiler. No syntax |

- [x] Approved in principle
- [ ] Discussion
- [x] Implementation (`tests/contained/`, `examples/service`, `bench/contained/`; reviewed in [docs/reports/contained-jobs.md](../reports/contained-jobs.md))

## Summary

A **contained job** is a function run with memory of its own, whose panic ends it and not the
program: its caller gets `Error` with the message and goes on. Nothing unwinds. It's sound
because of what Z# checks already: the function is a `share<F>`, so nothing it can leave
half-updated is reachable from outside it.

```fsharp
Contained.run  : share<unit -> 'a> -> result<'a, Panic>              // 'a is Share
Contained.task : share<unit -> Task<'a>> -> Task<result<'a, Panic>>

let answer (index: Index) (request: Request) : Task<Response> =
  task {
    let! r = Contained.task (fun () -> handle index request)
    match r with
    | Ok response -> return response
    | Error p -> return Response.failed p.message    // this request failed; the server goes on
  }
```

(`Index`, `Request` and `Response` are the program's own types; `Panic` is `{ message: string }`.)

## Motivation

**A panic is a bug, and a bug in one request shouldn't end the others.** The roadmap's review
says it: "a panic has no boundary below the process: a server's one bad request ends it. A task
or a job as a panic's boundary would need unwinding, which decision 5 declined."

- **A server:** an index out of bounds in one handler closes every connection.
- **A tool over many inputs** (a language server, a build server, a batch converter): one
  document that finds a bug loses the work on all the others.
- **A library under a host** (0033): its question 1 asks whether a host may call the library
  again after a failure, and says no, because "the objects the panic left half-updated are
  reachable from the next call, and nothing marks them."

**Without the feature:** a supervisor process that restarts the program, or a child process per
unit of work and a pipe, with every value serialized both ways and no immutable data shared.

**Why it needs no unwinding here.** Unwinding exists to put a program's state right on the way
out: counts, locks, half-made updates. A contained job has no state to put right:

1. **What it could break, nobody else can reach.** A `share<F>` captures only `Share` values
   and reaches no top-level value that isn't one (DESIGN §7), so the mutable cells it writes
   (`ref`, `Buffer`) are ones it made. What it shares with the rest is immutable, or an
   `Atomic`, `Mutex` or `Channel`, whose every change is whole.
2. **Its memory goes at once.** What it allocates comes from an arena of its own (§5.2).
3. **It leaves by a jump** to its entry, as 0033's failed library does.

[Goose](https://aardappel.github.io/goose/)'s contained threads do this by giving each thread
its own memory and copying every message. Z#'s types allow sharing what's immutable instead.

## Detailed design

### What crosses, and how

A job's memory is blocks of its own, opened at its entry. One rule keeps it separable: **a job
owns no count outside its memory, and nothing outside holds a pointer into it.**

- **Whose an object is** is in its header: the byte the pool keeps for where an object came
  from says "a job's". (The draft told a job's objects by their count's sign, above 0. That's
  wrong for an object of the job's that gets marked shared: one a weak reference is made to,
  one an inner job's function captures. A copy out must still copy those.)
- **In.** The closure crosses as at any crossing of §7.1, without decision 75's move: its
  object graph is marked shared, and the runtime holds it until the job ends. Inside a job a
  shared object's count isn't changed: in a program with contained jobs, the shared branch of
  `dup` and of a drop calls the runtime, which tests a thread-local. (The draft took that
  branch for a call already. It was two atomic instructions inline, and still is in a program
  without jobs.) The held closure keeps those objects alive.
- **Arriving later.** A value that comes to a running job from outside it is marked shared and
  added to the job's held values, released when the job ends: what `Mutex.get` and `update`
  give, `Channel.receive`'s and `Spsc.pop`'s message, the result of a `Parallel.*` job, a
  Share value's handle read back from C, and a `Mutex`, `Channel`, `Spsc` or `Atomic` the job
  makes (allocated outside its memory, since others may keep it). `Weak.get` in a job takes no
  count: what a job can reach, it holds already.
- **Out.** A value leaving a job is copied out of its memory, into no job's, by a function per
  type as the marking is: `Channel.send`'s and `Spsc.push`'s message, what `Mutex.make`, `set`
  and `update` put in, a `share<F>` given to `Parallel.*`, `Task.spawn` or `Task.blocking`, and
  a Share value given to C as a handle. The job's result is copied the same way, into the
  memory of what started the job (an outer job's, or none's). The job's objects are copied,
  sharing between them kept (an object whose count isn't 1 is looked up in a table while the
  copy runs); an object from outside is referred to, with a count for the copy.
- **The end,** by returning or by a panic: the job's blocks and its big objects (the system
  allocator's, so the job lists them) are freed whatever is live in them, then the held values
  are released. A job in a job hands what it held to the outer one when it returns: its
  result, now in the outer job's memory, may refer to them.

### A panic in a job

It prints its message and backtrace and runs the panic hook, as today. Then:

1. The thread jumps (`longjmp`) to the innermost job's entry, which set the jump on the way in
   (registers only, no signal mask). No count is dropped and no `use` is disposed on the way.
2. A mutex the job holds is unlocked with the value it had: `Mutex.update` replaces the value
   only when its function returns, so there's nothing to poison. The job lists the mutexes it
   holds.
3. What the runtime opened for the job is closed: its descriptors (files, sockets, a started
   process's pipes), timers and waits in the event loop, as a cancelled task's are. A
   descriptor is the job's when the runtime opened it in the job; it's closed whoever the job
   gave its number to.
4. What the runtime kept that pointed into the job goes: its weak references leave the table,
   a thread's handle C still holds is emptied (using it panics), a helper thread's or another
   loop's answer for it is dropped when it comes, and a pool job it forked and didn't join is
   taken back unrun, or left to the thread that's running it, which drops its result.
5. The job ends as above, and `run` returns `Error { message }`. An effect's yield that the
   panic interrupted is over.

**Not contained:**
- **A stack overflow and running out of memory** stop the program, as today, and so do the
  runtime's own failures raised with a lock held or a table half changed (a thread that can't
  start, the kernel's queue refusing a descriptor): each is marked in `rt.c` (`zs_fatal`).
- **What C holds:** a library's handle open in the job (a statement, a session) isn't closed.
  C can't be given what would dangle: passing a `callback<share<F>>` in a job panics (C may
  keep it past the job), and a thread's handle (a value that isn't Share) made on one side of
  a job's boundary panics when used on the other.
- **What already happened outside:** bytes written, a message sent, a mutex updated.
- **Work the job forked** to other threads isn't in the job: a panic there stops the program
  (question 1).

C frames between the panic and the entry (`qsort` calling a Z# comparison) are discarded, as
0033 says of them.

### Tasks

`Contained.task` runs a task, and the tasks it awaits on its loop, as one job. A task's
continuation is a closure made in the job, so it's in the job's memory, and the loop finds the
job from the closure's address (a block's start names its job): it makes that job current (its
memory, its jump) around each resume. A panic in any resume ends the job; the awaiting task
gets `Error`. A closure from outside handed to the loop in a job runs outside it.

Cancelling the awaiting task cancels the job's task in the job first (its `use` values are
disposed, its waits undone), then the job ends. A job's task that fails while a spawned task or
a helper thread works for it doesn't cancel them: their answers come back to no one. The jobs
of tasks started in a job, or left on a loop that closes, end with it.

### Effects

A `share<F>` performs no effect its caller handles (§6.1), so a job can't use a handler
installed outside it: a clause would run the caller's code in the job's memory. A service's
context, log and clock handlers are installed inside the job (question 5).

### Where

Programs and libraries on Linux, macOS and Windows (`rt.c`). Not a chip (no `setjmp` in
`rt-embedded.c`; a firmware resets) and not WebAssembly, so `Contained` is in `lib/std`, and
using it for those targets is the compile error the rest of `std` gives.

### As built

In the draft's order, with what changed on the way:

1. **The copy function per type** (`copyout.T` in `src/Gen/Helpers.zs`): it copies a slot's
   value in place, so the last field of a cell is copied by a tail call and a long list in a
   loop. There's no `Contained.copy` to test alone: outside a job nothing is a job's, so a
   copy there copies nothing. `tests/contained/copies.zs` tests it through results.
2. **`Contained.run`** (`tests/contained/basics.zs`, `memory.zs`: a thousand failed jobs take
   no memory from the system after the first, and leave nothing allocated).
3. **Arrivals and departures** (`crossings.zs`, `parallel.zs`, `resources.zs`).
4. **Descriptors, timers and waits** (`resources.zs`, `server.zs`).
5. **`Contained.task`** (`task.zs`, `server.zs`: a TCP server whose every connection is a job);
   `examples/service` answers 500. Its handler can't run whole in a job: SQLite's connection
   isn't Share, so the job works out what the request asks and the answer is made outside it.

The suite runs these under the address and thread sanitizers too, where each of a job's
objects is the system allocator's own.

## Drawbacks

- **Decision 5 gets its second exception:** Z# code now sees a panic, as a value. The risk is
  `Contained.run` used as `try`. Its cost (an arena, a copy out) and its `share<F>` argument
  make it a poor one, and the guide says what it's for: a supervisor, not an error path.
- **The runtime's burden.** Every way a value reaches a job must mark and hold it, and every
  way out must copy. One missed is a use-after-free in safe code. Each entry point gets a test
  under the sanitizers, and the list above is the specification's.
- **Copies.** A job's result and what it sends are copied; a large result costs its size.
- **A job's memory only grows** until it ends (an arena frees nothing), and so does its list
  of held values. It fits a request, not a worker that runs for hours (question 2). Measured:
  `examples/echo`'s server with each connection a contained task, 5,000 connections and 20
  round trips on each, peaks at 199 MB where the server without jobs peaks at 14 MB.
- **No handlers from outside** (above).
- **Leaks remain:** C's resources, and what a half-done conversation leaves in a peer.

## Alternatives

- **Unwinding,** with landing pads and a `try`. Decision 5 declined it: code at every call,
  and a second way to handle errors.
- **A thread with wholly separate memory,** every value copied both ways (Goose, Erlang).
  Simplest to trust, but §7.1 already declined copying at the crossing: a job reading one
  large shared table would copy it each time. And Z#'s I/O is tasks on loop threads; a thread
  per request doesn't fit it.
- **Count shared objects as usual, and leak the job's counts on a failure.** No held values in
  the runtime, but each failed job leaves what it touched allocated for good.
- **Leak everything,** as 0033's failed library does. Right for a library that's never called
  again; a server would lose a request's memory at every bad request.
- **Poisoned mutexes,** as Rust's. Not needed: the value under the lock is the one before.
- **A child process.** It works today, and stays the answer for a stack overflow and for a
  crash inside C.

## Compatibility

- **Additive:** a new module. A program that doesn't use it builds to the same bytes: the
  runtime's parts are linked only with it, as the effects' yield state is.
- **Decision 5's row** gains "except by a contained job's caller", beside 0033's host.
- **Stage 0:** the compiler can use `Contained` (the language server, per request) only once a
  release has it.

## Pragmatics

- **Diagnostics:** the existing ones for a `share<F>`: what it captures, an effect in its row,
  and its result (`function crossing threads: Buffer<int> can't be shared between threads (it
  isn't Share)`; no wording of a job's own was added), and the `std` error on a chip. At run
  time the panic prints as it does now (question 4).
- **Tooling:** nothing new in the editor. `zs test` keeps a process per test: it also contains
  a stack overflow and a crash in C.
- **Performance,** measured (`bench/contained/run.sh`, `--release`, the report's machine): a
  job that does nothing takes 33 ns (the jump and the job's record; it takes no block until it
  allocates, and a thread keeps 16 blocks of the jobs that ended for the next ones); a job in
  a job 68 ns; a job that panics 1.5 µs, its message's printing aside. A megabyte of small
  objects (16,384 of them) made in a job costs 0.12 ms where it costs 0.10 ms outside one, and
  0.20 ms when it's the job's result, copied out and dropped by the caller: 80 µs a megabyte
  for the copy and its drop. What the caller shared with the job costs nothing to give back
  (37 ns for the job). A shared object's count through the runtime costs what it did inline
  (2.2 ns on one thread, 30 ns with 16 threads on the same objects, either way): no difference
  measured on `bench/contained/shared.zs`, where every count is a shared one.
- **Scaling:**

  | | Typical | Stress |
  |---|---|---|
  | jobs a second | 10⁴ (requests) | 10⁶ (one per small message) |
  | a job's memory | under 1 MB | 1 GB |
  | held values | tens | 10⁶ (a job receiving in a loop) |
  | jobs nested | 1–2 | 100 |

- **Culture-aware formatting:** none.

## Unresolved questions

Answered by what was built:

1. **Forked work** is outside the job (the draft's answer): a `Parallel.*` job runs outside
   every job, on whichever thread, the job's own included when its join runs it, and its panic
   stops the program. A job that fails doesn't wait for what it forked.
4. **A contained panic prints,** and the host's hook runs: a bug mustn't pass unseen.
6. **The runtime's own panics:** those raised with a lock held or a table half changed, and
   every "out of memory", are marked (`zs_fatal`) and stop the program in a job too. The rest
   (an index, a closed channel, a descriptor that isn't open) are raised with the runtime
   whole, and are the job's.

Open:

2. **Long-lived jobs:** a pool of the job's own instead of blocks that only fill, and held
   values released when dropped, for a worker that runs for hours? Or is that a different
   feature?
3. **Stack overflow:** contain it, jumping from the signal's stack?
5. **Handlers from outside:** an operation as a crossing (arguments copied out, the clause run
   outside the job, the answer held)? It's what a service's log and clock would want.
7. **C's resources:** a way for a package to register what to release when a job fails? Until
   then a value that isn't Share (a database's connection) can't enter a job at all, which is
   what keeps a job from leaving one half used, and what makes `examples/service` split a
   request's work in two.
8. **0033's question 1:** should an export under `zs_catch_panics` run as a job, so the
   library lives on?
9. **A job's own wording in the checker,** for a result or a capture that isn't Share
   ("crossing threads" is what it says today).
10. **A descriptor the job opened and gave away** (its number in a message) is closed when the
    job fails, under whoever has it. Leave it, and leak one a failure?

## History

- 2026-11-14: drafted, from Goose's contained threads and the roadmap's review of errors.
- 2026-11-14: built, with these found on the way and changed in the text above. An object is
  a job's by its header, not by its count's sign (a job's own object can be marked shared, and
  must still be copied out). The shared branch of `dup` and drop becomes a call only in a
  program with contained jobs. C gets nothing of a job's that could dangle: no
  `callback<share<F>>` in a job, and a thread's handle stays on its side of a job's boundary.
  A weak cell is a job's own. The loop finds a callback's job from the closure's address
  rather than recording it. A failed job leaves what it forked instead of waiting for it. On
  Windows the jump is `_setjmp` without a frame (with one, `longjmp` unwinds). A program
  without a contained job is the bytes it was, checked against the commit before.
  Reviewed: [docs/reports/contained-jobs.md](../reports/contained-jobs.md).
