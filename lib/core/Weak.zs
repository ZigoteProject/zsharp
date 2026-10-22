/// Weak references: a `weak<T>` refers to an object (a union's cell, a `ref`, an array, a
/// string, a closure or a `dyn` value) without keeping it alive. Back-pointers, such as a tree
/// node's parent, are weak, so the links between parents and children aren't cycles that keep
/// the tree alive. Its functions are built into the compiler.
module Weak
