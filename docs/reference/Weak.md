# Weak

Weak references: a `weak<T>` refers to an object (a union's cell, a `ref`, an array, a
string, a closure or a `dyn` value) without keeping it alive. Back-pointers, such as a tree
node's parent, are weak, so the links between parents and children aren't cycles that keep
the tree alive. Its functions are built into the compiler.

## Functions

### `Weak.create`

```zsharp
Weak.create : 'a -> weak<'a>
```

A weak reference to the object: it doesn't keep the object alive.

### `Weak.get`

```zsharp
Weak.get : weak<'a> -> option<'a>
```

`Some` object while it lives (with a reference of its own), `None` once it has gone.

