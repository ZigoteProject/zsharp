let main () =
  let s = [| 1; 2 |].[0..]
  s.[0] <- 3
  0
