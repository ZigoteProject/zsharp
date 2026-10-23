// ZS_STATS=1 (0020, decision 75): a unique array of trees mapped through Array.Parallel.map. Each
// tree moves to the thread that sums it, nothing else holding it, so no object is marked shared.
type Tree =
  | Leaf
  | Node of Tree * int * Tree

let rec build (depth: int) (x: int) : Tree =
  if depth = 0 then Leaf else Node(build (depth - 1) (2 * x), x, build (depth - 1) (2 * x + 1))

let rec sum (t: Tree) : int =
  match t with
  | Leaf -> 0
  | Node(l, v, r) -> sum l + v + sum r

let main () =
  let trees = Array.init 64 (fun i -> build 8 i)
  let sums = Array.Parallel.map sum trees
  println $"{Array.fold (fun a b -> a + b) 0 sums}"
  0
