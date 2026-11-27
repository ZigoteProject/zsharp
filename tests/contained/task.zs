// Contained.task (0035): a task, and the tasks it waits for on its loop, as one contained job.
// A panic in any resume ends the job, and what waited for it gets Error; the other tasks on the
// loop go on. Cancelling it disposes what its tasks bound with `use`.
type Resource = Resource of string * Mutex<list<string>>

impl Dispose<Resource> =
  let dispose (Resource (name, log)) = Mutex.update log (fun names -> name :: names) |> ignore

// answers after two waits, or panics between them
let fetch (n: int) : Task<int> =
  task {
    do! Task.sleep 1
    if n = 3 then panic $"request {n}"
    let squares = List.map (fun x -> x * x) [ 1 .. n ]
    do! Task.sleep 1
    return List.sum squares
  }

// holds a resource while it waits (longer than the test runs)
let holder (name: string) (log: Mutex<list<string>>) : Task<int> =
  task {
    use r = Resource (name, log)
    do! Task.sleep 60000
    return 1
  }

// a job's task that waits for several: the panic of one ends them all
let several (ns: list<int>) : Task<list<int>> = Task.all (List.map fetch ns)

let main () =
  let first =
    Task.run (
      task {
        // a result, after waits
        let! a = Contained.task (fun () -> fetch 4)
        // a panic in a later resume
        let! b = Contained.task (fun () -> fetch 3)
        // a panic before the first wait
        let! c =
          Contained.task (fun () -> task { return (if a = Ok 30 then panic "at once" else 0) })
        // a result that's there at once
        let! d = Contained.task (fun () -> Task.ret "ready")
        return (a, b, c, d)
      })
  println $"{first}"

  // many at once on one loop, each a job: the third of every five fails, the others don't notice
  let many = Task.run (Task.all (List.init 20 (fun i -> Contained.task (fun () -> fetch (i % 5)))))
  let failed = List.length (List.filter Result.isError many)
  println $"{failed} of {List.length many} failed; the first five: {List.take 5 many}"

  // a job's task waiting for several: one's panic is the job's, and the tasks left go with it
  println $"{Task.run (Contained.task (fun () -> several [ 1; 2 ]))} {Task.run (Contained.task (fun () -> several [ 2; 3; 4 ]))}"

  // cancelled (the timeout's race): its task is cancelled in the job, which disposes its `use`
  let log = Mutex.make []
  let slow = Task.run (Task.timeout 20 (Contained.task (fun () -> holder "held in a job" log)))
  println $"{slow} {Mutex.get log}"

  // a job's task in a job's task: the inner panic is the outer one's Error value
  let nested =
    Task.run (
      Contained.task (fun () ->
        task {
          let! inner = Contained.task (fun () -> fetch 3)
          let! fine = Contained.task (fun () -> fetch 2)
          return (inner, fine)
        }))
  println $"{nested}"

  // a panic in the outer job while an inner one waits: both go
  let both =
    Task.run (
      Contained.task (fun () ->
        task {
          let! (x, y) = Task.both (Contained.task (fun () -> holder "inner" log)) (fetch 3)
          return (x, y)
        }))
  println $"{both}"

  // Contained.run inside a task, and a task run inside Contained.run
  let mixed = Task.run (task { return Contained.run (fun () -> Task.run (fetch 3)) })
  println $"{mixed} {Contained.run (fun () -> Task.run (fetch 3))} {Contained.run (fun () -> Task.run (fetch 2))}"
