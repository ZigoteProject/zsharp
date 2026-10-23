# 16. Effects: generators, typed exceptions and handlers

An **effect** declares operations, and a **handler** says what they do. A function that performs
an operation has the effect in its type, after its result, so what a function may do shows where
it's declared; a function with no effects shows nothing extra. One feature gives lazy sequences
(`seq { }`), exceptions that are part of a function's type, and handlers of your own.

## Generators: `seq { }`

A `seq { }` is a lazy sequence: its body runs when the sequence is consumed, and each `yield`
gives the consumer one element. The `Seq` functions transform and consume sequences, and
`for x in s do` goes through one.

```zsharp
let evens n = seq { for i in 1 .. n do if i % 2 = 0 then yield i }

let main () =
  let squares = evens 100 |> Seq.map (fun x -> x * x)
  println $"{squares |> Seq.take 3 |> Seq.toList}"
  let mutable total = 0
  for x in evens 10 do total <- total + x
  println $"{total} {Seq.sum (evens 10)}"
  let framed = seq {
    yield 0
    yield! evens 6
    yield 100 }
  println $"{Seq.toList framed}"
  0
```

```text
[4; 16; 36]
30 30
[0; 2; 4; 6; 100]
```

- **Lazy:** `Seq.take 3` stops the generator after three elements; the other 47 squares are never computed. A sequence can be infinite: `Seq.unfold (fun n -> Some(n, n + 1)) 0` is every natural number.
- **Computed each time it's consumed:** a `Seq` is the code that makes the elements, not a list of them. `Seq.toList` keeps them.
- **`yield!`** yields another sequence's elements; `yield` works anywhere inside the braces, a lambda's body included.

A generator is any function that performs `Yield`: `seq { }` is a way to write one.

```zsharp
// countdown : int -> unit / Yield<int>: its type says it yields ints
let countdown (n: int) =
  let mutable i = n
  while i > 0 do
    Yield.yield i
    i <- i - 1

let main () =
  println $"{Seq.toList (Seq(fun () -> countdown 3))}"
  0
```

```text
[3; 2; 1]
```

## Typed exceptions: `Throw`

`Throw.throw e` stops what's running with the error `e`. A function that may throw says so in
its type (`int / Throw<string>`), and `Throw.catch` gives back a `result` where it's handled.

```zsharp
let digit (c: char) : int / Throw<string> =
  if c >= '0' && c <= '9' then int c - int '0' else Throw.throw $"not a digit: {c}"

// throws from inside the loop: nothing after the throw runs
let number (s: string) =
  let mutable n = 0
  for c in s do n <- n * 10 + digit c
  n

let main () =
  println $"{Throw.catch (fun () -> number "1234")}"
  println $"{Throw.catch (fun () -> number "12x4")}"
  0
```

```text
Ok 1234
Error not a digit: x
```

- **Where to use it:** inside a parser, an interpreter, a computation of many steps, where threading `result` through every call is noise. At a module's boundary, return a `result`: callers match on it, as everywhere in Z#.
- **Between the two:** `Throw.ofResult r` throws a `result`'s error, `Throw.ofOption e o` throws `e` for `None`, and `Throw.recover f g` gives `f e` for an error.
- **Panics are separate:** a panic (a bug) isn't an effect and can't be caught.

## Effects and handlers

