// Phase V exit test: binary-trees with an arena per tree. Each tree is built and checked inside
// Arena.with, so its nodes come from the arena's blocks: malloc runs once per block (and once for
// the function given to Arena.with), not once per node, and the blocks go at once with the tree.
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
  let maxDepth = 10

  for d in 4 .. 2 .. maxDepth do
    let iterations = pow2 (maxDepth - d + 4)
    let objects0 = Runtime.allocations ()
    let mallocs0 = Runtime.mallocs ()
    let mutable sum = 0

    for _ in 1 .. iterations do
      sum <- sum + Arena.with (fun () -> check (make d))

    let objects = Runtime.allocations () - objects0
    let mallocs = Runtime.mallocs () - mallocs0
    println $"{iterations}\t trees of depth {d}\t check: {sum}\t objects: {objects}\t mallocs: {mallocs}"

  // the same without an arena: a malloc per node
  let mallocs0 = Runtime.mallocs ()
  let nodes = check (make maxDepth)
  let mallocs = Runtime.mallocs () - mallocs0
  println $"without an arena, one tree of depth {maxDepth}: {nodes} nodes, mallocs: {mallocs}"
  // a tree that outlives its arena keeps the arena's blocks until it goes itself
  let kept = Arena.with (fun () -> make 8)
  let inner = Arena.with (fun () -> check (Node (kept, make 2)))
  println $"kept: {check kept}, inside another arena: {inner}"
  0
