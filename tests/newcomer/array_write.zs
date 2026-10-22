// Writing to an array bound with let: arrays are values, so the binding must be mutable
let main () =
  let a = [| 1; 2; 3 |]
  a.[0] <- 9
  a.[0]
