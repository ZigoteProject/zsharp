// What contained jobs cost a program's shared objects (proposal 0035): in a program that has
// a contained job anywhere, a shared object's count changes through the runtime, which tests
// whether the thread is in a job. Every worker of the pool copies a shared list of strings
// (a count taken for each string) and drops the copy (a count given up for each).
// bench/contained/run.sh builds it twice, as it is and with CONTAINED's line in, and compares.
let table (n: int) : list<string> = List.init n (fun i -> $"entry {i}")

// a copy of the list's cells, sharing its strings, made and dropped: 2 n counts
let turn (xs: list<string>) : int = List.length (List.map (fun s -> s) xs)

let main () =
  let rounds =
    match Environment.args () with
    | s :: _ -> Option.defaultValue 200 (String.parseInt s)
    | _ -> 200
  // what a mutex holds is shared, whoever reads it
  let shared = Mutex.get (Mutex.make (table 10000))
  //CONTAINED Contained.run (fun () -> 0) |> ignore
  // one thread: the counts are atomic, and nothing else waits for them
  let start = Runtime.ticks ()
  let mutable alone = 0
  for _ in 1 .. rounds do
    alone <- alone + turn shared
  let ns = float (Runtime.ticks () - start) / float (alone * 2)
  println $"{alone * 2} counts of shared objects on one thread: {ns:F1} ns each"
  // every thread of the pool at once, on the same strings
  let start = Runtime.ticks ()
  let done = Array.Parallel.init (Parallel.workers ()) (fun _ ->
    let mutable n = 0
    for _ in 1 .. rounds do
      n <- n + turn shared
    n)
  let counts = Array.sum done * 2
  let ns = float (Runtime.ticks () - start) * float (Parallel.workers ()) / float counts
  println $"{counts} counts on {Parallel.workers ()} threads at once: {ns:F1} ns each, a thread"
  0
