// Allocation hints (0011, 0026): what each line does to the heap, from the passes after checking
type Tree =
  | Leaf
  | Node of Tree * int * Tree

let rec insert (x: int) (t: Tree) : Tree =
  match t with
  | Leaf -> Node(Leaf, x, Leaf)
  | Node(l, y, r) ->
    if x < y then Node(insert x l, y, r)
    else if x > y then Node(l, y, insert x r)
    else t

let report (items: list<string * int>) : string =
  let mutable out = ""
  for (name, qty) in items do
    out <- out + $"{name}: {qty}\n"
  out

[<NoAlloc>]
let area (w: int) (h: int) : int = w * h

let scaled (k: int) (xs: list<int>) : list<int> = List.map (fun x -> x * k) xs

let bump (a: array<int>) : array<int> =
  let mutable b = a
  b.[0] <- b.[0] + 1
  b

let pair (x: 'a) : list<'a> = [ x; x ]

let main () =
  let t = List.fold (fun t x -> insert x t) Leaf [ 3; 1; 2 ]
  println (report [ ("a", 1); ("b", 2) ])
  println $"{area 2 3} {List.length (scaled 2 [ 1; 2 ])} {(bump [| 1 |]).[0]}"
  println $"{List.length (pair 1)} {List.length (pair "s")} {t = Leaf}"
