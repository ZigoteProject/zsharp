// Task.spawn: tasks on other threads' event loops, their results coming back; Task.blocking's
// function crossing to the helper thread.

let rec fib (n: int) : int = if n < 2 then n else fib (n - 1) + fib (n - 2)

// a task that waits, then computes
let work (n: int) : Task<int> =
  task {
    do! Task.sleep 5
    return fib n
  }

let main () =
  let total =
    Task.run (
      task {
        let! a = Task.spawn (fun () -> work 20)
        let! b = Task.spawn (fun () -> work 21)
        let! xs = Task.all (List.init 8 (fun i -> Task.spawn (fun () -> work (10 + i))))
        let label = "fib"
        let! s = Task.spawn (fun () -> task { return $"{label} {fib 15}" })
        let! c = Task.blocking (fun () -> fib 22)
        println s
        return a + b + c + List.sum xs
      })
  println $"total: {total}"
