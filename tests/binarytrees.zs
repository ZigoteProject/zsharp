// Phase 2 exit test: binary-trees from the Computer Language Benchmarks Game
type Tree =
  | Leaf
  | Node of Tree * Tree

let rec make d = if d = 0 then Node (Leaf, Leaf) else Node (make (d - 1), make (d - 1))

let rec check t =
  match t with
  | Leaf -> 0
  | Node (l, r) -> 1 + check l + check r

let rec pow2 k = if k = 0 then 1 else 2 * pow2 (k - 1)

let main () =
  let minDepth = 4
  let maxDepth = max (minDepth + 2) 16
  let stretch = maxDepth + 1
  println $"stretch tree of depth {stretch}\t check: {check (make stretch)}"
  let longLived = make maxDepth
  for d in minDepth .. 2 .. maxDepth do
    let iterations = pow2 (maxDepth - d + minDepth)
    let mutable sum = 0
    for _ in 1 .. iterations do
      sum <- sum + check (make d)
    println $"{iterations}\t trees of depth {d}\t check: {sum}"
  println $"long lived tree of depth {maxDepth}\t check: {check longLived}"
  0
