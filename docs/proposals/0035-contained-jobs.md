# Proposal 0035: contained jobs: a panic's boundary inside a program

| | |
|---|---|
| **Status** | Draft |
| **Decided at** | not yet: a design review |
| **Builds** | after 0.7 |
| **Rests on** | [DESIGN §2.1](../../DESIGN.md) and decision 5 (a panic stops the program: no unwinding, can't be caught); §5.2 and decision 44 (arenas); §7 and §7.1 (`Share`, `share<F>`, how a value crosses threads); §6 (tasks) |
| **Related** | [0033](0033-library-failure-and-typed-handles.md) (the same jump out of a panic, for a C host; its question 1); [0008 threads](0008-threads.md); [0036 snapshots](0036-snapshots.md) (the same copy of a value's objects); [ROADMAP.md](../../ROADMAP.md)'s review of errors ("a panic has no boundary below the process") |
| **Changes** | decision 5's row and DESIGN §2.1, §5.2 and §7; the specification's §10 (execution); the guide; a new `lib/std/Threading/Contained.zs`; `runtime/rt.c`; a copy function per type in the compiler. No syntax |

- [ ] Approved in principle
- [ ] Discussion
- [ ] Implementation

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

A job's memory is an arena opened at its entry. One rule keeps it separable: **a job owns no
count outside its arena, and nothing outside holds a pointer into it.**

- **In.** The closure crosses as at any crossing of §7.1, without decision 75's move: its
  object graph is marked shared, and the runtime holds it until the job ends. Inside a job a
  shared object's count isn't changed (the slow path of `dup` and drop, already a call in a
  program with threads, tests a thread-local). The held closure keeps those objects alive.
- **Arriving later.** A value that comes to a running job from outside it is marked shared and
  added to the job's held values, released when the job ends: what `Mutex.get` and `update`
  give, `Channel.receive`'s message, the result of a `Parallel.*` job or a spawned task,
  `Weak.get`'s object, and a `Mutex`, `Channel` or `Atomic` the job makes (allocated outside
  the arena, since others may keep it).
- **Out.** A value leaving a job is copied out of the arena, into the memory of the thread it
  goes to, by a function per type as the marking is: the job's result, `Channel.send`'s
  message, what `Mutex.set` and `update` put in, and a `share<F>` given to `Parallel.*`,
  `Task.spawn` or `Task.blocking`. Objects of the arena are copied, sharing between them kept;
  a shared object the walk reaches gets a count for the copy.
- **The end,** by returning or by a panic: the arena's blocks and the job's big objects (which
  are `malloc`'s today, so the job lists them) are freed whatever is live in them, then the
  held values are released.

### A panic in a job

It prints its message and backtrace and runs the panic hook, as today. Then:

1. The thread jumps (`longjmp`) to the innermost job's entry, which set the jump on the way in
   (registers only, no signal mask). No count is dropped and no `use` is disposed on the way.
2. A mutex the job holds is unlocked with the value it had: `Mutex.update` replaces the value
   only when its function returns, so there's nothing to poison. The job lists the mutexes it
   holds.
3. What the runtime opened for the job is closed: its descriptors (files, sockets), timers and
   waits in the event loop, as a cancelled task's are.
4. The job ends as above, and `run` returns `Error { message }`.

**Not contained:**
- **A stack overflow and running out of memory** stop the program, as today.
- **What C holds:** a library's handle open in the job (a statement, a session) isn't closed.
- **What already happened outside:** bytes written, a message sent, a mutex updated.
- **Work the job forked** to other threads isn't in the job: a panic there stops the program
  (question 1).

C frames between the panic and the entry (`qsort` calling a Z# comparison) are discarded, as
0033 says of them.

### Tasks

`Contained.task` runs a task, and the tasks it awaits on its loop, as one job: a task made in a
job records it, and the loop makes that job current (its arena, its jump) around each resume.
A panic in any resume ends the job; the awaiting task gets `Error`. One load and one store per
resume, in a program that uses `Contained`.

### Effects

A `share<F>` performs no effect its caller handles (§6.1), so a job can't use a handler
installed outside it: a clause would run the caller's code in the job's arena. A service's
context, log and clock handlers are installed inside the job (question 5).

### Where

Programs and libraries on Linux, macOS and Windows (`rt.c`). Not a chip (no `setjmp` in
`rt-embedded.c`; a firmware resets) and not WebAssembly, so `Contained` is in `lib/std`, and
using it for those targets is the compile error the rest of `std` gives.

### Order of implementation

1. The copy function per type, tested alone (`Contained.copy`, internal): sharing kept, a
   shared object counted, under `--sanitize`.
2. `Contained.run` on one thread: the arena, held values for the closure, the jump, the result
   copied out; `tests/contained/` (a panic's message, the program going on, memory given back
   under `ZS_LEAKCHECK=1` after a thousand failed jobs, a nested job).
3. Arrivals and departures: `Mutex`, `Channel`, `Weak`; a mutex held at the panic.
4. Descriptors and timers closed at a failure.
5. `Contained.task`; `examples/service` answering 500 for a request that panics, under
   `bench/echo/soak.sh`'s load.

## Drawbacks

- **Decision 5 gets its second exception:** Z# code now sees a panic, as a value. The risk is
  `Contained.run` used as `try`. Its cost (an arena, a copy out) and its `share<F>` argument
  make it a poor one, and the guide says what it's for: a supervisor, not an error path.
- **The runtime's burden.** Every way a value reaches a job must mark and hold it, and every
  way out must copy. One missed is a use-after-free in safe code. Each entry point gets a test
  under the sanitizers, and the list above is the specification's.
- **Copies.** A job's result and what it sends are copied; a large result costs its size.
- **A job's memory only grows** until it ends (an arena frees nothing), and so does its list
  of held values. It fits a request, not a worker that runs for hours (question 2).
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

- **Diagnostics:** the existing ones for a `share<F>` (what it captures, an effect in its row).
  New: `the result of a contained job must be Share: Buffer<int> isn't`, and the `std` error on
  a chip. At run time the panic prints as it does now (question 4).
- **Tooling:** nothing new in the editor. `zs test` keeps a process per test: it also contains
  a stack overflow and a crash in C.
- **Performance,** measured before the review: a job that does nothing (the jump, the arena's
  first block, which wants a cache of blocks); the copy out per megabyte; the shared slow
  path's test on `bench/host`'s parallel programs.
- **Scaling:**

  | | Typical | Stress |
  |---|---|---|
  | jobs a second | 10⁴ (requests) | 10⁶ (one per small message) |
  | a job's memory | under 1 MB | 1 GB |
  | held values | tens | 10⁶ (a job receiving in a loop) |
  | jobs nested | 1–2 | 100 |

- **Culture-aware formatting:** none.

## Unresolved questions

1. **Forked work:** is a `Parallel.*` job or a spawned task started in a job part of it (its
   panic ends the job), or outside (the draft: it stops the program)?
2. **Long-lived jobs:** a pool of the job's own instead of an arena, and held values released
   when dropped, for a worker that runs for hours? Or is that a different feature?
3. **Stack overflow:** contain it, jumping from the signal's stack?
4. **Should a contained panic print?** The draft prints: a bug mustn't pass unseen. A
   supervisor that logs it again may want to say otherwise.
5. **Handlers from outside:** an operation as a crossing (arguments copied out, the clause run
   outside the arena, the answer held)? It's what a service's log and clock would want.
6. **The runtime's own panics** (a made-up descriptor): is each raised with no runtime lock
   held, so the jump leaves the runtime whole?
7. **C's resources:** a way for a package to register what to release when a job fails?
8. **0033's question 1:** should an export under `zs_catch_panics` run as a job, so the
   library lives on?

## History

- 2026-11-14: drafted, from Goose's contained threads and the roadmap's review of errors.
