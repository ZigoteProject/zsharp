// A function parameter crosses threads only as a share<…>: a plain function may capture what
// can't be shared.
let runTwice (f: unit -> int) = Parallel.both (fun () -> f ()) (fun () -> f ())

let main () =
  let (a, b) = runTwice (fun () -> 1)
  println $"{a} {b}"
