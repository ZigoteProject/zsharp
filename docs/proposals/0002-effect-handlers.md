# Proposal 0002: effect handlers

| | |
|---|---|
| **Status** | Approved in principle |
| **Decided at** | the phase 6 gate ([the spike report](../reports/effects-spike.md)): CPS for `Task` then, effects in phase 10. The third design review settles the open questions before phase 10 starts |
| **Builds** | phase 10 ([ROADMAP](../../ROADMAP.md#phase-10-effect-handlers-v3)) |
| **Rests on** | decisions 21 (one cold `Task`), 23 (effect handlers: one-shot, evidence passing), 36 (evaluation order), 47 (`share<F>`) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §6.1](../../DESIGN.md#61-effect-handlers-planned-phase-10-v3) |
| **Related** | [0017 iteration](0017-iteration.md) (`Seq` implements it), [0008 threads](0008-threads.md) (handlers are per thread) |

- [x] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

An `effect` declares operations; `handle … with` gives them meaning where it's written, and
can resume the code that performed one. Effect types are rows on function types, inferred and
polymorphic, so a pure function's type doesn't change and `List.iter` works for any effect.
Resumptions are one-shot and compiled by evidence passing with yield bubbling (Xie and
Leijen, ICFP 2021), as Koka does: plain code, no stack switching, and nothing paid by code
without effects. One feature then gives generators (`seq { }`), typed exceptions,
backtracking and dependency injection, and may later carry `Task`.

```fsharp
effect Yield<'a> =
  abstract yield : 'a -> unit

let numbers () =                            // inferred: unit -> unit / Yield<int>
  for i in 1 .. 3 do Yield.yield i

let sum () =
  let mutable total = 0
  handle numbers () with
  | Yield.yield x, k -> total <- total + x; k ()   // k: the resumption, called at most once
  | return () -> total
```

## Motivation

- **Generators.** Z# has no lazy sequences: `seq { }` and `Seq` wait for this (track S item 1). A generator is a function that yields, and a consumer is a handler; `Seq.take 10` stops a generator by not resuming it, and reference counting frees what it held.
- **Typed exceptions.** `result` and `?` are the error model at API boundaries and stay so. Inside a parser or an interpreter, threading `result` through every call is noise; an exception effect says in the function's type that it may throw, which unchecked exceptions never did, and `Throw.catch` turns it back into a `result` at the boundary.
- **Dependency injection and backtracking.** A clock, a logger, a random source as effects are replaced in tests by handling them; a search that performs `choose` and is handled by a backtracking handler is a few lines.
- **No function colouring.** An `await` inside a lambda given to `List.iter` works, because `iter` is polymorphic in its argument's effects. `task { }` can't do that: a wait must be in the body itself (the guide says so).
- **Measured.** The phase 6 spike compiled an `Async` effect by evidence passing: an await that completes at once allocated nothing (CPS: 5), one that suspended 2 (CPS: 7). Phase 9's state machines since took `task { }`'s allocations away, so the allocation argument for `Task` over `Async` is gone; what remains is the colouring argument and having one mechanism.

## Detailed design

### Syntax

```
declaration  +=  'effect' ident type-params? '=' INDENT ('abstract' ident ':' type)+ DEDENT
expression   +=  'handle' expr 'with' ('|' clause)+
clause       :=  effect-name '.' op-name pattern* ',' ident '->' expr     // an operation; the ident is the resumption
              |  'return' pattern '->' expr                               // the result; identity when left out
type         +=  type '->' type '/' row
row          :=  effect-type | '<' effect-type (',' effect-type)* ('|' type-var)? '>' | type-var
```

- **Performing** an operation is a call through the effect's name: `Yield.yield x`, `Throw.throw e`. Its type is the operation's, and the effect joins the row of the function that performs it.
- **A row** in an annotation is closed (`/ Yield<int>`, `/ <Yield<int>, Throw<string>>`) unless it ends in a variable (`/ <Yield<int> | 'e>`). Inference never needs them written; they show on hover.
- **Clauses** bind the operation's arguments by pattern and the resumption by name (`k`, by convention; `_` when it's never called). Deep handlers: resuming re-installs the handler, as in Koka.
- **`effect` and `handle`** are reserved already (DESIGN §6.1).

### Typing

- **Rows** are Leijen's extensible rows of effect labels, order-insensitive, with duplicates allowed, so a handler nested under another for the same effect is well-typed and the innermost handles. Unification and generalization treat row variables as type variables, so `let` generalizes them: `List.iter : ('a -> unit / 'e) -> list<'a> -> unit / 'e` comes out of `iter`'s body, with no change to the library.
- **An operation's result** may be polymorphic (`abstract await : Task<'a> -> 'a`), instantiated at each perform. An operation whose result type is a variable that appears nowhere else (`throw : 'e -> 'a`) can't be resumed with anything, so its clauses never call `k`; nothing special is needed.
- **`handle e with …`** has the type of its `return` clause's result, which every operation clause shares. `k`'s type is the operation's result to the handle's result. The handled expression's row loses the handled effect; what the clauses perform joins the handle's own row (`Seq.map` re-yields).
- **Where a row must be empty:** a function that becomes a `callback<F>` or an `fnptr`, and a `share<F>` (a job runs on a thread with no handler), as the C-callback rule in DESIGN §6.1 says. Checked where the function is made into one, as `share<F>`'s captures are (decision 47). An `extern` has an empty row.
- **`main`** has an empty row: an unhandled effect is an error naming it.

### Semantics and compilation

Evidence passing with yield bubbling, as Koka, Xie and Leijen (ICFP 2021):

1. **Evidence:** a function with a non-empty or polymorphic row takes one extra parameter, the evidence vector: a frame per label, each the handler's clauses and the evidence it was installed under. Monomorphization (DESIGN §9) instantiates rows as it does types, so the index of a label in the vector is known at each perform, and no search runs.
2. **Tail-resumptive clauses** (`| Op x, k -> k (expr)`, with `k` called once, last, and not captured) run at the perform site as an ordinary call through the evidence, with no capture at all. State, readers, loggers, `Seq.iter` and `Seq.map` are of this kind; it's Koka's `fun` operation, found by the compiler rather than declared.
3. **Control clauses** (any other) yield: the perform sets the thread's yielding state with the frame's clause and returns; every effectful call is followed by a test of that state, and a frame that finds it adds the rest of itself (a closure over its live variables) to the continuation and returns too, up to the `handle`, which runs the clause with `k` the composed continuation. The spike's `yield.zs` is this by hand.
4. **One-shot:** `k` is affine. Calling it moves its frames into the resumed code, and a second call panics (`resumption called twice`). Dropping `k` frees what the frames held, through reference counting as for any closure. This keeps Perceus's ownership exact and in-place reuse valid; multi-shot would copy frames and is a later, opt-in kind (decision 23).
5. **Nothing for pure code:** a function with an empty row has no evidence parameter and no tests after its calls, so phase 10's exit test holds: pure functions compile to the same IR as before.
6. **In Core:** `Effect`, `Handle`, `Perform` and `Resume` nodes, lowered by a pass after monomorphization, inlining and simplification (`Evidence`) into ordinary Core: closures, calls and a test. Running after simplification matters: a clause that becomes `k ()` once the consumer's lambda is inlined (`Iter`'s `forEach` over a `Seq`, [0017](0017-iteration.md)) is recognized as tail-resumptive. Reference counting, decision trees and code generation see nothing new. `task { }` keeps phase 9's coroutine form whether or not `Task` moves onto an effect.

