// arenas on a chip (track M item 8): binary trees built inside Arena.with, their nodes from the
// arena's blocks (an eighth of the heap each) and gone with it at once; a tree that outlives its
// arena keeps the blocks until it goes; the objects counted are the nodes (a Leaf is static) and
// each round's closure, and the exit report's live=0 says every block went back
type Tree =
  | Leaf
  | Node of Tree * Tree

let rec make d = if d = 0 then Node(Leaf, Leaf) else Node(make (d - 1), make (d - 1))

let rec check t =
  match t with
  | Leaf -> 0
  | Node(l, r) -> 1 + check l + check r

let main () =
  for d in 2 .. 2 .. 6 do
    let objects0 = Runtime.allocations ()
    let mutable sum = 0
    for _ in 1 .. 4 do
      sum <- sum + Arena.with (fun () -> check (make d))
    println $"4 trees of depth {d}: check {sum}, objects {Runtime.allocations () - objects0}"
  let kept = Arena.with (fun () -> make 4)
  let inner = Arena.with (fun () -> check (Node(kept, make 2)))
  println $"kept: {check kept}, inside another arena: {inner}"
  0
