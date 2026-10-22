/// Tasks: work that may wait (for input, a timer, other tasks) without blocking the program,
/// run by an event loop. `task { }` writes one, and `Task.run` runs it from `main`. Each thread
/// has a loop of its own: `Task.spawn` starts a task on another thread's, to use every core.
namespace Threading

/// A task's cancellation: whether it has been cancelled, and what to do then (stop waiting,
/// dispose what `use` bound). A task started by `both`, `all`, `race` or `Task.start` has its
/// own, under its parent's, so cancelling a task cancels what it started.
type Cancel =
  { /// Whether it has been cancelled.
    cancelled: ref<bool>
    /// What to do then, newest first, each with the number it was added under.
    actions: ref<list<int * (unit -> unit)>>
    /// The number the next action gets.
    nextAction: ref<int> }

/// Work that may wait (for input, a timer, other tasks) and then gives an `'a`. A task is cold:
/// making one does nothing, and running it twice does the work twice.
type Task<'a> =
  /// The work, given its cancellation and what to do with its result.
  | Task of (Cancel -> ('a -> unit) -> unit)

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
    /// The tasks waiting for it, newest first, each with its number.
    waiting: ref<list<int * ('a -> unit)>>
    /// The number the next waiting task gets.
    nextWaiting: ref<int> }

/// Functions on tasks.
module Task =
  let private newCancel () : Cancel = { cancelled = ref false; actions = ref []; nextAction = ref 0 }

  // runs a task's work with this cancellation and continuation, unless it's cancelled already
  let private runIn (t: Task<'a>) (c: Cancel) (k: 'a -> unit) =
    let (Task work) = t
    if not c.cancelled.Value then work c k

  // adds an action for when c is cancelled; its number removes it (forget) once it's not needed
  let private onCancel (c: Cancel) (f: unit -> unit) =
    let id = c.nextAction.Value
    c.nextAction.Value <- id + 1
    c.actions.Value <- (id, f) :: c.actions.Value
    id

  let private forget (c: Cancel) (id: int) = c.actions.Value <- List.filter (fun (i, _) -> i <> id) c.actions.Value

  // cancels c: its actions run, newest first (what the task did last is undone first), once
  let private cancelNow (c: Cancel) =
    if not c.cancelled.Value then
      c.cancelled.Value <- true
      let actions = c.actions.Value
      c.actions.Value <- []
      for (_, f) in actions do
        f ()

  // a cancellation under c, cancelled with it; the number unlinks it once it's done
  let private child (c: Cancel) =
    let k = newCancel ()
    let link = onCancel c (fun () -> cancelNow k)
    (k, link)

  // calls k x now, or through the event loop when continuations are already nested deeply (a
  // run of awaits that complete at once would otherwise grow the stack)
  let private resume (k: 'a -> unit) (x: 'a) =
    if Native.loopEnter () then
      k x
      Native.loopLeave ()
    else
      Native.loopPost (fun () -> k x)

  /// A task that gives `x` at once.
  let ret (x: 'a) : Task<'a> = Task (fun _ k -> resume k x)

  /// The task `t`, then the task `f` makes from its result: what `let!` is.
  let bind (t: Task<'a>) (f: 'a -> Task<'b>) : Task<'b> = Task (fun c k -> runIn t c (fun x -> runIn (f x) c k))

  /// The task's result with `f` applied.
  let map (f: 'a -> 'b) (t: Task<'a>) : Task<'b> = Task (fun c k -> runIn t c (fun x -> k (f x)))

  /// Runs the task on the event loop until it has finished, and gives its result: how `main`
  /// starts tasks (inside one, `let!` waits for another).
  let run (t: Task<'a>) : 'a =
    let result = ref None
    runIn t (newCancel ()) (fun x -> result.Value <- Some x)
    while Option.isNone result.Value && Native.loopStep () do
      ()
    Native.loopClose ()
    match result.Value with
    | Some x -> x
    | None -> panic "Task.run: the task waits for something that can't happen any more"

  /// Waits `ms` milliseconds.
  let sleep (ms: int) : Task<unit> =
    Task (fun c k ->
      let timer = ref 0
      let id = onCancel c (fun () -> Native.loopUntimer timer.Value)
      timer.Value <- Native.loopTimer ms (fun () ->
        forget c id
        resume k ()))

  /// Waits until the file descriptor can be read (or, with write, written) without blocking:
  /// for libraries over non-blocking system calls, as `Tcp` is.
  let waitFor (fd: int) (write: bool) : Task<unit> =
    Task (fun c k ->
      let id = onCancel c (fun () -> Native.loopUnwait fd write)
      Native.loopWait fd write (fun () ->
        forget c id
        resume k ()))

  /// Runs both tasks at once, and gives both results once both have finished.
  let both (a: Task<'a>) (b: Task<'b>) : Task<'a * 'b> =
    Task (fun c k ->
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
    Task (fun c k ->
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
  let race (a: Task<'a>) (b: Task<'a>) : Task<'a> =
    Task (fun c k ->
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
  let timeout (ms: int) (t: Task<'a>) : Task<option<'a>> = race (map Some t) (map (fun () -> None) (sleep ms))

  /// A promise with no result yet: `Task.fulfill` gives it one.
  let promise () : Promise<'a> = { result = ref None; waiting = ref []; nextWaiting = ref 0 }

  /// Gives the promise its result (only the first time), and the tasks waiting for it go on.
  let fulfill (p: Promise<'a>) (x: 'a) =
    if Option.isNone p.result.Value then
      p.result.Value <- Some x
      let waiting = List.rev p.waiting.Value
      p.waiting.Value <- []
      for (_, k) in waiting do
        resume k x

  /// Waits for the promise's result.
  let wait (p: Promise<'a>) : Task<'a> =
    Task (fun c k ->
      match p.result.Value with
      | Some x -> resume k x
      | None ->
        let id = p.nextWaiting.Value
        p.nextWaiting.Value <- id + 1
        let cid = onCancel c (fun () -> p.waiting.Value <- List.filter (fun (i, _) -> i <> id) p.waiting.Value)
        p.waiting.Value <- (id, fun x ->
          forget c cid
          k x) :: p.waiting.Value)

  /// Runs `body` with a scope for tasks to run alongside it (`Task.start`). The scope finishes
  /// once its body has and every task started in it has finished or been cancelled.
  let scope (body: Scope -> Task<'a>) : Task<'a> =
    Task (fun c k ->
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
    Task (fun c k ->
      let result = Mutex.make None
      Native.loopBlocking (fun () -> Mutex.set result (Some (f ()))) (fun () ->
        match Mutex.get result with
        | Some x when not c.cancelled.Value -> resume k x
        | _ -> ()))

  /// Runs the task `f` makes on another thread, which has an event loop of its own, so tasks
  /// use every core (a server's connections, say). `f` crosses threads, so what it captures
  /// must be Share, as the result must. The task stays on that thread to the end: cancelling
  /// this one doesn't stop it (its result is dropped).
  let spawn (f: share<unit -> Task<'a>>) : Task<'a> =
    Task (fun c k ->
      let result = Mutex.make None
      let token = Native.loopExpect (fun () ->
        match Mutex.get result with
        | Some x when not c.cancelled.Value -> resume k x
        | _ -> ())
      Native.loopSpawn (fun () ->
        runIn (f ()) (newCancel ()) (fun x ->
          Mutex.set result (Some x)
          Native.loopFulfill token)))

  /// The `task { }` builder.
  module Builder =
    /// `let!` and `do!`: the rest once the task has given its result.
    let bind t f = Task.bind t f

    /// `return x`.
    let ret x = Task.ret x

    /// An `if` without `else`, or a body that ends in a statement.
    let zero () = Task.ret ()

    /// The body, run when the task runs (a task is cold).
    let delay (f: unit -> Task<'a>) : Task<'a> = Task (fun c k -> runIn (f ()) c k)

    /// `use x = e`: the rest, with `x` disposed when it finishes or is cancelled.
    let using (x: 'r) (f: 'r -> Task<'b>) : Task<'b> =
      Task (fun c k ->
        let id = onCancel c (fun () -> dispose x)
        runIn (f x) c (fun r ->
          forget c id
          dispose x
          k r))

    /// `for x in xs do`: the body for each element, one after another.
    let rec forEach (xs: list<'a>) (f: 'a -> Task<unit>) : Task<unit> =
      match xs with
      | [] -> Task.ret ()
      | x :: rest -> Task.bind (f x) (fun () -> forEach rest f)
