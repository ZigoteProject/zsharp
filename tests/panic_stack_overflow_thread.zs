// A stack overflow on another thread (a task's loop thread, started by the runtime) is the same
// panic: each thread the runtime starts takes the fault on a stack of its own.
let rec deeper (b: Buffer<int>) (n: int) : int =
  Buffer.push n b
  1 + deeper b (n + 1)

let main () =
  println "before"
  let n = Task.run (Task.spawn (fun () -> task { return deeper Buffer.empty 0 }))
  println $"{n}"
  0
