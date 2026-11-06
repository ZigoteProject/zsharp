// A nested type (Perfect.Tree<'a> holds a Tree<'a * 'a>) is met at ever larger arguments: the
// cycle check and the Share check follow it once, then only its arguments, so both end. Holder
// reaches no cell; Loop reaches itself through a ref in the tree and through a field of its own.
type Holder = { t: Perfect.Tree<int> }

type Loop = Loop of back: Perfect.Tree<ref<option<Loop>>> * forth: ref<option<Loop>>

let main () =
  // Share, as its arguments are
  Mutex.make (Perfect.Node (Perfect.Leaf (1, 2))) |> ignore
  0
