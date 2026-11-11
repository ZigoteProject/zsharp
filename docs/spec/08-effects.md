# 8. Effects

An **effect** is a set of operations a function may *perform* without saying what they do; a
**handler** somewhere up the call chain gives them meaning. Effects express generators, typed
exceptions, dependency injection and state, and they are tracked in function types
([§3.8](03-types.md#38-effect-rows)).

## 8.1 Declaring an effect

```text
effect-decl = 'effect' ID [ type-params ] '='
              ( INDENT { 'abstract' ID ':' type NEWLINE } DEDENT | 'abstract' ID ':' type ) ;
```

```fsharp
effect Log =
  abstract note : string -> unit

effect State<'s> =
  abstract get : unit -> 's
  abstract put : 's -> unit
```

- An effect has one or more **operations**, each a function type. An effect may have type
  parameters, which its operations mention.
- An operation may have a type variable of its own in its **result** only:
  `abstract throw : 'e -> 'a` in `Throw<'e>` returns any type, which says it never returns.
- A function type written inside an operation's type has the empty row unless it names one.
- An effect is named like a type and follows the scope rules of
  [§2.4](02-programs.md#24-name-resolution). An operation is always named through its
  effect: `Log.note`.

## 8.2 Performing

An operation is called like a function: `Log.note "started"`. The call **performs** the
operation: control passes to the clause for it in the nearest enclosing handler of that
effect ([§8.4](#84-handlers)), with the arguments. If the clause resumes, the call returns
the value it was resumed with.

A function that may perform `E`, directly or by calling a function that does, has `E` in the
row of its type. This is inferred:

```fsharp
let total shapes =                       // list<Shape> -> float / Log
  Log.note $"{List.length shapes} shapes"
  shapes |> List.sumBy area
```

## 8.3 Rows in types

The typing of rows is in [§3.8](03-types.md#38-effect-rows). In summary:

- every function type has a row; rows are inferred and generalized like types, so a
  higher-order function performs what its argument does without saying so;
- a function may be annotated with its row, and then performs no more than it says;
- a function with an empty row is compiled exactly as if effects did not exist.

## 8.4 Handlers

```text
handle  = 'handle' block 'with' handler-clauses ;
handler-clauses = { '|' op-clause | '|' return-clause } ;       at least one op-clause
op-clause     = ID { atom-pattern } ',' ID '->' block ;         Effect.op args, k
return-clause = 'return' pattern '->' block ;
```

```fsharp
let sum () =
  let mutable total = 0
  handle numbers () with
  | Yield.yield x, k ->
    total <- total + x
    k ()
  | return () -> total
```

`handle` is a contextual word: it starts a handler only when followed by an indented block,
or by an expression and `with` on the same line.

**Static rules.**

- **Each effect whole.** For every effect a `handle` has a clause of, there must be a clause
  for **each** of the effect's operations, exactly once.
- **Several effects.** A `handle` whose clauses are for operations of several effects, in any
  order, is the handles nested, one per effect in the order of their first clauses: the first
  effect's handler is innermost and has the `return` clause. The rules below are per effect; so
  an operation that a clause of the first effect performs, of a later effect of the same
  `handle`, goes to that effect's clause, and one a later effect's clause performs goes outward.
- An operation clause is `Effect.op p1 … pn, k -> body`: an irrefutable atomic pattern per
  parameter of the operation, then the name of the **resumption** (`_` when it is not used).
- At most one `return` clause; without one it is `return x -> x`.
- **Types.** Let the handled expression have type `T` and the handler be for effect `E`:
  - the `return` clause's pattern has type `T`, and its body's type `R` is the type of the
    `handle` expression;
  - in the clause for `op : A -> B`, the patterns have `A`'s types, `k` has type `B -> R`,
    and the body has type `R`;
  - the handled expression's row loses its first `E`; the rest of its row, and whatever the
    clauses and the `return` clause perform, is the row of the `handle` expression.

**Dynamic semantics.** `handle e with clauses` evaluates `e` with the handler installed.

1. If `e` evaluates to a value `v`, the `return` clause is evaluated with `v`, and its value
   is the value of the `handle`.
2. If `e` performs an operation of `E` that no handler of `E` nearer to the call takes, the
   evaluation of `e` is suspended and the operation's clause is evaluated with the arguments
   and with `k` bound to the **resumption**: the rest of the evaluation of `e`, from the
   operation call on, *including the handler itself*. The clause's value is the value of the
   `handle`.
3. Calling `k v` resumes the suspended evaluation: the operation call returns `v`, `e`
   continues under the same handler (handlers are **deep**), and `k v` returns what the
   `handle` would have: the `return` clause's value when `e` finishes, or the value of a
   later clause.

Consequences:

- A clause that **does not call `k`** abandons the rest of `e`: the `handle` has the
  clause's value. This is how an exception is caught. The `return` clause is not applied to
  it.
- A clause that calls `k` as the last thing it does behaves as a function call from the
  operation's site.
- **Resumptions are one-shot.** `k` may be called at most once; a second call panics
  (`resumption called twice (one-shot)`).
- A resumption is a first-class value. It may be stored and called after the `handle`
  expression has produced its value; it then runs under the handlers that were around its
  `handle`.
- **Clauses run in the handler's context,** not the performer's:
  - an operation a clause performs, of `E` itself too, goes to the next handler outward;
  - a clause may read and assign the `let mutable` variables of the function the `handle`
    is written in ([§5.8](05-expressions.md#58-blocks-and-bindings)).
- **Nesting.** With several handlers of one effect installed, an operation goes to the
  innermost. A row may hold an effect twice for this reason
  ([§3.8](03-types.md#38-effect-rows)).
- There are no named handler instances and no way to skip a handler (`mask`).

**Disposal.** When a clause finishes without resuming, every `use` binding in the abandoned
evaluation is disposed, newest first, before the clause's body runs
([§5.8](05-expressions.md#58-blocks-and-bindings)). When a clause resumes, the scopes are
intact and are disposed as they end. Two cases dispose nothing at 0.7
([§14.3](14-evolution.md#143-known-deviations)): a resumption that is kept and never called,
and a `use` in a `task { }` body.

**Loops and recursion.** Performing inside a loop or a recursion, and resuming, uses stack
proportional to the program's own nesting, not to the number of operations performed.

## 8.5 Where the row must be empty

Some functions are called from where no handler can be. Their row must be empty, checked
where the function is declared or converted, with an error naming the effect:

| Position | Why |
|---|---|
| `main` | nothing is above it |
| a top-level value's initializer; a top-level `assert` | startup has no handler |
| a `share<F>`, and so every function given to another thread | a handler does not cross threads |
| a `callback<F>`, an `fnptr<F>`, an `[<Export>]` function, an `extern` | no resumption is captured across a C frame |
| an `[<Interrupt>]` handler | it runs between any two instructions |
| a `when` guard | matching has no effects |
| the functions given to a method through `dyn` | [§7.4](07-traits.md#74-dyn) |
| a `seq { }` body, beyond `Yield` | [§9.3](09-computations.md#93-seq) |

Such code handles what it performs inside itself: `Throw.catch` turns a throwing computation
into a `result`.

## 8.6 The built-in effects

Two effects are declared in the prelude.

**`Yield<'a>`** — generators.

```fsharp
effect Yield<'a> =
  abstract yield : 'a -> unit
```

`seq { }` bodies perform it and the `Seq` functions handle it
([§9.3](09-computations.md#93-seq)).

**`Throw<'e>`** — typed exceptions.

```fsharp
effect Throw<'e> =
  abstract throw : 'e -> 'a
```

- `Throw.throw e` never returns. A function that may throw shows it:
  `parse : string -> Entry / Throw<string>`.
- The library's `Throw` module has the handlers: `Throw.catch f` runs `f ()` and gives
  `Ok` of its value or `Error` of what it threw; `Throw.recover`, `Throw.ofResult` and
  `Throw.ofOption` convert between throws, results and options.
- A throw disposes the `use` bindings it passes.

**A panic is not an effect.** It cannot be handled ([§10.5](10-execution.md#105-panics)).
There is no `try … with`, `raise` or exception type.

## 8.7 Effects and other features

- **Tasks.** `Task` is not an effect: waiting is written with `let!` in a `task { }`
  ([§9.2](09-computations.md#92-task)). A task's body may perform effects, before and after
  its waits:
  - The `task { }` expression performs what its body does: the effects are in the row of the
    function that makes the task, and are handled around the making, not around the run.
  - The task keeps the handlers in place where it was made. Its body runs later, when the
    task is run or waited for, and each operation it performs goes to those handlers, whether
    or not their `handle` has returned by then.
  - Such a handler's clause must resume last (`k v` as the last thing it does): the clause
    answers the operation where it is performed. A clause that stops, or keeps `k`, for an
    operation a task performed is a panic there, since no handler is on the stack to return to.
  - An effect with an operation that never resumes (one whose result is its own type
    variable, as `Throw.throw`) cannot be in a task's row: it is an error at the `task { }`.
    Handle it inside the task, in code that does not wait, or give a `result`.
- **Threads.** A function that crosses threads performs nothing; each thread has its own
  handlers.
- **Modules.** An effect may be performed in one module and handled in another; rows are
  part of the types modules export.
- **Members and fields** may have effectful function types
  (`type Step = { run: int -> int / Log }`).
- **Cost model.** *Implementation.* Effects are compiled by evidence passing. A clause that
  resumes last, or does not resume, runs as a call at the operation's site and allocates
  nothing; only a clause that keeps `k` or uses it other than last captures the suspended
  evaluation, at one allocation per function suspended.
