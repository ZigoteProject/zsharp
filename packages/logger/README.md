# logger

Logging for Z#, in Z#: no C, no dependencies.

```toml
[dependencies]
logger = { path = "../zsharp/packages/logger" }
```

```zsharp
open Logger

// a function that logs says so in its type: connect : int -> bool / Log
let connect (tries: int) : bool =
  info "connecting"
  for i in 1 .. tries do
    event Warn "retrying" [ field "try" i ]
  lazily Debug (fun () -> "made only if someone listens")
  tries < 3

let main () =
  let (recent, held) = Sink.memory 500 Debug
  let log = create [ Sink.stderr Info Format.text; Sink.file "app.log" 1000000 Debug Format.json; recent ]
  into log "net" (fun () -> connect 2) |> ignore
  0
```

```text
2026-11-21T08:00:00.318747211Z INFO  net: connecting
2026-11-21T08:00:00.318954199Z WARN  net: retrying try=1
2026-11-21T08:00:00.318997991Z WARN  net: retrying try=2
```

## What it has

| | |
|---|---|
| **Levels** | `Trace`, `Debug`, `Info`, `Warn`, `Fail`, ordered; each sink takes its level and those above |
| **Records** | time, level, source, message, and fields (`field "tries" 3`, or any `string * string`) |
| **Formats** | `Format.text` (a line a person reads), `Format.json` (one object a line), or any `Record -> string` |
| **Sinks** | `Sink.stderr`, `Sink.file` (rotates to `<path>.1` past a size), `Sink.memory` (the last records, to show in a program), `Sink.filter`; a sink is a record of a level and a function, so a program writes its own |
| **The effect** | `trace`, `debug`, `info`, `warn`, `fail`, `event`, `lazily` perform `Log`; `into logger source` sends them to a logger, `silent` drops them, `collect` gives them to a test |
| **Threads** | a `Logger` is `Share`: `write` from any thread, records reach the sinks whole and one at a time |
| **A queue** | `queued capacity sinks` gives a logger whose records another thread writes (`drain`, or `pump` as a task); past the capacity, records are dropped and counted (`dropped`) rather than waited for |

## What it promises

- **A sink never fails its caller.** A file that can't be written loses the line.
- **A record is one line.** Control characters in a message, a source or a field are escaped
  in both formats, and a text field's value is quoted when it holds a space, a quote or an
  equals sign, so text from outside can't forge a line or a field.
- **A level nobody takes costs a comparison,** and `lazily` doesn't make its message.
- **No `unsafe`.** Threads meet through the library's `Mutex`, `Atomic` and `Channel`, which
  the compiler checks.

Within a thread, effects can't cross to another thread (a function run elsewhere performs
nothing), so code on other threads calls `write` with the logger, and code on one thread
can use either.

## Cost

Measured with `zs bench tests/LoggerBench.zs` (debug build, x86-64): a record no sink takes,
22 ns; a record kept in memory, 0.2 µs; through the effect into a logger, 0.25 µs; a text
line, 0.75 µs.

## Tests

`zs test` in this folder: formats, levels, filters, rotation, the effect's handlers, 2000
records from the thread pool at once, the queue in order and dropping past its capacity, and a
property that any text stays one line.
