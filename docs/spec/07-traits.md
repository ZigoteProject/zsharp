# 7. Traits

A trait is a set of operations that types implement. Traits are Z#'s one mechanism for
overloading: the operators, equality, printing, iteration and disposal are traits. Trait calls
are resolved at compile time; a `dyn` value ([§7.4](#74-dyn)) is the one run-time dispatch.

## 7.1 Traits

```text
trait-decl = 'trait' ID '<' TYVAR { ',' TYVAR } '>' '='
             INDENT { 'abstract' ID ':' type NEWLINE } DEDENT ;
```

```fsharp
trait Describe<'a> =
  abstract describe : 'a -> string
```

- The first type parameter is the **implementing type**: an impl is chosen by it.
- Each `abstract` line declares a **method** with its type, which mentions the trait's
  parameters. A method need not be a function (`abstract zero : 'a`).
- A trait has methods only: no default bodies, no supertraits, no associated types or
  constants.
- **Calling a method.** A method is a function, generic in the trait's parameters with the
  constraint `'a : Trait`. It is named `method` where the trait's module is in scope, and
  `Module.method` or `Trait.method` elsewhere ([§2.4](02-programs.md#24-name-resolution)).
  A call at a known type uses that type's impl; a call at a type variable makes the enclosing
  function generic with the constraint, which is inferred
  ([§3.5](03-types.md#35-type-variables-and-constraints)).
- **Effects.** A method performs nothing of its own. The arrows of its function arguments
  written without a row, and its own last arrow, share one row variable: a method performs
  what the functions it is given perform ([§3.8](03-types.md#38-effect-rows)). A method's
  type must not declare a row of its own.

**Traits with several parameters.** In `trait Iter<'c, 'a>`, the first parameter dispatches
and **the impl determines the others**: there is one impl per implementing type, and its other
arguments are built from that type's variables (`impl Iter<Map<'k, 'v>, 'k * 'v>`). A
constraint carries them (`'c : Iter<int>`), and they are known once the implementing type is.

## 7.2 Impls

```text
impl-decl = 'impl' ID '<' type { ',' type } '>' '='
            INDENT { 'let' ID { parameter } [ ':' type ] '=' block NEWLINE } DEDENT ;
```

```fsharp
impl Describe<Point> =
  let describe p = $"({p.x}, {p.y})"

impl Describe<list<'a>> =                       // needs Describe<'a>: inferred
  let describe xs = String.join ", " (List.map describe xs)
```

- An impl defines **every** method of the trait and nothing else, each with the trait's type
  at the implementing type.
- **The head** (the first type argument) is a named type applied to distinct type variables or
  to no arguments, a primitive type, or a tuple type of variables (`impl Binary<'a * 'b>`).
  An impl for a generic head is generic; the constraints its body needs on the head's
  variables are inferred and become the impl's requirements.
- A function type, a type variable alone and `dyn` types are not heads.
- A method of an impl may call the trait's methods at other types, and itself.

## 7.3 Coherence

A program has **at most one impl of a trait for a type**.

- Two impls of one trait with the same head are an error (`Area<int> is already implemented`).
  Since a generic head's arguments are type variables, an impl is for a type constructor as a
  whole: there is no `impl T<list<int>>` beside, or instead of, `impl T<list<'a>>`, and no
  specialization.
- **The orphan rule.** An impl must be written in the package that declares the trait or in
  the package that declares the head type. So two packages cannot both implement a trait for
  a type. A derived impl belongs with its type and is exempt. A program that needs a foreign
  trait for a foreign type wraps the type in a one-case union of its own.
- **Hand-written before first use.** For the traits with automatic derives
  ([§7.5](#75-derive)), a hand-written impl must precede, in checking order, every use of the
  trait at that type: a use that comes first would have derived a second impl, and is an
  error saying to write the impl before it, beside the type.

A **missing impl** is an error at the use that needs it, naming the type and the trait
(`Square does not implement Area; write impl Area<Square> = …`).

## 7.4 `dyn`

`dyn Trait` is the type of a value of any type implementing `Trait`, with the type forgotten.

```fsharp
let shapes : list<dyn Shape> = [ Circle 1.0; Square 2.0 ]
for s in shapes do println (describe s)
```

- **Which traits.** A trait can be `dyn` when it has one parameter, and each of its methods
  is a function that takes the implementing type as its first parameter and does not mention
  it elsewhere. `Show` and `Dispose` can; `Ord`, `Eq` and `Add` cannot; `Iter` cannot.
- **Making one.** A value of a type implementing the trait is accepted where a `dyn Trait` is
  expected ([§5.11](05-expressions.md#511-implicit-conversions)): an annotated binding, a
  parameter, a result, an element of a collection of `dyn Trait`. Nothing is written.
- **Using one.** `dyn Trait` implements `Trait`: its methods call the methods of the value's
  own type.
- A `dyn` value has no other operations: its type cannot be recovered, and it has no
  equality, ordering or printing unless `Trait` is the trait that gives it.
- Through `dyn`, the functions given to a method must perform no effect.
- A `dyn` value is not `Share` ([§10.6](10-execution.md#106-threads-and-share)).

## 7.5 Derive

A **derive** is a definition that implements a trait for any record or union by walking its
fields. It is the language's only compile-time code generation.

```text
derive-decl = 'derive' ID '='
              INDENT { 'let' ID { parameter } [ ':' type ] '=' block NEWLINE } DEDENT
            | 'derive' ID '=' ID { ',' ID } ;                       a group
```

```fsharp
derive ToJson =
  let toJson (x: 'self) =
    match Shape.of x with
    | Record r ->
      let mutable fields = []
      for f in r.fields do
        fields <- (f.name, toJson f.value) :: fields
      JObject (List.rev fields)
    | Union c -> …

derive Json = ToJson, FromJson

[<Derive(Json)>]
type User = { name: string; age: int = 18 }
```

- `derive T = …` defines the trait `T`'s methods for the type `'self`.
  `[<Derive(T)>]` on a record or union declaration makes `impl T<ThatType>` from it. A
  **group** names several derives applied together.
- **Shape.** Inside a derive, the type being derived is seen through these forms:

  | Form | Gives |
  |---|---|
  | `Shape.of x` | `Record r` or `Union c` for the value `x : 'self` |
  | `r.fields`, `c.fields` | the fields of the record, or of the value's case |
  | `f.name`, `f.index`, `f.value` | a field's name, position, and value at the field's own type |
  | `f.default` | a record field's default as `Some v`, or `None` |
  | `c.name`, `c.index`, `c.count` | the case's name, position and number of fields |
  | `Shape.pair a b` | `Same c`, with `f.left` and `f.right` per field, or `Different (i, j)` |
  | `Shape.kind` | `RecordKind` or `UnionKind`, with no value at hand |
  | `Shape.cases` | a union's cases without a value |
  | `Shape.build (fun f -> …)` | a record from a result per field, stopping at the first `Error` |
  | `Shape.buildCase name (fun f -> …)` | the named case, or `None` for an unknown name |

- **Unrolling.** A `for f in ….fields do` loop in a derive is expanded when the derive is
  applied: one copy of the body per field, each checked at that field's type. So
  `toJson f.value` resolves `ToJson` separately for each field. No other construct is
  expanded this way.
- **Checking.** Where it is defined, a derive is checked for syntax and names. At each type
  it is applied to, the expansion is fully type-checked, and an error names the derive, the
  type and the field (`Derive(Json) on Callback: field run: … does not implement Json`).
- **Names** inside a derive are resolved in the derive's module, whatever the program
  defines where it is applied.
- **Generic types.** Deriving for `Tree<'a>` gives an impl requiring the trait of `'a` as
  far as the fields need it. Recursive types are derived like any others.
- A derive defines impls only; it cannot add members, types or other declarations.
- A derived impl has no run-time type information behind it: it is ordinary code.

**Automatic derives.** `Eq`, `Ord`, `Hash`, `Show` and `Diff` are derived for every record
and union without being asked, the first time a program uses the trait at the type
([§4.3](04-declarations.md#structural-operations)), unless the type has a hand-written impl
or opted out. Tuples have them structurally.

## 7.6 The prelude traits

| Trait | Methods | Used by | Built-in impls |
|---|---|---|---|
| `Add<'a>` | `add : 'a -> 'a -> 'a`, `zero : 'a` | `+`, `List.sum`, … | numbers, vectors, `string` |
| `Num<'a>` | `sub`, `mul`, `div`, `rem : 'a -> 'a -> 'a`, `neg : 'a -> 'a` | `-` `*` `/` `%`, prefix `-` | numbers, vectors |
| `Eq<'a>` | `equal : 'a -> 'a -> bool` | `=`, `<>` | numbers, vectors, `string`, `bool`, `char`, `unit` |
| `Ord<'a>` | `compare : 'a -> 'a -> int` | `<` `>` `<=` `>=`, `compare`, `min`, `max` | numbers, `string`, `char` |
| `Show<'a>` | `show : 'a -> string` | `string x`, `$"{x}"` | numbers, vectors, `string`, `bool`, `char`, `unit`, `list` |
| `Format<'a>` | `format : 'a -> string -> string` | `$"{x:F2}"` | numbers |
| `Hash<'a>` | `hash : 'a -> int` | `hash`, `HashMap`, `HashSet` | numbers, `string`, `bool`, `char` |
| `Dispose<'a>` | `dispose : 'a -> unit` | `use` | none |
| `Iter<'c, 'a>` | `forEach : 'c -> ('a -> bool) -> bool` | `for … in`, the `Iter` module | in the library, per collection |
| `Diff<'a>` | `diff : 'a -> 'a -> option<string>` | a failed `assert`'s report | numbers, `string`, `bool`, `char` |

- `compare a b` is negative, zero or positive as `a` is less than, equal to or greater than
  `b`.
- `Iter.forEach c f` calls `f` on each element in order while `f` returns `true`, and returns
  whether it reached the end. `for x in c do body` is `forEach c (fun x -> body; true)`, with
  the difference that the body may assign the enclosing function's mutable variables
  ([§5.8](05-expressions.md#58-blocks-and-bindings)).
- User types implement any of these with `impl`. Implementing `Add` and `Num` for a type
  gives it the operators.
- `Share` ([§10.6](10-execution.md#106-threads-and-share)) is an **auto trait**: computed
  from a type's structure by the compiler, with no declaration, and not implementable by
  hand.
