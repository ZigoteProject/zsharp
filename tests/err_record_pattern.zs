type Kind =
  | A
  | B
  | C

type Item = { kind: Kind; n: int }

let score (i: Item) =
  match i with
  | { kind = A } -> 1
  | { kind = B; n = n } -> n

let main () = score { kind = A; n = 1 }
