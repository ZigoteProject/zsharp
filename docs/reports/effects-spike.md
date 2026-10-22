# The phase 6 gate: an Async effect or CPS

DESIGN §6 put a time-boxed spike before phase 6: one built-in `Async` effect with one-shot
resumptions, compiled by evidence passing (§6.1). If it type-checked and met the performance
bar, `Task` would be a library over effects from the start; if not, the CPS design would stand.
The result: **CPS stands** for phase 6. Effects are faster at run time, but they can't be
type-checked without the effect types that are phase 10's work.

## What was measured

`bench/effects` holds the same loop of awaits in both translations, written by hand as the
compiler would emit them: `cps.zs` as `task { }` compiles with CPS (each bind hands its
continuation to the computation), and `yield.zs` as evidence passing with yield bubbling (Xie &
Leijen, ICFP 2021; Koka's scheme): an operation that completes at once just returns, and one
that can't sets a flag, so each caller on the way out adds the rest of its frame to the
continuation and returns too, until the handler (the event loop) has it to resume.

| | an await that completes at once | an await that suspends |
|---|---|---|
| CPS | 5 allocations, and the stack grows with each one | 7 allocations |
| Yield bubbling | none, and a test of the flag after the call | 2 allocations |

Yield bubbling allocates only when a computation really waits, and then one closure per frame
waiting (one here: the loop is tail-recursive). CPS allocates on every bind, and an await that
completes at once calls its continuation inside the current one, so a loop of them needs a
trampoline (the `Task` library sends one continuation in 64 through the event loop).

## Why it doesn't type-check yet

The flag test goes after every call that may yield, and only there; pure code must pay nothing
(phase 10's exit test: pure functions compile to the same IR). Knowing which calls may yield is
the whole of the type problem:
- **A closure's call:** `List.iter (fun x -> await …) xs` yields inside `List.iter`, through a
  closure. Only the closure's type can say that its call may yield, and `List.iter` must be
  polymorphic in it (`('a -> unit / e) -> list<'a> -> unit / e`): effect rows on every function
  type, unified and generalized like types, which is what phase 10 adds.
- **Without them:** every closure call would be assumed to yield, and so every function that
  calls one (`List.map`'s instances, every fold): the checks and the code that builds
  continuations would go into code that never waits. Or async lambdas couldn't go through
  generic code at all, which `Task.all (List.map fetch urls)` needs.
- **And soundness:** with no effect in `await`'s type, a call outside any task compiles and
  yields to no handler. Effect types reject it at compile time.

## The decision

- **Phase 6:** `Task<'a>` over CPS, as DESIGN §6 describes, with the same API users see either
  way: `task { }` (a computation expression), `Task.run`, `both`, `all`, `race`, `scope`.
- **Phase 9:** `task { }` lowered to state machines removes the allocation per bind, the cost
  measured here.
- **Phase 10:** effect handlers, with rows; the measurement says `Task` over an `Async` effect
  would then allocate only for real waits, so phase 10 may reimplement `Task` that way, as
  §6.1 allows. Nothing in phase 6's API stands in the way: `Task` stays opaque.
