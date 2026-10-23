// Cancelling a task cancels the tasks it spawned onto other threads: each is cancelled on its
// own loop, which disposes what it bound with `use` there, before the cancelled task's loop goes
// on. A spawned task that has finished isn't cancelled afterwards.
type Resource = Resource of string * Mutex<list<string>>

// recorded rather than printed: the loops dispose at the same time
impl Dispose<Resource> =
  let dispose (Resource (name, log)) = Mutex.update log (fun names -> name :: names) |> ignore

// a task that holds a resource while it waits (longer than the test runs)
let holder (name: string) (log: Mutex<list<string>>) (started: Atomic<int>) =
  task {
    use r = Resource (name, log)
    Atomic.add started 1 |> ignore
    do! Task.sleep 60000
    return 1
  }

// done once n tasks have started
let rec until (started: Atomic<int>) (n: int) : Task<int> =
  task {
    if Atomic.get started < n then
      do! Task.sleep 1
      return! until started n
    else
      return 0
  }

let main () =
  let log = Mutex.make []
  let started = Atomic.make 0

  // the race cancels the task waiting for two spawned ones once both have started: both are
  // cancelled on their loops
  let waiting =
    task {
      let! (a, b) =
        Task.both (Task.spawn (fun () -> holder "first" log started)) (Task.spawn (fun () ->
            holder "second" log started))
      return a + b
    }

  let r = Task.run (Task.race waiting (until started 2))
  println $"the race: {r}"
  println $"disposed on their threads: {List.sort (Mutex.get log)}"

  // one that finishes in time
  let quick = Task.run (Task.timeout 5000 (Task.spawn (fun () -> task { return 42 })))
  println $"finished in time: {quick}"
  0
