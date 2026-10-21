# 5. Collections

## Lists

A list, `list<'a>`, is an immutable singly linked list.
- **Literals:** `[ 1; 2; 3 ]`, and `[]` is the empty list.
- **Building:** `x :: xs` puts an element in front, and `xs @ ys` appends.
- **Pattern matching:** lists match with the same forms ([Data](03-data.md#pattern-matching)).
- **Indexing:** `List.item n xs` takes the element at index `n`, in O(n) time. Only arrays have `.[i]`.

```zsharp
let main () =
  let xs = [ 5; 3; 8; 1 ]
  println $"{0 :: xs} {xs @ [ 9 ]} {List.length xs} {List.head xs} {List.item 2 xs}"
  println $"{List.sort xs} {List.rev xs} {List.map (fun x -> x * 2) xs}"
  println $"{List.filter (fun x -> x > 3) xs} {List.fold (fun acc x -> acc + x) 0 xs} {List.max xs}"
  println $"{List.zip [ 1; 2 ] [ "a"; "b" ]} {List.partition (fun x -> x > 4) xs} {List.init 4 (fun i -> i * i)}"
  0
```

```text
[0; 5; 3; 8; 1] [5; 3; 8; 1; 9] 4 5 8
[1; 3; 5; 8] [1; 8; 3; 5] [10; 6; 16; 2]
[5; 8] 17 8
[(1, a); (2, b)] ([5; 8], [3; 1]) [0; 1; 4; 9]
```

**Performance:**
- The list functions are tail-recursive, so long lists don't exhaust the stack.
- When a list has only one owner, functions like `List.rev` reuse its cells instead of allocating new ones.

## Arrays

An array, `array<'a>`, is a fixed-size block of elements, written `[| 1; 2; 3 |]`. Arrays are **values**: assigning one to another name or passing it to a function never lets the two see each other's changes.

**Changing an array:**
- **In place:** declare it `let mutable` and write `a.[i] <- x`.
- **Copy-on-write:** the write happens in place when nothing else refers to the array, and the array is copied first otherwise. A loop filling a fresh array doesn't allocate.
- **A changed copy:** `Array.set a i x` returns a changed array and leaves `a` alone.

```zsharp
let main () =
  let a = [| 1; 2; 3 |]
  let mutable b = a
  b.[0] <- 100
  println $"{a.[0]} {b.[0]} {Array.length b}"
  let c = Array.set a 2 30
  println $"{Array.toList a} {Array.toList c}"
  let mutable squares = Array.create 5 0
  for i in 0 .. 4 do
    squares.[i] <- i * i
  println $"{Array.toList squares} {Array.sum squares} {Array.toList (Array.map (fun x -> x + 1) squares)}"
  0
```

```text
1 100 3
[1; 2; 3] [1; 2; 30]
[0; 1; 4; 9; 16] 30 [1; 2; 5; 10; 17]
```

Indexing past the end stops the program with `panic: index out of bounds`.

## Buffer

A `Buffer<'a>` is the other choice: a mutable array shared by every name that refers to it, like an array in C# or Java. Use one when several parts of a program must see the same changing data.

```zsharp
let main () =
  let buf = Buffer.create 3 0
  let alias = buf
  alias.[0] <- 7
  println $"{buf.[0]} {Buffer.length buf}"
  let snapshot = Buffer.toArray buf
  alias.[0] <- 8
  println $"{snapshot.[0]} {buf.[0]}"
  0
```

```text
7 3
7 8
```

## Map and Set

**`Map<'k, 'v>`:** a persistent sorted map, a balanced tree with O(log n) operations. Adding or removing gives a new map that shares most of its structure with the old one, and the old one stays valid. Keys need an ordering, which every number, string, record, union and tuple has.

**`Set<'a>`:** the same, holding only keys.

```zsharp
let main () =
  let ages = Map.ofList [ ("ada", 36); ("alan", 41) ]
  let older = Map.add "ada" 37 ages |> Map.add "grace" 85
  println $"{Map.tryFind "ada" ages} {Map.tryFind "ada" older} {Map.count older} {Map.containsKey "bob" older}"
  println $"{Map.toList (Map.remove "alan" older)} {Map.keys ages}"
  let s = Set.ofList [ 3; 1; 2; 3 ]
  println $"{Set.toList s} {Set.contains 2 s} {Set.toList (Set.union s (Set.ofList [ 9 ]))}"
  0
```

```text
Some 36 Some 37 3 false
[(ada, 37); (grace, 85)] [ada; alan]
[1; 2; 3] true [1; 2; 3; 9]
```

## HashMap

**What it is:** a hash table. Keys need `Hash` and `Eq`, which the same types have.

**A value, like an array:** `HashMap.add` returns the changed map. The old map is unchanged, and when nothing else refers to it, the update happens in place. The usual pattern is a `let mutable` map updated in a loop, which costs no copies.

```zsharp
let main () =
  let mutable counts = HashMap.empty ()
  for w in String.split " " "the cat and the hat and the bat" do
    let n = HashMap.tryFind w counts |> Option.defaultValue 0
    counts <- HashMap.add w (n + 1) counts
  println $"{List.sort (HashMap.toList counts)}"
  println $"{HashMap.count counts} {HashMap.tryFind "the" counts} {HashMap.containsKey "dog" counts}"
  0
```

```text
[(and, 2); (bat, 1); (cat, 1); (hat, 1); (the, 3)]
5 Some 3 false
```
