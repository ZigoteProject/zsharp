/// Events and choice for tasks, as in Concurrent ML (Hopac's alternatives): an Alt is something
/// a task can wait for, alone or as a branch of a choice of which exactly one happens. A Ch meets
/// a task giving a value with one taking it; a Mailbox holds what's posted to it. All of it is for
/// the tasks of one event loop: a Ch or Mailbox can't cross threads (it isn't Share).
namespace Threading

// How a sync works. Alt.sync runs the event's guards and withNack functions first (prepare),
// which leaves a flat list of base events (prims), then asks each in order whether it can
// happen now (ready): the first that can commits. If none can, each is left waiting (block),
// and the first to become ready commits. The sync's branches share a Pick, which goes over
// exactly once: at that commit, or when the task is cancelled. Going over undoes what the other
// branches left waiting (queue cells, timers, promise and nack waiters) before any nack fires or
// either side goes on. No user code runs while the sync's own branches are queued, and the tasks
// of one loop take turns, so nothing here needs a lock. A sync on a channel's give or take, or a
// mailbox's take, alone (Ch.send, Ch.receive) needs none of it: its waiter is queued with its
// task's Cancel, and the partner that pops it takes back its action there.

// a nack: its cancellation, its link on the syncing task's, the branches it covers [lo, hi)
type private Nack = { nack: Cancel; link: int; lo: int; hi: int }

// where a sync is: over once a branch committed or the task was cancelled; what its waiting
// branches left (queue cells, timers, promise and nack waiters); its action on the task's Cancel;
// whether the committed value went on through the loop (it can't be dropped then)
type private PickState = { over: bool; undo: list<unit -> unit>; link: int; posted: bool }

// one sync, shared by its branches so that exactly one commits; its nacks newest first
type private PickData = { state: ref<PickState>; cancel: Cancel; nacks: list<Nack> }

// a PickData in one heap cell: the branches share it without copying its fields (only scalars
// change, in state)
type private Pick =
  | Pick of PickData
  member p.state = match p with | Pick { state = x } -> x
  member p.cancel = match p with | Pick { cancel = x } -> x
  member p.nacks = match p with | Pick { nacks = x } -> x

// what's left of a base event's go that a long run of maps took too deep: nothing, or a step
type private Rest =
  | Done
  | Again of (unit -> Rest)

// a base event as branch i of pick p: ready says whether it can happen now; go p i k true then
// makes it happen (resuming k through Task.complete), and go p i k false leaves it waiting,
// adding its undo to p
type private Prim<'a> = { ready: unit -> bool; go: Pick -> int -> ('a -> unit) -> bool -> Rest }

// an event: base events, flat (a choice of them is one list); a base event with the work a sync
// on it alone does in place of run's (a give, a take: no Pick); a choice with a guard
// or a nack among its branches; the event a task makes at each sync; the event a function makes
// at each sync, given a nack
type private Ev<'a> =
  | Prims of list<Prim<'a>>
  | Solo of Prim<'a> * (Cancel -> ('a -> unit) -> unit)
  | Choose of list<Ev<'a>>
  | Guard of Task<Ev<'a>>
  | WithNack of (Ev<unit> -> Ev<'a>)

/// Something a task can wait for (a channel's value, room to give one, a timer, a promise), alone
/// or as a branch of Alt.choose: Alt.sync waits for it. Like a task it's cold: making one does
/// nothing, and each sync does the work afresh.
type Alt<'a> =
  { /// What it is, made by the functions of Alt, Ch and Mailbox.
    ev: Ev<'a> }

// a task waiting on a queue, with what it gives (or unit) and what to resume: a branch of a sync
// (its Pick, its place there), or a sync on a give or take alone, which needs no Pick (its
// task's cancellation, its action there). One heap cell, which is also its queue cell's Some
type private Waiter<'v, 'r> =
  | Branch of Pick * int * 'v * ('r -> unit)
  | Lone of Cancel * int * 'v * ('r -> unit)

// oldest first; a dropped entry leaves an empty cell; dead counts empty cells at or after head
type private Queue<'w> = { cells: Buffer<ref<option<'w>>>; head: ref<int>; dead: ref<int> }

