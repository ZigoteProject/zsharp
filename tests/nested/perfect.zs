// a module for main.zs: a nested (non-regular) type, which holds itself at other arguments, and
// one that holds itself at its arguments swapped, so the ref is at the other one the second time
type Tree<'a> =
  | Leaf of 'a
  | Node of Tree<'a * 'a>

type Swap<'a, 'b> = Swap of first: 'a * second: ref<'b> * next: option<Swap<'b, 'a>>
