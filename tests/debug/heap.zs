// Debug info for heap values (tests/debug/gdb_heap.sh drives gdb over it): a list, an array, a
// tree, a tagged union's cell, an option over a string, a ref
type Tree =
  | Leaf
  | Node of Tree * int * Tree

type Token =
  | Word of string * int
  | Number of f64

let main () =
  let xs = [ 1; 2; 3 ]
  let names = [| "ab"; "cd" |]
  let tree = Node(Leaf, 7, Leaf)
  let token = Word("hi", 2)
  let some = Some "yes"
  let cell = ref 5
  println $"{List.length xs} {names.[0]} {tree} {token} {some} {cell.Value}"
  0
