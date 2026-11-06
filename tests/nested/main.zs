// A nested type (Perfect.Tree<'a> holds a Tree<'a * 'a>) is met at ever larger arguments: the
// cycle check and the Share check follow it a set number of times, then only its arguments, so
// both end. Holder reaches no cell; Loop reaches itself through a ref in the tree and through a
// field of its own; Turn through the ref of the Swap it holds, at the Swap's second instantiation.
type Holder = { t: Perfect.Tree<int> }

type Loop = Loop of back: Perfect.Tree<ref<option<Loop>>> * forth: ref<option<Loop>>

type Turn = Turn of turned: Perfect.Swap<option<Turn>, int> * again: option<Turn>

let main () =
  // Share, as its arguments are
  Mutex.make (Perfect.Node (Perfect.Leaf (1, 2))) |> ignore
  0
