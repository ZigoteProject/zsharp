# Proposal 0017: iteration

| | |
|---|---|
| **Status** | Approved (decision 57) and built, steps 1 to 4: list expressions over any `Iter` (0005) and the versioning pass's `while` shape are what's left |
| **Decided at** | the third design review ([ROADMAP](../../ROADMAP.md#third-design-review-)): `forEach` returns `bool`, collecting is a function per type, ranges are a `Range` record, the dispatch rule is decision 57's text |
| **Builds** | track S item 1 ([ROADMAP](../../ROADMAP.md#library-s)), before phase 11: phase 12's "kept before phase 11" list names the iteration trait |
| **Rests on** | decisions 20 (derive, no macros), 43 (`dyn Trait`), 49 (SIMD: a module per vector type, since HM can't relate a vector type to its element type) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §3](../../DESIGN.md#3-traits) (traits take one type parameter; requirements are inferred), [§4](../../DESIGN.md#4-computation-expressions) (`B.forEach`), [§9.1](../../DESIGN.md#91-optimization-strategy) (inlining; a lambda applied in place) |
| **Related** | [0002 effect handlers](0002-effect-handlers.md) (`Seq` implements it), [0003 spans](0003-spans-and-slices.md) (spans iterate), [0005 ergonomics](0005-ergonomics.md) (list expressions over any `Iter`), [0024 the library's API](0024-library-api.md) (its tables list the `ofIter` functions as this proposal's) |

- [x] Approved in principle
- [x] Discussion
- [x] Implementation: traits with several parameters (`Typer.methodType`, kinds' `params`, `implOthers`), `for` over `Iter.forEach`, the inliner's rule, Lift's cell fallback, the library's impls (`tests/iter/basics.zs`, `maps.zs`, `loops.sh`, `err_*.zs`)

## Summary

`for x in c do` works on what the type checker knows how to walk: lists, arrays, `Buffer`s and
strings (`Typer.fs:1572-1627`, main checkout). A `Map`, a `Set`, a `HashMap`, a span or a
tree of the program's own needs its module's `iter`, and a generic function can't loop over a
parameter at all. This proposal makes iteration a trait:

```fsharp
trait Iter<'c, 'a> =
  /// Calls `f` on each element in order until it returns false; whether it ran to the end.
  abstract forEach : 'c -> ('a -> bool) -> bool

impl Iter<Map<'k, 'v>, 'k * 'v> =
  let forEach m f = …                    // one loop, in key order (below)

let total xs =                           // 'c -> int when 'c : Iter<int>
  let mutable t = 0
  for x in xs do
    t <- t + x
  t
```

`for x in c do body` becomes `Iter.forEach c (fun x -> body; true)`, and costs what today's
loops cost: the impl's `forEach` is small, monomorphized and inlined, and Simplify applies the
lambda where the impl calls it, so the body sits in the impl's loop and no closure exists.
The one language change is the trait's second parameter: **a trait's first parameter
dispatches; its other parameters are determined by the impl, one impl per head type.**
`Iter.fold`, `exists`, `toList` and `List.ofIter`, `Set.ofIter` follow as generic functions
over the trait; `Seq` implements it in phase 10.

## Motivation

- **A map is walked by hand.** Counting words today is `Map.iter (fun w n -> …) counts`, or
  `for (w, n) in Map.toList counts do`, which builds a list of the whole map first. `Set.toList`,
  `Map.keys` and `Map.values` exist for the same reason: the loop the programmer wants isn't
  writable. [The collections chapter](../guide/05-collections.md) teaches `for` on lists and
  arrays and a function per type for the rest.
- **A generic function can't loop.** `let total xs = … for x in xs …` is an error unless `xs`
  is annotated: the checker settles the collection's type at the loop and picks a lowering by
  its head (`Typer.fs:1574`, `1627`), so a type variable gives `'for ... in' needs a list, an
  array or a string, not 'a`. A sum, a count or a search over "anything iterable" is written
  three times or takes a list, which callers then build.
- **The program's own types.** A tree, a ring, a matrix's rows, a token stream: each gets an
  `iter` function in its module and no `for`. Rust (`IntoIterator`), Swift (`Sequence`) and F#
  (`seq`) make `for` work on user types; Z# should, without their per-element cost.
- **Builders.** `Option.Builder.forEach` takes a list only (`Option.zs:86-92`), so a `for` in
  `option { }` or `result { }` over a `Map` doesn't work either.
- **What F# has, and what carries over.** F#'s `for x in xs` takes any `IEnumerable`: an
  enumerator object, an interface call to `MoveNext` and one to `Current` per element, and
  `Seq.*` over the same interface. What carries over is the surface: `for` over anything, and
  the library's `fold`, `exists`, `toList` once over all collections. The mechanism can't:
  there is no interface dispatch and no enumerator; iteration is internal (a `forEach` that
  can stop early, as CE `for` already is, DESIGN §4), resolved statically and inlined.
- **Without the feature:** every collection keeps its `iter`, `for` stays four hard-coded
  cases in the checker, and the compiler rewritten in Z# (phase 11) loops over its maps
  through `Map.iter` and lambdas throughout.

## Detailed design

### Syntax

```
trait-decl   :=  'trait' ident '<' type-var { ',' type-var } '>' '=' INDENT abstract+ DEDENT
impl-decl    :=  'impl' ident '<' type { ',' type } '>' '=' INDENT let-def+ DEDENT
```

- **Traits take a list of type parameters.** Today's parser reads one (`Syntax.fs:2307-2334`,
  main checkout); `Trait of name * tparams * methods` carries the list. Inside the trait's
  methods, `TGen 0` is the first parameter and `TGen i` the others (`Core.fs:627-631` has
  only `TGen 0`).
- **An impl gives a type per parameter:** the head first, then the others.
  `impl Iter<Map<'k, 'v>, 'k * 'v>`, `impl Iter<string, char>`, `impl Iter<Tree<'a>, 'a>`.
- **`for` is unchanged.** `for x in c do`, `for (k, v) in m do` (a pattern: the parser already
  binds a fresh name and takes it apart at the top of the body, `Syntax.fs:1403-1422`), and
  `for i in a .. b do` are the same syntax. Nothing of this needs decision 34's discussion:
  trait and impl forms are Z#'s own, and gain a comma.

### The rule: the first parameter dispatches

This is the language change, and the only one:

- **Dispatch by the head.** An impl is found by the trait and the first parameter's type
  constructor, as today (`impls[(trait, head)]`, one per pair: `Typer.fs:3048`, `Mono.fs`'s
  `implFn`). The other parameters aren't looked at to find an impl: there is no overlap, no
  specialization, and no search.
- **Determined by the impl.** An impl's other parameters are types over the head's type
  variables (`'k * 'v` for `Map<'k, 'v>`; `char` for `string`). Once the impl is found, they
  are instantiated with the head's variables and unified with the requirement's. So
  `Iter<Map<string, int>, ?>` resolves `?` to `string * int`, and a requirement with the wrong
  element type is an error at the use, not a missing impl.
- **A requirement remembers them.** Today a type variable's kind holds the traits it needs
  (`Core.fs:96-106`: `{ allowed; traits: Set<string> }`), and hover prints `when 'a : Show`
  (`Typer.fs:3342-3348`). The kind gains the other parameters per trait, so a variable needs
  `Iter<int>` rather than `Iter`, hover shows `when 'c : Iter<int>`, and two requirements on
  one variable unify their parameters: `'c : Iter<int>` and `'c : Iter<string>` on the same
  `'c` is the error below. Resolution happens where it happens today: when the variable is
  bound to a type with a head constructor.
- **`declareImpl`** (`Typer.fs:3016-3095`) keeps its rules for the head (a named type with
  distinct type variables) and checks that every type variable in the other parameters is
  one of the head's, so an impl can't leave an element type open. The methods' expected types
  substitute all parameters (today `substGen [head]`, `Typer.fs:3073-3076`). Monomorphization,
  `dyn` tables and derives are untouched: a two-parameter trait isn't `dyn` and isn't derived
  in this proposal (*Unresolved questions*).

**Why this works where SIMD couldn't (decision 49).** A generic `load : array<'e> -> 'v` has to
find the vector type from the element type, and the relation runs the wrong way for HM: `'v`
is the result, inferred from its uses, and `f32` has three vector types (`f32x4`, `f32x8`,
`f32x16`), so nothing determines it. Iteration's relation runs from an argument the checker
already has, by its head constructor, to a type that constructor fixes: `list<'a>` has `'a`,
`Map<'k, 'v>` has `'k * 'v`, `string` has `char`. That is a functional dependency from the
first parameter to the rest, resolved at impl lookup, where the checker already is. It's the
whole of what a type family would give here, without type-level functions to normalize.

### What `for` becomes

- **Lowering:** `for x in c do body` is `Iter.forEach c (fun x -> body; true) |> ignore`, typed
  as a call: `c : 'c` with `'c : Iter<'a>`, `x : 'a`, the body `unit`. `for` works wherever
  an impl exists, and a loop over a parameter makes the function generic (`total` above).
- **The body is the function's.** A lambda can't capture a `let mutable` (`Typer.fs:1500`; the
  guide's rule, [basics](../guide/02-basics.md)). The lambda `for` makes is the compiler's own
  and is marked so: its body may assign the enclosing function's mutables, as a loop body
  does today. In the normal case it's applied in place (next section) and the assignments are
  to locals of the same function. In the fallback (an impl the inliner can't inline, below),
  closure conversion (`Lift`) moves each outer mutable the lambda assigns into a `ref` cell
  for the loop's duration and reads it back after: what the guide tells the programmer to
  write by hand, done once by the compiler, costing one allocation per such variable per
  loop run, not per element.
- **Early exit stays internal.** `for` always passes `true`: there is no `break`, as in F#.
  `forEach`'s `bool` is for library writers: `Iter.exists`, `tryFind`, `forall` and the
  builders' `forEach` stop through it, so a search over a `Map` stops at its first hit without
  walking the rest.
- **The collection is taken once:** `c` is evaluated before the loop, as `$coll` is today
  (`Typer.fs:1575-1580`). A `Buffer` is a shared reference, so a body's writes to it are seen
  by the loop; an array is a value (decision 7), so a body's `Array.set` makes its own copy and
  the loop goes on over the original.
- **CE `for` is unchanged:** `for x in xs do` inside `w { }` is `W.Builder.forEach xs (fun x -> …)`
  (DESIGN §4, `Syntax.fs:1987`), and the error for a builder without one still names the form
  (`Typer.fs:2397-2407`). `Option.Builder.forEach` and `Result.Builder.forEach` are rewritten
  over `Iter.forEach`, so they take any `Iter`; `task { }`'s `for` is the compiler's state
  machine and doesn't change.
- **Ranges:** `for i in a .. b do` keeps its own loop (`CFor`, with the bounds-check versioning
  of DESIGN §8). As a value, a range is a Core record, `{ start = 1; stop = 10; step = 1 }`
  of type `Range`, with `impl Iter<Range, int>` (a counted loop); whether `a .. b` outside a
  `for` or `[ ]` builds one is a decision 34 question (*Unresolved questions*).

### The cost: one loop, no closure

What a `for` over a `Map` compiles to, pass by pass (DESIGN §9):

1. **Typer** emits the call with the compiler's lambda.
2. **Mono** replaces `Iter.forEach` by the impl's function, `Iter<Map>#forEach`, a known global
   (`Mono.implFn`).
3. **Inline** copies the impl into the caller. Today it inlines functions of at most 60 nodes
   without local functions that don't call themselves (`Inline.fs:115-118`), callees first
   (`Inline.fs:97`). The one addition: **a call of an `Iter` impl's `forEach` is inlined
   whatever its size** (it still can't be self-calling or hold local functions). Callees
   first means `Set`'s one-line impl already holds `Map`'s loop when it's inlined in turn.
4. **Simplify** finds the lambda bound to the impl's parameter `f` and applied at one site, and
   applies it there whatever its size (`Simplify.fs:240-292`: one call site at any size, several
   only under 40 nodes). The `true` it returns reaches the impl's `ok <- f x` and the loop
   condition; `if` on a known bool folds (`Simplify.fs:329-334`), and LLVM removes the
   constant flag.
5. **Rc and Codegen** see a loop over locals, as for today's lowering: the collection
   borrowed, nothing allocated, nothing captured.

**The required optimization is step 4 after step 3,** and the exit test states it: a `for`
over a `Map` compiles to the same loop as `Map.iter`, with no closure allocated.
`Map.iter f m` is itself `Iter.forEach m (fun (k, v) -> f k v; true) |> ignore`, so both sides
inline one impl; the test is a `.same-ir` sidecar (`test.sh:40-46`), two programs that differ
only in `for` against `Map.iter`. A second test checks a `for` over an array, a list and a
string for one loop and no call to the allocator in the IR. Array loops have one more thing to
keep: the bounds-check versioning applies to `CFor` loops (`Codegen.fs:2794-2795`), and the
array impl is a `while` with an index (it needs early exit); LLVM's range facts remove the
checks in that shape, and if the host benchmarks' 5% guard (DESIGN §9.1) says otherwise, the
versioning pass learns the `while i < Array.length a` shape in step 2 of the order below.

**Impl writers get one rule:** call `f` at one site, in a loop rather than a recursion, and a
`for` over your type costs nothing. A recursive impl works too, at today's `Map.iter` cost: a
call per element through a closure, and the `ref` fallback for an assigning body.

### Impls in the library

The trait is in the prelude, as `Show` and `Dispose` are, since `for` needs it in every
program and `impl Iter<…>` is written unqualified; the module `Iter` of functions over it is
Core (`lib/core/Iter.zs`), as `Map` is both a type and a module. Each impl sits in its type's
file. Every one is a loop that calls `f` once:

| Type | Element | The loop | Order |
|---|---|---|---|
| `list<'a>` | `'a` | a cursor, as today's lowering | front to back |
| `array<'a>`, `Buffer<'a>`, `span<'a>` ([0003](0003-spans-and-slices.md)) | `'a` | an index against the length, read each round for a `Buffer` | by index |
| `string` | `char` | `String.decodeAt`'s cursor (`String.zs:77`), as today | code points; bytes are `for b in String.bytes s` |
| `Map<'k, 'v>` | `'k * 'v` | in-order with the path kept in a list (below); replaces the recursive `Map.iter` (`Map.zs:132-138`) | ascending keys |
| `Set<'a>` | `'a` | `Iter.forEach s.items (fun (x, _) -> f x)` | ascending |
| `HashMap<'k, 'v>` | `'k * 'v` | an index over the buckets; each chain through the list impl, `f` passed along | bucket order, unspecified |
| `option<'a>` | `'a` | `match o with Some x -> f x \| None -> true` | zero or one |
| `Range` | `int` | a counted loop by `step` | `start` to `stop` |
| `Seq<'a>` (phase 10) | `'a` | a handler (below) | the generator's |

```fsharp
impl Iter<list<'a>, 'a> =
  let forEach xs f =
    let mutable cur = xs
    let mutable ok = true
    while ok && not (List.isEmpty cur) do
      match cur with
      | x :: rest ->
        cur <- rest
        ok <- f x
      | [] -> ()
    ok

impl Iter<Map<'k, 'v>, 'k * 'v> =
  /// In-order, with the path to the current node as a list: a loop, not a recursion, so a
  /// `for` over a map is one loop with its body in place.
  let forEach m f =
    let mutable path = []
    let mutable cur = m
    let mutable ok = true
    while ok && not (Map.isEmpty cur && List.isEmpty path) do
      match cur with
      | MapNode (l, _, _, _, _) ->
        path <- cur :: path
        cur <- l
      | MapLeaf ->
        match path with
        | MapNode (_, k, v, r, _) :: rest ->
          path <- rest
          cur <- r
          ok <- f (k, v)
        | _ -> ()
    ok
```

The path's cells come from the pool's free lists (DESIGN §9.1) and are reused as the walk
pops and pushes; the recursion it replaces used stack frames. `Map.toList`, `keys`, `values`,
`count` and `Set.toList` are rewritten over `forEach` or `fold` and keep their results.

**A user type** needs one function:

```fsharp
type Tree<'a> = | Leaf | Node of Tree<'a> * 'a * Tree<'a>

impl Iter<Tree<'a>, 'a> =
  let rec forEach t f =
    match t with
    | Leaf -> true
    | Node (l, x, r) -> forEach l f && f x && forEach r f
```

Three lines, recursive: a `for` over it calls the body through a closure per element, as
`Map.iter` does today. The map impl above is the shape to copy when the loop must be free.

**`Seq`** ([0002](0002-effect-handlers.md)) is `Seq of (unit -> unit / Yield<'a>)`, a
single-case union, so it can be an impl head:

```fsharp
impl Iter<Seq<'a>, 'a> =
  let forEach (Seq run) f =
    handle run () with
    | Yield.yield x, k -> if f x then k () else false
    | return () -> true
```

With `for`'s `true` applied in place the clause is `k ()`: tail-resumptive, and since 0002's
`Evidence` pass runs after Simplify, a `for` over a generator is one loop. A real early exit
(`Iter.exists` over a `Seq`) captures per element, as 0002's `take` does.

### Functions over the trait

| Function | Type | Written as |
|---|---|---|
| `Iter.forEach` | `'c -> ('a -> bool) -> bool when 'c : Iter<'a>` | the method |
| `Iter.iter` | `('a -> unit) -> 'c -> unit` | `forEach c (fun x -> f x; true) \|> ignore` |
| `Iter.fold` | `('s -> 'a -> 's) -> 's -> 'c -> 's` | a `ref` accumulator around `forEach`: one allocation per call, not per element |
| `Iter.exists`, `Iter.forall` | `('a -> bool) -> 'c -> bool` | `not (forEach c (fun x -> not (p x)))`; `forEach c p` |
| `Iter.tryFind` | `('a -> bool) -> 'c -> option<'a>` | a `ref` holding the hit; stops at it |
| `Iter.length` | `'c -> int` | `fold (fun n _ -> n + 1) 0 c` |
| `Iter.toList` | `'c -> list<'a>` | `List.rev (fold (fun acc x -> x :: acc) [] c)` |
| `List.ofIter`, `Array.ofIter`, `Set.ofIter`, `Map.ofIter` | `'c -> list<'a>`, `'c -> array<'a>`, `'c -> Set<'a>`, `'c -> Map<'k, 'v>` (pairs) | `toList`; `Array.ofList (toList c)` until 0024's `Buffer.push` makes it one pass; a `fold` of `add` |

Argument order is F#'s (function first, collection last), so `xs |> Iter.fold (+) 0` reads
as `List.fold` does. The functions are small and inline; after step 4 their lambdas are in
place too, so `Iter.exists` over a list is the cursor loop with the predicate in it.

**List expressions** ([0005](0005-ergonomics.md)) over a source that is a list, an array or
a range keep their fused pipelines; over any other `Iter` they lower through `Iter.forEach`
into a loop that builds the list in order, so `[ for (k, v) in m -> k ]` is one walk of the
map. **Fusion over `Iter` pipelines** (`Iter.map`, `filter` as stages) is later: lazy
stages are `Seq`'s, and phase 10 brings them.

### Order of implementation

1. **Traits with several parameters:** parser, AST, kinds with parameters, hover, `declareImpl`,
   resolution with the determined parameter. The prelude declares `Iter` with impls for
   `list`, `array`, `Buffer`, `string` and `option`; `Iter.zs` holds the functions and
   `Range`. Tests `tests/iter/*.zs`, with `.err` files for the diagnostics below. `for` is
   untouched at this step, so the suite stays green throughout.
2. **`for` over the trait:** the lowering, the compiler's lambda, the inliner's addition, and
   the exit tests: `tests/iter/map_for.same-ir` against `Map.iter`, the array, list and
   string loops with no allocator call, and the host benchmarks' 5% guard (the versioning
   pass learns the `while` shape if they say so). The four hard-coded cases leave `Typer`.
3. **The `ref` fallback** in `Lift`, with a test of a recursive user impl under an assigning
   body, and its allocation shown by [0011](0011-debug-info-profiles-traces.md)'s hints.
4. **The rest of the library:** `Map`, `Set`, `HashMap` impls; `Map.iter`, `toList`, `keys`,
   `values`, `Set.toList` over `forEach`; the builders' `forEach`; the `ofIter` functions; the
   reference pages and the guide's loops ([basics](../guide/02-basics.md),
   [collections](../guide/05-collections.md), [traits](../guide/06-traits.md)); the Cortex-M0+
   build of Core (track S's exit test).
5. **Later arrivals:** `span` with [0003](0003-spans-and-slices.md), list expressions over
   `Iter` with [0005](0005-ergonomics.md), `Seq` with phase 10.

## Drawbacks

- **One more rule about traits.** "The first parameter dispatches" is a sentence the guide's
  traits chapter must teach, and `Iter<'c, 'a>` reads differently from `Show<'a>`. It's one
  sentence, and Haskell's functional dependencies and Rust's associated types teach the same
  thing with more machinery.
- **`forEach`'s shape is for the compiler.** Returning `true` to continue is unusual next to
  `List.iter`; most programmers never write an impl, and the ones who do copy nine lines.
- **A tree is easier to walk recursively** than with an explicit path, and the recursive impl
  is the slow one. The library's own impls take the cost once; a user's recursive impl works
  and is as fast as today's `Map.iter`.
- **The inliner gets an exception** (size doesn't limit a `forEach` impl), and `Lift` a
  fallback it never needed. Both are a few lines, in the passes whose job they are.
- **`Iter.fold` allocates a `ref`** per call. `List.fold`, `Array.fold` and `Map.fold` stay
  the fast folds for their types; the generic one is for generic code, and a later Simplify
  rule can remove the cell (*Unresolved questions*).
- **`HashMap`'s order is unspecified,** which a `for` makes easier to depend on by accident
  than `HashMap.toList` did. The reference page says so.

## Alternatives

- **Pull iterators:** `next : unit -> option<'a>` on an iterator object, as C#'s enumerators
  and Rust's `Iterator`. Each needs a mutable cursor (a heap object, or a `ref`) per loop,
  per-element state for trees (a stack the iterator owns), and a generator can't be a pull
  iterator without a coroutine, while a push `Seq` is a handler and frees what it holds when
  the consumer stops (0002). Rust pays for pull with lifetimes and a `Peekable` ecosystem;
  Z# has nothing to spend there. Not chosen; `Seq.zip` is the one operation that's cheaper
  with pull, and it's rare.
- **Per-module `iter` functions only,** which is what exists. `for` can't use them, generic
  code can't abstract over them, and every collection grows a `toList`. Not chosen: it's the
  situation in *Motivation*.
- **Type families or associated types** (`type Elem` inside the impl, Rust's `Item`). The same
  information as the second parameter, as a type-level function the checker normalizes during
  unification, with the kinds and the pretty-printer learning it. The dispatch rule gets the
  same result at impl lookup. Not chosen: heavier for one use.
- **Closures per element without an inlining guarantee,** F#'s model: `for` calls the body
  through a function value, and the optimizer does what it can. Measured against today's
  loops it's a call and a closure per loop, and the guarantee is the reason to make `for` a
  trait call at all. Not chosen; the `.same-ir` test is the contract.
- **Keep the four hard-coded cases and use the trait for the rest.** Two mechanisms, two
  loops for `Map.iter` and `for`, and no `for` over a type variable. Not chosen.
- **A `break` keyword,** or `forEach`'s `bool` surfaced in `for`. Not F# syntax (decision 34),
  and the exit forms exist as functions; a `break` inside the lowered lambda would need a
  non-local exit. Not chosen.
- **An error when a recursive impl meets an assigning body,** instead of the `ref` fallback.
  Simpler for the compiler; it makes the program's own tree types second-class in `for`
  loops, with an error the newcomer programs of the third review would collect. Not chosen.
- **A one-parameter trait over the element,** `trait Iter<'a>`, with the collection as the
  method's own type variable. Then `forEach`'s collection type isn't the trait's parameter and
  nothing dispatches on it. Not possible; it's why the trait has two.

## Compatibility

- **Not a breaking change.** `for` over a list, an array, a `Buffer` or a string keeps its
  meaning, order and cost; over anything else it was an error. A program with its own `Iter`
  trait or `Iter` module shadows the prelude's in its own files (a module's names come first,
  DESIGN §2.1), and `for` names the prelude's `Iter.forEach` by its full name.
- **An older compiler** stops at `trait Iter<'c, 'a>` and `impl Iter<Map<'k, 'v>, 'k * 'v>`
  with `expected '>'` (`Syntax.fs:2311-2319`), and at a `for` over a map with `'for ... in'
  needs a list, an array or a string, not Map<string, int>`.
- **Compiled binaries:** none to consider. Packages are source (decision 27), and the trait
  leaves nothing in a binary: no tables, no enumerators, no runtime support.
- **The library:** `Iter`, `Range`, the impls and the `ofIter` functions are additions.
  `Map.iter`, `Map.toList`, `keys`, `values`, `count`, `Set.toList` and the builders'
  `forEach` are rewritten and keep their signatures and results, except that the builders'
  `forEach` now take any `Iter` where they took a list. Nothing in 0024's tables moves.
- **Microcontrollers:** the trait and every Core impl need no OS, build for Cortex-M0+ with
  the rest of Core, and add no code a program doesn't use.

## Pragmatics

### Diagnostics

| Situation | Error |
|---|---|
| `for` over a type with no impl | `for needs a collection: Point doesn't implement Iter. list, array, Buffer, span, string, Map, Set, HashMap, option and Range do; impl Iter<Point, <element>> = let forEach p f = … adds yours` |
| a generic function called at such a type | `total needs 'c : Iter<int>, and Point doesn't implement Iter` |
| one variable looped at two element types | `'c : Iter<int> and 'c : Iter<string> can't both hold: a type's elements have one type` |
| a loop variable used at the wrong type | `x is string * int, an element of counts, not string: write for (w, n) in counts` |
| an impl whose other parameter isn't determined | `impl Iter<Tree<'a>, 'b>: 'b isn't a type variable of Tree<'a>; the element type is made of the head's variables ('a, 'a * int, list<'a>)` |
| a second impl for one head | `Iter<Tree> is already implemented (Iter<Tree<'a>, 'a>); one impl per type: a wrapper type iterates differently` |
| the wrong number of parameters | `Iter takes 2 type parameters, Iter<Tree<'a>> gives 1: impl Iter<Tree<'a>, 'a>` |
| `forEach` missing or ill-typed in an impl | `impl Iter<Tree> is missing 'forEach'`; `forEach in impl Iter<Tree<'a>, 'a> must return bool (whether it ran to the end), not unit` |
| `break` | `unknown name 'break': a for loop runs to the end; to stop early use Iter.exists, Iter.tryFind or Iter.forEach` |
| a body that isn't `unit` | `the body of 'for' must be unit, not int; to collect values write [ for x in xs -> … ]` |

- **Recovery:** a `for` whose collection has no impl leaves the body checked with `x` at a
  fresh type, so the rest of the function still reports its own errors; an impl with a wrong
  `forEach` registers the trait so uses of it aren't reported twice.

### Tooling

- **Hover:** `x` in `for (w, n) in counts do` shows `w : string`, `n : int`, the types the impl
  determined; a generic function shows `total : 'c -> int when 'c : Iter<int>`, from the
  constraints text the server already has; `forEach` in an impl shows the trait's `///` doc.
- **Completion:** after `Iter.`, the functions; in an impl body, `forEach`; after `impl Iter<`,
  the types with impls aren't listed today (completion isn't scope-aware) and needn't be.
- **Definition and references:** definition on `forEach` in an impl goes to the trait; on a
  call of `Iter.fold` to `Iter.zs`; references on the trait's method list the impls.
- **Diagnostics while editing:** the table above as it's typed, with no build; a `for` over a
  parameter adds the requirement to the function's hover at once.
- **Inlay hints:** the loop variable's type when the collection is a parameter or a call
  (`for x in xs` gets `x: string * int`), as `let` bindings get theirs.
- **Grammar:** `trait_declaration` takes `type_parameters` where it takes one `type_variable`
  (`grammar.js:171-172`), and `impl_declaration` a comma-separated list after the head
  (`grammar.js:177`); `for` is unchanged. Pinned for Zed as grammar changes are.
- **`zs fmt`** has nothing new (the token layout covers commas); **`zs doc`** writes
  `docs/reference/Iter.md`, and each type's page says "implements `Iter`" with its order.
- **Debugging:** a `for` body keeps its lines; the impl's loop has the library's, as any
  inlined code does under `-g`.

### Performance

- **Existing loops:** lists, arrays, `Buffer`s and strings compile to the loops they compile to
  today, from the library's impls instead of the checker's hard-coded ones; the exit tests
  check it, and the host benchmarks' 5% guard holds it.
- **New loops:** a `for` over a `Map`, a `Set` or a `HashMap` is one loop with the body in
  place and nothing allocated per element (the map's path list reuses its cells). A `for` over
  a `Seq` is the generator's loop (phase 10).
- **The fallback:** a recursive or local-function impl costs a closure call per element and,
  for a body that assigns outer mutables, one `ref` per such variable per loop run. 0011's
  allocation hints show it at the loop, and `zs build --stats` counts it; no Core impl hits it.
- **Generic functions:** `Iter.fold` and `tryFind` allocate one `ref` per call; `iter`,
  `exists`, `forall`, `length`, `toList` and the `ofIter` functions allocate nothing beyond
  their results.
- **Compile time and code size:** an impl's loop is copied per `for` site (the map's is about
  50 nodes), as today's lowering copies a loop per site; a body is never copied. The inliner's
  addition applies to `forEach` calls only.
- **Microcontrollers:** the same code at `-Os`; nothing in the runtime.

### Scaling

| Dimension | Typical | Upper bound |
|---|---|---|
| impls of `Iter` in a program | the library's 10, and 0–3 of the program's | 1,000: lookup is one dictionary read per `for`, by head constructor |
| elements per loop | 10–10,000 | unbounded; linear, nothing allocated per element |
| `for` sites per module | 20 | 5,000: a 50-node loop copied per site |
| nesting depth | 2 | 20: each level inlines its impl, none makes a closure |
| nodes in a `for` body | 10–100 | 10,000: applied in place at one site, never copied |
| other parameters of a trait | 1 (`Iter`) | a handful: the rule doesn't limit the count |

### Culture-aware formatting and parsing

- **Nothing is formatted or parsed.** The trait touches no text.
- **Strings iterate by code point,** decoded from UTF-8 (`String.decodeAt`), as `for c in s`
  does today; grapheme clusters and locale-aware segmentation are a package's.
- **`Map` and `Set` order is `Ord`'s** (ordinal for strings, decision 10), never a collation.

## Unresolved questions

1. **`forEach`'s result:** `bool` (this proposal: one shape, `true` from `for` folds away)
   against a `tryFind` form, `'c -> ('a -> option<'b>) -> option<'b>`, which gives `tryFind`
   and `exists` without a `ref`. The option form needs a type variable of the method's own,
   which trait methods don't have today.
2. **`for (k, v) in m`:** patterns, as the parser already does (this proposal), against a
   dedicated form such as F#'s `for KeyValue(k, v) in m`. Nothing to add.
3. **Collecting:** functions per type (`List.ofIter`, `Set.ofIter`, …; this proposal) against
   a `Collect<'c, 'a>` trait with one `ofIter`. A collect trait dispatches on its result type,
   which HM infers from use and may never settle at the call: decision 49's problem again.
4. **Ranges as values:** a `Range` record built by a literal (this proposal) against `a .. b`
   as an expression, which isn't F# outside `[ ]` and `for` and so needs decision 34's
   discussion; 0005 keeps `[ a .. b ]` as `List.init`.
5. **`dyn Iter<int>`:** not in this proposal; the alternative is `dyn` for a multi-parameter
   trait whose other parameters are written, when a heterogeneous collection of iterables
   turns up.
6. **A non-escaping `ref` as a local:** a Simplify rule that would make `Iter.fold`, `tryFind`
   and the `for` fallback allocation-free; this proposal measures first and adds it if the
   generic functions show up in profiles.
7. **A new decision row,** numbered by the coordinator, for the dispatch rule: "a trait's
   first parameter dispatches; its other parameters are determined by the impl, one impl per
   head type".

## History

- **2026-10-23:** built before `compiler/`, with 0025's ambient rows for `forEach`'s body. The exit test compares `main`'s instructions with `Map.iter`'s (sorted, locals' names aside), since one `dup` lands a line apart and the two programs keep different helper copies; an impl must be declared before the code that loops over its type, as other explicit impls are.
- **2026-10-22:** drafted from track S item 1 ("needs design first"), DESIGN §3's one-parameter
  traits, the `ForIn` lowering in `Typer.fs`, and the agreements with 0002, 0003 and 0005.
