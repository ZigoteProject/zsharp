let main () =
  Parallel.for 0 9 (fun i -> Throw.throw "no")
  0
