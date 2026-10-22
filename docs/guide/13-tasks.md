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
- **One thread:** tasks take turns on one event loop. Each runs until it waits.

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

**Blocking calls:** `Task.blocking (fun () -> …)` runs a function on a helper thread, for a C call that blocks (a database's, say), while the event loop goes on. Until phase 7 can check it, the function must not share reference-counted values with the rest of the program: give it copies. `File.readAllTextAsync` and `File.writeAllTextAsync` work this way.

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

It holds 10,000 connections in 21 MB, and its memory stays flat under traffic: the same 20,936 KB at every minute of an hour-long soak test (`bench/echo/soak.sh`), through 32.6 million round trips.
