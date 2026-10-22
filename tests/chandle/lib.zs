// Z# objects held by C as opaque handles (tests/chandle/main.c): a tree C builds up through the
// library, and a closure C keeps and calls later. C gives up each handle with zs_release.
type Tree =
  | Leaf
  | Node of Tree * int * Tree

let rec private insert x t =
  match t with
  | Leaf -> Node (Leaf, x, Leaf)
  | Node (l, v, r) -> if x < v then Node (insert x l, v, r) else Node (l, v, insert x r)

let rec private count t =
  match t with
  | Leaf -> 0
  | Node (l, _, r) -> count l + 1 + count r

let rec private total t =
  match t with
  | Leaf -> 0
  | Node (l, v, r) -> total l + v + total r

[<Export "tree_empty">]
let empty () : Tree = Leaf

[<Export "tree_insert">]
let add (t: Tree) (x: int) : Tree = insert x t

[<Export "tree_count">]
let size (t: Tree) : int = count t

[<Export "tree_sum">]
let sum (t: Tree) : int = total t

// a closure that captures a tree: C keeps it and calls it through tree_apply
[<Export "tree_adder">]
let adder (t: Tree) : int -> int = fun x -> x + total t

[<Export "tree_apply">]
let apply (f: int -> int) (x: int) : int = f x
