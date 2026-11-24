# Proposal 0039: verifying the runtime's concurrency, starting with the pool's deque

| | |
|---|---|
| **Status** | Draft |
| **Decided at** | not yet; a design review |
| **Builds** | a spike first: the deque's check, then the contained jobs' held values |
| **Rests on** | [security.md](../contributing/security.md)'s first promise (safe code is memory-safe); [the ownership report](../reports/ownership-check.md), *What it doesn't cover* and *Next*; [the 0.7 review](../reports/security-review-0.7.md), R1-7 and R1-20; decision 22 (threads) in [DESIGN §13](../../DESIGN.md#13-decisions); the deque's own comment in `runtime/rt.c` |
| **Related** | [0008 threads](0008-threads.md); [0035 contained jobs](0035-contained-jobs.md) (the next protocol, and its owed second reader); [0010 properties and fuzzing](0010-properties-and-fuzzing.md) (the dynamic complement this doesn't replace) |
| **Changes** | `.devcontainer/Containerfile` (`cbmc`); a new `verify/` (the harness, the fault, `check.sh`, a short README); one line in `test.sh`; one constant and two marker comments in `runtime/rt.c`; a paragraph in `docs/contributing/testing.md`; a row in `AGENTS.md` once the directory exists. No change to a program's behavior |

- [ ] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

The safety promise has two instruments today: Rocq proofs of the ownership judgment (not of the
runtime), and dynamic tests (the leak check, AddressSanitizer, ThreadSanitizer) that cannot reach
every order of steps. The pool's deque sits where both are weak: the 0.7 review found a high
severity race there (R1-7), the fix's evidence was C harnesses the suite doesn't run, the code's
comment says ThreadSanitizer doesn't model its accesses, and no Z# program reaches the window
reliably. This proposal adds the missing instrument — bounded model checking of the runtime's C —
and makes the deque its first check.

The first check runs `dq_push`, `dq_pop` and `dq_steal` themselves (copied verbatim from
`runtime/rt.c` and diffed by the check), with two threads, small capacities, and one property:

> Every job pushed on a deque is claimed exactly once, by the owner's pop or by one thief; a
> resize while a thief reads loses no job and lets no second claimant take one.

The check includes the fault that R1-7 was: the thief pairing a ring with the other ring's
capacity. If the check passes on that fault, the check fails. It runs in the suite next to
`proofs/check.sh`, in seconds.

## Motivation

**The defect is real and the evidence is gone.** R1-7 and R1-20 (high): during a resize a thief
could pair the new buffer with the old capacity, so a job was lost and a join hung forever; or it
could pair the old buffer with the new capacity, read past it, and call through what was read. The
fix is the ring that carries its own capacity
([`runtime/rt.c`](../../runtime/rt.c), "a deque's ring of jobs"). The 0.7 review
recorded that the race "is proven by C harnesses, which the suite doesn't run (no Z# program
reaches the window reliably)". A later change to the deque can undo the fix with every check
green.

**The instruments don't cover it.** The suite's leak check and sanitizers are dynamic: they see
the orders that a run takes. The deque's own comment says its accesses are "release/acquire or
seq_cst operations rather than fences, which ThreadSanitizer doesn't model". And the Rocq
development proves the ownership judgment, which is a property of Core IR; the runtime's atomics,
shared counts and contained jobs are listed in the report as not covered.

**Why the runtime, and not more of the compiler.** The compiler already has the instrument that
fits it: the ownership checker, its mutation tests, and the Rocq proofs of its judgment. The
runtime has tests only, and the review's high severity findings in it are mostly concurrency
defects (R1-2, R1-3, R1-4, R1-7, R1-8, R1-9, R1-36). A proof of the judgment does not say the C
that implements it is correct.

**Without this proposal:** the deque's correctness rests on a comment and a report about harnesses
that no longer exist; the next race ships, on the platforms where the suite runs, silently.

## Detailed design

### The tool

**CBMC**, Fedora's package, a bounded model checker for C: it runs the code, explores thread
interleavings up to an unwinding bound, checks assertions and pointer safety, and prints a trace
of the steps that break one. It is chosen over the alternatives for three reasons: the code runs
as written (no hand model to drift), it explores every interleaving within the bound (the gap the
dynamic tests leave), and it is one package in the image, not a vendored download.

| Tool | Runs the C? | Every interleaving? | Weak memory? | Cost |
|---|---|---|---|---|
| **CBMC** | yes | within the bound | TSO, PSO, RMO and POWER through `goto-instrument --mm`; the first check uses sequential consistency | one dnf package |
| TLA+/TLC | no, a hand model | yes, within the model | no | Java and a pinned jar |
| GenMC | yes | yes, and C11 orders | yes | a source build, pinned and maintained |
| Rocq (today) | no | n/a | n/a | a memory model and the C semantics, to write |
| TSan, valgrind | yes | no | no | already in the suite |

The limit of the first check is stated in the check itself: a pass covers every interleaving of
the modeled steps under sequential consistency, at the bound; it does not prove the
release/acquire annotations sufficient. For those, the order below compares `goto-instrument
--mm`'s weaker models with GenMC's C11 model rather than assuming either one fits this code.

### The property

In the code's words:

- `dq_push` stores the job in a slot and publishes `bottom`; a full deque is copied into a ring
  twice as large, and the ring is published once.
- `dq_pop` takes from the bottom, and on the last job a compare-and-swap of `top` decides who
  gets it.
- `dq_steal` reads `top` and `bottom`, then the ring, and indexes the slot by the ring's own
  capacity; a compare-and-swap of `top` decides who gets it.

Two failure stories, told in those steps:

- **Lost:** the thief loads `top` and `bottom`, the owner resizes, and the thief indexes the new
  ring with the old capacity (or the old ring with the new one). It reads a slot that was never
  written or one outside the copied range; the compare-and-swap succeeds, and the job is never
  claimed. The owner joins and waits forever.
- **Double:** two claimants read the same slot, and both take it; the job runs twice and its
  result is freed twice. The compare-and-swap on `top` is what prevents this; the atomic claim
  counting below is what makes a violation visible.

The harness asserts, for every job id the test pushes:

```c
// claims is an _Atomic int array, zeroed before either thread starts.
int before = atomic_fetch_add_explicit(&claims[id], 1, memory_order_seq_cst);
__CPROVER_assert(before == 0, "a job is claimed at most once");
__CPROVER_assert(pushed[id], "no claim of a job that wasn't pushed");
// after both threads join, with the deque empty:
__CPROVER_assert(atomic_load_explicit(&claims[id], memory_order_relaxed) == 1,
                 "every pushed job was claimed");
```

### The harness

- `verify/deque.c` holds `runtime/rt.c`'s deque code between the markers `verify:begin deque`
  and `verify:end deque`, copied verbatim, and the harness's own `main`: an owner thread that
  pushes a few jobs and pops some, a thief that steals, a join, the assertions above. The payload
  is the harness's; the deque is the runtime's. The harness supplies what the copied code names
  but doesn't define — the pool's `P.old` list that keeps a replaced ring alive, `zs_fatal`, and
  the lock around them — so the copy needs no edit.
- `verify/check.sh` extracts the marked region from `runtime/rt.c` and compares it with the copy.
  A change to the deque fails the check until the copy, its bounds and the property are read
  again. That is how this check is kept true to the code; a comment in each file names the commit
  at which that was last done.
- `verify/deque-fault.c` is the negative control: the same harness with the deque from
  `423d2fb^`, in which `buf` and `cap` were two atomics published separately at resize. This is
  the layout that lets a thief pair one ring with the other ring's cap; loading the capacity
  separately from today's immutable `par_ring` would not recreate the fault. `check.sh` requires
  the named lost-claim, double-claim or pointer-safety assertion appropriate to each fault, and
  passes the good one. Parse failures, timeouts and unwinding assertions count as harness
  failures, never as a caught fault; the output must say which of those happened. A check that
  has never failed is a draft.
- `runtime/rt.c` gains `#define DQ_FIRST_CAP 64` beside the deque, and `dq_init` uses it where it
  writes `64`; the harness defines it as 2, so a resize happens after two pushes. No behavior
  changes: the value in a program is still 64.
- Bounds: two threads, four jobs, capacities 2, 4 and 8, `--unwind 8`, one function. If CBMC's
  front end cannot take the C11 atomics as written, the harness supplies indivisible equivalents
  for the claim counters and sequentially consistent equivalents for the deque operations. That
  variant covers the algorithm, not the annotations — the spike decides, and the header says
  which.

### Running it

```sh
./dev ./verify/check.sh        # the diff, the pass, the fault that must fail
```

The script prints one line per part, as `proofs/check.sh` does. `test.sh` runs it beside
`proofs/check.sh` and skips it with a message when `cbmc` isn't in the image (the image built
before Rocq does the same for the proofs). The suite's time budget for it is 60 seconds; if the
spike shows it costs more, it becomes its own CI job and the suite keeps a shorter bound.

