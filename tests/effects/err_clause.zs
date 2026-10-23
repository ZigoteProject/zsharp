let main () =
  let r =
    handle Yield.yield 1 with
    | Yield.yield x, k -> "one"
    | return () -> 0
  0
