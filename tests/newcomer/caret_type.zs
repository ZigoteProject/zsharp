// F#: a statically resolved ^a; Z# infers a function's constraints from the traits it uses
let inline add (x: ^a) (y: ^a) = x + y

let main () =
  0
