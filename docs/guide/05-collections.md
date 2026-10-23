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

**List expressions:** `[ for x in xs -> e ]` is the list of `e` for each `x`; inside, `if c then yield e` keeps some, nested `for`s and `let`s and `match`es may yield, and `yield! ys` adds each of `ys`. `[| … |]` is the same for an array. A range is a source too: `[ for i in 1 .. n -> i * i ]`.

```zsharp
let main () =
  let xs = [ 5; 3; 8; 1 ]
  println $"{[ for x in xs -> x * 10 ]} {[ for x in xs do if x > 2 then yield x * x ]}"
  println $"{[ for i in 1 .. 3 do for j in 1 .. i -> (i, j) ]} {Array.toList [| for i in 0 .. 3 -> i * i |]}"
  0
```

```text
[50; 30; 80; 10] [25; 9; 64]
[(1, 1); (2, 1); (2, 2); (3, 1); (3, 2); (3, 3)] [0; 1; 4; 9]
```

**Performance:**
- The list functions are tail-recursive, so long lists don't exhaust the stack.
- When a list has only one owner, functions like `List.rev` reuse its cells instead of allocating new ones.
- A pipeline like `xs |> List.map f |> List.filter p |> List.sum`, with lambdas that only compute, runs as one loop: the lists in between are never built.
- A list expression is such a pipeline when its body only computes (a `for`, its `if`s, the value yielded), so `List.sum [ for x in xs do if x > 2 then yield x * x ]` builds no list. Any other body runs as written, in order, and builds only the result.

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

**Growing:** `Buffer.push x b` adds an element at the end and `Buffer.pop b` takes the last one (an `option`), each in constant time (the storage doubles when it's full); `Buffer.truncate n b` keeps the first `n`, `Buffer.clear b` none, and `Buffer.empty` is a new empty Buffer at each use. A slice of a Buffer (`b.[1..3]`) shares its storage until either grows past it.

```zsharp
let main () =
  let names = Buffer.empty
  for n in [ "ada"; "bob"; "cy" ] do
    Buffer.push n names
  println $"{Buffer.length names} {Buffer.pop names} {Buffer.length names}"
  0
```

```text
3 Some cy 2
```

## Spans and slices

A span, `span<'a>`, is a window into an array, a string's bytes or a Buffer, without a copy.
- **Slices:** `a.[1..3]` is elements 1 to 3 (inclusive, as in F#), and `a.[..n]` and `a.[i..]` run from the start and to the end. A slice of an array or a span is a span; a slice of a Buffer is a Buffer sharing its storage, so a write through either is seen through both; a slice of a string is a string (a copy), at byte offsets that must fall between characters.
- **Where a span is expected,** an array or a Buffer becomes one with nothing written, so `Array.sum`, `Array.fold`, `Array.map` and the other functions that read arrays take all three.
- **Read-only:** `s.[i]` reads, and nothing writes through a span. A span holds a reference to what it windows, which lives as long as the span; while it does, a change to the array copies it, as arrays are values.
- **Bytes:** `String.bytes s` is a string's bytes (its UTF-8) as a `span<u8>`, for parsers; `String.ofBytes` copies bytes into a string.

```zsharp
let main () =
  let a = [| 1; 2; 3; 4; 5 |]
  let mid = a.[1..3]
  println $"{Array.sum mid} {Array.sum a.[3..]} {mid.[0]} {Span.length mid}"
  let b = Buffer.ofArray a
  let front = b.[..1]
  front.[0] <- 10
  println $"{b.[0]} {Array.sum b}"
  let s = "héllo"
  println $"{s.[0..2]} {(String.bytes s).[0]}"
  0
```

```text
9 9 2 3
10 24
hé 104
```

A slice past the end stops the program, naming it: `panic: slice 4..9 of an array of length 6`.

## Fixed-size arrays

`fixed<'a, N>` holds N elements inline. It's a value, copied like a record and indexed like an array, and N is a number in the type, so `fixed<u8, 16>` and `fixed<u8, 32>` differ. It's what a C struct's array field is (`uint8_t data[16]`), so `[<CLayout>]` records and `import c` use it.
- **Elements:** `f.[i]` reads, and `f.[i] <- x` writes when `f`, or the record holding it, is `let mutable`.
- **Making one:** `Fixed.init (fun i -> …)` and `Fixed.create x`, the length from the type expected of them, or `Fixed.ofArray` from an array of as many elements.
- **Reading:** `Fixed.toArray`, `map`, `fold`, `iter`, and `for x in f do`. Equality, ordering, hashing and printing go element by element.

```zsharp
type Pixel = { rgb: fixed<u8, 3>; alpha: u8 }

let main () =
  let mutable p = { rgb = Fixed.ofArray [| u8 10; u8 20; u8 30 |]; alpha = u8 255 }
  p.rgb.[0] += u8 5
  let steps: fixed<int, 4> = Fixed.init (fun i -> i * 10)
  println $"{p.rgb} {Fixed.fold (fun acc x -> acc + int x) 0 p.rgb} {steps} {steps = Fixed.create 0}"
  0
```

```text
[|15; 20; 30|] 65 [|0; 10; 20; 30|] false
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

**In a loop:** `for (k, v) in m` goes over a map's entries in ascending key order, and `for x in s` over a set's elements.

**Any collection:** the `Iter` module's functions take any collection a `for` can walk: `Iter.fold`, `iter`, `exists`, `forall`, `tryFind`, `length` and `toList`; and `List.ofIter`, `Array.ofIter`, `Set.ofIter` and `Map.ofIter` collect one.

```zsharp
let main () =
  let ages = Map.ofList [ ("ada", 36); ("alan", 41) ]
  let mutable total = 0
  for (name, age) in ages do
    total <- total + age
  println $"{total} {Iter.exists (fun (_, a) -> a > 40) ages} {Set.toList (Set.ofIter "banana")}"
  0
```

```text
77 true [a; b; n]
```

## HashMap

**What it is:** a hash table. Keys need `Hash` and `Eq`, which the same types have.

**A value, like an array:** `HashMap.add` returns the changed map. The old map is unchanged, and when nothing else refers to it, the update happens in place. The usual pattern is a `let mutable` map updated in a loop, which costs no copies.

```zsharp
let main () =
  let mutable counts = HashMap.empty
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
