// One handle with clauses of several effects, as a match has cases: the handles nested, one per
// effect in the order of their first clauses, the first innermost.
effect State =
  abstract get : unit -> int
  abstract put : int -> unit

effect Emit =
  abstract emit : int -> unit

effect Stop =
  abstract stop : string -> unit

let work () =
  for i in 1 .. 3 do
    State.put (State.get () + i)
    Emit.emit (State.get ())
  State.get ()

// clauses in any order, a return clause, a clause that uses what k gives
let collected () =
  let mutable cell = 0
  handle work () with
  | State.get (), k -> k cell
  | Emit.emit x, k -> x :: k ()
  | State.put v, k ->
    cell <- v
    k ()
  | return n -> [ n * 100 ]

// a clause that stops: its value is the handle's
let stopped () =
  let mutable cell = 0
  handle
    let n = work ()
    Stop.stop "enough"
    $"finished {n}"
  with
  | State.get (), k -> k cell
  | State.put v, k ->
    cell <- v
    k ()
  | Emit.emit _, k -> k ()
  | Stop.stop why, _ -> $"stopped: {why} at {cell}"

// the first effect is innermost: an operation its clause performs meets the later effect's
// clause of the same handle; one a later effect's clause performs goes out
let nested () =
  let mutable seen = []
  handle
    handle
      State.put 7
      Emit.emit 1
    with
    | State.get (), k -> k 0
    | State.put v, k ->
      Emit.emit v
      k ()
    | Emit.emit x, k ->
      seen <- x :: seen
      State.put (x + 1)
      k ()
  with
  | State.get (), k -> k 0
  | State.put v, k ->
    seen <- -v :: seen
    k ()
  List.rev seen

let main () =
  println $"{collected ()}"
  println (stopped ())
  println $"{nested ()}"
  0