`effect` declares operations; `handle e with` runs `e` and gives meaning to the operations it
performs, with a clause each. A clause gets the operation's arguments and `k`, the
**resumption**: calling `k v` continues `e` from the operation, with `v` as its result. The
`return` clause maps the value `e` finishes with (left out, it's the value itself).

```zsharp
effect State<'s> =
  abstract get : unit -> 's
  abstract put : 's -> unit

let counter () =
  let n = State.get ()
  State.put (n + 1)
  State.get ()

let main () =
  let mutable cell = 10
  let result =
    handle counter () with
    | State.get (), k -> k cell
    | State.put v, k ->
      cell <- v
      k ()
  println $"{result} {cell}"
  0
```

```text
11 11
```

- **Clauses run in the handler's place:** they may use and assign the variables of the function the `handle` is in (`cell` here), and an operation a clause performs goes to the next handler out.
- **Once:** a resumption may be called at most once (calling it again panics), or not at all: then `e` stops there, and the clause's value is the handle's.
- **Deep:** what `k` resumes is handled by the same handler again, so each `State.get` in `counter` meets the clause.
- **The innermost handler:** with two handlers of one effect, an operation goes to the nearer.

A clause that calls `k` and uses what it gives back can collect what's performed:

```zsharp
effect Emit =
  abstract emit : int -> unit

let squares () =
  for i in 1 .. 4 do Emit.emit (i * i)

let collected () =
  handle squares () with
  | Emit.emit x, k -> x :: k ()
  | return () -> []

let main () =
  println $"{collected ()}"
  0
```

```text
[1; 4; 9; 16]
```

Resumptions are one-shot, so a handler can't try every choice by calling `k` twice
(backtracking): a generator yielding each candidate is the way to write a search.

## Effect types

A function's effects follow its result type: `/ E`, `/ <E, F>` for several, `/ <E | 'e>` for
those and whatever `'e` is, and `/ <>` for none. They're inferred: a type annotation can leave
them out, and hover shows them (an editor shows a function's inferred effects before its `=`).

**A function argument's effects are the function's:** one that calls a function it's given
performs what that function performs, so the library's higher-order functions work with any:
`List.iter : ('a -> unit) -> list<'a> -> unit` takes a body that logs or throws, and then
performs that too. The row variable that says so (`/ 'e` on both arrows) isn't shown. The rare
function that needs a pure argument shows `/ <>` on it: `Seq.map : ('a -> 'b / <>) -> Seq<'a> -> Seq<'b>`.
A trait's method works the same way, and hover adds what a type says in words when its rows
have labels: `Throw.catch : (unit -> 'a / Throw<'b>) -> result<'a, 'b>`, "handles Throw<'b>
from f".

```zsharp
effect Log =
  abstract log : string -> unit

// shout : list<string> -> unit / Log, through List.iter
let shout (xs: list<string>) = List.iter (fun x -> Log.log (String.toUpper x)) xs

let main () =
  let mutable lines = []
  handle shout [ "a"; "b" ] with
  | Log.log s, k ->
    lines <- s :: lines
    k ()
  println $"{List.rev lines}"
  0
```

```text
[A; B]
```

**Where effects can't go:** nothing can handle an effect after it leaves `main`, a top-level
value's initializer, a `task { }` body (it runs from the event loop), a function C calls (an
`[<Export>]`, a `callback<…>`: the C-callback rule), a function run on another thread
(`share<…>`, `Parallel.for`) or a trait's method. Each is a compile error naming the effect:
handle it inside.

```text
main performs Yield<int> and nothing handles it: wrap the call in handle … with, or consume the Seq
a function given to C must have no effects: this one performs Yield<i32> (the C-callback rule)
a function run on another thread must have no effects: this one performs Throw<string>; handle it inside
```

## How it runs

Effects compile to plain code (evidence passing, as in Koka): a function with effects gets its
handlers as hidden parameters, and a function without any compiles exactly as it would if
effects didn't exist.

- **A clause that resumes last** (`k v` at its end on every path, or stops without `k`) runs right where the operation is performed, as a call: nothing is captured. `Seq.map`, `filter`, `iter`, `fold`, `sum`, `State` and `Log` above are of this kind, and so is a `Throw` handler (it stops).
- **Any other clause** (`x :: k ()`, keeping `k` for later) unwinds to its handler, each function on the way making the rest of itself a closure: one allocation per function waiting, only when such a clause runs.
- **Generators** allocate nothing per element: a pipeline of `Seq` functions is a loop calling each stage's clause in turn.

**Limits:**
- **`use` and stopping:** a throw, or any clause that stops without resuming, passes over a `use` on the way to its handler: what was bound is freed, but its `Dispose.dispose` doesn't run. Dispose before throwing, or handle the effect inside the `use`'s scope.
- **A resumption kept for later** runs under the handlers that were around its `handle`, wherever it's called from.
- **An operation's own type variable** may appear in its result only (`throw : 'e -> 'a`), not in its parameters.

**Tasks stay `task { }`:** a task's waits are state machines (chapter 13) that allocate nothing
per wait, where an `Async` effect would capture the waiting functions at each wait that
suspends (measured in phase 10: seven allocations per such wait). So `let!` and `do!` stay in a
task's own body.
