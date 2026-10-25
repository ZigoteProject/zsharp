// Where events (Threading.Alt) beat plain tasks, and where they don't: jobs that wait for the
// first of several things, each written with Alt and with the best plain-task code we found.
//  1. Taking from two queues, high priority first, with a timeout. The obvious task version,
//     Task.race of two takes, loses messages: the losing take stays registered with its queue,
//     which later hands a value to a task that's gone (here every high message: the dead
//     waiters pile up on the queue posted to less often). A disposable registration ("careful
//     takes") fixes the waiting path, but still loses values when both queues hold some: both
//     takes finish at once, their resumptions go through the loop, and Task.race keeps one.
//     The task version that is correct keeps values in the queues and races only a wake-up (a
//     bell the queues share); it's as fast as Alt, but every producer must ring that bell.
//     Alt.choose needs no change to the queues: it commits exactly one branch, takes the rest back.
//  2. Hedged requests: a client asks two replicas and takes the first answer (or gives up). A
//     replica that isn't told its client left does the whole job anyway. Plain tasks can tell
//     it: the call binds a "gone" promise with `use`, fulfilled however the call ends, which
//     does as well as Alt.withNack; with Alt the nack is part of the event, nothing to remember.
//  3. Four independent queues, one consumer. A bell shared by the queues is fastest (faster than
//     Alt), but couples every producer to this consumer. With queues that don't know who takes
//     from them, the task version races a signal per queue; Alt.choose just composes the takes.
// So Alt's wins are being correct the first time and composing events from parts that don't
// know each other, cheaply; a task version can match it, with care, for one fixed shape.
// Usage: main [messages] (200000 by default, for part 3).

// ---------------------------------------------------------------- a queue for tasks

// a FIFO, amortized O(1): pushed onto back, popped from front (back reversed when it's empty)
type Fifo<'a> = { front: ref<list<'a>>; back: ref<list<'a>> }

let fifo () : Fifo<'a> = { front = ref []; back = ref [] }

let push (f: Fifo<'a>) (x: 'a) = f.back.Value <- x :: f.back.Value

