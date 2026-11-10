// The pool started by tasks on the loop threads, not by this one: at exit the loop threads stop
// first, each that forked giving its deque back into the pool's arrays as it ends, and then the
// pool frees those arrays (the other way round, the loop threads wrote into freed memory).

let part (k: int) : int = Parallel.reduce 0 1000 0 (fun i -> i * k) (fun x y -> x + y)

let main () =
  let total =
    Task.run (
      task {
        let! xs = Task.all (List.init 4 (fun k -> Task.spawn (fun () -> task { return part k })))
        return List.sum xs
      })

  println $"total: {total}"
  0
