// a match whose or-patterns multiply past what can be checked is an error, not minutes of work
// and gigabytes: exhaustiveness with or-patterns is NP-hard, (X | Y) in 24 columns 2^24 paths
type B =
  | X
  | Y

let f t =
  match t with
  | ((X | Y), (X | Y), (X | Y), (X | Y), (X | Y), (X | Y), (X | Y), (X | Y), (X | Y), (X | Y),
    (X | Y), (X | Y), (X | Y), (X | Y), (X | Y), (X | Y), (X | Y), (X | Y), (X | Y), (X | Y),
    (X | Y), (X | Y), (X | Y), (X | Y)) -> 0

let main () = 0
