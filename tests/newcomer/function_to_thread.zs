// A plain function parameter can't cross threads: it may capture what isn't Share
let twice (f: unit -> int) = Parallel.both (fun () -> f ()) (fun () -> f ())

let main () =
  let (a, b) = twice (fun () -> 21)
  a + b
