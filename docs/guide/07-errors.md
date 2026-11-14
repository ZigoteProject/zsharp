# 7. Errors

Z# separates two kinds of failure:
- **Expected failures:** a missing file, bad input. These are values, `result<'a, 'e>`, that the caller has to handle. Inside a module, a function may instead throw a typed exception, the `Throw` effect, which its type shows and `Throw.catch` turns back into a `result`; a throw disposes the `use` values it passes over, newest first ([chapter 16](16-effects.md#typed-exceptions-throw)).
- **Bugs:** an index out of bounds, an overflow, a failed assertion. These are **panics**, which stop the program at once.

## result and `?`

**`result` holds either outcome:** `Ok value` or `Error err`. The `?` operator after an expression unwraps an `Ok`, or returns the `Error` from the enclosing function right away. A chain of fallible steps reads like straight-line code.

```zsharp
let parseAge (s: string) =
  match String.parseInt s with
  | Some n when n >= 0 -> Ok n
  | Some n -> Error $"negative age: {n}"
  | None -> Error $"not a number: {s}"

let totalAge a b =
  let x = parseAge a?
  let y = parseAge b?
  Ok (x + y)

let main () =
  for (a, b) in [ ("36", "41"); ("36", "x"); ("-1", "2") ] do
    match totalAge a b with
    | Ok n -> println $"total {n}"
    | Error e -> println $"error: {e}"
  0
```

```text
total 77
error: not a number: x
error: negative age: -1
```

**`?` on an `option`:** in a function that returns an `option`, `x?` is the value in a `Some`, or returns `None` right away. Which `?` it is comes from the operand; a `result` under `?` in a function returning an `option` (or the reverse) is an error that names the conversion (`Result.toOption`, `Option.toResult`).

```zsharp
let initials (first: string) (last: string) =
  let f = List.tryHead (String.chars first)?
  let l = List.tryHead (String.chars last)?
  Some $"{f}.{l}."

let main () =
  println $"{initials "Ada" "Lovelace"} {initials "" "Hopper"}"
  0
```

```text
Some A.L. None
```

**How far `?` reaches:** `?` applies to the whole call before it, so `parseAge a?` is `(parseAge a)?`. It's allowed in `let x = e?` and as a statement of its own, and an error about it (in a function returning `unit`, say) points at the `?`.

**Working with results without matching:**
- `Result.map`, `Result.bind`, `Result.mapError` and `Result.defaultValue` transform or unwrap a result.
- `Option.toResult` turns a `None` into an error.
- **`result { }`:** a block whose `let!` stops at the first error, the way `?` stops a function ([Computation expressions](13-tasks.md#computation-expressions)); `option { }` does the same for `None`.

## Panics

A panic prints a message to standard error and ends the program with exit status 134.
- **No unwinding:** nothing is cleaned up, and a panic can't be caught. A
  [contained job](#containing-a-panic) is the one place it ends less than the program.
- **When to use one:** for bugs, not for errors a caller should handle.

**What panics:**
- indexing out of bounds;
- integer division by zero;
- integer overflow;
- `List.head` of an empty list and similar;
- `assert` with a false condition, which names its file and line;
- recursion too deep for the stack (`stack overflow`; on Linux and macOS);
- `panic "message"` (or `failwith`), called explicitly.

```zsharp
let main () =
  println "checking"
  assert (1 + 1 = 2)
  let xs: list<int> = []
  println $"{List.tryHead xs}"
  println $"{List.head xs}"
  0
```

```text
checking
None
panic: List.head: empty list
```

**In a C program:** a panic in a Z# library ends the host process too. The host can set a hook that runs first ([C interop](09-c-interop.md)).

**Backtraces:** a panic also prints a backtrace. On Linux it names the Z# functions the panic came through, an `at` line each, the program's `main` last (a function inlined into another is part of it). A release build's is shorter: often only the function the panic is in, and sometimes no `at` line at all. Set `ZS_BACKTRACE=0` to leave it out, as these examples do. In a test run with `zs test`, a panic fails that one test only ([Programs](08-programs.md#tests)).

## Containing a panic

A panic is a bug, and a program that does many independent things (a server's requests, a
tool's files) shouldn't lose them all to a bug in one. `Contained.run f` runs `f` as a
**contained job**: `Ok` with its result, or `Error` with the message of the panic that ended
it. The program goes on.

```zsharp
type Order = { item: string; quantity: int }

// a bug: there's no price for a pear
let price (o: Order) : int =
  let prices = [ ("apple", 3); ("plum", 5) ]
  let (_, each) = List.find (fun (name, _) -> name = o.item) prices
  each * o.quantity

let main () =
  let orders = [ { item = "apple"; quantity = 2 }; { item = "pear"; quantity = 1 }; { item = "plum"; quantity = 4 } ]
  for o in orders do
    match Contained.run (fun () -> price o) with
    | Ok total -> println $"{o.item}: {total}"
    | Error bug -> println $"{o.item}: failed ({bug.message})"
  0
```

```text
apple: 6
panic: List.find: no element satisfies the predicate
pear: failed (List.find: no element satisfies the predicate)
plum: 20
```

- **It's still a panic:** the message and backtrace are printed, as for any other. A contained
  job is for a supervisor, which reports the failure and carries on. Errors a caller handles
  are still `result` values.
- **Nothing unwinds,** and nothing needs to. A job's function is a `share<…>`
  ([Parallelism](14-parallel.md#what-can-cross-to-another-thread)): what it captures must be
  Share, as its result must. So the cells it changes are ones it made, and what it shares with
  the rest of the program is immutable, or an `Atomic`, a `Mutex` or a `Channel`. A panic
  leaves nothing half changed that anything else can reach.
- **A job has memory of its own,** which goes at once when it ends. Its result is copied out of
  it (what the caller shared with the job comes back as it was, not as a copy), and so is what
  it sends on a channel or puts in a mutex. A large result costs its size.
- **A job's memory only grows** until the job ends: what it drops isn't used again (but for
  big objects). So a job is a piece of work that ends, a request or a file, not a connection
  that stays open or a worker that runs all day.
- **When a job fails,** no `use` in it is disposed. The runtime undoes what it did for the job
  instead: a `Mutex.update` under way leaves the mutex unlocked with the value it had, and the
  files, sockets and timers opened in the job are closed.

**Tasks.** `Contained.task` runs a task, and the tasks it waits for on its loop, as one job:
a panic in any of them is its `Error`, and the other tasks on the loop go on. A server runs
each request this way:

```zsharp
// a request's work: it waits, and one request in four finds a bug
let answer (request: int) : Task<string> =
  task {
    do! Task.sleep 1
    let parts = [| "a"; "b"; "c" |]
    return $"request {request} got {parts.[request % 4]}"
  }

// each request is a job: its panic is its own failure
let serve (request: int) : Task<string> =
  task {
    let! r = Contained.task (fun () -> answer request)
    match r with
    | Ok reply -> return reply
    | Error bug -> return $"request {request} failed: {bug.message}"
  }

let main () =
  for line in Task.run (Task.all (List.map serve [ 1; 2; 3; 4 ])) do
    println line
  0
```

```text
panic: index out of bounds
request 1 got b
request 2 got c
request 3 failed: index out of bounds
request 4 got a
```

Cancelling a contained task cancels its task as any other: its `use` values are disposed.

**What crosses into a job must be Share,** and that decides how a service is written. A
request's method, path and body are Share; a database connection is a C library's and isn't.
So the job does the request's own work (what's asked, what the answer is made of) and the
connection is used outside it, as `examples/service` does.

**Not contained:**
- a stack overflow and running out of memory, which stop the program;
- what the job did outside itself before it failed: bytes written, a message sent, a mutex set;
- what a C library holds for it (a statement, a session), which isn't released;
- work it started on other threads (`Parallel.both`, `Task.spawn`, `Task.blocking`): that work
  isn't in the job, and a panic there stops the program.

For those, a process of its own is still the answer, as `zs test` gives every test. Contained
jobs are for programs on Linux, macOS and Windows, not for a chip or WebAssembly.

## Overflow

**Integer arithmetic is checked:** `+`, `-`, `*`, negation and `MIN / -1` panic on overflow, in optimized builds too, as in Swift. A silently wrong number is worse than a stopped program.

**Wrap-around on purpose:** for hashes, checksums and random number generators, use `Int.wrappingAdd`, `Int.wrappingSub` and `Int.wrappingMul`.

```zsharp
let main () =
  let big = 9223372036854775807
  println $"{Int.wrappingAdd big 1} {Int.wrappingMul (u8 200) (u8 2)}"
  println $"{big - 1}"
  println $"{big + 1}"
  0
```

```text
-9223372036854775808 144
9223372036854775806
panic: integer overflow
```

**A whole function:** `[<Wrapping>]` makes a function's integer `+`, `-` and `*` wrap around, including in the lambdas inside it. Floats and strings are unaffected, and negation and division keep their checks.

```zsharp
[<Wrapping>]
let fnv1a (s: string) =
  let mutable h = u32 2166136261
  for i in 0 .. String.length s - 1 do
    h <- (h ^^^ u32 (String.byte s i)) * u32 16777619
  h

let main () =
  println $"{fnv1a "hello"} {fnv1a "world"}"
  0
```

```text
1335831723 933488787
```

**Checked and saturating:** when an overflow is an input's fault rather than a bug (a parsed size, a timestamp plus a duration), `Int.checkedAdd a b` is `Some` the sum or `None`, with `checkedSub` and `checkedMul` beside it. `Int.saturatingAdd`, `saturatingSub` and `saturatingMul` stop at the type's bounds instead (`Int.saturatingSub (u8 3) (u8 5)` is `0`), as a gain control or a counter that must not wrap does. Each works on `int` and every sized integer; the bit operations beside them in `Int` are in [Basics](02-basics.md#bitwise-operators).

```zsharp
let main () =
  let size = u8 200
  println $"{Int.checkedAdd size (u8 100)} {Int.checkedAdd size (u8 50)} {Int.checkedMul 3 4}"
  println $"{Int.saturatingAdd size (u8 100)} {Int.saturatingSub (u8 3) (u8 5)} {Int.saturatingMul (i8 -100) (i8 2)}"
  0
```

```text
None Some 250 Some 12
255 0 -128
```
