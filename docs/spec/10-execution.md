# 10. Execution model

## 10.1 Values

Every Z# expression evaluates to a **value**. Values are immutable: numbers, strings, tuples,
records, unions, lists, arrays, functions, spans. A value has no identity: nothing in the
language tells two equal values apart, and nothing observes whether a value is shared or
copied. In particular a program cannot observe:

- whether a value is held in registers, on the stack or on the heap;
- whether an update (`{ r with … }`, a write to a `let mutable` array, rebuilding a list)
  copied the value or reused its storage;
- the moment a value's memory is freed, except through `use`, `weak` and the leak report.

Mutation exists in two forms, both explicit:

- **mutable variables** (`let mutable`), which are local to a function activation and cannot
  be captured or aliased ([§5.8](05-expressions.md#58-blocks-and-bindings));
- **cells**, values that *are* identities ([§10.2](#102-values-and-cells)).

## 10.2 Values and cells

| Type | Kind | Semantics |
|---|---|---|
| `array<'a>` | value | Fixed length. `a.[i] <- x` needs `a` to be a `let mutable` and changes that variable only: no other variable, field or collection holding the "same" array sees the write (**copy-on-write**). `Array.set a i x` gives the changed array |
| `fixed<'a, N>` | value | As an array of exactly `N` elements, held inline in its record or variable |
| `string` | value | Immutable bytes |
| `span<'a>` | value | A window (owner, start, length) into an array, a string's bytes or a `Buffer`. Over an array or a string it is read-only. It keeps its owner alive, so it never dangles |
| `ref<'a>` | cell | One mutable slot: `ref v`, `r.Value`, `r.Value <- v`. Every holder of `r` sees the write |
| `Buffer<'a>` | cell | A shared mutable array that can grow. A write is seen by every holder, and by its slices |
| `Atomic<'a>`, `Mutex<'a>`, `Channel<'a>`, `Spsc<'a>` | cell | Cells made for use across threads ([§10.6](#106-threads-and-share)) |
| `weak<'a>` | cell | [§10.4](#104-lifetime) |

- Cells are created by functions (`ref`, `Buffer.create`, `Atomic.make`, …) and compared, where
  they have equality at all, by the library's definitions; `ref` has no `Show`.
- Arrays and `Buffer`s are created filled: there is no uninitialized element.
- Records and tuples are values. `x.f <- v` on a `let mutable` record replaces the variable's
  record ([§5.8](05-expressions.md#58-blocks-and-bindings)).
- **Top-level state** is a top-level cell ([§4.2](04-declarations.md#42-top-level-values)).

## 10.3 Representation

*Implementation.* This section describes the reference implementation. A program can depend
on it only through `sizeof`, `alignof` ([§11.3](11-low-level.md#113-layout)), `[<NoAlloc>]`
and `--no-heap` ([§11.4](11-low-level.md#114-bare-metal)), which make parts of it
checkable.

- **Plain values** are held unboxed and copied: numbers, `bool`, `char`, tuples, records,
  `fixed` arrays, and **small unions** (not recursive, at most four fields over all cases,
  none of them a heap value). A union whose cases have no fields is one byte. A small union
  of a single case has no tag: `type UserId = UserId of int` is an `int`.
- **Heap objects** are reference counted: strings, arrays, `Buffer`s, cells, closures, list
  cells, and the other unions. A case without fields is a static object; `option` of a
  pointer type is that pointer (`None` a static object), so `Some s` allocates nothing.
- String literals, static tables and constant constructors are static objects, never freed.
- A type's layout is otherwise unspecified, and fields may be reordered, unless the type is
  `[<CLayout>]` or `[<Bits>]`.

## 10.4 Lifetime

Memory is managed without a tracing collector, by reference counting the compiler inserts.

**Guarantees.**

- An object is never used after it is freed, and never freed twice.
- An object's memory is released when its last reference is gone, which is no later than the
  end of the last scope that could use it, and may be at its **last use**, earlier than the
  end of its scope.
- Releasing memory runs no user code. There are no finalizers: cleanup that must happen is
  written with `use` and `Dispose` ([§5.8](05-expressions.md#58-blocks-and-bindings)), which
  is deterministic and tied to scope.
- Startup values are released at exit.

**Cycles.** Values can only refer to values that existed before them, so values alone cannot
form a cycle. Cells can: a `ref` or a `Buffer` holding something that refers back to it,
directly or through a closure. A cycle of references is **never freed**. This is a leak, and
memory-safe.

- **`weak<'a>`** is a reference that does not keep its object alive. `Weak.create x` makes
  one to a heap object; `Weak.get w` is `Some x` while the object is alive and `None` after.
  Back-references (a child's parent, an observer list) are `weak`.
- **The `cycle` warning** ([§12.4](12-builtins.md#124-warnings)) is given at a type
  declaration whose values can reach themselves through a cell. `[<Cyclic>]` on the type
  states that the program breaks its cycles; `[<NoWarn "cycle">]` that none can form. Cycles
  through closures and `dyn` values are not detected.
- The run-time report `ZS_LEAKCHECK=1` lists the objects alive at exit.

**Arenas.** `Arena.with f` runs `f ()` with allocation served from a region that is released
as a whole. Objects in an arena are counted like any others; the region is released when its
last object dies, so an object that escapes `f` stays valid and keeps the region.

## 10.5 Panics

A **panic** is the response to a bug: a condition the program should not have reached. A
panic prints a message (and where available a backtrace) to standard error and **ends the
process at once**, with exit status 134. It does not unwind: no `use` is disposed, no handler
runs, and nothing can catch it. The one exception is a panic inside a contained job
([§10.6.1](#1061-contained-jobs)), which ends the job and not the process.

These conditions panic, in every build:

| Condition | Message |
|---|---|
| integer overflow in `+`, `-`, `*`, negation, `MIN / -1` | `integer overflow` |
| integer division or remainder by zero | `division by zero` |
| an index or slice out of bounds | `index out of bounds`, `slice 4..9 of an array of length 6` |
| a string slice inside a character | `byte 2 is inside a character` |
| a failed `assert` | `assertion failed at file:line: expr` |
| `panic msg`, `failwith msg` | the message |
| a resumption called twice | `resumption called twice (one-shot)` |
| stack overflow, where the platform reports it | `stack overflow (recursion too deep)` |
| a `[<Bits>]` field written with a value too wide, or read with bits naming no case | |
| a `callback` or a thread-bound handle used on another thread | names the type |
| a `callback<share<F>>` passed, or a thread-bound handle used, across a contained job's boundary | |
| a library function's stated precondition (`List.head []`, `Option.get None`) | names the function |

- Recoverable errors are values: `result`, `option` ([§5.9](05-expressions.md#59-control-flow))
  or the `Throw` effect ([§8.6](08-effects.md#86-the-built-in-effects)).
- A panic on any thread ends the whole process, unless that thread is running a contained job
  ([§10.6.1](#1061-contained-jobs)). In a library linked into a C program, a panic
  ends the host too; the host may register a hook that runs first
  ([§11.1](11-low-level.md#111-c-interop)).
- Under the test runner each test is a process, so a panic fails that test only.
- On bare metal, a panic reports through the target's output and stops the core.

## 10.6 Threads and `Share`

A program starts on one thread. Threads arise from the library's thread pool
(`Parallel.*`, `Array.Parallel.*`), from `Task.spawn` and `Task.blocking`, from interrupt
handlers on bare metal ([§11.4](11-low-level.md#114-bare-metal)), and from C calling in.

**Rule.** *A value may be used on a thread other than the one that created it only if its
type is `Share`.* The compiler enforces this at every point where a value can cross, so a
program without `unsafe` has no data races.

**`Share`** is determined by a type's structure:

| `Share` | Not `Share` |
|---|---|
| numbers, `bool`, `char`, `string`, `unit`, SIMD vectors | `ref<_>`, `Buffer<_>`, `weak<_>` |
| tuples, records, unions, `list`, `array`, `fixed`, `option`, … whose parts are all `Share` | `span<_>`, `ptr<_>`, `cptr`, `cstr` |
| `share<F>`, `fnptr<F>` | plain functions `A -> B`, `callback<F>` |
| `Atomic<_>`; `Mutex<T>`, `Channel<T>`, `Spsc<T>` with `T` `Share` | `dyn Trait` |

**Where values cross.**

- **`share<F>`** ([§3.7](03-types.md#37-function-types)) is the type of a function another
  thread may run; the thread-starting functions take it
  (`Parallel.both : share<unit -> 'a> -> share<unit -> 'b> -> 'a * 'b`). Where a lambda, a
  local function or a named function is given as a `share<F>`:
  - every variable it captures must have a `Share` type, including through the local
    functions it captures;
  - it must not reach a top-level value that is not `Share`, directly or through the
    functions it calls;
  - it performs no effect, and its result type is `Share` where the result returns to
    another thread.

  A violation is an error naming the variable and its type (`this function crosses threads,
  but it captures 'hits' : ref<int>, which can't be shared between threads`).
- `Channel.send`, the contents of a `Mutex`, and a `Task.spawn`'s result carry values across
  and require `Share`.
- An `[<Interrupt>]` handler is checked as a `share<unit -> unit>`.

**Shared mutation** goes through the cells made for it: `Atomic<T>` (lock-free; `T` a number,
`bool` or `char`), `Mutex<T>`, `Channel<T>` (bounded), and `Spsc<T>` (bounded and never
waiting, for interrupt handlers; any number of producers and consumers).

**Tasks and threads.** A task belongs to the event loop that runs it and never moves between
threads; values used inside one task need not be `Share`.

*Implementation.* Reference counts are non-atomic for objects used by one thread. When a
value crosses, the objects reachable from it are marked shared, and only those are counted
atomically from then on. Shared objects are never updated in place.

### 10.6.1 Contained jobs

`Contained.run f`, for `f : share<unit -> 'a>` with `'a` `Share`, evaluates `f ()` as a
**contained job**, and `Contained.task f`, for `f : share<unit -> Task<'a>>`, runs the task
`f ()` makes, and every task it waits for on the same event loop, as one. Neither is available
on bare metal or WebAssembly (`Contained` is a `Std` module).

**Result.** `Ok v` where the job's function (or task) gives `v`; `Error { message = m }` where
a panic with message `m` occurs on the job's thread while the job is running. The panic prints
as any other ([§10.5](#105-panics)) and the host's hook runs; then the job ends and evaluation
continues after the call. The innermost job running on the thread is the one that ends.

**What a job observes.** A job's function is a `share<F>`: it reads `Share` values of its
caller's, and changes only cells it creates and the cells made for sharing (`Atomic`, `Mutex`,
`Channel`, `Spsc`). The values it is given and its result behave as in a call. A value that
leaves the job (its result, a channel's message, a mutex's new value, a function given to
`Parallel.*`, `Task.spawn` or `Task.blocking`) is a copy where the job created it, and the
caller's own object where the caller did; the difference is observable only as allocation.

**When a job fails,**

- no `use` binding of the job is disposed, and no code of the job runs again;
- a `Mutex` held by a `Mutex.update` in progress is unlocked, and holds the value it had before
  that update;
- the file descriptors the runtime opened for the job and the job did not close are closed, and
  what waited for them, its timers and its waits for other threads' results are dropped;
- a `weak` reference made in the job no longer exists, and neither does any object the job
  created and did not send out;
- what the job did outside itself before the panic stays done: bytes written, a message sent,
  a mutex or an atomic changed.

**When a contained task is cancelled,** its task is cancelled inside the job first, as any task
is (its `use` bindings are disposed, [§9](09-computations.md)), and the job then ends without a
result.

**Not contained.** These end the process as outside a job: a stack overflow; running out of
memory; a failure of the runtime itself (a thread or a descriptor queue it cannot create).
Work the job starts on other threads (`Parallel.*`, `Task.spawn`, `Task.blocking`) is not part
of the job: a panic there ends the process, and a job that fails does not wait for or cancel a
task it spawned. Resources a C library holds for the job are not released. Passing a
`callback<share<F>>` to C inside a job panics, and a thread-bound handle
([§11.1](11-low-level.md#111-c-interop)) made on one side of a job's boundary panics when used
on the other.

*Implementation.* Nothing unwinds: the thread jumps to the job's entry. A job's objects are in
memory of its own, freed whole when it ends; in a job a shared object's count is not changed,
and the job holds what came in from outside until it ends. A value leaving a job is copied by
a function per type, which keeps the sharing between the job's objects.

## 10.7 Safety summary

A program that uses no `unsafe` expression, no `extern` and no `Mmio` function has these
properties on every target:

| Property | By |
|---|---|
| no use after free, no double free | reference counting |
| no null | `option` |
| no uninitialized read | every binding and element has a value |
| no out-of-bounds access | checked indexing; a panic |
| no data race | no captured mutable; `Share` |
| no silent integer overflow | checked arithmetic; a panic |
| no unhandled effect | rows |
| no unmatched value | exhaustive `match` |
| deterministic cleanup | `use` |

Not excluded: non-termination, exhaustion of memory or stack (a panic or a platform fault),
deadlock, and leaks through cycles of cells.
