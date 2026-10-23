# 6. Traits

A trait is a set of functions that a type can implement, like an interface or a type class.
Operators, equality, ordering, hashing and printing are all traits. That's how `+` works on
both `int` and `f64`, and how `=` works on records.

| Trait | Gives | Built in for |
|---|---|---|
| `Eq` | `=`, `<>` | everything except functions |
| `Ord` | `<`, `>`, `<=`, `>=`, `compare` | numbers, strings, records, unions, tuples, lists |
| `Hash` | `hash` | same as `Ord` |
| `Show` | `string x`, `$"{x}"` | same as `Ord` |
| `Add` | `+`, `Add.zero` (used by `List.sum`) | numbers, strings |
| `Num` | `-`, `*`, `/`, `%`, negation | numbers |

## Equality and printing come free

**Automatic derivation:** records and unions get `Eq`, `Ord`, `Hash` and `Show` automatically, from their structure.
- **Equality:** field by field.
- **Ordering:** by case, then by fields.
- **Printing:** in F# style.

**Opting out:** `[<NoEquality>]` or `[<NoComparison>]` turns derivation off for a type, for example a handle whose identity matters more than its contents.

```zsharp
type Card =
  | Number of int
  | Jack
  | Queen

type Hand = { owner: string; cards: list<Card> }

let main () =
  let h = { owner = "ada"; cards = [ Number 7; Queen ] }
  println $"{h}"
  println $"{h = { owner = "ada"; cards = [ Number 7; Queen ] }} {Number 9 < Jack} {compare Queen Jack}"
  println $"{List.sort [ Queen; Number 2; Jack; Number 1 ]} {hash h = hash h}"
  0
```

```text
{ owner = ada; cards = [Number 7; Queen] }
true true 1
[Number 1; Number 2; Jack; Queen] true
```

## Implementing a trait

`impl Trait<Type>` gives a type its own implementation. An explicit impl replaces the derived one, and implementing `Add` and `Num` makes the operators work.

```zsharp
type Vec = { x: f64; y: f64 }

impl Add<Vec> =
  let add a b = { x = a.x + b.x; y = a.y + b.y }
  let zero = { x = 0.0; y = 0.0 }

impl Show<Vec> =
  let show v = $"<{v.x}, {v.y}>"

let main () =
  let a = { x = 1.0; y = 2.0 }
  println $"{a + a} {List.sum [ a; a; a ]}"
  0
```

```text
<2, 4> <3, 6>
```

## Your own traits

`trait Name<'a>` declares the functions with `abstract`.
- **Calling:** a trait's functions are called like any function. The type decides which implementation runs, and that's resolved at compile time, so there's no runtime dispatch (unless the value is a `dyn`, below).
- **Generic functions:** a generic function that uses a trait function works for every type that implements it. The requirement is inferred; hover shows it, e.g. `twice : 'a -> string when 'a : Describe`.
- **Impls that need impls:** an impl for a generic type may need impls for its parts. `Describe<list<'a>>` below needs `Describe<'a>`, also inferred.

```zsharp
trait Describe<'a> =
  abstract describe : 'a -> string

impl Describe<int> =
  let describe n = $"the number {n}"

impl Describe<bool> =
  let describe b = if b then "yes" else "no"

impl Describe<list<'a>> =
  let describe xs =
    match xs with
    | [] -> "nothing"
    | x :: rest -> describe x + ", then " + describe rest

let twice x = describe x + " / " + describe x

let main () =
  println (twice 4)
  println (describe [ true; false ])
  0
```

```text
the number 4 / the number 4
yes, then no, then nothing
```

## Traits with several parameters

**The first parameter picks the impl; the impl fixes the others.** `trait Iter<'c, 'a>`, the prelude's trait behind `for`, has the collection's type first and its elements' second: `impl Iter<Map<'k, 'v>, 'k * 'v>` says a map's elements are pairs. One impl per type, and its other parameters are made of the type's own variables, so the collection's type settles the element type wherever it's known.

