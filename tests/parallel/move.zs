// The moving crossing (decision 75): a unique array of trees mapped in parallel moves each part
// into its job, so no object is marked shared; an array the caller keeps using is shared.
type Tree =
  | Leaf
  | Node of Tree * int * Tree

let rec make (d: int) = if d = 0 then Leaf else Node (make (d - 1), d, make (d - 1))

let rec sum (t: Tree) =
  match t with
  | Leaf -> 0
  | Node (l, x, r) -> sum l + x + sum r

let main () =
  let trees = Array.init 64 (fun _ -> make 6)
  let before = Runtime.marks ()
  let sums = Array.Parallel.map sum trees
  let moved = Runtime.marks () - before
  let kept = Array.init 64 (fun _ -> make 6)
  let again = Array.Parallel.map sum kept
  let shared = Runtime.marks () - before - moved
  println $"{Array.fold (fun a b -> a + b) 0 sums} {Array.fold (fun a b -> a + b) 0 again} {moved} {shared > 0} {Array.length kept}"
  0
