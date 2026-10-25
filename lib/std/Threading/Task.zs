/// Tasks: work that may wait (for input, a timer, other tasks) without blocking the program,
/// run by an event loop. `task { }` writes one, and `Task.run` runs it from `main`. Each thread
/// has a loop of its own: `Task.spawn` starts a task on another thread's, to use every core.
namespace Threading

// where a Callbacks is: the number the next one gets, and how many have been taken back
type private Counts = { next: int; dead: int }

// callbacks under numbers, in the order they were added: a Cancel's actions, or the tasks
// waiting for a Promise. Adding one, taking it back and taking them all out are cheap, whatever
// the order. Each entry has its number, ascending (None once taken back)
type private Callbacks<'f> = { entries: Buffer<int * option<'f>>; counts: ref<Counts> }

/// A task's cancellation: whether it has been cancelled, and what to do then (stop waiting,
/// dispose what `use` bound). A task started by `both`, `all`, `race` or `Task.start` has its
/// own, under its parent's, so cancelling a task cancels what it started.
type Cancel =
  { /// Whether it has been cancelled.
    cancelled: ref<bool>
    /// What to do then.
    actions: Callbacks<unit -> unit> }

/// Work that may wait (for input, a timer, other tasks) and then gives an `'a`. A task is cold:
/// making one does nothing, and running it twice does the work twice.
type Task<'a> =
  { /// The result, when it's there already (`Task.ret`): waiting for it takes no turn of the loop.
    ready: option<'a>
    /// Otherwise the work, given its cancellation and what to do with its result.
    work: Cancel -> ('a -> unit) -> unit }

/// The tasks started in a `Task.scope` with `Task.start`: they can't outlive it.
type Scope =
  { /// The cancellation of the tasks started in it.
    children: Cancel
    /// How many of them haven't finished.
    running: ref<int>
    /// What to do once the last has (the scope finishing, after its body).
    whenDone: ref<option<unit -> unit>> }

/// A result to come: a task's started with `Task.start`, or one given with `Task.fulfill`.
/// `Task.wait` waits for it.
type Promise<'a> =
  { /// The result, once there is one.
    result: ref<option<'a>>
    /// The tasks waiting for it.
    waiting: Callbacks<'a -> unit> }

// ---------------------------------------------------------------- callbacks
// For Task and Alt only (they're private to the namespace): a Cancel's actions, a Promise's
// waiting tasks, and what Alt leaves on them.

// none yet
let private callbacks () : Callbacks<'f> =
  { entries = Buffer.empty; counts = ref { next = 0; dead = 0 } }

// adds f, and gives the number that takes it back
let private addCallback (cs: Callbacks<'f>) (f: 'f) : int =
  let c = cs.counts.Value
  cs.counts.Value <- { c with next = c.next + 1 }
  Buffer.push (c.next, Some f) cs.entries
  c.next

// the place of id among the entries, or -1
let private findCallback (cs: Callbacks<'f>) (id: int) : int =
  let mutable lo = 0
  let mutable hi = Buffer.length cs.entries
  while lo < hi do
    let mid = (lo + hi) / 2
    if fst cs.entries.[mid] < id then lo <- mid + 1 else hi <- mid
  if lo < Buffer.length cs.entries && fst cs.entries.[lo] = id then lo else -1

// drops the taken-back entries at the end, and moves the rest up once most are taken back
let private compactCallbacks (cs: Callbacks<'f>) =
  let es = cs.entries
  let before = cs.counts.Value.dead
  let mutable dead = before
  while Buffer.length es > 0 && Option.isNone (snd es.[Buffer.length es - 1]) do
    Buffer.removeLast es |> ignore
    dead <- dead - 1
  let n = Buffer.length es
  if dead > 32 && 2 * dead > n then
    let mutable j = 0
    for i in 0 .. n - 1 do
      if Option.isSome (snd es.[i]) then
        es.[j] <- es.[i]
        j <- j + 1
    Buffer.truncate j es
    dead <- 0
  if dead <> before then cs.counts.Value <- { cs.counts.Value with dead = dead }

// takes back what's under id, and says whether it was still there
let private removeCallback (cs: Callbacks<'f>) (id: int) : bool =
  let es = cs.entries
  let n = Buffer.length es
  if n > 0 && fst es.[n - 1] = id then
    // the newest, as a wait's is (the last entry is never one taken back)
    Buffer.removeLast es |> ignore
    compactCallbacks cs
    true
  else
    let i = findCallback cs id
    if i >= 0 && Option.isSome (snd es.[i]) then
      es.[i] <- (id, None)
      cs.counts.Value <- { cs.counts.Value with dead = cs.counts.Value.dead + 1 }
      compactCallbacks cs
      true
    else
      false

// takes them all out, and gives each to call: newest first, or oldest first
let private drainCallbacks (cs: Callbacks<'f>) (newestFirst: bool) (call: 'f -> unit) =
  let n = Buffer.length cs.entries
  cs.counts.Value <- { cs.counts.Value with dead = 0 }
  if n = 1 then
    // the usual case, with nothing to copy (the one entry is never one taken back)
    match snd (Buffer.removeLast cs.entries) with
    | Some f -> call f
    | None -> ()
  else if n > 1 then
    // a copy, as call may add more or take some back
    let all = Buffer.toArray cs.entries
    Buffer.truncate 0 cs.entries
    for j in 0 .. n - 1 do
      match snd all.[if newestFirst then n - 1 - j else j] with
      | Some f -> call f
      | None -> ()

let private newCancel () : Cancel = { cancelled = ref false; actions = callbacks () }

// adds f to what c does when it's cancelled (a wait to undo then, as Alt's are); its number
// goes to forget once it's not needed
let private onCancel (c: Cancel) (f: unit -> unit) : int = addCallback c.actions f

// takes back an action onCancel added
let private forget (c: Cancel) (id: int) = removeCallback c.actions id |> ignore

// cancels c: its actions run, newest first, once
let private cancelNow (c: Cancel) =
  if not c.cancelled.Value then
    c.cancelled.Value <- true
    drainCallbacks c.actions true (fun f -> f ())

// a cancellation under c, cancelled with it, and the number (forget c) that unlinks it
let private child (c: Cancel) : Cancel * int =
  let k = newCancel ()
  let link = onCancel c (fun () -> cancelNow k)
  (k, link)

/// Functions on tasks.
module Task =
  // a task that does this work when it runs
  let private pending (work: Cancel -> ('a -> unit) -> unit) : Task<'a> =
    { ready = None; work = work }

  // the work of a task that's ready: never called
  let private never (c: Cancel) (k: 'a -> unit) = ()

  // calls k x now, or through the event loop when continuations are already nested deeply (a
  // run of awaits that complete at once would otherwise grow the stack)
  let private resume (k: 'a -> unit) (x: 'a) =
    if Native.loopEnter () then
      k x
      Native.loopLeave ()
    else
      Native.loopPost (fun () -> k x)

  // runs a task with this cancellation and continuation, unless it's cancelled already
  let private runIn (t: Task<'a>) (c: Cancel) (k: 'a -> unit) =
    match t.ready with
    | Some x -> resume k x
    | None -> if not c.cancelled.Value then t.work c k

  /// Gives a task's result to what waits for it: the end of the code `task { }` compiles to.
  let complete (k: 'a -> unit) (x: 'a) = resume k x

  /// `use x = …` in a task: x is disposed if the task is cancelled. The number goes to
  /// `Task.disposed` when the scope ends.
  let disposeOnCancel (c: Cancel) (x: 'r) : int = onCancel c (fun () -> dispose x)

  /// The end of a `use` scope in a task: x is disposed, and no longer on cancellation.
  let disposed (c: Cancel) (id: int) (x: 'r) =
    // gone when the cancellation has disposed it already
    if removeCallback c.actions id then dispose x

  /// A task that gives `x` at once.
  let ret (x: 'a) : Task<'a> = { ready = Some x; work = never }

  /// Lets the other tasks run, then goes on: a turn of the event loop.
  let yield () : Task<unit> = pending (fun _ k -> Native.loopPost k)

  /// The task `t`, then the task `f` makes from its result.
  let bind (t: Task<'a>) (f: 'a -> Task<'b>) : Task<'b> =
    match t.ready with
    | Some x -> f x
    | None -> pending (fun c k -> runIn t c (fun x -> runIn (f x) c k))

  /// The task's result with `f` applied.
  let map (f: 'a -> 'b) (t: Task<'a>) : Task<'b> =
    match t.ready with
    | Some x -> ret (f x)
    | None -> pending (fun c k -> runIn t c (fun x -> k (f x)))

  /// Runs the task on the event loop until it has finished, and gives its result: how `main`
  /// starts tasks (inside one, `let!` waits for another).
  let run (t: Task<'a>) : 'a =
    let result = ref None
    runIn t (newCancel ()) (fun x -> result.Value <- Some x)
    while Option.isNone result.Value && Native.loopStep () do
      ()
    // what it spawned and then cancelled answers once it's done there (its use values disposed
    // on its thread): waited for, so nothing of it outlives this
    while Native.loopJobs () > 0 && Native.loopStep () do
      ()
    Native.loopClose ()
    match result.Value with
    | Some x -> x
    | None -> panic "Task.run: the task waits for something that can't happen any more"

  /// Waits `ms` milliseconds.
  let sleep (ms: int) : Task<unit> =
    pending (fun c k ->
      let timer = ref 0
      let id = onCancel c (fun () -> Native.loopUntimer timer.Value)
      timer.Value <- Native.loopTimer ms (fun () ->
        forget c id
        resume k ()))

  /// Waits until the file descriptor can be read (or, with write, written) without blocking:
  /// for libraries over non-blocking system calls, as `Tcp` is.
  let waitFor (fd: int) (write: bool) : Task<unit> =
    pending (fun c k ->
      let id = onCancel c (fun () -> Native.loopUnwait fd write)
      Native.loopWait fd write (fun () ->
        forget c id
        resume k ()))

  /// Runs both tasks at once, and gives both results once both have finished.
  let both (a: Task<'a>) (b: Task<'b>) : Task<'a * 'b> =
    pending (fun c k ->
      let ra = ref None
      let rb = ref None
      let (ca, la) = child c
      let (cb, lb) = child c
      let finish () =
        match (ra.Value, rb.Value) with
        | (Some x, Some y) ->
          forget c la
          forget c lb
          resume k (x, y)
        | _ -> ()
      runIn a ca (fun x ->
        ra.Value <- Some x
        finish ())
      runIn b cb (fun y ->
        rb.Value <- Some y
        finish ()))

  /// Runs the tasks at once, and gives their results, in order, once all have finished.
  let all (ts: list<Task<'a>>) : Task<list<'a>> =
    pending (fun c k ->
      let n = List.length ts
      if n = 0 then
        resume k []
      else
        let results = Buffer.create n None
        let left = ref n
        let mutable i = 0
        for t in ts do
          let at = i
          let (ci, link) = child c
          runIn t ci (fun x ->
            forget c link
            results.[at] <- Some x
            left.Value <- left.Value - 1
            if left.Value = 0 then
              resume k (List.init n (fun j -> Option.get results.[j])))
          i <- i + 1)

  /// Runs both tasks at once, and gives the result of the first to finish. The other is
  /// cancelled: what it waits for is dropped, and what it bound with `use` disposed.
  /// It isn't a choice: when both finish in the same turn of the loop (both had a value ready,
  /// say), the second's result is dropped, and a task that had taken something to give it (a
  /// queue's value) loses it. To wait for the first of several such things, use Alt.choose,
  /// which commits exactly one.
  let race (a: Task<'a>) (b: Task<'a>) : Task<'a> =
    pending (fun c k ->
      let (ca, la) = child c
      let (cb, lb) = child c
      let decided = ref false
      let finish (x: 'a) =
        if not decided.Value then
          decided.Value <- true
          forget c la
          forget c lb
          cancelNow ca
          cancelNow cb
          resume k x
      runIn a ca finish
      runIn b cb finish)

  /// The task's result, or `None` when it takes longer than `ms` milliseconds (it's cancelled then).
  let timeout (ms: int) (t: Task<'a>) : Task<option<'a>> =
    race (map Some t) (map (fun () -> None) (sleep ms))

  /// A promise with no result yet: `Task.fulfill` gives it one.
  let promise () : Promise<'a> = { result = ref None; waiting = callbacks () }

  /// Gives the promise its result (only the first time), and the tasks waiting for it go on.
  let fulfill (p: Promise<'a>) (x: 'a) =
    if Option.isNone p.result.Value then
      p.result.Value <- Some x
      drainCallbacks p.waiting false (fun k -> resume k x)

  /// Waits for the promise's result.
  let wait (p: Promise<'a>) : Task<'a> =
    pending (fun c k ->
      match p.result.Value with
      | Some x -> resume k x
      | None ->
        // the number addCallback gives it below
        let id = p.waiting.counts.Value.next
        let cid = onCancel c (fun () -> removeCallback p.waiting id |> ignore)
        // a task resumed before it may have cancelled this one
        addCallback p.waiting (fun x ->
          if not c.cancelled.Value then
            forget c cid
            k x)
        |> ignore)

  /// Runs `body` with a scope for tasks to run alongside it (`Task.start`). The scope finishes
  /// once its body has and every task started in it has finished or been cancelled.
  let scope (body: Scope -> Task<'a>) : Task<'a> =
    pending (fun c k ->
      let (children, link) = child c
      let s = { children = children; running = ref 0; whenDone = ref None }
      runIn (body s) c (fun x ->
        let finish () =
          forget c link
          resume k x
        if s.running.Value = 0 then finish () else s.whenDone.Value <- Some finish))

  // one of the scope's tasks has finished, or been cancelled
  let private finished (s: Scope) =
    s.running.Value <- s.running.Value - 1
    if s.running.Value = 0 then
      match s.whenDone.Value with
      | Some f ->
        s.whenDone.Value <- None
        f ()
      | None -> ()

  /// Starts `t` in the scope now, running alongside what started it: the promise gives its
  /// result (`Task.wait`). The scope doesn't finish before it does.
  let start (s: Scope) (t: Task<'a>) : Promise<'a> =
    let p = promise ()
    if not s.children.cancelled.Value then
      let (c, link) = child s.children
      let over = ref false
      s.running.Value <- s.running.Value + 1
      let id = onCancel c (fun () ->
        if not over.Value then
          over.Value <- true
          forget s.children link
          finished s)
      runIn t c (fun x ->
        // a task cancelled after its last wait was over goes on to here: it's finished already
        if not over.Value then
          over.Value <- true
          forget c id
          forget s.children link
          fulfill p x
          finished s)
    p

  /// Cancels the tasks started in the scope (and what they started).
  let cancel (s: Scope) = cancelNow s.children

  /// Runs `f` on a helper thread, for a C call that blocks (a database's, say) while the event
  /// loop goes on. `f` crosses threads, so what it captures must be Share, as its result must.
  let blocking (f: share<unit -> 'a>) : Task<'a> =
    pending (fun c k ->
      let result = Mutex.make None
      Native.loopBlocking (fun () -> Mutex.set result (Some (f ()))) (fun () ->
        match Mutex.get result with
        | Some x when not c.cancelled.Value -> resume k x
        | _ -> ()))

  /// Runs the task `f` makes on another thread, which has an event loop of its own, so tasks
  /// use every core (a server's connections, say). `f` crosses threads, so what it captures
  /// must be Share, as the result must. The task stays on that thread to the end; cancelling
  /// this one cancels it there (its `use` values are disposed on its thread).
  let spawn (f: share<unit -> Task<'a>>) : Task<'a> =
    pending (fun c k ->
      let result = Mutex.make None
      // where the spawned task is: 0 not started, -1 cancelled before it started, -2 done (or
      // cancelled), else the token of its loop's that cancels it there
      let state = Mutex.make 0

      let link =
        onCancel c (fun () ->
          Mutex.update state (fun s ->
            match s with
            | 0 -> -1
            | s when s > 0 ->
              Native.loopFulfill s
              -2
            | s -> s)
          |> ignore)

      // what this loop runs once the spawned task is done or cancelled
      let token = Native.loopExpect (fun () ->
        forget c link
        match Mutex.get result with
        | Some x when not c.cancelled.Value -> resume k x
        | _ -> ())

      Native.loopSpawn (fun () ->
        let cc = newCancel ()
        let finished = ref false

        let finish () =
          if not finished.Value then
            finished.Value <- true
            Native.loopFulfill token

        // cancels it here (and is fulfilled when it's done, doing nothing then)
        let here = Native.loopExpect (fun () ->
          if not finished.Value then
            cancelNow cc
            finish ())

        if Mutex.update state (fun s -> if s = 0 then here else s) = -1 then
          Native.loopFulfill here
        else
          runIn (f ()) cc (fun x ->
            Mutex.set result (Some x)

            Mutex.update state (fun s ->
              match s with
              | s when s > 0 ->
                Native.loopFulfill s
                -2
              | s -> s)
            |> ignore

            finish ())))

  /// `return! t` at the end of a task's body: `t` runs with the task's cancellation, and its
  /// result goes to what waits for the task, which is done. So a task that loops by `return!`
  /// keeps one state machine, not one per round.
  let handOff (t: Task<'a>) (c: Cancel) (k: 'a -> unit) = runIn t c k

/// A test whose body is a task: it runs on the event loop, and its result is the outcome.
impl Testing.Outcome<Task<'a>> =
  let finish t = Testing.finish (Task.run t)
