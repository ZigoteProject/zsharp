# 9. Computation expressions

A computation expression is a block written between braces after a **builder** name, in which
`let!`, `do!`, `return`, `use` and loops are given meaning by the builder. `option { }`,
`result { }` and user builders are translated into calls ([§9.1](#91-builders)); `task { }`
and `seq { }` are built in ([§9.2](#92-task), [§9.3](#93-seq)).

```text
computation = ID '{' ce-body '}' ;
ce-body     = ce-statement | INDENT ce-statement { NEWLINE ce-statement } DEDENT ;
```

An identifier directly followed by `{` starts a computation expression when the brace is
followed by a new indented line, or by `let`, `do`, `for`, `if`, `match`, `while`, `return`,
`use` or `yield`. Otherwise the braces are a record expression applied as an argument.

## 9.1 Builders

A builder is a **module**: `w { … }` uses the module `W.Builder`, where `W` is `w` with its
first letter upper-cased (`option { }` uses `Option.Builder`, `parser { }` `Parser.Builder`).
The body is rewritten into calls of the module's functions:

| In the body | Becomes |
|---|---|
| the whole body | `B.delay (fun () -> body)` |
| `let! p = m` and the rest | `B.bind m (fun p -> rest)` |
| `do! m` and the rest | `B.bind m (fun () -> rest)`; when last, the rest is `B.ret ()` |
| `return e` | `B.ret e` |
| `return! m` | `m` |
| `use x = e` and the rest | `B.using e (fun x -> rest)` |
| `for p in xs do body` | `B.forEach xs (fun p -> body)` |
| `if c then body` without `else` | the missing branch is `B.zero ()` |
| a statement of type `unit` and the rest | the statement, then the rest; when last, `B.zero ()` |
| `if`, `match`, or `for … in … do` followed by more statements | `B.bind` of it to `fun () -> rest` |
| `let p = e`, `let f x = …` | themselves, the rest translated |

- A range loop (`for i in a .. b do`) and `while` are plain loops, not `forEach`.
- The branches of `if` and the clauses of `match` are translated as bodies.
- `return` and `return!` must be last in their block. A body must not end with a binding.
- **Checking.** The translated calls are ordinary calls: the builder's functions give the
  body its types, and a form whose function the builder lacks is an error at that form
  (`counter { } needs Counter.Builder.bind, for let! and do!`). There is no builder trait.
- `let!`, `do!`, `return!` and `yield!` are a keyword directly followed by `!`.
- `return` outside a computation expression is an error: a function's last expression is its
  result.

**The prelude's builders:**

- `option { }`: `let! x = o` continues with the value of `Some`, and makes the whole
  expression `None` otherwise.
- `result { }`: `let! x = r` continues with the value of `Ok`, and makes the whole expression
  that `Error` otherwise.

Both evaluate when reached (their `delay` runs the body). In plain code, the postfix `?` does
the same without a builder ([§5.9](05-expressions.md#59-control-flow)).

## 9.2 `task`

`Task<'a>` is the type of an asynchronous computation giving an `'a`. `task { }` is compiled
directly, not through a builder module: its body is ordinary code (direct style) in which
these forms are also allowed:

| Form | Meaning |
|---|---|
| `let! p = t` | wait for the task `t`; bind its result |
| `do! t` | wait for `t : Task<unit>` |
| `return e` | the task's result; must be last |
| `return! t` | the task's result is `t`'s; must be last |
| `use x = e` | disposed when the block ends, and when the task is cancelled |

- **A task is cold.** A `task { }` expression is a value describing work. Evaluating it runs
  nothing; each time the task is run (`Task.run`, a `let!`, `Task.start`) its body runs from
  the start.
- **Waits** may be anywhere in the body's own control flow: in `if`, `match`, `for` and
  `while`. They may not be inside a lambda or a local function defined in the body (that
  function is not the task).
- A body that ends without `return` gives `unit`.
- **The body performs no effect** ([§8.5](08-effects.md#85-where-the-row-must-be-empty)); it
  may call functions that handle their own.
- **Scheduling.** Tasks run on an event loop, one per thread. A task runs without
  interruption until it waits; tasks of one loop never run at the same time. `Task.run t`
  runs the loop until `t` finishes and gives its result; it is how `main` starts tasks.
- **Cancellation.** A task is cancelled at a wait: it does not continue past the wait it is
  suspended in, and its `use` bindings in scope are disposed, newest first. Cancelling a task
  cancels the tasks it is waiting for and those it started in a scope.
- **Structured concurrency.** The library's combinators do not let a task outlive the code
  that started it: `Task.both`, `all`, `race` and `timeout` wait for (or cancel) their
  tasks, and `Task.scope` waits for every task started in it.
- **`return!` in tail position** hands the caller's wait to the named task, so a task that
  loops by `return!` uses constant memory. Inside a `use`'s scope it is a wait.
- Tasks are in Core and run on every target; `Task.spawn` and `Task.blocking` (other
  threads) are errors on a target without threads.

*Implementation.* A `task { }` body is one state machine allocated when the task starts; a
wait allocates nothing.

## 9.3 `seq`

`Seq<'a>` is a lazy sequence: a computation that yields its elements one at a time.
`seq { }` is compiled directly: its body is ordinary code in which

| Form | Meaning |
|---|---|
| `yield e` | the next element is `e` (performs `Yield.yield e`) |
| `yield! s` | the elements of the sequence `s`, in order |

- A `seq { }` is a value; its body runs each time the sequence is consumed (`for x in s`, the
  `Seq` functions), from the start, and only as far as the consumer goes.
- `yield` may be anywhere in the braces, the bodies of lambdas written there included.
- The body performs only `Yield`; any other effect must be handled inside it.
- A consumer that stops early abandons the body where it last yielded; the body's `use`
  bindings are disposed.
- `Seq<'a>` is declared `Seq of (unit -> unit / Yield<'a>)`; a sequence can be made from any
  function that yields.

`yield` in a list or array expression is that expression's
([§5.10](05-expressions.md#510-lists-arrays-and-ranges)), also inside a `seq { }`. Outside
both, `yield` is an error.
