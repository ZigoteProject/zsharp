// A type without an Iter impl, given to a function over Iter.
type Point = { x: int; y: int }

let main () =
  println $"{Iter.length { x = 1; y = 2 }}"
  0