### Generators

```fsharp
type Seq<'a> = Seq of (unit -> unit / Yield<'a>)      // a single-case union, so Seq can be an impl head

let evens n = seq { for i in 1 .. n do if i % 2 = 0 then yield i }   // Seq<int>

evens 100 |> Seq.map (fun x -> x * x) |> Seq.take 3 |> Seq.toList   // [4; 16; 36]
```

- **`seq { }`** is a builder (decision 46): `yield` is `Yield.yield`, `yield!` iterates another `Seq`, and `for`, `if`, `match`, `let` and `while` are themselves. The body runs when the sequence is consumed.
- **Consumers are handlers:** `Seq.iter f s` handles `yield` tail-resumptively, so it compiles to the generator's loop with `f` inlined into it; `Seq.map` and `filter` re-yield; `Seq.take n` stops calling `k` after `n` elements, and the generator's frames are freed. `Seq.toList`, `fold`, `exists`, `sum` as for lists.
- **Push, not pull.** A `Seq` drives its consumer. `Seq.zip` of two sequences interleaves them by capturing each one's resumption per element, which allocates; it's the one operation that's cheaper with pull, and it's rare.
- **Iteration:** `Seq` implements the iteration trait ([0017](0017-iteration.md)), so `for x in evens 100 do` works, and `List.ofIter`, `Set.ofIter` take sequences.

