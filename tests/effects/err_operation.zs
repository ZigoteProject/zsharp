let main () =
  handle Yield.yield 1 with
  | Yield.yeild x, k -> k ()
  0
