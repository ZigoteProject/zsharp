// weak references: the nodes of a tree know their parent through a weak reference, so the links
// between parents and children aren't cycles that keep the tree alive. When the root goes,
// every node goes (test.sh runs this with ZS_LEAKCHECK, and under valgrind with --valgrind).
type Node = Node of name: string * parent: ref<option<weak<Node>>> * children: ref<list<Node>>

let node (name: string) = Node (name, ref None, ref [])

let name (Node (n, _, _)) = n

let parentOf (Node (_, p, _)) =
  match p.Value with
  | Some w -> Weak.get w
  | None -> None

let adopt (parent: Node) (child: Node) =
  let (Node (_, p, _)) = child
  let (Node (_, _, kids)) = parent
  p.Value <- Some (Weak.create parent)
  kids.Value <- child :: kids.Value

// root -> a -> c, root -> b
let build () =
  let root = node "root"
  let a = node "a"
  adopt root a
  adopt root (node "b")
  let c = node "c"
  adopt a c
  c

let show (n: option<Node>) = n |> Option.map name |> Option.defaultValue "gone"

let childCount (Node (_, _, kids)) = List.length kids.Value

let main () =
  let root = node "root"
  let kid = node "kid"
  adopt root kid
  println $"kid's parent: {show (parentOf kid)}"
  // only c is kept: the nodes above it go, though c's parent link still names one
  let c = build ()
  println $"c's parent, once the rest of its tree has gone: {show (parentOf c)}"
  // a list's first cell, weakly referenced, then reused in place by List.map: the reference
  // sees its object die, not the new list
  let xs = [ 1; 2; 3 ]
  let w = Weak.create xs
  println $"alive: {(Weak.get w).IsSome}"
  let ys = List.map (fun x -> x * 10) xs
  println $"after its cells were reused: {(Weak.get w).IsSome} {ys}"
  // a static object (a list's end) never dies
  let empty: list<int> = []
  println $"static: {(Weak.get (Weak.create empty)).IsSome}"
  println $"{name root} still has {childCount root} child"
  0