### What comes after, in this order

1. **The deque** (this proposal).
2. **The contained jobs' held values:** `job_hold`, the `few[6]` array and the chunks beyond it,
   and `job_end`'s transfer to a parent on success, or drop when it has failed or has no parent.
   CBMC proves a pointer property: every held entry reaches exactly one drop, and no chunk is lost
   or reached twice while the lists are spliced. The report says a second reader of this code is
   owed; the test suite checks outcomes, not the splicing, and a job holding more than six shared
   values is the boundary the code names.
3. **The shared counts and the crossings:** the count a job doesn't change (`zs_dup_shared`), the
   window a count is taken outside it (`zs_job_out`), and `job_hold`'s read of the count. This is
   where the C11 orders matter, so the spike compares GenMC with `goto-instrument --mm`'s TSO,
   PSO, RMO and POWER models on the deque. Those models are not C11's source semantics: if they do
   not fit the code, GenMC is the C11 check. If neither runs at a cost we can keep, a TLA+ model
   of the counts and holds is the fallback, and the orders stay a written argument with a litmus
   test.
4. **Cancellation's held list** (`task.held`) in the existing Rocq development: the ownership
   report's first *Next* item, and the place where a wrong list is a double drop or a leak.
5. **The checker and the judgment:** the report's first *What it doesn't cover* — nothing but
   reading and the mutants ties `Core.Check.owned` to the Rocq judgment. A differential check of
   an extracted judgment against the Z# checker over the suite's IR is the long pole, and waits
   for 1–4.

