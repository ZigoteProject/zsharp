# 13. Computation expressions and tasks

## Computation expressions

**Builder syntax:** `name { … }` writes code in a style that a module, the builder, decides: `option { }` stops at the first missing value, `result { }` at the first error, and `task { }` waits where a task does. Inside the braces, a few forms mean something to the builder:

| Form | Means |
|---|---|
| `let! x = e` | the rest, with the value `e` gives: for `option`, stop with `None` if it's `None` |
| `do! e` | the same, for a computation giving `unit` |
| `return x` | the computation's value |
| `return! e` | the computation `e` itself, as the value |
| `use x = e` | the rest, then `x` disposed (`Dispose`), even when a task is cancelled |
| `for x in xs do` | the body for each element of a list, in the builder's way |
| `if c then …` without `else` | nothing happens on the other branch |

Plain statements and `let`, `if`, `match` and loops work as anywhere else.

```zsharp
let parse (s: string) =
  match String.parseInt s with
  | Some n -> Ok n
  | None -> Error $"'{s}' isn't a number"

let ratio (a: string) (b: string) =
  result {
    let! x = parse a
    let! y = parse b
    if y = 0 then
      return! Error "division by zero"
    else
      return x / y
  }

let main () =
  println $"{ratio "84" "2"} {ratio "84" "x"} {ratio "1" "0"}"
  0
```

```text
Ok 42 Error 'x' isn't a number Error division by zero
```

**Your own builder:** `parser { }` uses the module `Parser.Builder`: a module named after the word, capitalized, with a nested `Builder` module holding the functions the forms need: `bind` (for `let!` and `do!`), `ret` (`return`), `zero` (an `if` without `else`, or a body that ends in a statement), `delay` (the whole body, as a function: an eager builder runs it at once), `using` (`use`) and `forEach` (`for`). A form whose function is missing is a compile error at the form that needs it.

## Tasks

**Work that waits:** a `Task<'a>` is work that may wait, for a timer, a socket or another task, without blocking the program: while it waits, other tasks run. `task { }` writes one, and `Task.run` runs it from `main`.
- **Cold:** making a task does nothing, and running it twice does the work twice.
- **One thread:** tasks take turns on one event loop. Each runs until it waits. `Task.spawn` runs one on another thread's loop, to use every core ([chapter 14](14-parallel.md#tasks-on-every-core)).
- **Cheap waits:** the compiler turns `task { }` into a state machine, allocated once when the task starts, so a wait allocates nothing, and one on a task whose result is ready goes on at once. Waits can be anywhere in the body, inside `for`, `while`, `if` and `match` included, but not inside a function the body defines.

```zsharp
let step (name: string) (ms: int) =
  task {
    do! Task.sleep ms
    println $"{name} done after {ms} ms"
    return ms
  }

let main () =
  let (a, b) = Task.run (Task.both (step "slow" 30) (step "fast" 10))
  println $"both: {a + b} ms of waiting, at once"
  0
```

```text
fast done after 10 ms
slow done after 30 ms
both: 40 ms of waiting, at once
```

**Several at once:**
- **`Task.both a b`** and **`Task.all [ … ]`** run tasks at once and give all their results.
- **`Task.race a b`** gives the first result, and cancels the other. **`Task.timeout ms t`** is `Some` result, or `None` once the time is up.
- **`Task.scope (fun s -> …)`** runs tasks started in it with `Task.start s t` alongside its body; `Task.wait` waits for one's result. The scope finishes only after all of them, so no task outlives the code that started it. `Task.cancel s` cancels them.
- **`Task.promise ()`**, `Task.fulfill` and `Task.wait`: a result one task waits for and another gives.

**Cancellation:** a cancelled task stops where it waits, and never goes on. What it bound with `use` is disposed, newest first, as when it finishes:

```zsharp
type Connection = Connection of string

impl Dispose<Connection> =
  let dispose (Connection name) = println $"{name} closed"

let download () =
  task {
    use c = Connection "the slow server"
    do! Task.sleep 5000
    return "the whole file"
  }

let main () =
  match Task.run (Task.timeout 20 (download ())) with
  | Some text -> println text
  | None -> println "gave up after 20 ms"
  0
```

```text
the slow server closed
gave up after 20 ms
```

