// The Iter trait (0017): its impls and the functions over it, on the library's collections, a
// Range, a type of the program's own, and a generic function that needs Iter<int>.
type Tree<'a> =
  | Leaf
  | Node of Tree<'a> * 'a * Tree<'a>

impl Iter<Tree<'a>, 'a> =
  let forEach t f =
    match t with
    | Leaf -> true
    | Node (l, x, r) -> forEach l f && f x && forEach r f

let total (xs: 'c) = Iter.fold (fun acc x -> acc + x) 0 xs

let main () =
  let xs = [ 3; 1; 4; 1; 5 ]
  let t = Node (Node (Leaf, 1, Leaf), 2, Node (Leaf, 3, Leaf))
  let up: Iter.Range = { start = 1; stop = 10; step = 3 }
  let down: Iter.Range = { start = 10; stop = 0; step = -5 }
  println $"{total xs} {total [| 10; 20 |]} {total t} {total (Some 7)} {total up}"
  println $"{Iter.exists (fun x -> x > 4) xs} {Iter.forall (fun x -> x > 0) xs} {Iter.tryFind (fun x -> x > 3) xs}"
  println $"{Iter.length "héllo"} {Iter.toList "abc"} {Iter.toList t} {Iter.length (None: option<int>)}"
  let b = Buffer.ofArray [| 1; 2; 3 |]
  println $"{total b} {total b.[1..2]} {Iter.toList down}"
  Iter.iter (fun x -> print $"{x} ") t
  println ""
  0
