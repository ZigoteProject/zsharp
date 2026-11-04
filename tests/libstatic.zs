// a library's constants are static objects (tests/libstatic.sh links it into C): a table, a tree of
// union cases and a record need no startup, which a library doesn't have
type Tree =
  | Leaf
  | Node of Tree * int * Tree

type Range = { lo: int; hi: int }

let rec sum (t: Tree) : int =
  match t with
  | Leaf -> 0
  | Node(l, v, r) -> sum l + v + sum r

let tree = Node(Node(Leaf, 1, Leaf), 2, Leaf)
let table = [| 10; 20; 30 |]
let range = { lo = 1; hi = 4 }
// folded to a table, under -g and --coverage too (an initializer is folded as in an optimized build)
let folded = [| 1 + 2; 3 * 4 |]

[<Export>]
let total (n: int) : int = sum tree + Array.sum table + range.hi - range.lo + Array.sum folded + n
