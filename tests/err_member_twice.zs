// a member declared twice, and one named as a field, are each reported and left out; the type's
// other members stand, so the calls after them still check (the compiler crashed on them)
type Stack<'a> =
  { items: list<'a> }
  member s.Push(x) = { items = x :: s.items }
  member s.Push(x) = { items = x :: x :: s.items }
  member s.items = []
  member s.Peek = List.head s.items

type P = { x: int }
  static member Make(n) = { x = n }
  static member Make(n) = { x = n + 1 }

let main () =
  let s = { items = [ 1 ] }
  println $"{s.Push(2).Peek} {(P.Make(3)).x}"
  0
