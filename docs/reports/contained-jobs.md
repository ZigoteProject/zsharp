# Contained jobs: a security and a performance review

**Question:** [proposal 0035](../proposals/0035-contained-jobs.md) lets a panic end a job and
not the program, without unwinding. Is that sound (nothing reachable without `unsafe` reads or
writes memory it doesn't own, races, or leaks a failed job's memory), and what does it cost: a
job, a job's result, and a program that has no job at all?

**Answer:** as built and tested, yes, with what's listed under *What it doesn't cover*. A job
that does nothing takes 33 ns, a job's result costs its copy (80 µs a megabyte of small
objects, copied and dropped), a shared object's count costs what it did, and a program without
a contained job is the bytes it was. The review is the author's own, made while building it, with the sanitizers as its second
reader: five defects were found in the first version and fixed before the commit. They're
listed, since each is a way the design fails if the rule behind it is forgotten. A reader who
didn't write the code was started on `runtime/rt.c` and stopped before it reported: that
review is still owed.

## Setup, 2026-11-14

| | |
|---|---|
| Machine | AMD Ryzen 7 PRO 8840U (8 cores, 16 threads), the dev container (`./dev`: Fedora 44, LLVM 23.1.4) |
| Code | the working tree that became the commit: `runtime/rt.c` (the job, under `ZS_CONTAINED`), `src/Gen/` (the copy function per type, the crossings), `lib/std/Threading/Contained.zs` |
| Tests | `tests/contained/` built as they are, with `--sanitize` (AddressSanitizer and UndefinedBehaviorSanitizer, leaks counted) and with `--sanitize=thread`; for aarch64 Linux under qemu and for Windows under Wine; macOS built only |
| Times | `bench/contained/run.sh`, `--release`, the best of three runs |

## The rule, and where it's kept

A job's memory can go whole, with no drop run, because *a job owns no count outside its
memory, and nothing outside holds a pointer into it.* Every way a value reaches a job or leaves
one has to keep that, and so does everything the runtime remembers on a job's behalf. The
review went through them one by one.

| Way in or out | What keeps the rule | Test |
|---|---|---|
| the job's function, and what it captured | marked shared; held by the job until it ends | `basics`, `memory` |
| a shared object's count, in a job | the runtime doesn't change it (`zs_dup_shared`, `zs_release_shared`) | `memory` (the table is whole after 2,000 jobs, and nothing is left allocated) |
| `Mutex.get`, `Mutex.update`'s result | a count taken outside the job, held by it | `crossings` |
| `Channel.receive`, `Spsc.pop`, a pool job's result | marked shared and held on arrival | `crossings`, `parallel` |
| `Channel.send`, `Spsc.push`, `Mutex.make`, `set`, `update` | copied out of the job first | `crossings` |
| a function for `Parallel.*`, `Task.spawn`, `Task.blocking` | copied out; the work runs outside every job | `parallel`, `resources` |
| the job's result | copied into its starter's memory | `copies` |
| an `Atomic`, a `Mutex`, a `Channel`, an `Spsc` made in a job | allocated outside it, shared from its making, held | `crossings` |
| a callback the event loop holds | the loop finds its job from its address, runs it there, and forgets it when the job ends | `task`, `server` |
| another thread's answer for the job (a helper's, a spawned task's) | orphaned when the job ends: dropped when it comes | `resources` |
| a weak reference | the cell is the job's own, and leaves the table with the job; `Weak.get` in a job takes no count | `resources` |
| a handle C holds | a Share value's: copied out. A thread's: emptied when the job ends, and a panic to use across a job's boundary | not tested: the suite has no C host that keeps a handle of a program's |
| a callback C may keep (`callback<share<F>>`) | a panic to pass in a job | `c` |
| a descriptor the runtime opened | listed in the job; closed if it fails | `resources`, `server` |
| a mutex held by `Mutex.update` | listed in the job; unlocked if it fails, the value the one before | `crossings` |
| a pool job forked and not joined | taken back unrun, or left to the thread running it, which drops its result | `parallel` |
| an effect's yield the panic interrupted | reset where the outcome is read | `resources` |
| `Arena.with` | nothing in a job; around one, the job's result is the arena's | `resources` |
| the runtime's `io_error` text | cleared when it's the ending job's | read |

## What the review found

1. **A job's object told by its count's sign** (the draft's rule: above 0 is the job's). An
   object of the job's that's marked shared (a weak reference made to it, an inner job's
   function capturing it) would have been referred to by a copy, not copied, and the copy
   left pointing into the job's memory. Fixed in the design: the header says whose it is.
2. **The copy function's name was an array's copy-on-write function's** (`copy.array<T>`), so
   a closure capturing an array was copied by the wrong function, with a wrong size. The
   pool's build ran; AddressSanitizer reported it (`tests/contained/parallel.zs`). Renamed
   `copyout.T`.
