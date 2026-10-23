# Proposal 0025: reading effect rows

| | |
|---|---|
| **Status** | Draft |
| **Decided at** | a design review with 0017, before the rewrite starts: 0017's `forEach` needs the trait-method rule, the printed form is part of the suite both compilers must pass, and every signature written with a row costs more to change later |
| **Builds** | the F# compiler first (the printer, one rule in the checker, hover and `zs doc`), then phase 11's `Types/Ty.show` and `Lsp` carry it over |
| **Rests on** | decision 23 and [0002](0002-effect-handlers.md) (rows, scoped labels, the empty rows of `share<F>`, callbacks and trait methods); [DESIGN §6.1](../../DESIGN.md#61-effect-handlers-phase-10-v3) |
| **Related** | [0017 iteration](0017-iteration.md) (`forEach`'s body), [0020 the compiler in Z#](0020-self-hosting.md) (the printer is written twice if this waits), [0021 warnings](0021-warnings.md) (the diagnostic text), [0019 the syntax tree](0019-syntax-tree.md) (hover) |

- [ ] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

A function's own row variable is not shown where it only says "this function performs what the
functions it is given perform": `List.iter : ('a -> unit) -> list<'a> -> unit`, not
`('a -> unit / 'e) -> list<'a> -> unit / 'e`. An arrow without a row in argument position reads
as that ambient row, as Frank's ambient ability does and as Unison accepts in a signature; an
argument that must be pure shows `/ <>`, so the rare thing is the explicit one. The same rule
makes a trait method's function arguments ambient, which [0017](0017-iteration.md)'s `forEach`
needs. Hover and `zs doc` add one line in words derived from the type ("handles `Gen<'b>` from
`f`, performs `Gen<'b>`"), and errors print types through the same printer as hover.

## Motivation

- **The common case is noise.** Every higher-order function in the library carries `'e` twice: `List.map : ('a -> 'b / 'e) -> list<'a> -> list<'b> / 'e`, `Seq.fold : ('a -> 'b -> 'a / 'e) -> 'a -> Seq<'b> -> 'a / 'e`, `Throw.catch : (unit -> 'a / <Throw<'b> | 'e>) -> result<'a, 'b> / 'e` (`docs/reference`). The variable says the same thing each time, and a newcomer reads it as a type parameter to supply.
- **The rare case is invisible.** `Seq.map` requires a pure function (`lib/core/Collections/Seq.zs:130`, `f: 'a -> 'b / <>`), and the reference prints it as `Seq.map : ('a -> 'b) -> Seq<'a> -> Seq<'b>`: the same as `List.map` after the tail is dropped, though one takes any function and the other only a pure one.
- **Two `Gen`s need a sentence.** `doubled` ([tests/effects/handlers.zs](../../tests/effects/handlers.zs)) hovers as `(unit -> 'a / <Gen<'b>, Gen<'b> | 'e>) -> 'a / <Gen<'b> | 'e>`: scoped labels say it handles one `Gen` of `f`'s and performs one, which the reader must know to see.
- **0017's `forEach` as written is pure in its body.** `abstract forEach : 'c -> ('a -> bool) -> bool`: in a trait, an arrow without a row has none (`Typer.fs:1212`: `tparams.IsSome`), so once `for x in c do body` lowers to `Iter.forEach`, `for x in m do Throw.throw e` over a `Map` is an error. The ambient reading of argument arrows is what makes it check.
- **Without it:** rows stay Koka's, written in full; the printer, the guide's chapter 16, the reference and the `.err` files are the F# compiler's today and are written again for the Z# one, and 0017 adds a row rule of its own.

## Detailed design

### The ambient row

In a function type `p1 -> … -> pn -> r / R`, the tail variable of `R` is the function's **ambient
row**. An occurrence of it is *ambient* when it is the tail of the row of an arrow that is the
function's own last arrow, or the last arrow of a function type in argument position: a parameter
type, or a parameter type of such a function type, at any depth. Inside a type constructor's
argument, a tuple or a record (`list<unit -> unit / 'e>`, `(int -> int / 'e) * int`) an occurrence
is not ambient.

- **Printing:** when every occurrence of the ambient variable is ambient, it is not printed: `/ <A | 'e>` prints as `/ A`, `/ 'e` as nothing. Any other row variable, and the ambient one where it occurs elsewhere, prints as today.
- **Argument arrows without a row print `/ <>` when the row is empty.** The empty own row of a function still prints as nothing (`int -> int`), as does an arrow inside a type constructor, a record or a tuple: there, no row means none, as written. `share<F>`, `callback<F>` and `fnptr<F>` print as today: their kind says the arrow is pure.
- **Today's rule** that a variable mentioned once is hidden (`Core.fs:321`) goes: `let ignore (f: int -> int) = 0` prints `(int -> int / 'e) -> int`, since `(int -> int) -> int` would now say that `ignore` performs `f`'s effects.

| Today | Proposed |
|---|---|
| `List.iter : ('a -> unit / 'e) -> list<'a> -> unit / 'e` | `List.iter : ('a -> unit) -> list<'a> -> unit` |
| `Throw.catch : (unit -> 'a / <Throw<'b> \| 'e>) -> result<'a, 'b> / 'e` | `Throw.catch : (unit -> 'a / Throw<'b>) -> result<'a, 'b>` |
| `doubled : (unit -> 'a / <Gen<'b>, Gen<'b> \| 'e>) -> 'a / <Gen<'b> \| 'e>` | `doubled : (unit -> 'a / <Gen<'b>, Gen<'b>>) -> 'a / Gen<'b>` |
| `Seq.map : ('a -> 'b) -> Seq<'a> -> Seq<'b>` | `Seq.map : ('a -> 'b / <>) -> Seq<'a> -> Seq<'b>` |
| `Task.map : ('a -> 'b) -> Task<'a> -> Task<'b>` | `Task.map : ('a -> 'b / <>) -> Task<'a> -> Task<'b>` |
| `Parallel.for : int -> int -> share<int -> unit> -> unit` | unchanged |
| `pair : (int -> int / 'e) -> (int -> int / 'e) * int` | unchanged: `'e` occurs in the result type |

### Reading an annotation

- **Parameters:** unchanged. An arrow without a row in a parameter's annotation is already a fresh row variable (`Typer.fs:1212`), unified with the function's own row where the body calls it, and `/ <>` already means pure. Written `/ 'e` keeps its meaning and becomes unnecessary in the common case; the formatter doesn't remove it.
- **Type definitions:** unchanged. A field or a case of function type has the row it writes, none when it writes none: a type can't be polymorphic in a row it doesn't name.
- **Trait methods, the one change:** in a method's signature, the arrows without a row in argument position and the method's own last arrow share one fresh row variable, the method's ambient. A method performs what the functions it is given perform and nothing of its own (phase 10's rule that a method's own row is empty stays for what it declares: `abstract log : string -> unit / Log` remains an error). Each impl is checked against the instantiated signature, and monomorphization instantiates the row as it does a type, so a static call pays what the row costs and a pure call nothing.
  - **`dyn` closes the row:** a call through `dyn Trait` has no instance to carry evidence, so the ambient is empty there: `forEach` through a `dyn Iter<int>` takes a pure body, and the error names the `dyn`, as `share<F>`'s does.
  - **0017:** `abstract forEach : 'c -> ('a -> bool) -> bool` then means what its users assume: `for x in m do Throw.throw e` checks, with `Throw` on `forEach`'s instance.

### In words

Hover and `zs doc` add a line under the signature, derived from the type by one function
(`Ty.explain`), and only when a row has labels:

```
doubled : (unit -> 'a / <Gen<'b>, Gen<'b>>) -> 'a / Gen<'b>
  handles Gen<'b> from f, performs Gen<'b>

Throw.catch : (unit -> 'a / Throw<'b>) -> result<'a, 'b>
  handles Throw<'b> from f

Seq.map : ('a -> 'b / <>) -> Seq<'a> -> Seq<'b>
  f must perform nothing
```

- **Derivation:** for each parameter of function type, the labels of its row beyond those of the own row (as multisets, in order) are *handled from* it; the labels of the own row are *performed*; an empty argument row is *must perform nothing*. Parameter names come from the definition; a lambda's parameters show as `the argument`.
- **The type can't say more:** `performs Gen<'b>` covers both an operation the function performs itself and one it passes on from `f`'s second `Gen`; the line says what the type says.

### One printer

`Ty.show` is the one function behind hover, inlay hints, `zs doc`, the formatter's signature
output and every diagnostic that prints a type, so an error and the hover over the same name
read the same. The `full` form (symbol names, lookup keys, `Core.fs:318`) keeps every row: it is
not read by people, and two instances that differ in a row must have two names.

### Order of implementation

1. **The printer,** in `Core.showWith`: the ambient rule, `/ <>` on argument arrows, the lone rule removed. Regenerate `docs/reference` (`tests/reference.sh`) and the `.err` and `.expected` files that print a function type; the guide's chapter 16 gets the new `List.iter` line and a paragraph on `/ <>`.
2. **Trait methods:** `Typer.fs:1212`'s `tparams.IsSome` branch gives a method's argument arrows and its own arrow one fresh row variable; `dyn` instantiates it empty. Tests: a trait with a function parameter called with a throwing body, and the same through `dyn` as an `.err`.
3. **`Ty.explain`** in hover and `zs doc`, with `tests/lsp/effects.sh` checking the line for `doubled` and `Throw.catch`.
4. **Phase 11** writes `Types/Ty.show` and `explain` once, to these rules.

## Drawbacks

- **Two readings of a bare arrow:** ambient in argument position, pure inside a type definition. Frank has the same split (a type's components are not argument positions) and the guide says it in one sentence; the alternative, rows written everywhere, is what this proposal is against.
- **A regenerated suite:** every printed function type with a connecting `'e` changes in `docs/reference` and in the expectations that show one; one commit, before any of them is written for the Z# compiler.
- **`dyn` is the one place the ambient is lost,** and the error has to teach that.

## Alternatives

- **Rows written in full,** Koka's form, as today. Not chosen: the common case costs two tokens per higher-order function and the rare case shows nothing.
- **Hiding only in hover, not in `zs doc` or errors.** Not chosen: three forms of one signature.
- **Trait methods fully effect-polymorphic,** with declared own rows (`abstract log : string -> unit / Log`). Not chosen now: it reopens phase 10's rule for impls' own effects and `dyn` dispatch; the ambient covers 0017 and every higher-order method without it.
- **Keeping the lone rule** (hide any variable mentioned once). Not chosen: under the ambient reading a hidden variable would claim an effect flow that isn't there.

## Compatibility

- **Programs:** no program that checks today stops checking. A trait method with a function parameter accepts effectful arguments where it required pure ones (more programs check); a `dyn` call keeps requiring them. Annotations keep their meaning, `/ 'e` included.
- **Older compilers:** the sources this changes print types differently and accept more through traits; a program written against the new trait rule fails on an old compiler at that call, as any program using a newer rule does.
- **The library:** `lib/`'s eight `/ <>` stay and now show; nothing else is written with a row.
- **Grammar and editors:** no syntax changes; the tree-sitter grammar already parses `/ <>`.
- **Phase 11:** the suite the Z# compiler must pass carries the new forms, so `Ty.show` is written once.

## Pragmatics

### Diagnostics

| Situation | Error |
|---|---|
| an effectful function given where `/ <>` is written | `this function performs Throw<string>, but Seq.map's f must perform nothing (its type says 'a -> 'b / <>): handle it inside, or use List.map` |
| an effectful body through `dyn` | `this performs Throw<string>, but forEach is called through dyn Iter<int>, where its arguments must perform nothing: call it on the value's own type, or handle it inside` |
| a method declaring its own row | unchanged: `a trait's method performs nothing of its own; its arguments' effects are its row` |

### Tooling

- **`zs lsp`:** hover shows the signature in the new form and the line in words; inlay hints before `=` show labels only, as they do now that the variable is hidden; completion's detail is the signature.
- **`zs doc`:** the same two lines per function; `docs/reference` is regenerated.
- **`zs mcp`:** `type_at` returns the signature as hover shows it.
- **`zs fmt`:** unchanged; it doesn't rewrite annotations.

### Performance

None at run time: a printing rule, and a row variable on trait methods that monomorphization instantiates as it does today for functions (an empty instance costs nothing, phase 10's exit test). Checking: one more row variable per trait method signature.

### Scaling

| Dimension | Typical | Upper bound |
|---|---|---|
| labels in a shown row | 0–2 | as many as the function performs; the line in words lists them in the row's order |
| parameters of function type per signature | 1 | a line in words per parameter with labels |

### Culture-aware formatting

The line in words is English, as every message is; labels print as `Ty.show` prints them.

## Unresolved questions

1. **`dyn` and the ambient:** closed to empty (chosen), or evidence carried through the vtable at run time, as Koka's dynamic evidence allows, which would let a `dyn Iter` take a throwing body at the cost of an evidence parameter on every method.
2. **The words:** "handles X from f, performs Y" (chosen), or Koka's vocabulary ("masks"), or none and only the signature.
3. **The lone rule for non-ambient variables:** removed (chosen); the review may prefer to keep hiding a variable in a result type's arrow, where no effect flow can be read into it.

## History

- **2026-10-23:** drafted from the phase 10 hover forms (`docs/reference`, `tests/lsp/effects.expected`), `Core.showWith`'s lone rule (`Core.fs:316-372`), `Typer.fs:1212`'s treatment of arrows without a row, and 0017's `forEach`.