let pop (f: Fifo<'a>) : option<'a> =
  if List.isEmpty f.front.Value then
    f.front.Value <- List.rev f.back.Value
    f.back.Value <- []
  match f.front.Value with
  | x :: rest ->
    f.front.Value <- rest
    Some x
  | [] -> None

/// A queue between tasks: posting never waits, a take waits on a promise for the next value.
type TQueue<'a> = { items: Fifo<'a>; waiters: Fifo<int * Promise<'a>>; next: ref<int> }

let tqueue () : TQueue<'a> = { items = fifo (); waiters = fifo (); next = ref 0 }

// a value goes to the oldest waiter, else into the queue
let post (q: TQueue<'a>) (x: 'a) =
  match pop q.waiters with
  | Some (_, p) -> Task.fulfill p x
  | None -> push q.items x

// registers a waiter: its number and its promise
let wait (q: TQueue<'a>) : int * Promise<'a> =
  let id = q.next.Value
  q.next.Value <- id + 1
  let p = Task.promise ()
  push q.waiters (id, p)
  (id, p)

// the obvious take: a value if there is one, else wait on a promise
let take (q: TQueue<'a>) : Task<'a> =
  task {
    match pop q.items with
    | Some x -> return x
    | None ->
      let (_, p) = wait q
      return! Task.wait p
  }

// ---------------------------------------------------------------- the careful take

// a take that's waiting. When its task is cancelled (`use` disposes it then), it leaves the
// queue's waiters, and a value already given to it goes back: to the next waiter, else to the
// queue's front, so the order holds
type Waiting<'a> = { queue: TQueue<'a>; id: int; promise: Promise<'a>; taken: ref<bool> }

impl Dispose<Waiting<'a>> =
  let dispose (w: Waiting<'a>) =
    if not w.taken.Value then
      let ws = w.queue.waiters
      let all = List.append ws.front.Value (List.rev ws.back.Value)
      ws.front.Value <- List.filter (fun (i, _) -> i <> w.id) all
      ws.back.Value <- []
      match w.promise.result.Value with
      | Some x ->
        match pop ws with
        | Some (_, p) -> Task.fulfill p x
        | None -> w.queue.items.front.Value <- x :: w.queue.items.front.Value
      | None -> ()

// a take a race can cancel without losing a value
let takeCarefully (q: TQueue<'a>) : Task<'a> =
  task {
    match pop q.items with
    | Some x -> return x
    | None ->
      let (id, p) = wait q
      use w = { queue = q; id = id; promise = p; taken = ref false }
      let! x = Task.wait p
      w.taken.Value <- true
      return x
  }

// ---------------------------------------------------------------- the bell: one wake-up for all

// the queues' values stay in plain FIFOs; a waiting consumer waits only for a ring, so
// cancelling the wait loses nothing. Every producer must ring this consumer's bell
type Bell = { ring: ref<option<Promise<unit>>> }

let bell () : Bell = { ring = ref None }

let ring (b: Bell) =
  match b.ring.Value with
  | Some p ->
    b.ring.Value <- None
    Task.fulfill p ()
  | None -> ()

let bpost (b: Bell) (f: Fifo<'a>) (x: 'a) =
  push f x
  ring b

// the first queue's value, in the list's order (so the first queue has priority)
let rec first (qs: list<Fifo<'a>>) : option<'a> =
  match qs with
  | q :: rest ->
    match pop q with
    | Some x -> Some x
    | None -> first rest
  | [] -> None

let rec bellTake (b: Bell) (qs: list<Fifo<'a>>) : Task<'a> =
  task {
    match first qs with
    | Some x -> return x
    | None ->
      let p = Task.promise ()
      b.ring.Value <- Some p
      do! Task.wait p
      return! bellTake b qs
  }

// with a timeout on the wait only: a timeout around bellTake would race a take that pops a
// value, and lose it as Task.race does
let rec bellWithin (b: Bell) (qs: list<Fifo<'a>>) (ms: int) : Task<option<'a>> =
  task {
    match first qs with
    | Some x -> return Some x
    | None ->
      let p = Task.promise ()
      b.ring.Value <- Some p
      let! w = Task.timeout ms (Task.wait p)
      match w with
      | Some () -> return! bellWithin b qs ms
      | None -> return None
  }

// ---------------------------------------------------------------- a signal per queue

// a queue that doesn't know who takes from it: it signals that it has a value, and a consumer
// of several races their signals, then looks
type SQueue<'a> = { values: Fifo<'a>; signal: ref<option<Promise<unit>>> }

let squeue () : SQueue<'a> = { values = fifo (); signal = ref None }

let spost (q: SQueue<'a>) (x: 'a) =
  push q.values x
  match q.signal.Value with
  | Some p ->
    q.signal.Value <- None
    Task.fulfill p ()
  | None -> ()

let nonEmpty (q: SQueue<'a>) : Task<unit> =
  match q.signal.Value with
  | Some p -> Task.wait p
  | None ->
    let p = Task.promise ()
    q.signal.Value <- Some p
    Task.wait p

let rec signalTake (qs: list<SQueue<'a>>) : Task<'a> =
  task {
    match first (List.map (fun (q: SQueue<'a>) -> q.values) qs) with
    | Some x -> return x
    | None ->
      do! List.reduce Task.race (List.map nonEmpty qs)
      return! signalTake qs
  }

// ---------------------------------------------------------------- 1. two queues, a timeout

// posts n numbers, every third to high, the rest to low, letting the consumer run between some
let rec producing (postHigh: int -> unit) (postLow: int -> unit) (i: int) (n: int) : Task<unit> =
  task {
    if i < n then
      if i % 3 = 0 then postHigh i else postLow i
      if i % 2 = 0 then
        do! Task.yield ()
      return! producing postHigh postLow (i + 1) n
  }

// takes until nothing comes for a while: how many it got
let rec consuming (next: unit -> Task<option<int>>) (got: int) : Task<int> =
  task {
    let! x = next ()
    match x with
    | Some _ -> return! consuming next (got + 1)
    | None -> return got
  }

let twoQueues (name: string) (n: int) (postHigh: int -> unit) (postLow: int -> unit) (next: unit -> Task<option<int>>) =
  let got =
    Task.run (Task.scope (fun s ->
        task {
          Task.start s (producing postHigh postLow 0 n) |> ignore
          return! consuming next 0
        }))
  println $"  {name}: sent {n}, received {got}, lost {n - got}"

// the same with every value posted before the consumer starts: both queues hold values
let allFirst (name: string) (n: int) (postHigh: int -> unit) (postLow: int -> unit) (next: unit -> Task<option<int>>) =
  for i in 0 .. n - 1 do
    if i % 3 = 0 then postHigh i else postLow i
  let got = Task.run (consuming next 0)
  println $"  {name}: sent {n} first, received {got}, lost {n - got}"

let partOne () =
  let n = 10000
  println "1. two queues and a timeout"
  let (high, low) = (tqueue (), tqueue ())
  twoQueues "Task.race of takes" n (post high) (post low) (fun () ->
    Task.timeout 20 (Task.race (take high) (take low)))
  let careful (high: TQueue<int>) (low: TQueue<int>) () =
    Task.timeout 20 (Task.race (takeCarefully high) (takeCarefully low))
  let (high, low) = (tqueue (), tqueue ())
  twoQueues "careful takes     " n (post high) (post low) (careful high low)
  let (high, low) = (tqueue (), tqueue ())
  allFirst "careful takes     " n (post high) (post low) (careful high low)
  let withBell (f: string -> int -> (int -> unit) -> (int -> unit) -> (unit -> Task<option<int>>) -> unit) =
    let b = bell ()
    let (high, low) = (fifo (), fifo ())
    f "a bell            " n (bpost b high) (bpost b low) (fun () -> bellWithin b [ high; low ] 20)
  withBell twoQueues
  withBell allFirst
  let withAlt (f: string -> int -> (int -> unit) -> (int -> unit) -> (unit -> Task<option<int>>) -> unit) =
    let (high, low) = (Mailbox.make (), Mailbox.make ())
    let next =
      Alt.choose [ Alt.map Some (Mailbox.take high)
        Alt.map Some (Mailbox.take low)
        Alt.map (fun () -> None) (Alt.after 20) ]
    f "Alt.choose        " n (Mailbox.post high) (Mailbox.post low) (fun () -> Alt.sync next)
  withAlt twoQueues
  withAlt allFirst

// ---------------------------------------------------------------- 2. hedged requests

// how long a replica's job takes (the slow one's 4 ms more), and how long a client waits
let jobMs = 1
let deadlineMs = 100

/// A replica's counts: the jobs it finished, and those it skipped or stopped part way.
type Counts = { finished: ref<int>; stopped: ref<int> }

// a task replica: takes n requests in turn, does each job and answers it (whether anyone
// listens or not)
let rec taskReplica (reqs: TQueue<int * Promise<int>>) (slowdown: int) (counts: Counts) (n: int) : Task<unit> =
  task {
    if n > 0 then
      let! (x, reply) = take reqs
      do! Task.sleep (jobMs + slowdown)
      counts.finished.Value <- counts.finished.Value + 1
      Task.fulfill reply (x * 2)
      return! taskReplica reqs slowdown counts (n - 1)
  }

let taskCall (reqs: TQueue<int * Promise<int>>) (x: int) : Task<int> =
  task {
    let reply = Task.promise ()
    post reqs (x, reply)
    return! Task.wait reply
  }

// the careful task version: the call hands over a "gone" promise, fulfilled by a `use`d value,
// so every way the call ends (it won, lost the race, timed out, its scope was cancelled) tells
// the replica. A nack, by hand

/// Fulfils its promise when disposed: when the call that bound it ends, however it ends.
type Leaving = { gone: Promise<unit> }

impl Dispose<Leaving> =
  let dispose (l: Leaving) = Task.fulfill l.gone ()

// a careful task replica: skips a request whose client has gone, and races its job with the
// client going
let rec carefulReplica (reqs: TQueue<int * Promise<int> * Promise<unit>>) (slowdown: int) (counts: Counts) (n: int) : Task<unit> =
  task {
    if n > 0 then
      let! (x, reply, gone) = take reqs
      if Option.isSome gone.result.Value then
        counts.stopped.Value <- counts.stopped.Value + 1
      else
        let! finished =
          Task.race (Task.map (fun () -> true) (Task.sleep (jobMs + slowdown))) (Task.map (fun () ->
              false) (Task.wait gone))
        if finished then
          counts.finished.Value <- counts.finished.Value + 1
          Task.fulfill reply (x * 2)
        else
          counts.stopped.Value <- counts.stopped.Value + 1
      return! carefulReplica reqs slowdown counts (n - 1)
  }

let carefulCall (reqs: TQueue<int * Promise<int> * Promise<unit>>) (x: int) : Task<int> =
  task {
    let reply = Task.promise ()
    use l = { gone = Task.promise () }
    post reqs (x, reply, l.gone)
    return! Task.wait reply
  }

/// A request to an Alt replica: the number, where the answer goes, and the client's nack.
type Request = int * Ch<int> * Alt<unit>

/// What an Alt replica's job comes to.
type Job =
  | Done
  | Left

// an Alt replica: takes n requests in turn; skips one whose client has left, and stops a job
// when its client leaves (the job is an event too: its timer)
let rec altReplica (reqs: Mailbox<Request>) (slowdown: int) (counts: Counts) (n: int) : Task<unit> =
  task {
    if n > 0 then
      let! (x, reply, nack) = Alt.sync (Mailbox.take reqs)
      let! job =
        Alt.sync (Alt.choose [ Alt.map (fun () -> Left) nack
            Alt.map (fun () -> Done) (Alt.after (jobMs + slowdown)) ])
      match job with
      | Done ->
        counts.finished.Value <- counts.finished.Value + 1
        do! Alt.sync (Alt.choose [ Ch.give reply (x * 2); nack ])
      | Left -> counts.stopped.Value <- counts.stopped.Value + 1
      return! altReplica reqs slowdown counts (n - 1)
  }

// a call to an Alt replica: the request goes out when the sync starts, with its nack
let altCall (reqs: Mailbox<Request>) (x: int) : Alt<int> =
  Alt.withNack (fun nack ->
    let reply = Ch.make ()
    Mailbox.post reqs (x, reply, nack)
    Ch.take reply)

let counts () = { finished = ref 0; stopped = ref 0 }

let report (name: string) (answered: list<option<int>>) (a: Counts) (b: Counts) (ms: u64) =
  let ok = answered |> List.filter Option.isSome |> List.length
  let jobs = a.finished.Value + b.finished.Value
  println $"  {name}: {ok} answered of {List.length answered}, {jobs} jobs done ({jobs - ok} for no one), {a.stopped.Value + b.stopped.Value} skipped or stopped, all done in {ms} ms"

let partTwo () =
  let clients = 40
  println $"2. hedged requests: {clients} clients at once, each asking a fast and a slow replica"
  let (ra, rb) = (tqueue (), tqueue ())
  let (ca, cb) = (counts (), counts ())
  let start = Runtime.ticks ()
  let answered =
    Task.run (Task.scope (fun s ->
        task {
          Task.start s (taskReplica ra 0 ca clients) |> ignore
          Task.start s (taskReplica rb 4 cb clients) |> ignore
          let! answers =
            Task.all (List.init clients (fun i ->
                Task.timeout deadlineMs (Task.race (taskCall ra i) (taskCall rb i))))
          // the scope ends once the replicas have handled every request
          return answers
        }))
  report "Task.race of calls" answered ca cb ((Runtime.ticks () - start) / u64 1000000)

  let (ra, rb) = (tqueue (), tqueue ())
  let (ca, cb) = (counts (), counts ())
  let start = Runtime.ticks ()
  let answered =
    Task.run (Task.scope (fun s ->
        task {
          Task.start s (carefulReplica ra 0 ca clients) |> ignore
          Task.start s (carefulReplica rb 4 cb clients) |> ignore
          let! answers =
            Task.all (List.init clients (fun i ->
                Task.timeout deadlineMs (Task.race (carefulCall ra i) (carefulCall rb i))))
          return answers
        }))
  report "careful calls     " answered ca cb ((Runtime.ticks () - start) / u64 1000000)

  let (ra, rb) = (Mailbox.make (), Mailbox.make ())
  let (ca, cb) = (counts (), counts ())
  let start = Runtime.ticks ()
  let answered =
    Task.run (Task.scope (fun s ->
        task {
          Task.start s (altReplica ra 0 ca clients) |> ignore
          Task.start s (altReplica rb 4 cb clients) |> ignore
          let! answers =
            Task.all (List.init clients (fun i ->
                Alt.sync (
                  Alt.choose
                  [ Alt.map Some (altCall ra i)
                    Alt.map Some (altCall rb i)
                    Alt.map (fun () -> None) (Alt.after deadlineMs) ]
                )))
          // the scope ends once the replicas have handled every request
          return answers
        }))
  report "Alt.choose + nacks" answered ca cb ((Runtime.ticks () - start) / u64 1000000)

// ---------------------------------------------------------------- 3. throughput

// posts n numbers to the queue, letting the others run after each
let rec feeding (post: int -> unit) (i: int) (n: int) : Task<unit> =
  task {
    if i < n then
      post i
      do! Task.yield ()
      return! feeding post (i + 1) n
  }

let rec draining (next: unit -> Task<int>) (left: int) (sum: int) : Task<int> =
  task {
    if left = 0 then
      return sum
    else
      let! x = next ()
      return! draining next (left - 1) (sum + x)
  }

// four producers, one consumer taking from any of their queues: the checksum, ms and
// allocations per message
let fourQueues (name: string) (n: int) (posts: list<int -> unit>) (next: unit -> Task<int>) =
  let a0 = Runtime.allocations ()
  let t0 = Runtime.ticks ()
  let sum =
    Task.run (Task.scope (fun s ->
        task {
          for p in posts do
            Task.start s (feeding p 0 (n / 4)) |> ignore
          return! draining next n 0
        }))
  let ms = (Runtime.ticks () - t0) / u64 1000000
  let allocs = (Runtime.allocations () - a0) / n
  println $"  {name}: {ms} ms, {allocs} allocations per message (checksum {sum})"

let partThree (n: int) =
  println $"3. one consumer, four independent queues, {n} messages"
  let qs = List.init 4 (fun _ -> tqueue ())
  let careful = List.reduce Task.race (List.map takeCarefully qs)
  fourQueues "careful takes     " n (List.map post qs) (fun () -> careful)
  let ss = List.init 4 (fun _ -> squeue ())
  fourQueues "a signal per queue" n (List.map spost ss) (fun () -> signalTake ss)
  let b = bell ()
  let fs = List.init 4 (fun _ -> fifo ())
  fourQueues "a shared bell     " n (List.map (bpost b) fs) (fun () -> bellTake b fs)
  let ms = List.init 4 (fun _ -> Mailbox.make ())
  let any = Alt.choose (List.map Mailbox.take ms)
  fourQueues "Alt.choose        " n (List.map Mailbox.post ms) (fun () -> Alt.sync any)

let main () =
  let n =
    match Environment.args () with
    | a :: _ -> Option.defaultValue 200000 (String.parseInt a)
    | [] -> 200000
  partOne ()
  partTwo ()
  partThree (n / 4 * 4)
  0
