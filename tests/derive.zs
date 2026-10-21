// Phase 3: structural equality, ordering, hashing and printing from prelude derives
type Point = { x: int; y: int }

type Shape =
  | Circle of radius: f64
  | Rect of Point * Point
  | Empty

type Tree<'a> =
  | Leaf
  | Node of Tree<'a> * 'a * Tree<'a>

[<NoEquality>]
type Handle = { id: int }

let rec insert x t =
  match t with
  | Leaf -> Node (Leaf, x, Leaf)
  | Node (l, v, r) -> if x < v then Node (insert x l, v, r) else Node (l, v, insert x r)

let main () =
  let p = { x = 1; y = 2 }
  println $"{p} {p = { x = 1; y = 2 }} {p = { x = 2; y = 2 }} {compare p { x = 1; y = 3 }}"
  let a = Rect ({ x = 0; y = 0 }, p)
  println $"{a} | {Circle 1.5} | {Empty}"
  println $"{a = a} {Circle 1.0 = Empty} {compare Empty (Circle 2.0)} {compare (Circle 1.0) (Circle 2.0)}"
  println $"{hash p = hash { x = 1; y = 2 }} {hash p = hash { x = 2; y = 1 }}"
  let t = insert 2 (insert 1 (insert 3 Leaf))
  println $"{t}"
  println $"{t = insert 2 (insert 1 (insert 3 Leaf))} {[Some 1; None]} {[1; 2] = [1; 2]} {compare [1; 2] [1; 3]}"
  let words = [ "b"; "a" ]
  println $"{Ok 5} {words}"
  for w in words do
    print $"{w} "
  for n in [| 3; 4 |] do
    print $"{n} "
  println ""
  0
