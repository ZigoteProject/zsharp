// a module for main.zs: a nested (non-regular) type, which holds itself at other arguments
type Tree<'a> =
  | Leaf of 'a
  | Node of Tree<'a * 'a>