### Typed exceptions

```fsharp
effect Throw<'e> =
  abstract throw : 'e -> 'a

let digit (c: char) : int / Throw<string> =
  if c >= '0' && c <= '9' then int c - int '0' else Throw.throw $"not a digit: {c}"

let parsed = Throw.catch (fun () -> digit 'x')     // result<int, string>: Error "not a digit: x"
```

- **`Throw.catch`** is a library function written with `handle`: the `throw` clause gives `Error e` without resuming, the `return` clause `Ok`. The error model at boundaries stays `result` and `?` (decision 19); an effect says, in the type, that a function may throw, which is what unchecked exceptions lacked and why Z# has none.
- **Panics** are untouched: not an effect, not catchable.

### `Task` and `Async`

`Task` keeps its API and `task { }` (DESIGN §6). Whether its implementation moves onto an
`effect Async = abstract await : Task<'a> -> 'a` with the event loop as the handler is decided
in phase 10 by measurement: the echo soak (`bench/echo/soak.sh`) and `tests/task/awaits.zs`
must not regress. The gain would be `await` inside any lambda, through `List.iter`,
`Option.map` and the rest, with no `let!`; the cost is a test after every call that may wait,
which phase 9's coroutines don't pay.

### Order of implementation

1. **Rows in the type checker:** `effect` declarations, performs, rows on function types, inference and generalization, the empty-row rules; `handle` typed. Hover shows rows.
2. **The `Evidence` pass** and the yielding runtime state (a thread-local in `rt.c` and `rt-embedded.c`); tail-resumptive detection; one-shot resumptions.
3. **`seq { }`, `Seq` and `Throw`** in Core, and the iteration impl.
4. **The `Task` measurement,** and the decision.

## Drawbacks

- **Rows on function types** are the largest change to the language left: every higher-order signature gains a row variable on hover, and errors can mention rows a programmer never wrote. Pure code's types print as today, which keeps most of the language looking as it does.
- **Two ways to write async** if `Task` stays on coroutines and `Async` exists too; the design avoids this by making the `Task` question a measured decision, not a second API.
- **A test after each effectful call** is a cost the compiler can't remove where a call is polymorphic in its effects; it's the price Koka pays, and it's bounded by the rows: pure calls have none.
- **Push-based generators** make `zip` and other pull patterns cost captures.

## Alternatives

