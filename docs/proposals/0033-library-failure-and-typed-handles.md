# Proposal 0033: a library's panic as its host's error, and typed handles

| | |
|---|---|
| **Status** | Draft |
| **Decided at** | not yet: a design review |
| **Builds** | after 0.7 |
| **Rests on** | [DESIGN §2.1](../../DESIGN.md) and decision 5 (a panic stops the program: no unwinding, can't be caught; `zs_set_panic_hook`); DESIGN §11 and the specification's [§11.1](../spec/11-low-level.md#111-c-interop) (`[<Export>]`, `--lib`, the header, `zs_handle`); [0008 threads](0008-threads.md) (a handle's thread, `Share`) |
| **Related** | [0004 C layout](0004-c-layout.md) (the header's structs and their names); [0022 targets](0022-targets-macos-windows.md) |
| **Changes** | decision 5's row and DESIGN §2.1 and §11; the specification's §10 (execution) and §11.1; the guide's C interop chapter; the generated header; `runtime/rt.c`. No syntax |

- [ ] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

Two changes to what a C host sees of a Z# library (`zs build --lib`), neither to the language:

1. **A host can outlive the library's panic.** After `zs_catch_panics()`, a panic in a call from
   C doesn't stop the process: the call returns zero, the library is *failed* for good, and
   `zs_failure()` gives the message. Nothing unwinds, and Z# code still can't catch a panic.
2. **A handle has its type's name.** The header declares `Tree` where it declared `zs_handle`,
   so the host's compiler, or the binding generator reading the header, tells a tree from a
   list. The runtime checks the type too, since a host can cast.

```c
zs_catch_panics();
Tree t = tree_empty();                 // was: zs_handle t
Tree bigger = tree_insert(t, 5);
if (zs_failure()) {                    // NULL, or the panic's message
    report(zs_failure());              // the host goes on, without the library
    return;
}
tree_count(names);                     // a list<string>: now a compile error in C
```

## Motivation

**The host isn't always C written for the library.** A header and an archive are what every
foreign-function generator consumes: Python's cffi, Swift's and C#'s importers, Dart's ffigen,
LuaJIT. Their hosts are applications with a user in front of them or a server with other
requests in flight, and two things the library does today are worse there than in a C program:

- **A panic ends the host.** An index out of bounds in the library closes the editor with the
  user's document, or the server with every connection. `zs_set_panic_hook` lets the host log;
  it can't let the host live. The hosts' own languages turn their bugs into an exception at
  the boundary, and their users expect the same of a native library.
- **Every object is one type.** `zs_handle tree_insert(zs_handle p0, intptr_t p1)` generates a
  binding whose every object is the same opaque pointer. Passing a list where a tree goes
  compiles in C and in every generated binding, and reads the wrong object's memory in Z#:
  the one place safe Z# code can be made to misread memory without `unsafe` on its side.

**Without the feature:** a host that must survive runs the library in a child process and talks
to it over a pipe; a host that wants typed objects writes a wrapper struct per type by hand.

## Detailed design

### 1. A failed library

**The host opts in,** once, before or between calls, from any thread:

```c
void zs_catch_panics(void);        // from now on, a panic fails the library instead of the process
const char *zs_failure(void);      // NULL, or the first panic's message once the library has failed
```

Without the call nothing changes: a panic prints, runs the hook and stops the process with 134.
The default stays because a host that doesn't check `zs_failure()` would carry on with zeros.

**What a panic does then.** It prints its message and backtrace and runs the panic hook, as
today. Then, instead of stopping:

1. The library is marked failed, with the message. The first panic wins; the mark is never
   cleared, so `zs_failure()`'s pointer is good for the rest of the process.
2. The thread leaves Z# by a `longjmp` to its **outermost** call from C: the export, or the
   callback, that C called first on this thread. That call returns the zero of its C type: 0,
   `false`, a null pointer or handle, a `[<CLayout>]` struct of zero bytes, nothing for `void`.
3. From then on every call into the library returns zero without running any Z# code: each
   export, each `callback` C still holds, and `zs_retain` and `zs_release` (which would run
   a drop).

**Nothing is cleaned up.** No count is decremented and no `use` is disposed on the way out,
as decision 5 says: what the library allocated stays allocated, a file it held open stays
open. That's why the library is failed rather than resumed: its objects may be half-updated,
and a caller that went on would compute with them. It's WebAssembly's rule for a trap (the
instance is dead, the embedder lives) and what a `Mutex` poisoned in Rust says of one lock,
said of the whole library.

**C frames in between.** When C called Z#, Z# called a C function, and that called back into
Z# where the panic is (`qsort`'s comparison, a host function calling a second export), the
jump goes to the outermost call and discards the C frames between, as any `longjmp` does, as
Lua's errors and libpng's do. The alternative, returning zero to the inner C frame, would
return through it into Z# code of a failed library.

**Other threads.**
- **A host thread inside the library** when another one panics runs on until its call
  returns; its next call returns zero.
- **A wait** in the runtime (a `Mutex`, a `Channel`, a join on the pool) is woken when the
  library fails and panics itself, so a thread waiting for a lock the failed thread held
  leaves by its own outermost call instead of hanging.
- **A thread the library started** (a pool worker, `Thread.spawn`) has no C caller to return
  to: it marks the library failed, wakes the waits, and ends.

**In the generated code,** an export's and a callback's C entry begins with:

```
if failed            -> return zero
if catching && this thread has no entry yet
                     -> setjmp; on its second return, return zero
```

Two loads and two branches when the host hasn't opted in, a `setjmp` of the registers only
(no signal mask) on a thread's outermost entry when it has. An inner entry adds nothing.

**Where.** Library builds on Linux, macOS and Windows (`rt.c`). Not a program: decision 5
stands there, and in Z# itself. Not a chip (`rt-embedded.c` has no C library's `setjmp`, and a
firmware's answer to a panic is a reset) nor WebAssembly (a trap already leaves the host alive).
A library still leaves its host's signals alone, so a stack overflow in it stays a SIGSEGV.

### 2. Typed handles

**The header names each handle's type.** A type that crosses as a handle gets an opaque pointer
type of its own, named as a `[<CLayout>]` struct is (the type's name, a module's dot as `_`):

```c
typedef struct Tree_ *Tree;
Tree tree_empty(void);
Tree tree_insert(Tree p0, intptr_t p1);
intptr_t tree_count(Tree p0);
```

- **A generic type's instance** is named by its parts: `list<int>` is `list_int`,
  `option<Tree>` is `option_Tree`, `Map<string, array<f64>>` is `Map_string_array_f64`.
- **A function and a `dyn` value** stay `zs_handle`: `int -> int` has no name a C programmer
  would guess, and C can only pass one back.
- **`zs_handle` becomes `void *`,** and `zs_retain` and `zs_release` take a `void *`, so one
  pair serves every type, a typed handle converts to the untyped one without a cast, and
  `zs_release` has the signature a host's finalizer wants (`void (*)(void *)`).
- **Two types with one C name** (`Geo.Tree` and `Ui.Tree` are different, `Geo_Tree` and a
  record `Geo_Tree` aren't) are an error at the build, naming both.

**The runtime checks what the compiler can't.** A handle already carries its type's name for
the wrong-thread message. A call into Z# compares it with the parameter's type, and a mismatch
is a panic: `tree_count: argument 1 is a handle of list<string>, not Tree`. With part 1 the
host gets that as a failure it can report; without it, a stop at the bug rather than a wrong
answer later. A handle used after its last release is still undefined, as a freed pointer is.

### Order of implementation

1. Typed names in the header, `zs_handle` as `void *` (`src/Gen/Module.zs`'s `cName`); the
   guide and `tests/chandle`, `tests/cthreads` updated to the names.
2. The type check in `zs_handle_get`; a test that passes the wrong handle.
3. `zs_catch_panics` and `zs_failure` on one thread: the entry's check, the jump, zero
   results; `tests/cpanic` (a panic, the message, a later call, a callback under `qsort`,
   and the same library without the opt-in still exiting with 134).
4. Threads: a failed library's waits, and a panic on the library's own thread.

## Drawbacks

- **A host can now go on after a bug,** with whatever the library leaked. The opt-in and the
  permanent failure keep that to "report and carry on without the library".
- **Zero is a valid result.** A host that doesn't ask `zs_failure()` can't tell `tree_count`'s
  0 from a failure's. A binding generator asks after every call; hand-written C must remember.
- **Decision 5 gets an exception,** if a narrow one: a panic still can't be caught in Z#.
- **Every export pays** two loads and two branches, and a handle parameter one comparison.
- **Longer names** in headers of generic types.

## Alternatives

- **Unwinding** (landing pads, counts dropped on the way, a `try` in Z# or a catch at the
  export). It's what decision 5 declined: code at every call, and a second way to handle
  errors. A failed library needs none of it.
- **Resuming the library after a panic,** leaks accepted. A server would like one bad request
  not to end the rest. But the objects the panic left half-updated are reachable from the
  next call, and nothing marks them; see the unresolved questions.
- **The panic hook decides** (it returns "stop" or "go on"). It changes the hook's type under
  every host that has one, and the entry's `setjmp` must have happened before the panic.
- **A build option** (`--lib` with caught panics) instead of the host's call. The host is the
  one that knows whether it checks; one binary should serve both kinds.
- **A status result on every export** (the result through an out parameter). It changes each
  signature the author wrote, for hosts that didn't ask.
- **A thread-local failure,** as `errno`. The failure is the library's, not the thread's.
- **`static inline` `Tree_release`** per type. Binding generators bind symbols, not inline
  functions; one `zs_release(void *)` is bound once.
- **A handle's type left to the host's wrappers.** It's the status quo, and the runtime
  check would still be missing.

## Compatibility

- **Part 1** adds two functions to the header; a host that doesn't call them sees no change.
- **Part 2 changes generated headers.** C that holds handles in `zs_handle` variables still
  compiles (`void *` converts both ways); C++ needs a cast where it gives an untyped handle to
  a typed parameter, or the new name. The ABI is the same: a handle is a pointer.
- **A host that passed the wrong handle** and happened to work panics now.
- **Older compilers** write the old header; nothing in a library's source changes.
- Stage 0 isn't touched: the compiler isn't a library and uses neither part.

## Pragmatics

- **Diagnostics:** the name clash (`types Geo.Tree and Ui.Tree are both Tree in the header`
  in whatever form the clash takes); the wrong handle's panic above.
- **Tooling:** the header is the interface, so binding generators get the types with no
  change of theirs. The editor shows nothing new.
- **Performance:** measured before the review on `tests/cexport`'s calls in a loop: the
  entry's check with the host not opted in, opted in, and the handle's comparison. The
  comparison is of the names' addresses where one library made both, of their text otherwise.
- **Windows:** mingw-w64's `setjmp` takes the frame as a second argument; the entry calls the
  form each C library has.
- **Scaling:** one typedef per handle type an export names, not per type in the program.

## Unresolved questions

1. **May a host clear the failure** and call the library again, leaks and half-updated
   objects accepted (a server per request)? The draft says no.
2. **A panic under C frames:** discard them (the draft), or stop the process there as today,
   so that only a panic with no C between it and the host is caught?
3. **Locks:** is waking the runtime's waits enough, or can a host thread still hang on
   something the failed thread held (a C library's own lock, taken under an `extern`)?
4. **Names for functions and `dyn`:** `zs_handle` (the draft) or a spelled name such as
   `fn_int_int`? And should a type be nameable in C by an attribute where its Z# name clashes?
5. **`option` of a handle type:** a typed handle that may be null, instead of a handle of
   its own?
6. **Chips:** a firmware that wants a failed library instead of a reset needs a `setjmp` in
   `rt-embedded.c`. Wait for someone to ask?
7. **A failed library's memory:** should the runtime give back what it can (its pools)
   when the host asks, since nothing will use it again?

## History

- 2026-11-12: drafted, from looking at Z# libraries under hosts other than C.