**Blocking calls:** `Task.blocking (fun () -> …)` runs a function on a helper thread, for a C call that blocks (a database's, say), while the event loop goes on. The function crosses threads, so what it captures must be shareable ([chapter 14](14-parallel.md#what-can-cross-to-another-thread)), as its result must. `File.readAllTextAsync` and `File.writeAllTextAsync` work this way.

### Choosing between events

**Events:** `Threading.Alt` is Concurrent ML's events (Hopac's alternatives) for tasks. An `Alt<'a>` is something a task can wait for: a value on a channel, room to give one, a timer, a promise. `Alt.sync e` waits for it. `Alt.choose [ … ]` is an event too: the first of its branches to happen, and exactly one of them does.
- **`Ch.make ()`:** a channel. `Ch.give ch x` meets a `Ch.take ch` in another task, and both go on. It holds nothing in between, so a giver waits for a taker. `Ch.send ch x` and `Ch.receive ch` are short for `Alt.sync (Ch.give ch x)` and `Alt.sync (Ch.take ch)`.
- **`Mailbox.make ()`:** a queue. `Mailbox.post` never waits, and `Mailbox.take` is an event.
- **`Alt.map f e`**, **`Alt.after ms`**, **`Alt.always x`**, **`Alt.wait p`** (a promise), and **`Alt.guard`** (an event a task makes at each sync).
- **One loop:** a Ch or Mailbox is for the tasks of one event loop. Its values need not be shareable, and it can't cross threads.

```zsharp
let main () =
  let numbers = Ch.make ()
  let words = Ch.make ()
  let r =
    Task.run (Task.scope (fun s ->
      task {
        Task.start s (Ch.send words "hello") |> ignore
        let first = Alt.choose [ Alt.map string (Ch.take numbers); Ch.take words; Alt.map (fun () -> "nothing") (Alt.after 100) ]
        return! Alt.sync first
      }))
  println r
  0
```

```text
hello
```

**Nacks:** `Alt.withNack (fun nack -> e)` makes e at each sync and hands it `nack`, an event that happens if the sync commits to another branch, or the task is cancelled while it waits. A server that is sent `nack` with a request chooses between replying and seeing that the client gave up:

```zsharp
let server (requests: Mailbox<int * Ch<int> * Alt<unit>>) =
  task {
    let! (x, reply, nack) = Alt.sync (Mailbox.take requests)
    do! Task.sleep 20
    let! said = Alt.sync (Alt.choose [ Alt.map (fun () -> "replied") (Ch.give reply (x * 2)); Alt.map (fun () -> "the client gave up") nack ])
    println said
    return ()
  }

let call (requests: Mailbox<int * Ch<int> * Alt<unit>>) (x: int) : Alt<int> =
  Alt.withNack (fun nack ->
    let reply = Ch.make ()
    Mailbox.post requests (x, reply, nack)
    Ch.take reply)

let main () =
  let requests = Mailbox.make ()
  Task.run (Task.scope (fun s ->
    task {
      Task.start s (server requests) |> ignore
      let! r = Alt.sync (Alt.choose [ Alt.map Some (call requests 21); Alt.map (fun () -> None) (Alt.after 5) ])
      println $"client: {r}"
      return ()
    }))
  0
```

```text
client: None
the client gave up
```

**Not Task.race:** racing two `Ch.receive`s isn't a choice. The race cancels the loser after the fact, so when the winner's resumption has to wait for a turn of the loop, the loser can also take a value, which is then lost. A choice commits exactly one branch, and drops the others before any task goes on.

## Sockets

`Tcp` has TCP for tasks: `Tcp.listen`, then `Tcp.accept` for each connection; `Tcp.connect`; and `Tcp.read`, `Tcp.write` and `Tcp.writeText`. Each gives a `result`, and `use` closes a connection. An echo server, with a task per connection (the whole program is `examples/echo/server.zs`):

```fsharp
let rec echo (c: TcpStream) (buf: Buffer<u8>) : Task<unit> =
  task {
    let! r = Tcp.read c buf
    match r with
    | Ok n when n > 0 ->
      let! w = Tcp.write c buf n
      if Result.isOk w then
        return! echo c buf
    | _ -> return ()
  }

let rec accepting (l: TcpListener) (s: Scope) : Task<unit> =
  task {
    let! r = Tcp.accept l
    match r with
    | Ok conn ->
      Task.start s (task {
        use c = conn
        return! echo c (Buffer.create 512 (u8 0))
      }) |> ignore
    | Error e -> eprintln e
    return! accepting l s
  }
```

`return!` last in a task gives the task it names what waits for this one, so `echo` and `accepting` loop with one state machine, not one per round (in a `use`'s scope, `return!` waits, so `c` is closed after `echo`). It holds 10,000 connections in 26 MB, and its memory stays flat under traffic: the same 26,428 KB at every minute of an hour-long soak test (`bench/echo/soak.sh`), through 33.1 million round trips.
