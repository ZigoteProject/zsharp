# 14. Parallelism

## Using every core

`Parallel` runs work on a thread pool: a thread per core, each taking work from the others when
it runs out (work stealing). `ZS_WORKERS=n` sets how many threads it has.
- **`Parallel.both f g`** runs both functions at once, and gives both results.
- **`Parallel.for lo hi f`** calls `f i` for each `i` from `lo` up to (not including) `hi`, in no particular order.
- **`Parallel.reduce lo hi zero f combine`** combines `f i` for each `i` with `combine`, which must be associative.
- **`Array.Parallel.init n f`** and **`Array.Parallel.map f a`** build an array, its elements computed in parallel.

```zsharp
let rec fib (n: int) : int = if n < 2 then n else fib (n - 1) + fib (n - 2)

let main () =
  let (a, b) = Parallel.both (fun () -> fib 24) (fun () -> fib 25)
  println $"{a} {b}"
  let squares = Array.Parallel.map (fun x -> x * x) [| 1; 2; 3; 4 |]
  println $"{squares.[3]}"
  let total = Parallel.reduce 1 101 0 (fun i -> i) (fun x y -> x + y)
  println $"{total}"
  0
```

```text
46368 75025
16
5050
```

## What can cross to another thread

A function another thread runs has the type `share<F>`, as `Parallel.both`'s arguments do: a
function whose captured values can all be shared. A lambda written where one is expected is
checked there.
- **Can be shared (`Share`):** numbers, `bool`, `char`, `string`, and records, unions, tuples, lists, arrays and options of such; `share<F>` functions; `Atomic`, `Mutex` and `Channel`.
- **Can't:** `ref`, `Buffer`, `weak`, `dyn` values, C pointers, and plain functions, which may capture any of those.

So no two threads change the same data at once:

```fsharp
let main () =
  let total = ref 0
  Parallel.for 0 100 (fun i -> total.Value <- total.Value + i)
  // error: this function crosses threads, but it captures 'total' : ref<int>, which can't
  // be shared between threads
```

The check follows a captured local function to what it captures. A function crossing threads
can't use a top-level `ref` either, even through the functions it calls.

**Function parameters:** a function that hands its parameter to another thread declares it a
`share<…>`, and a lambda its caller passes is checked there. A `share<F>` is called as any
function.

```zsharp
let parallelSquares (f: share<int -> int>) (n: int) = Array.Parallel.init n (fun i -> f i * f i)

let main () =
  let offset = 10
  let a = parallelSquares (fun i -> i + offset) 3
  println $"{a.[0]} {a.[1]} {a.[2]}"
  0
```

```text
100 121 144
```

## What threads change together

**`Atomic<T>`:** a number, `bool` or `char` that threads change without a lock: `Atomic.get`,
`set`, `exchange`, `compareExchange` and `add` (which gives the new value).

**`Mutex<T>`:** any value that can be shared, behind a lock. `Mutex.update m f` replaces it with
`f` of it while holding the lock, so updates from several threads don't lose one another.

**`Channel<T>`:** values sent from some threads and received by others, in order, holding up
to its capacity: `Channel.send` waits while it's full, and `Channel.receive` waits for a value,
giving `None` once the channel is closed (`Channel.close`) and empty.

```zsharp
let main () =
  let hits = Atomic.make 0
  let seen = Mutex.make []
  Parallel.for 0 1000 (fun i ->
    if i % 100 = 0 then
      Atomic.add hits 1 |> ignore
      Mutex.update seen (fun xs -> i :: xs) |> ignore)
  println $"{Atomic.get hits} {List.sum (Mutex.get seen)}"
  0
```

```text
10 4500
```

**Waiting in parallel work:** a job of the pool that waits on a channel holds its thread. When
the job that would send runs later on the same thread, they wait for each other forever, so a
channel between two pool jobs needs room for what one sends before the other receives (or
tasks: `Task.spawn` runs each on a thread of its own loop).

## How sharing works

Reference counts are plain, not atomic, as on one thread. A value crossing to another thread
has its objects marked *shared* once, and only shared objects have atomic counts. Marking
stops at objects already shared, so sending the same value again costs one test. A shared object
is never unique, so writing to a shared array, or a `List.map` over a shared list, copies
instead of working in place. Data that stays on one thread keeps every optimization.

**Moving instead of sharing:** a value that only the job, task or channel receiving it will use
moves there unmarked. A work item, a `Task.spawn` or `Task.blocking` function and a value sent on
a channel are given up by the sender, so an object the moved value holds the only reference to
stays thread-local, the receiver's now; only what the sender still reaches is marked shared.
`Array.Parallel.map` cuts its array into parts and moves each into its job, so mapping an array
the caller doesn't use afterwards marks nothing. A `Mutex`'s value is always shared, since every
thread can reach it. `Runtime.marks ()` counts the objects marked so far, and `ZS_STATS=1`
prints it when the program exits.

Results come back without marking: `Parallel.both`'s results, and an array that
`Array.Parallel.init` builds, belong to the thread that asked for them.

## Tasks on every core

`Task.spawn (fun () -> t)` runs the task `t` on another thread, each of which has an event loop
of its own, and gives its result (the next chapter's tasks share one loop). The task stays on
that thread until it finishes. `Task.blocking (fun () -> …)` runs a function on a helper thread,
for a C call that blocks. Both functions are `share<…>`, and their results must be Share.

```zsharp
let rec fib (n: int) : int = if n < 2 then n else fib (n - 1) + fib (n - 2)

let work (n: int) =
  task {
    do! Task.sleep 10
    return fib n
  }

let main () =
  let total = Task.run (task {
    let! xs = Task.all (List.init 4 (fun i -> Task.spawn (fun () -> work (20 + i))))
    return List.sum xs
  })
  println $"{total}"
  0
```

```text
64079
```

## Checking for races

`zs build --sanitize=thread` builds with ThreadSanitizer, which reports two threads touching the
same memory without synchronizing. Code without `unsafe` can't race; C code, and C callbacks
called from other threads, can.
