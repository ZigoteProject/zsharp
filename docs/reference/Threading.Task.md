# Threading.Task

Tasks: work that may wait (for input, a timer, other tasks) without blocking the program,
run by an event loop. `task { }` writes one, and `Task.run` runs it from `main`. Each thread
has a loop of its own: `Task.spawn` starts a task on another thread's, to use every core.

## Types

### `Cancel`

```zsharp
type Cancel
```

A task's cancellation: whether it has been cancelled, and what to do then (stop waiting,
dispose what `use` bound). A task started by `both`, `all`, `race` or `Task.start` has its
own, under its parent's, so cancelling a task cancels what it started.

### `Task`

```zsharp
type Task<'a>
```

Work that may wait (for input, a timer, other tasks) and then gives an `'a`. A task is cold:
making one does nothing, and running it twice does the work twice.

### `Scope`

```zsharp
type Scope
```

The tasks started in a `Task.scope` with `Task.start`: they can't outlive it.

### `Promise`

```zsharp
type Promise<'a>
```

A result to come: a task's started with `Task.start`, or one given with `Task.fulfill`.
`Task.wait` waits for it.

## Functions

### `Task.complete`

```zsharp
Task.complete : ('a -> unit) -> 'a -> unit
```

Gives a task's result to what waits for it: the end of the code `task { }` compiles to.

### `Task.disposeOnCancel`

```zsharp
Task.disposeOnCancel : Cancel -> 'a -> int when 'a : Dispose
```

`use x = …` in a task: x is disposed if the task is cancelled. The number goes to
`Task.disposed` when the scope ends.

### `Task.disposed`

```zsharp
Task.disposed : Cancel -> int -> 'a -> unit when 'a : Dispose
```

The end of a `use` scope in a task: x is disposed, and no longer on cancellation.

### `Task.ret`

```zsharp
Task.ret : 'a -> Task<'a>
```

A task that gives `x` at once.

### `Task.yield`

```zsharp
Task.yield : unit -> Task<unit>
```

Lets the other tasks run, then goes on: a turn of the event loop.

### `Task.bind`

```zsharp
Task.bind : Task<'a> -> ('a -> Task<'b>) -> Task<'b>
```

The task `t`, then the task `f` makes from its result.

### `Task.map`

```zsharp
Task.map : ('a -> 'b) -> Task<'a> -> Task<'b>
```

The task's result with `f` applied.

### `Task.run`

```zsharp
Task.run : Task<'a> -> 'a
```

Runs the task on the event loop until it has finished, and gives its result: how `main`
starts tasks (inside one, `let!` waits for another).

### `Task.sleep`

```zsharp
Task.sleep : int -> Task<unit>
```

Waits `ms` milliseconds.

### `Task.waitFor`

```zsharp
Task.waitFor : int -> bool -> Task<unit>
```

Waits until the file descriptor can be read (or, with write, written) without blocking:
for libraries over non-blocking system calls, as `Tcp` is.

### `Task.both`

```zsharp
Task.both : Task<'a> -> Task<'b> -> Task<'a * 'b>
```

Runs both tasks at once, and gives both results once both have finished.

### `Task.all`

```zsharp
Task.all : list<Task<'a>> -> Task<list<'a>>
```

Runs the tasks at once, and gives their results, in order, once all have finished.

### `Task.race`

```zsharp
Task.race : Task<'a> -> Task<'a> -> Task<'a>
```

Runs both tasks at once, and gives the result of the first to finish. The other is
cancelled: what it waits for is dropped, and what it bound with `use` disposed.

### `Task.timeout`

```zsharp
Task.timeout : int -> Task<'a> -> Task<option<'a>>
```

The task's result, or `None` when it takes longer than `ms` milliseconds (it's cancelled then).

### `Task.promise`

```zsharp
Task.promise : unit -> Promise<'a>
```

A promise with no result yet: `Task.fulfill` gives it one.

### `Task.fulfill`

```zsharp
Task.fulfill : Promise<'a> -> 'a -> unit
```

Gives the promise its result (only the first time), and the tasks waiting for it go on.

### `Task.wait`

```zsharp
Task.wait : Promise<'a> -> Task<'a>
```

Waits for the promise's result.

### `Task.scope`

```zsharp
Task.scope : (Scope -> Task<'a>) -> Task<'a>
```

Runs `body` with a scope for tasks to run alongside it (`Task.start`). The scope finishes
once its body has and every task started in it has finished or been cancelled.

### `Task.start`

```zsharp
Task.start : Scope -> Task<'a> -> Promise<'a>
```

Starts `t` in the scope now, running alongside what started it: the promise gives its
result (`Task.wait`). The scope doesn't finish before it does.

### `Task.cancel`

```zsharp
Task.cancel : Scope -> unit
```

Cancels the tasks started in the scope (and what they started).

### `Task.blocking`

```zsharp
Task.blocking : share<unit -> 'a> -> Task<'a> when 'a : Share
```

Runs `f` on a helper thread, for a C call that blocks (a database's, say) while the event
loop goes on. `f` crosses threads, so what it captures must be Share, as its result must.

### `Task.spawn`

```zsharp
Task.spawn : share<unit -> Task<'a>> -> Task<'a> when 'a : Share
```

Runs the task `f` makes on another thread, which has an event loop of its own, so tasks
use every core (a server's connections, say). `f` crosses threads, so what it captures
must be Share, as the result must. The task stays on that thread to the end: cancelling
this one doesn't stop it (its result is dropped).

