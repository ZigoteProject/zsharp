# Threading.Alt

Events and choice for tasks, as in Concurrent ML (Hopac's alternatives): an Alt is something
a task can wait for, alone or as a branch of a choice of which exactly one happens. A Ch meets
a task giving a value with one taking it; a Mailbox holds what's posted to it. All of it is for
the tasks of one event loop: a Ch or Mailbox can't cross threads (it isn't Share).

## Types

### `Alt`

```zsharp
type Alt<'a>
```

Something a task can wait for (a channel's value, room to give one, a timer, a promise), alone
or as a branch of Alt.choose: Alt.sync waits for it. Like a task it's cold: making one does
nothing, and each sync does the work afresh.

### `Ch`

```zsharp
type Ch<'a>
```

A channel between tasks on one event loop: a task giving a value meets a task taking one, and
both go on (the one that waited first). It holds nothing between them. Its values need not be
Share. One heap cell, so passing it around is cheap.

#### `Ch`

```zsharp
| Ch of ChData<'a>
```

Its state, private to Threading.

#### `Ch#givers`

```zsharp
member ch.givers
```

The tasks waiting to give, oldest first.

#### `Ch#takers`

```zsharp
member ch.takers
```

The tasks waiting to take, oldest first.

#### `Ch#taking`

```zsharp
member ch.taking
```

Taking a value: the event `Ch.take` gives, made once.

### `Mailbox`

```zsharp
type Mailbox<'a>
```

A queue between tasks on one event loop: posting never waits, taking waits for a value.

## Functions

### `Alt.sync`

```zsharp
Alt.sync : Alt<'a> -> Task<'a>
```

Waits for the event and gives its value: `let! x = Alt.sync e`. Its guards run first; then
the first branch that can happen now does, or else the first to become ready. Exactly one
branch commits; the others are dropped and their nacks given. If the task is cancelled while
it waits, every branch is dropped and every nack given. If it's cancelled once a branch has
committed (by a partner that went on first, say), the value is dropped, unless the task's
resumption had to be posted before: then it goes on.

### `Alt.always`

```zsharp
Alt.always : 'a -> Alt<'a>
```

An event that happens at once, with x.

### `Alt.never`

```zsharp
Alt.never : unit -> Alt<'a>
```

An event that never happens: syncing on it alone waits until the task is cancelled.

### `Alt.after`

```zsharp
Alt.after : int -> Alt<unit>
```

An event that happens ms milliseconds after the sync starts waiting (at once for 0 or
less). Its timer stops if another branch commits.

### `Alt.wait`

```zsharp
Alt.wait : Promise<'a> -> Alt<'a>
```

The promise's result as an event (an IVar's read), so a choice can wait for Task.start's
result.

### `Alt.map`

```zsharp
Alt.map : ('a -> 'b / <>) -> Alt<'a> -> Alt<'b>
  f must perform nothing
```

The event with f applied to its value once it has committed (CML's wrap), before the syncing
task goes on. For a task to run after the commit, map to the task and run it: `let! t =
Alt.sync (Alt.map f e)` then `return! t`.

### `Alt.choose`

```zsharp
Alt.choose : list<Alt<'a>> -> Alt<'a>
```

The first of the events to happen. When several can at once, the earliest in the list does:
the choice is biased, not random as in CML, so a loop can starve a later branch. `choose []`
never happens.

### `Alt.guard`

```zsharp
Alt.guard : Task<Alt<'a>> -> Alt<'a>
```

The event t makes, made afresh at each sync (CML's guard): write t as `task { }`, which runs
again each time; it may wait, and the sync waits for it (polling none of its branches yet).

### `Alt.withNack`

```zsharp
Alt.withNack : (Alt<unit> -> Alt<'a> / <>) -> Alt<'a>
  f must perform nothing
```

The event f makes at each sync, given a nack: an event that happens if the sync commits to a
branch outside f's, or the task is cancelled while it waits, and never if a branch of f's
commits. A server chooses between its reply and the nack to see that a client gave up. The
nack is given at the commit, before the syncing task goes on. To wait inside f, compose with
guard: `withNack (fun n -> guard (task { … }))`.

### `Ch.make`

```zsharp
Ch.make : unit -> Ch<'a>
```

A channel with no one waiting.

### `Ch.give`

```zsharp
Ch.give : Ch<'a> -> 'a -> Alt<unit>
```

Giving x: happens when it meets a taker.

### `Ch.take`

```zsharp
Ch.take : Ch<'a> -> Alt<'a>
```

Taking a value: happens when it meets a giver. It's the same event each time, so getting
it costs nothing.

### `Ch.send`

```zsharp
Ch.send : Ch<'a> -> 'a -> Task<unit>
```

`Alt.sync (Ch.give ch x)`, faster: no event is made.

### `Ch.receive`

```zsharp
Ch.receive : Ch<'a> -> Task<'a>
```

`Alt.sync (Ch.take ch)`, as fast: its work is made once, with the channel.

### `Mailbox.make`

```zsharp
Mailbox.make : unit -> Mailbox<'a>
```

An empty mailbox.

### `Mailbox.post`

```zsharp
Mailbox.post : Mailbox<'a> -> 'a -> unit
```

Adds x: the oldest waiting taker gets it at once, else it's kept. Never waits, so it works
outside tasks too.

### `Mailbox.take`

```zsharp
Mailbox.take : Mailbox<'a> -> Alt<'a>
```

The oldest value posted, as an event (the same each time, so getting it costs nothing).

