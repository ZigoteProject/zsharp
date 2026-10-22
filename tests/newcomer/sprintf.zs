// F#: sprintf with a format string; Z# interpolates
let label (n: int) = sprintf "item %d" n

let main () =
  println (label 1)
  0