This order is by what each check would find for its cost, not by how easy each is: the deque
first because its break is silent today, the contained jobs next because their code is newest and
was reviewed by its author alone.

## Drawbacks

- **Another tool, another CI line.** CBMC is one package and seconds of suite time; it is not
  free, and an image without it skips the check.
- **The harness copy.** The extraction diff keeps it honest but doesn't remove it; a change to the
  deque costs a look at the harness.
- **Sequential consistency.** A pass does not prove the release/acquire annotations; the check's
  name and header must not imply that it does.
- **Bounds.** Two threads and four jobs are not the program; the algorithm is size-independent,
  but the check is a bounded proof, and a reader can mistake it for a proof at every size.
- **A false alarm is possible.** A model checker can report a harness artifact; the fault file
  and a reader who knows CBMC's trace are what keeps a finding a finding.

## Alternatives

- **TLA+ (TLC):** the best readability for a counterexample and no dependence on the C, but a hand
  model can drift from the code, and it cannot see the atomics either. It needs Java and a pinned
  jar, a larger addition than `cbmc`. Kept as the fallback for the counts and holds, where the C
  is not standalone.
- **GenMC:** checks the C11 memory model directly on the code, where CBMC's `goto-instrument
  --mm` instead gives TSO, PSO, RMO and POWER. That distinction is why this proposal spikes CBMC's
  sequential and weaker models first and compares them with GenMC at the order's third item,
  rather than requiring a pinned source build up front.
- **Rocq:** already here, but the runtime's C is outside the judgment; a memory model and the
  runtime's semantics would be a much larger first step than one bounded check.
- **Dynamic only** (TSan, valgrind, a stress test): cannot model the accesses, and the review's
  own harnesses showed the gap is reachable but not reachable reliably from a Z# program.
- **Nothing:** the status quo, with the deque resting on a comment and a report about harnesses
  nobody can rerun.

## Compatibility

- **Programs:** none. `DQ_FIRST_CAP` has the same value; the markers are comments.
- **The dev image:** one more package. An image without it skips the check with a message, as
  Rocq's check does.
- **The suite:** one line and one skip message; no expected output changes.
- **The bootstrap and the compiler:** untouched.

## Pragmatics

- **Diagnostics:** CBMC's trace names the harness's steps (a push, a pop, a steal, a resize); the
  `verify/README.md` says how to read one and which assertion failed.
- **Performance:** the check prints its own time; the target is under 60 seconds for the pass and
  the fault together.
- **Scaling:** the bounds are in the harness; a third thread or a larger job count is a new
  constant and a new time budget, not a new check.
- **Culture:** the same rule `tests/owned-mutants.sh` follows — the fault is part of the check,
  and a check that has never failed is not counted as one.

## Unresolved questions

1. **The tool:** is `cbmc` in the dev image, and the suite line, approved? The alternative is a
   separate CI job that installs it.
2. **The first target:** the deque, as here, or the contained jobs' ledger (newer code, a review
   by its author only)? The order above puts the deque first; a reviewer who values the newer
   code more can swap 1 and 2 without changing the tool.
3. **The bounds:** two threads and four jobs, at under 60 seconds — enough, or the third thread
   now?
4. **The memory orders:** compare GenMC with `goto-instrument --mm` now, or wait until this check
   proves the harness pattern?
5. **The second reader** of the contained jobs (the report says one is owed): does the second
   check in the order count as that reader, or is a person still needed?

## History

- 2026-11-23: first draft.