3. **A failed job waited for the pool jobs it had forked,** which may be waiting for it. It
   takes back what no thread has taken and leaves the rest to the thread running it. The
   first version of that freed a job's record under a relaxed read of its state, which
   ThreadSanitizer reported; the compare-and-swap is sequentially consistent now.
4. **On Windows the jump's builtin (`__builtin_setjmp`) lost the entry's state:** every test
   ended at its first contained panic under Wine. `_setjmp` without a frame, as QEMU uses it,
   and the entry's locals in memory.
5. **C could be left with a pointer into a job** two ways the draft didn't name: a
   `callback<share<F>>`, and a thread's handle. Both are a panic now.

Also on the way: a scripted edit of the author's put its replacement between every character
of `runtime/rt.c`; the file was recovered exactly (the text removed again, the length checked)
and every test run again after it.

## What it doesn't cover

- **A stack overflow, running out of memory, and the runtime's own failures** stop the program
  in a job as outside one. Those the runtime raises with a lock held or a table half changed
  are marked (`zs_fatal`); the review read each of the other 23 places `rt.c` panics, and each
  is raised with the runtime whole.
- **C.** A job can't be handed a C library's handle (a `cptr` isn't Share), which is what keeps
  it from leaving one half used; one it opens itself and fails holding isn't released. The two
  ways C could be left with a pointer into a job panic instead (above). A package's `extern`
  functions are trusted as before.
- **A descriptor the job opened and gave away** (its number, in a message or its result's
  record on an earlier job) is closed if the job fails, under whoever has it by then: another
  thread could then write to a descriptor the system has given to something else. A job that
  returns normally closes nothing. It's the proposal's open question 10.
- **A panic inside a `Mutex.update`'s function leaves the mutex's value as it was,** but what
  the function did elsewhere before the panic (another mutex set, a message sent) stays done.
- **Work forked to other threads** runs outside every job: its panic stops the program, and a
  job that fails doesn't cancel a task it spawned.
- **A failed job's `use` values aren't disposed:** only what the runtime itself opened is
  closed.
- **A hang isn't a failure:** a job that never returns holds its memory and its thread.
- **A job's memory only grows** until it ends: see *What it costs*.

## What it costs

| | |
|---|---|
| a function called | under 1 ns |
| a job that does nothing | 33 ns |
| a job in a job | 68 ns |
| a job that panics (its message to `/dev/null`) | 1.5 µs |
| a megabyte of small objects (16,384) made and dropped, outside a job | 0.10 ms |
| the same made in a job, and left in it | 0.12 ms |
| the same made in a job, returned, and dropped by the caller | 0.20 ms |
| a megabyte of the caller's own, returned by a job | 37 ns |
| a shared object's count, one thread: inline (no job in the program), through the runtime (one) | 2.2 ns, 2.2 ns |
| the same, 16 threads on the same objects | 30 ns, 30 ns (29.5 to 35 across runs, either way) |

- **A job** is a record, a jump buffer filled, and the held function given up at its end. It
  takes no block until it allocates; a thread keeps 16 blocks (64 KB each) of the jobs that
  ended for the next ones, so `tests/contained/memory.zs`'s 2,000 jobs take nothing from the
  system after the first ten.
- **Allocation in a job** bumps through blocks and frees nothing but big objects, so it's the
  pool's speed on fresh memory: a fifth slower than the pool on a megabyte, where the pool is
  reusing what it just freed.
- **The copy out** is 5 ns an object here, the allocation included, and it's the whole cost of
  a result: nothing is paid for what the job doesn't return, and nothing for what the caller
  shared with it.
- **A long-lived job only grows.** `examples/echo`'s server with each connection a contained
  task (5,000 connections, 20 round trips each, none failed) peaks at 199 MB, where the server
  without jobs peaks at 14 MB: about 40 KB a connection, 1.8 KB a round trip never used again.
  A job is a request, not a connection; free lists in the job would lift that (the proposal's
  question 2).
- **A program without a contained job is the same bytes** as the commit before built it, debug
  and `--release`, on seven of the suite's programs (plain, threads, tasks, weak references,
  arenas), with the same compiler and the runtime's two texts at one path; and the compiler's
  IR for them is the same text. A sanitizer's build differs, by the runtime's line numbers.
- **A program with one** counts its shared objects through a call that tests one thread-local,
  and tests it again where a value crosses. No difference was measured.

## Not done

- macOS was built, not run; Windows ran under Wine, not on Windows.
- The handles' two rules have no test (above).
- `bench/echo/soak.sh`'s hour wasn't run: the load above is 20 seconds.
- The review by a second reader (above).