// a channel's state: the tasks waiting to give and to take, oldest first, and the event
// Ch.take gives (made once)
type private ChData<'a> =
  { givers: Queue<Waiter<'a, unit>>
    takers: Queue<Waiter<unit, 'a>>
    taking: Alt<'a> }

/// A channel between tasks on one event loop: a task giving a value meets a task taking one, and
/// both go on (the one that waited first). It holds nothing between them. Its values need not be
/// Share. One heap cell, so passing it around is cheap.
type Ch<'a> =
  /// Its state, private to Threading.
  | Ch of ChData<'a>
  /// The tasks waiting to give, oldest first.
  member ch.givers = match ch with | Ch { givers = x } -> x
  /// The tasks waiting to take, oldest first.
  member ch.takers = match ch with | Ch { takers = x } -> x
  /// Taking a value: the event `Ch.take` gives, made once.
  member ch.taking = match ch with | Ch { taking = x } -> x

/// A queue between tasks on one event loop: posting never waits, taking waits for a value.
type Mailbox<'a> =
  { /// What's been posted and not taken, oldest first.
    values: Queue<'a>
    /// The tasks waiting to take, oldest first (only while there are no values).
    takers: Queue<Waiter<unit, 'a>>
    /// Taking the oldest value: the event `Mailbox.take` gives, made once.
    taking: Alt<'a> }

// ------------------------------------------------------------------- queues

let private queue () : Queue<'w> = { cells = Buffer.empty; head = ref 0; dead = ref 0 }

// empties q once everything's taken, and moves its live cells to the front once most aren't
let private compact (q: Queue<'w>) =
  let n = Buffer.length q.cells
  let gone = q.head.Value + q.dead.Value
  if q.head.Value = n then
    Buffer.truncate 0 q.cells
    q.head.Value <- 0
    q.dead.Value <- 0
  else if gone > 32 && 2 * gone > n then
    let mutable j = 0
    for i in q.head.Value .. n - 1 do
      let cell = q.cells.[i]
      if Option.isSome cell.Value then
        q.cells.[j] <- cell
        j <- j + 1
    Buffer.truncate j q.cells
    q.head.Value <- 0
    q.dead.Value <- 0

// adds w at the end; the cell drops it
let private push (q: Queue<'w>) (w: 'w) : ref<option<'w>> =
  let cell = ref (Some w)
  Buffer.push cell q.cells
  cell

// takes the cell's entry out of q, if it's still there (emptying it frees what it holds)
let private drop (q: Queue<'w>) (cell: ref<option<'w>>) =
  if Option.isSome cell.Value then
    cell.Value <- None
    q.dead.Value <- q.dead.Value + 1
    compact q

// the oldest entry, taken out (the cell's own option, so nothing is allocated)
let private pop (q: Queue<'w>) : option<'w> =
  let mutable found = None
  let n = Buffer.length q.cells
  while Option.isNone found && q.head.Value < n do
    let cell = q.cells.[q.head.Value]
    q.head.Value <- q.head.Value + 1
    let entry = cell.Value
    if Option.isSome entry then
      cell.Value <- None
      found <- entry
    else
      q.dead.Value <- q.dead.Value - 1
  compact q
  found

// how many entries q has (a queued waiter's sync isn't over: close's undo drops its cells)
let private size (q: Queue<'w>) = Buffer.length q.cells - q.head.Value - q.dead.Value

// --------------------------------------------------------------- the commit

let private pick (c: Cancel) (nacks: list<Nack>) : Pick =
  Pick { state = ref { over = false; undo = []; link = -1; posted = false }
    cancel = c
    nacks = nacks }

let private over (p: Pick) = p.state.Value.over

// adds what to undo once p is over
let private onUndo (p: Pick) (f: unit -> unit) =
  let s = p.state.Value
  p.state.Value <- { s with undo = f :: s.undo }

// ends p: no branch can commit any more; its waits are dropped, its actions on the task's Cancel removed
let private close (p: Pick) =
  let s = p.state.Value
  p.state.Value <- { over = true; undo = []; link = -1; posted = false }
  if s.link >= 0 then forget p.cancel s.link
  // newest first: each is the newest left, so it goes at once
  for n in p.nacks do
    forget p.cancel n.link
  for f in s.undo do
    f ()

// gives the nacks of the branches p didn't commit to (i = -1: all of them)
let private fire (p: Pick) (i: int) =
  for n in p.nacks do
    if i < n.lo || i >= n.hi then cancelNow n.nack

// gives x to k (what pick p's task waits with, or a map on the way there), unless what went on
// before it (a partner, a nack's waiter, a map's function) cancelled that task. Nested deeply, it
// goes on through the loop, as Task's resume does, and that's final: the rest of the way (the
// maps left) isn't dropped, whatever happens before the loop runs it
let private resume (p: Pick) (k: 'a -> unit) (x: 'a) =
  let s = p.state.Value
  if s.posted || not p.cancel.cancelled.Value then
    if Native.loopEnter () then
      k x
      Native.loopLeave ()
    else
      if not s.posted then p.state.Value <- { s with posted = true }
      Native.loopPost (fun () -> k x)

// runs what's left of a base event's go, a step at a time
let private finish (r: Rest) =
  let mutable rest = r
  let mutable going = true
  while going do
    match rest with
    | Again step -> rest <- step ()
    | Done -> going <- false

// p commits to its branch i on its own (always, a timer, a promise, a nack, a mailbox value)
let private win (p: Pick) (i: int) =
  close p
  fire p i

// what w gives
let private given (w: Waiter<'v, 'r>) : 'v =
  match w with
  | Branch (_, _, v, _) -> v
  | Lone (_, _, v, _) -> v

// w, taken off its queue, commits: its sync is over, and the nacks of its other branches given
let private taken (w: Waiter<'v, 'r>) =
  match w with
  | Branch (p, i, _, _) -> win p i
  | Lone (c, link, _, _) -> forget c link

// gives x to w's task (after taken), unless what went on before cancelled it
let private wake (w: Waiter<'v, 'r>) (x: 'r) =
  match w with
  | Branch (p, _, _, k) -> resume p k x
  | Lone (c, _, _, k) -> if not c.cancelled.Value then Task.complete k x

// branch i of p meets waiter w: both close before any nack fires or either side goes on
let private meet (p: Pick) (i: int) (w: Waiter<'v, 'r>) =
  close p
  taken w
  fire p i

// what a sync leaves on its task's cancellation once its branches wait: they're all dropped
let private link (p: Pick) =
  let id = onCancel p.cancel (fun () ->
    if not (over p) then
      close p
      fire p -1)
  p.state.Value <- { p.state.Value with link = id }

// queues Ch.send's or Ch.receive's waiter, and drops it on the task's cancellation (a partner
// that pops it forgets that first)
let private wait (c: Cancel) (q: Queue<Waiter<'v, 'r>>) (x: 'v) (k: 'r -> unit) =
  // the number onCancel gives below
  let id = c.actions.counts.Value.next
  let cell = push q (Lone (c, id, x, k))
  onCancel c (fun () -> drop q cell) |> ignore

// gives x to the oldest taker, or waits as a giver: Ch.send's work, and Ch.give's Solo
let private sendWork (ch: Ch<'a>) (x: 'a) (c: Cancel) (k: unit -> unit) =
  match pop ch.takers with
  | Some w ->
    taken w
    wake w x
    // the partner went on first, and may have cancelled this task
    if not c.cancelled.Value then Task.complete k ()
  | None -> wait c ch.givers x k

// takes the oldest giver's value, or waits as a taker: Ch.receive's work, and Ch.take's Solo
let private receiveWork (givers: Queue<Waiter<'a, unit>>) (takers: Queue<Waiter<unit, 'a>>) (c: Cancel) (k: 'a -> unit) =
  match pop givers with
  | Some w ->
    taken w
    wake w ()
    // the partner went on first, and may have cancelled this task
    if not c.cancelled.Value then Task.complete k (given w)
  | None -> wait c takers () k

// takes the oldest value posted, or waits as a taker: Mailbox.take's Solo
let private postedWork (values: Queue<'a>) (takers: Queue<Waiter<unit, 'a>>) (c: Cancel) (k: 'a -> unit) =
  match pop values with
  | Some x -> Task.complete k x
  | None -> wait c takers () k

// syncs on the base events: the first that can happen now does, else each waits
let private run (c: Cancel) (nacks: list<Nack>) (prims: list<Prim<'a>>) (k: 'a -> unit) =
  let p = pick c nacks
  let mutable rest = prims
  let mutable i = 0
  let mutable done = false
  while not done && not (List.isEmpty rest) do
    match rest with
    | prim :: tail ->
      if prim.ready () then
        finish (prim.go p i k true)
        done <- true
      rest <- tail
      i <- i + 1
    | [] -> ()
  if not done then
    // nothing can become ready in between: the sync doesn't give up its turn
    i <- 0
    for prim in prims do
      finish (prim.go p i k false)
      i <- i + 1
    link p

// ------------------------------------------------------------------ prepare

// what prepare has left to do: an event to flatten, or a nack's range to close at the count
type private Step<'a> =
  | Next of Ev<'a>
  | Close of Cancel * int * int

// a prepare's state: the work left, the prims so far (newest first), their count, the nacks
type private Prep<'a> =
  { steps: ref<list<Step<'a>>>
    prims: ref<list<Prim<'a>>>
    count: ref<int>
    nacks: ref<list<Nack>>
    cancel: Cancel
    k: list<Prim<'a>> -> list<Nack> -> unit }

// an event that happens once n is cancelled: a nack's
let private nackEv (n: Cancel) : Ev<unit> =
  Prims [ { ready = (fun () -> n.cancelled.Value)
      go = fun p i k now ->
        if now then
          win p i
          resume p k ()
        else
          let commit () =
            if not (over p) then
              win p i
              resume p k ()
          // a sync may wait for another's nack, and so on: a long chain of them goes on
          // through the loop when it nests deeply, as Task's resume does
          let id = onCancel n (fun () ->
            if Native.loopEnter () then
              commit ()
              Native.loopLeave ()
            else
              Native.loopPost commit)
          onUndo p (fun () -> forget n id)
        Done } ]

// runs the guards and withNack functions, in order, until a guard waits (its continuation goes
// on from there, through Task.complete); then gives the prims in order and the nacks
let rec private prepLoop (s: Prep<'a>) =
  let mutable waiting = false
  // a withNack function or a guard's continuation may have cancelled the task: none runs after
  while not waiting && not s.cancel.cancelled.Value && not (List.isEmpty s.steps.Value) do
    match s.steps.Value with
    | step :: rest ->
      s.steps.Value <- rest
      match step with
      | Next (Prims ps) ->
        for prim in ps do
          s.prims.Value <- prim :: s.prims.Value
        s.count.Value <- s.count.Value + List.length ps
      | Next (Solo (prim, _)) ->
        s.prims.Value <- prim :: s.prims.Value
        s.count.Value <- s.count.Value + 1
      | Next (Choose xs) -> s.steps.Value <- List.append (List.map Next xs) s.steps.Value
      | Next (Guard t) ->
        waiting <- true
        // under the task's cancellation: cancelling it stops the guard
        Task.handOff t s.cancel (fun a ->
          s.steps.Value <- Next a :: s.steps.Value
          prepLoop s)
      | Next (WithNack f) ->
        let (n, nlink) = child s.cancel
        s.steps.Value <- Next (f (nackEv n)) :: Close (n, nlink, s.count.Value) :: s.steps.Value
      | Close (n, nlink, lo) ->
        s.nacks.Value <- { nack = n; link = nlink; lo = lo; hi = s.count.Value } :: s.nacks.Value
    | [] -> ()
  if not waiting then s.k (List.rev s.prims.Value) s.nacks.Value

// an event as an Alt
let private alt (e: Ev<'a>) : Alt<'a> = { ev = e }

// a base event as an Alt
let private prim (x: Prim<'a>) : Alt<'a> = alt (Prims [ x ])

// a base event, and the work of a sync on it alone, as an Alt
let private solo (work: Cancel -> ('a -> unit) -> unit) (x: Prim<'a>) : Alt<'a> =
  alt (Solo (x, work))

/// Functions on events.
module Alt =
  /// Waits for the event and gives its value: `let! x = Alt.sync e`. Its guards run first; then
  /// the first branch that can happen now does, or else the first to become ready. Exactly one
  /// branch commits; the others are dropped and their nacks given. If the task is cancelled while
  /// it waits, every branch is dropped and every nack given. If it's cancelled once a branch has
  /// committed (by a partner that went on first, say), the value is dropped, unless the task's
  /// resumption had to be posted before: then it goes on.
  let sync (a: Alt<'a>) : Task<'a> =
    match a.ev with
    | Solo (_, work) -> { ready = None; work = work }
    | Prims ps -> { ready = None; work = fun c k -> run c [] ps k }
    | e ->
      { ready = None
        work = fun c k ->
          let s =
            { steps = ref [ Next e ]
              prims = ref []
              count = ref 0
              nacks = ref []
              cancel = c
              k = fun prims nacks -> if not c.cancelled.Value then run c nacks prims k }
          prepLoop s }

  /// An event that happens at once, with x.
  let always (x: 'a) : Alt<'a> =
    prim { ready = (fun () -> true)
      go = fun p i k now ->
        if now then
          win p i
          resume p k x
        Done }

  /// An event that never happens: syncing on it alone waits until the task is cancelled.
  let never () : Alt<'a> = alt (Prims [])

  /// An event that happens ms milliseconds after the sync starts waiting (at once for 0 or
  /// less). Its timer stops if another branch commits.
  let after (ms: int) : Alt<unit> =
    prim { ready = (fun () -> ms <= 0)
      go = fun p i k now ->
        if now then
          win p i
          resume p k ()
        else
          // the loop posts a timer that's due, so another branch may have committed by then
          let t = Native.loopTimer ms (fun () ->
            if not (over p) then
              win p i
              resume p k ())
          onUndo p (fun () -> Native.loopUntimer t)
        Done }

  /// The promise's result as an event (an IVar's read), so a choice can wait for Task.start's
  /// result.
  let wait (pr: Promise<'a>) : Alt<'a> =
    prim { ready = (fun () -> Option.isSome pr.result.Value)
      go = fun p i k now ->
        match pr.result.Value with
        | Some x ->
          win p i
          resume p k x
        | None ->
          // Task.fulfill resumes it through the loop already
          let id = addCallback pr.waiting (fun x ->
            if not (over p) then
              win p i
              if not p.cancel.cancelled.Value then k x)
          onUndo p (fun () -> removeCallback pr.waiting id |> ignore)
        Done }

  // a base event with f applied to its value. Its value goes on through Task.complete, and a
  // long run of maps unwinds to finish once the stack is deep (where Task's resume would post),
  // so neither grows the stack
  let private mapPrim (f: 'a -> 'b) (prim: Prim<'a>) : Prim<'b> =
    { ready = prim.ready
      go = fun p i k now ->
        // f may cancel the task (waking one that does): the value is dropped then, unless it went
        // on through the loop before (resume)
        let mapped = fun x -> resume p k (f x)
        if Native.loopEnter () then
          let rest = prim.go p i mapped now
          Native.loopLeave ()
          rest
        else
          Again (fun () -> prim.go p i mapped now) }

  // an event with f applied to its value
  let rec private mapEv (f: 'a -> 'b) (e: Ev<'a>) : Ev<'b> =
    match e with
    | Prims ps -> Prims (List.map (mapPrim f) ps)
    | Solo (prim, _) -> Prims [ mapPrim f prim ]
    | Choose xs ->
      // flattened with a work list, as prepare does (nesting doesn't change a choice), so a
      // choice nested deeply doesn't grow the stack
      let mutable todo = xs
      let mutable mapped = []
      while not (List.isEmpty todo) do
        match todo with
        | Choose ys :: rest -> todo <- List.append ys rest
        | x :: rest ->
          mapped <- mapEv f x :: mapped
          todo <- rest
        | [] -> ()
      Choose (List.rev mapped)
    // not Task.map: its pending path calls k directly, and a deep chain would grow the stack.
    // A map over n nested guards maps each again at every level: O(n^2), fine for real nesting
    | Guard t -> Guard (Task.bind t (fun x -> Task.ret (mapEv f x)))
    | WithNack g -> WithNack (fun n -> mapEv f (g n))

  /// The event with f applied to its value once it has committed (CML's wrap), before the syncing
  /// task goes on. For a task to run after the commit, map to the task and run it: `let! t =
  /// Alt.sync (Alt.map f e)` then `return! t`.
  let map (f: 'a -> 'b) (a: Alt<'a>) : Alt<'b> = alt (mapEv f a.ev)

  /// The first of the events to happen. When several can at once, the earliest in the list does:
  /// the choice is biased, not random as in CML, so a loop can starve a later branch. `choose []`
  /// never happens.
  let choose (xs: list<Alt<'a>>) : Alt<'a> =
    let flat =
      List.forall (fun (x: Alt<'a>) ->
        match x.ev with
        | Prims _ -> true
        | Solo _ -> true
        | _ -> false) xs
    if flat then
      alt (Prims (List.collect (fun (x: Alt<'a>) ->
            match x.ev with
            | Prims ps -> ps
            | Solo (prim, _) -> [ prim ]
            | _ -> []) xs))
    else
      alt (Choose (List.map (fun (x: Alt<'a>) -> x.ev) xs))

  /// The event t makes, made afresh at each sync (CML's guard): write t as `task { }`, which runs
  /// again each time; it may wait, and the sync waits for it (polling none of its branches yet).
  let guard (t: Task<Alt<'a>>) : Alt<'a> = alt (Guard (Task.bind t (fun a -> Task.ret a.ev)))

  /// The event f makes at each sync, given a nack: an event that happens if the sync commits to a
  /// branch outside f's, or the task is cancelled while it waits, and never if a branch of f's
  /// commits. A server chooses between its reply and the nack to see that a client gave up. The
  /// nack is given at the commit, before the syncing task goes on. To wait inside f, compose with
  /// guard: `withNack (fun n -> guard (task { … }))`.
  let withNack (f: Alt<unit> -> Alt<'a>) : Alt<'a> = alt (WithNack (fun n -> (f (alt n)).ev))

/// Functions on channels. When a give meets a take, the side that was waiting goes on first,
/// then the one that met it (as with `Task.fulfill`), unless the first cancelled it.
module Ch =
  /// A channel with no one waiting.
  let make () : Ch<'a> =
    let givers = queue ()
    let takers = queue ()
    let taking =
      solo (receiveWork givers takers) { ready = (fun () -> size givers > 0)
        go = fun p i k now ->
          if now then
            match pop givers with
            | Some w ->
              meet p i w
              wake w ()
              resume p k (given w)
            | None -> ()
          else
            let cell = push takers (Branch (p, i, (), k))
            onUndo p (fun () -> drop takers cell)
          Done }
    Ch { givers = givers; takers = takers; taking = taking }

  /// Giving x: happens when it meets a taker.
  let give (ch: Ch<'a>) (x: 'a) : Alt<unit> =
    solo (sendWork ch x) { ready = (fun () -> size ch.takers > 0)
      go = fun p i k now ->
        if now then
          match pop ch.takers with
          | Some w ->
            meet p i w
            wake w x
            resume p k ()
          | None -> ()
        else
          let cell = push ch.givers (Branch (p, i, x, k))
          onUndo p (fun () -> drop ch.givers cell)
        Done }

  /// Taking a value: happens when it meets a giver. It's the same event each time, so getting
  /// it costs nothing.
  let take (ch: Ch<'a>) : Alt<'a> = ch.taking

  /// `Alt.sync (Ch.give ch x)`, faster: no event is made.
  let send (ch: Ch<'a>) (x: 'a) : Task<unit> = { ready = None; work = sendWork ch x }

  /// `Alt.sync (Ch.take ch)`, as fast: its work is made once, with the channel.
  let receive (ch: Ch<'a>) : Task<'a> = Alt.sync ch.taking

/// Functions on mailboxes.
module Mailbox =
  /// An empty mailbox.
  let make () : Mailbox<'a> =
    let values = queue ()
    let takers = queue ()
    let taking =
      solo (postedWork values takers) { ready = (fun () -> size values > 0)
        go = fun p i k now ->
          if now then
            match pop values with
            | Some x ->
              win p i
              resume p k x
            | None -> ()
          else
            let cell = push takers (Branch (p, i, (), k))
            onUndo p (fun () -> drop takers cell)
          Done }
    { values = values; takers = takers; taking = taking }

  /// Adds x: the oldest waiting taker gets it at once, else it's kept. Never waits, so it works
  /// outside tasks too.
  let post (m: Mailbox<'a>) (x: 'a) =
    match pop m.takers with
    | Some w ->
      taken w
      wake w x
    | None -> push m.values x |> ignore

  /// The oldest value posted, as an event (the same each time, so getting it costs nothing).
  let take (m: Mailbox<'a>) : Alt<'a> = m.taking
