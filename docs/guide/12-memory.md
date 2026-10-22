# 12. Memory

**No garbage collector:** Z# frees each object when the last reference to it goes, with reference counting that the compiler inserts and optimizes. Nothing pauses, and memory comes back as soon as it's unused. Most programs need nothing more; this chapter is about the two cases that do.

## Cycles and weak references

**Cycles:** data can only point to data made before it, so ordinary values never form a cycle. A cycle needs a mutable cell: a `ref` that holds a value pointing back to the cell. Reference counting never frees a cycle. It stays safe, but it leaks, and `ZS_LEAKCHECK=1` reports the objects left at exit.

**Weak references:** a `weak<T>` refers to an object without keeping it alive, so a back-pointer (a child's parent, a list of observers) made weak isn't part of a cycle.
- **Making one:** `Weak.create x`, for an object: a union's cell, a `ref`, an array, a string, a closure or a `dyn` value.
- **Using one:** `Weak.get w` is `Some x` while the object lives, and `None` once it has gone.

```zsharp
type Node = Node of name: string * parent: ref<option<weak<Node>>> * children: ref<list<Node>>

let node (name: string) = Node (name, ref None, ref [])

let adopt (parent: Node) (child: Node) =
  let (Node (_, p, _)) = child
  let (Node (_, _, kids)) = parent
  p.Value <- Some (Weak.create parent)
  kids.Value <- child :: kids.Value

let parentName (Node (_, p, _)) =
  match p.Value |> Option.bind Weak.get with
  | Some (Node (n, _, _)) -> n
  | None -> "gone"

let childCount (Node (_, _, kids)) = List.length kids.Value

// only the child is kept: its parent goes when the function returns
let orphan () =
  let child = node "child"
  adopt (node "root") child
  child

let main () =
  let child = node "child"
  let root = node "root"
  adopt root child
  println $"parent: {parentName child}"
  println $"an orphan's parent: {parentName (orphan ())}"
  println $"the root has {childCount root} child" // root lives until here, its last use
  0
```

```text
parent: root
an orphan's parent: gone
the root has 1 child
```

**Lifetimes:** an object lives until its last use, not to the end of its scope. Without the last line, `root` would go right after `adopt`, and the child's parent would already be gone.

## Arenas

**Bulk allocation:** `Arena.with (fun () -> …)` runs the function with an arena. What it allocates comes from the arena's large blocks, bumped through, and the blocks are freed at once, back to the system. (Without an arena, small objects come from the runtime's pool, which keeps the memory of those that die for the next ones.)
- **When:** for many short-lived objects built together, such as a tree that is built, used and dropped.
- **Safe:** an object made in the arena that lives on (returned, or stored in a `ref`) keeps the arena's blocks until it goes too, so nothing outlives its memory.

```zsharp
type Tree =
  | Leaf
  | Node of Tree * Tree

let rec make d = if d = 0 then Leaf else Node (make (d - 1), make (d - 1))

let rec count t =
  match t with
  | Leaf -> 0
  | Node (l, r) -> 1 + count l + count r

let main () =
  let before = Runtime.mallocs ()
  let nodes = Arena.with (fun () -> count (make 10))
  let mallocs = Runtime.mallocs () - before
  println $"{nodes} nodes from {mallocs} malloc call(s)"
  0
```

```text
1023 nodes from 1 malloc call(s)
```

## Which reference, which function

Five kinds of reference and four kinds of function, each for one situation. The compiler's
errors name the one to use; this table is the same answer in one place.

| You want | Write | Because |
|---|---|---|
| a value that changes, on this thread | `let mutable x`, or `ref` when a closure or a record holds it | arrays and records are values; a `ref` is the one cell several names share |
| an array several names write, or a scratch buffer handed to C | `Buffer<'a>` | arrays copy on write; a `Buffer` is shared mutable memory, so it stays on its thread |
| a window into an array, a string or a `Buffer`, without a copy | `span<'a>`, or a slice `a.[i..j]` | it holds a reference to its owner, so it can't dangle; read-only unless over a `Buffer` |
| a back-pointer that mustn't keep its target alive | `weak<'a>` | a cycle of `ref`s leaks; a `weak` is a pointer the count doesn't see |
| memory C owns | `ptr<'a>`, inside `unsafe` | nothing checks its lifetime, so the block says so |
| a function | `'a -> 'b` | a closure; what it captures is its own business |
| a function another thread may run | `share<'a -> 'b>` | what it captures must be Share, checked where the function is made |
| a function C calls back, with Z# state | `callback<'a -> 'b>` | a C function pointer plus `void *` user data; borrowed for the call |
| a C function pointer, with no state | `fnptr<'a -> 'b>`, called inside `unsafe` | C's convention, nothing checked |

What crosses threads is Share (immutable data, or `Atomic`, `Mutex` and `Channel`), so `ref`,
`Buffer`, `weak`, `ptr` and plain functions stay on their thread, and `share<F>` is how a
function crosses.
