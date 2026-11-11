// Effects in a task (track G, item 4): a task's body performs effects, across its waits, with
// the handlers in place where the task was made, which it keeps. A service's context, log and
// clock are handled once, around the tasks, and reach every function without being passed.
type Context = { name: string; limit: int }

effect Ctx =
  abstract get : unit -> Context

effect Log =
  abstract note : string -> unit

effect Clock =
  abstract now : unit -> int

// a plain function and a task, both using the context
let greeting () : string / Ctx = $"hello, {(Ctx.get ()).name}"

let step (n: int) : Task<int> / <Log, Clock> =
  task {
    Log.note $"step {n}"
    do! Task.sleep 1
    Log.note $"step {n} woke at {Clock.now ()}"
    return n * 2
  }

let work () =
  task {
    Log.note (greeting ())
    let! a = step 1
    let! b = step a
    // a loop, a lambda and a match in the task's body perform too
    for x in [ a; b ] do
      if x > (Ctx.get ()).limit then
        Log.note $"{x} is over the limit"
    [ "p"; "q" ] |> List.iter (fun s -> Log.note s)
    let! both = Task.all [ step 10; step 20 ]
    return a + b + List.sum both
  }

// a handler with state: the lines it was given, counted where the task was made
let counted (f: unit -> Task<int> / <Log | 'e>) : Task<int> * ref<int> / 'e =
  let lines = ref 0
  let t =
    handle f () with
    | Log.note s, k ->
      lines.Value <- lines.Value + 1
      println $"  log: {s}"
      k ()
  (t, lines)

let main () =
  let ticks = ref 100
  let made () =
    handle work () with
    | Clock.now (), k ->
      ticks.Value <- ticks.Value + 1
      k ticks.Value
    | Ctx.get (), k -> k { name = "aiko"; limit = 3 }
  let (t, lines) = counted made
  println "made: nothing has run yet"
  println $"result {Task.run t}, {lines.Value} lines"
  // the same work under other handlers: another context, a silent log
  let quiet =
    handle work () with
    | Clock.now (), k -> k 0
    | Ctx.get (), k -> k { name = "test"; limit = 100 }
    | Log.note _, k -> k ()
  println $"quiet {Task.run quiet}"
