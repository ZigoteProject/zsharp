// a match on strings needs a case for the rest
let name n =
  match n with
  | "a" -> 1
  | "b" -> 2

let main () = name "a"
