// Binary trees (the Benchmarks Game): allocating and walking many small trees.
type Tree =
  | Leaf
  | Node of Tree * Tree

let rec make depth = if depth = 0 then Node (Leaf, Leaf) else Node (make (depth - 1), make (depth - 1))

let rec check t =
  match t with
  | Leaf -> 0
  | Node (l, r) -> 1 + check l + check r

let main () =
  let n =
    match Environment.args () with
    | a :: _ -> Option.defaultValue 16 (String.parseInt a)
    | [] -> 16
  let maxDepth = max 6 n
  let stretch = maxDepth + 1
  println $"stretch tree of depth {stretch}\t check: {check (make stretch)}"
  let longLived = make maxDepth
  let mutable d = 4
  while d <= maxDepth do
    let iterations = 1 <<< (maxDepth - d + 4)
    let mutable total = 0
    for _ in 1 .. iterations do
      total <- total + check (make d)
    println $"{iterations}\t trees of depth {d}\t check: {total}"
    d <- d + 2
  println $"long lived tree of depth {maxDepth}\t check: {check longLived}"
  0