- **Keep CPS and builders only** (what phase 6 chose for its time): generators would be a builder over closures, allocating per element, and exceptions would stay absent. The spike's numbers and the colouring problem are the reasons to go on.
- **Stack switching** (Wasm's stack switching, Lua's coroutines, Go's goroutines): needs a runtime that owns stacks, and a C frame in the middle of a capture is undefined. DESIGN §6.1 kept the option open by letting nothing assume one contiguous stack; evidence passing needs none of it, stays in plain code, and keeps the C-callback rule checkable.
- **Multi-shot resumptions** (Koka, OCaml 5's are one-shot): need frames copied and Perceus's uniqueness lost at every capture. One-shot keeps reuse; multi-shot can be an opt-in kind later.
- **Capability passing by hand** (passing a record of functions): what effect handlers compile to, written by the programmer at every call site, without the resumption.
- **Monads for everything** (Haskell): colouring at every layer; Z#'s builders already show the cost in `let!`.

## Compatibility

- **Not breaking for programs without effects:** their rows are empty, their types print as today, and their IR is the same (the exit test).
- **Printed types** of higher-order library functions gain a row variable (`('a -> 'b / 'e) -> list<'a> -> list<'b> / 'e`) where hover shows them.
- **Reserved words** `effect` and `handle` have been reserved since v1, so no program uses them as names.
- **`share<F>`, `callback<F>`, `fnptr`:** the empty-row rule can't reject an existing program, whose functions have empty rows.
- **The library:** `Seq`, `Throw` and `seq { }` are additions; no signature is rewritten by hand.

## Pragmatics

### Diagnostics

| Situation | Error |
|---|---|
| an unhandled effect | `main performs Yield<int> and nothing handles it: wrap the call in handle … with, or consume the Seq` |
| a C callback with effects | `a function given to C must have no effects: this one performs Async (the C-callback rule)` |
| a `share<F>` with effects | `a function run on another thread must have no effects: this one performs Throw<string>; handle it inside` |
| clause types differ | `clause Yield.yield gives string, the return clause int` |
| `k` called twice | at run time: `panic: resumption called twice (one-shot)` |
| an unknown operation | `effect Yield has no operation 'yeild' (yield)` |

### Tooling

- **Hover** shows a function's row; a pure function's type is unchanged. An inlay hint on a `let` whose inferred row isn't empty is worth adding (`/ Yield<int>`), so an effect that leaks into a function shows.
- **Definition** on `Yield.yield` goes to the operation; on a clause, references find the performs it handles.
- **Debugging:** a resumed frame runs with the handler as its caller, so a backtrace after a resumption shows the handler, not the original call chain, as async backtraces do. Tail-resumptive clauses leave backtraces as they were.
- **The grammar** gains `effect`, `handle` and `/` in types.

### Performance

- **Existing code:** none (the exit test).
- **Effectful code:** one evidence parameter per call, and a test after each call that may yield. Tail-resumptive operations are an indirect call. A capture allocates one closure per frame between the perform and its handler, only when a control clause runs: the spike's 2 allocations for a suspending await.
- **Generators:** `Seq.iter`, `map`, `filter` and `fold` over a generator compile to one loop; `take` and `zip` capture.

### Scaling

| Dimension | Typical | Upper bound |
|---|---|---|
| effects in one row | 1–3 | 16 |
| handlers nested at one point | 2 | 64 |
| frames between a perform and its handler | 5 | 10,000 (a recursive generator), each a closure on capture |
| generator pipeline stages | 3 | 50, one loop when every stage is tail-resumptive |

Evidence vectors are small tuples; monomorphizing over rows multiplies instances only by the rows actually used, which the module cache keeps per module.

### Culture-aware formatting and parsing

None.

## Unresolved questions

1. **`Task` over `Async`:** measured in phase 10 (above).
2. **Named handler instances:** two handlers of `State<int>` in scope resolve to the innermost. Koka's `mask` and named effects let code reach the outer one; whether Z# needs either waits for a program that does.
3. **Row syntax in annotations:** `/ <A, B | 'e>` here; Koka's `<a,b|e>` after the result type is the model, and decision 34's discussion may prefer another spelling.
4. **Polymorphic operations** (`await : Task<'a> -> 'a`): allowed here; they make evidence frames generic, which monomorphization handles by instantiation.
5. **Interrupt handlers** ([0012](0012-interrupts-noalloc-intrinsics.md)) have empty rows; whether a bare-metal `Task` ([0016](0016-async-bare-metal.md)) wants `Async` as an effect is that proposal's question.

## History

- **2026-10-22:** drafted from DESIGN §6.1, the phase 6 spike and Koka's design.