**Your own collection:** an `Iter` impl is a `forEach` that calls `f` on each element in order until it returns `false`, and says whether it got to the end. Then `for` and the `Iter` functions work on the type, and a function looping over a parameter works on any collection (`total : 'c -> int when 'c : Iter<int>`).

```zsharp
type Tree<'a> =
  | Leaf
  | Node of Tree<'a> * 'a * Tree<'a>

impl Iter<Tree<'a>, 'a> =
  let forEach t f =
    match t with
    | Leaf -> true
    | Node (l, x, r) -> forEach l f && f x && forEach r f

let total xs =
  let mutable n = 0
  for x in xs do
    n <- n + x
  n

let main () =
  let t = Node (Node (Leaf, 1, Leaf), 2, Node (Leaf, 3, Leaf))
  println $"{total t} {total [ 4; 5 ]} {Iter.toList t}"
  0
```

```text
6 9 [1; 2; 3]
```

- **What it costs:** a `forEach` that calls `f` at one place in a loop is inlined, and the body of a `for` lands in that loop: no closure, nothing allocated per element. A recursive one, like the tree's, works too; the body is then a function called per element, as with `List.iter`.
- **No `dyn`:** a trait with several parameters can't be a `dyn` value.

## dyn: values of different types together

**A trait as a type:** `dyn Shape` is a value of any type that implements `Shape`, so values of different types can go in one list, or be returned from different branches.
- **Making one:** a value becomes a `dyn Shape` where one is expected: a list or a parameter declared with that type, a function's declared result, or `(x : dyn Shape)`.
- **Calling:** the trait's functions work on it as on any type that implements the trait, and a generic function over the trait takes it too. A call goes through a table of the value's own impl, chosen when the value was made.
- **Which traits:** every function of the trait must take the value first and not mention its type anywhere else. `Show` qualifies, `Ord` doesn't: `compare` would need two values of the same type.

```zsharp
trait Shape<'a> =
  abstract area : 'a -> f64
  abstract name : 'a -> string

type Circle = { r: f64 }

type Rect = Rect of f64 * f64

impl Shape<Circle> =
  let area c = 3.14 * c.r * c.r
  let name _ = "circle"

impl Shape<Rect> =
  let area (Rect (w, h)) = w * h
  let name _ = "rect"

let main () =
  let shapes: list<dyn Shape> = [ { r = 1.0 }; Rect (2.0, 3.0) ]
  for s in shapes do
    println $"{name s}: {area s}"
  println $"total area {List.sumBy area shapes}"
  0
```

```text
circle: 3.14
rect: 6
total area 9.14
```

## Writing a derive

`derive Name` writes an impl once for every record and union, the way the automatic `Show` is written in the standard library.
- **Inside a derive:** `Shape.of x` matches the value as a `Record` or a `Union` case, and `for f in r.fields` runs once per field. In the loop, `f.name`, `f.index` and `f.value` describe the field.
- **Expansion:** the derive is expanded for each type at compile time, and each copy is type-checked at that type. A field whose type lacks the impl is an error that names the field.
- **Applying it:** `[<Derive(Name)>]` on a type applies a derive.

```zsharp
trait Fields<'a> =
  abstract fieldNames : 'a -> list<string>

derive Fields =
  let fieldNames (x: 'self) =
    match Shape.of x with
    | Record r ->
      let mutable names = []
      for f in r.fields do
        names <- f.name :: names
      List.rev names
    | Union c -> [ c.name ]

[<Derive(Fields)>]
type User = { name: string; age: int; admin: bool }

[<Derive(Fields)>]
type Status =
  | Active
  | Banned of reason: string

let main () =
  println $"{fieldNames { name = "ada"; age = 36; admin = true }} {fieldNames (Banned "spam")}"
  0
```

```text
[name; age; admin] [Banned]
```

Core's `Text.Json` (`lib/core/Text/Json.zs`) has a fuller example: `[<Derive(Json)>]`, a JSON encoder and decoder written as two derives and a group of them. `Binary` (`lib/core/Binary.zs`) is another: `[<Derive(Binary)>]` writes a value as compact bytes and reads it back (`Binary.toBytes`, `Binary.ofBytes`), for a cache or a message between processes.
