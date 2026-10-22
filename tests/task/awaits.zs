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

let main () =
  let (small, a) = allocationsFor 5
  let (large, b) = allocationsFor 100000
  println $"{small} and {large}: {a} and {b} allocations for 10 and 200,000 waits"
