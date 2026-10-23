// Phase 10's measurement (DESIGN §6.1): Task on an Async effect, against task { } (phase 9's
// state machines). The same work both ways: n waits for a ready task (Task.ret) and n for one
// that suspends (Task.yield, a turn of the event loop). Async's handler resumes a ready task's
// result at once (the clause runs where await is performed, nothing captured) and gives a
// pending task's work the resumption, so a wait that suspends captures the frames waiting.
// Here await is for Task<int> and pause for Task.yield (): the measurement needs no more.

effect Async =
  abstract awaitInt : Task<int> -> int
  abstract pause : unit -> unit

/// A task running body, its awaits handled on the event loop.
let asyncTask (body: unit -> int / Async) : Task<int> =
  let work (c: Cancel) (complete: int -> unit / <>) =
    handle complete (body ()) with
    | Async.awaitInt t, k ->
      match t.ready with
      | Some x -> k x
      | None -> t.work c (fun x -> k x)
    | Async.pause (), k -> (Task.yield ()).work c (fun () -> k ())
  { ready = None; work = work }

let viaEffect (n: int) : Task<int> =
  asyncTask (fun () ->
    let mutable total = 0
    for i in 1 .. n do
      let x = Async.awaitInt (Task.ret i)
      Async.pause ()
      total <- total + x
    total)

let viaTask (n: int) : Task<int> =
  task {
    let mutable total = 0
    for i in 1 .. n do
      let! x = Task.ret i
      do! Task.yield ()
      total <- total + x
    return total
  }

let measure (name: string) (run: int -> Task<int>) (n: int) =
  let before = Runtime.allocations ()
  let watch = Stopwatch.startNew ()
  let total = Task.run (run n)
  let ms = watch.ElapsedMilliseconds
  let allocations = Runtime.allocations () - before
  println $"{name}: {n} rounds (a ready wait and a suspending one each), sum {total}, {allocations} allocations, {ms} ms"

let main () =
  for n in [ 10; 1000000 ] do
    measure "task { }" viaTask n
    measure "Async effect" viaEffect n
  0
