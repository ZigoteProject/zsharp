// a let's pattern must match every value, at the top level as inside a function
let (Some x) = Some 1

let first (xs: list<int>) =
  let y :: _ = xs
  y

let main () =
  println x
  0
