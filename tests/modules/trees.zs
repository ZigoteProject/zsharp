// a module for parts.zs: what's built here is matched in the main file, and the other way
type Tree =
  | Leaf
  | Node of Tree * int * Tree

let rec insert x t =
  match t with
  | Leaf -> Node (Leaf, x, Leaf)
  | Node (l, v, r) -> if x < v then Node (insert x l, v, r) else Node (l, v, insert x r)

let rec size t =
  match t with
  | Leaf -> 0
  | Node (l, _, r) -> size l + 1 + size r

let isLeaf t =
  match t with
  | Leaf -> true
  | Node _ -> false

let lookup (k: string) = if k = "a" then Some "first" else None

// computed at startup: one value, whichever module reads it
let names = List.map (fun (s: string) -> s + "!") [ "x"; "y" ]

let firstName () = List.head names
