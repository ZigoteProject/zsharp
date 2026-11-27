// contained jobs and the thread pool (0035): a job forks work onto the pool, and jobs run on the
// pool's threads. Forked work isn't in the job: its closure is copied out, and its result
// arrives. A job that fails with a fork not joined waits for it, and gives its result up.
open Threading

let rec fib (n: int) : int = if n < 2 then n else fib (n - 1) + fib (n - 2)

let main () =
  // a job that forks: the halves' results arrive in it
  let both =
    Contained.run (fun () ->
      Parallel.both (fun () -> List.init 5 fib) (fun () -> $"fib 20 is {fib 20}"))
  println $"{both}"
  // a parallel map in a job, over what the job made
  let mapped =
    Contained.run (fun () ->
      let words = Array.init 64 (fun i -> $"w{i}")
      let lengths = Array.Parallel.map String.length words
      Array.sum lengths)
  println $"{mapped}"
  // jobs on the pool's threads, some failing
  let results =
    Array.Parallel.init 64 (fun i ->
      Contained.run (fun () -> if i % 8 = 5 then panic "on the pool" else fib (i % 20)))
  let ok = Array.sumBy (fun r -> Result.defaultValue 0 r) results
  let failed = Array.length (Array.filter Result.isError results)
  println $"{failed} failed, the others gave {ok}"
  // a job that fails while what it forked is still to join
  let lost =
    Contained.run (fun () ->
      let left = [ 1; 2; 3 ]
      let (a, b) =
        Parallel.both (fun () -> if List.length left = 3 then panic "before the join" else 0) (fun () ->
          List.init 1000 (fun i -> $"{i}"))
      a + List.length b)
  println $"{lost}"
  // and the pool goes on
  println $"{Parallel.reduce 0 100 0 (fun i -> i) (fun a b -> a + b)}"
