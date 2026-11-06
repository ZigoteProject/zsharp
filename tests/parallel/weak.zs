// Weak references in a program with threads. A weak reference to a Share value marks the value
// shared with all it holds when it's made, so a crossing that moves the value (decision 75)
// leaves it shared: the thread with the weak reference takes a reference again atomically, and
// only while the value lives (unmarked, 0 objects, the moved list was the other thread's, which
// Weak.get here counted non-atomically while that thread freed it). And each thread's weak
// references to one object have a cell of their own, which only that thread counts (both jobs'
// shared one lost counts, and was freed under the other). test.sh runs this under
// ThreadSanitizer too.
let main () =
  let xs = List.init 3 (fun i -> i + 1)
  let before = Runtime.marks ()
  let w = Weak.create xs
  println $"{Runtime.marks () - before} {(Weak.get w).IsSome}"
  // xs's last use: the job takes it to another thread, which drops it there
  let (none, sum) = Parallel.both (fun () -> 0) (fun () -> List.sum xs)
  let length =
    match Weak.get w with
    | Some l -> List.length l
    | None -> 3
  println $"{none} {sum} {length}"
  // a list both jobs hold, weakly referenced on both threads at once
  let names = List.init 4 (fun i -> i)
  let weakly () =
    let mutable seen = 0
    for _ in 1 .. 10000 do
      let r = Weak.create names
      match Weak.get r with
      | Some l -> seen <- seen + List.length l
      | None -> ()
    seen
  let (p, q) = Parallel.both weakly weakly
  println $"{p} {q}"
  0
