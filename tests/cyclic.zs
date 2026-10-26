// types the cycle warning leaves alone (0021): one field back (a list, a tree whose parent is
// weak), recursion without a cell, a cycle the program breaks ([<Cyclic>]) and one the analysis
// can't tell from a tree ([<NoWarn "cycle">])
type Link = Link of value: int * next: ref<option<Link>>

type Tree = Tree of name: string * children: ref<list<Tree>> * parent: ref<option<weak<Tree>>>

type Expr =
  | Num of int
  | Add of Expr * Expr

// a ring whose links are cut before it's dropped
[<Cyclic>]
type Ring = Ring of value: int * next: ref<option<Ring>> * prev: ref<option<Ring>>

[<NoWarn "cycle">]
type Bin = Bin of left: ref<option<Bin>> * right: ref<option<Bin>>

let links (r: Ring) : ref<option<Ring>> * ref<option<Ring>> =
  match r with
  | Ring(_, next, prev) -> (next, prev)

let value (r: Ring) : int =
  match r with
  | Ring(v, _, _) -> v

let main () =
  let a = Ring(1, ref None, ref None)
  let b = Ring(2, ref None, ref None)
  // a ring of two, each the other's next and prev
  for (r, other) in [ (a, b); (b, a) ] do
    let (next, prev) = links r
    next.Value <- Some other
    prev.Value <- Some other
  let (fromA, _) = links a
  match fromA.Value with
  | Some n -> println $"after 1 comes {value n}"
  | None -> ()
  // cut, so counting frees both
  for r in [ a; b ] do
    let (next, prev) = links r
    next.Value <- None
    prev.Value <- None
  println "cut"
  0
