// C: return; in Z# a function's last expression is its result (return belongs in task { } and result { })
let sign (x: int) =
  if x < 0 then return -1
  1

let main () = sign 3
