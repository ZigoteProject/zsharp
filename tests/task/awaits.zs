// Phase 9's exit test: a task's waits allocate nothing. task { } is a state machine (an LLVM
// coroutine) allocated once when the task starts; a wait for a ready result (Task.ret) goes on
// at once, and a wait that suspends (Task.yield: a turn of the event loop) passes the state
// machine itself as what to resume. So the same task allocates as much for 10 waits as for
// 200,000.
let work (n: int) : Task<int> =
  task {
    let mutable total = 0
    for i in 1 .. n do
      let! x = Task.ret i
      do! Task.yield ()
      total <- total + x
    return total
  }

let allocationsFor (n: int) =
  let before = Runtime.allocations ()
  let total = Task.run (work n)
  (total, Runtime.allocations () - before)

// return! at the end of a task gives its task what waits for this one, so a task looping by
// return! keeps no state machine per round. A round's holds 8 KB (pad, kept across the wait):
// one per round would be 160 MB for 20,000 rounds (valgrind holds back 20 MB of freed memory)
let rec countdown (n: int) : Task<int> =
  task {
    let mutable pad: fixed<int, 1024> = Fixed.create 0
    pad.[n % 1024] <- n
    do! Task.yield ()
    if n = 0 then return pad.[Runtime.allocations () % 1024] else return! countdown (n - 1)
  }

// the process's peak memory in KB: Linux's VmHWM
let peakKB () =
  match File.readAllText "/proc/self/status" with
  | Ok s ->
    String.split "\n" s
    |> List.tryFind (String.startsWith "VmHWM:")
    |> Option.bind (fun l -> String.parseInt (String.trim (String.replace (String.replace l "VmHWM:" "") "kB" "")))
    |> Option.defaultValue 0
  | Error _ -> 0

let growthKB (n: int) =
  let before = peakKB ()
  Task.run (countdown n) |> ignore
  peakKB () - before

// in a use's scope, return! waits: the resource is closed after the task it waits for
type Resource = Resource of string

impl Dispose<Resource> =
  let dispose (Resource name) = println $"{name} closed"

let inner () =
  task {
    do! Task.yield ()
    println "inner done"
    return 1
  }

let outer () =
  task {
    use r = Resource "r"
    return! inner ()
  }

let main () =
  let (small, a) = allocationsFor 5
  let (large, b) = allocationsFor 100000
  println $"{small} and {large}: {a} and {b} allocations for 10 and 200,000 waits"
  println $"return!: 20,000 rounds in steady memory: {growthKB 20000 < 64000}"
  println $"{Task.run (outer ())}"
