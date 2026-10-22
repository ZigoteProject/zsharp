// A Buffer is shared mutable memory, so it can't cross to another thread; split the work into results
let main () =
  let b = Buffer.create 10 0
  Parallel.for 0 10 (fun i -> b.[i] <- i)
  b.[9]
