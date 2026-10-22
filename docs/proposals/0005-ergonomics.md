# Proposal 0005: ergonomics: the F# forms of phase 9.6

| | |
|---|---|
| **Status** | Approved in principle |
| **Decided at** | the phase 9.6 design review (decisions 54 and 55; the rest in DESIGN §2.1 as planned) |
| **Builds** | phase 9.6 ([ROADMAP](../../ROADMAP.md#phase-96-ergonomics-spans-and-c-structs)) |
| **Rests on** | decisions 19 (`?`), 34 (new syntax needs a discussion: compound assignment had it), 36 (evaluation order), 41 (lambda arguments typed last), 54 (generic constants), 55 (compound assignment) in [DESIGN §13](../../DESIGN.md#13-decisions) |
| **Related** | [0003 spans](0003-spans-and-slices.md) (slices), [0006 anonymous records](0006-anonymous-records.md) (phase 12's deferred forms) |

- [x] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

Six forms an F# programmer reaches for in the first week, each lowered to what the language
has, so the optimizer sees nothing new:

| Form | Meaning |
|---|---|
| `let empty : Map<'k, 'v> = MapLeaf` | a generic constant: `Map.empty` at any type, no `()` |
| `x?` in a function returning `option` | `Some v` gives `v`; `None` returns early |
| `total.Value += i * i` | compound assignment to any place `<-` assigns, evaluated once |
| `function \| p -> … \| q -> …` | `fun x -> match x with …` |
| `[ for x in xs do if p x then yield f x ]` | a list expression, lowered to a fused pipeline |
| `f x?` | `?` applies to the whole call; its errors point at the `?` |

They come before phase 11 so the compiler's Z# is written in them once (ROADMAP).

## Motivation

Each replaces code written by hand today: `Map.empty ()` with a unit nobody wants;
`match x with Some v -> v | None -> None` around every optional step; `a.[i] <- a.[i] + 1`
with the index written twice (and evaluated twice); `fun x -> match x with …` where the match
is the whole lambda; `List.filter p xs |> List.map f` where the comprehension says it
directly. None needs a runtime, so each passes decision 39's rule.

## Detailed design

### Generic constants

- **Rule:** a top-level constant (DESIGN §2.1: built from literals, operators, conditionals, constructors, records, tuples, conversions and other constants) whose type has type variables is generalized, as F# generalizes syntactic values. It's inlined at each use at that use's type, as a generic function of no arguments is monomorphized. A constant is a syntactic value, so the generalization is sound without a value restriction.
- **Not generalized:** other top-level values (computed at startup) and `let mutable`; a generic one of those is an error that says to make it a function.
- **The library:** `Map.empty`, `Set.empty` and `HashMap.empty` become values; the `()` goes, and `examples/` and the guide follow.

### `?` on `option`

- **Rule:** inside a function whose result type is `option<_>`, `e?` on an `option<'a>` is `'a`, returning `None` early on `None`. The enclosing function's declared or inferred result type decides which `?` it is; a `result` under `?` in a function returning an `option` (or the reverse) is an error naming the conversion (`Result.toOption`, `Option.toResult`). In a lambda, the lambda's own result decides.
- **Lowering:** as `?` on `result`: a match that returns early, so after inlining and known constructors it builds no `option`.

### Compound assignment

- **Operators:** `+=`, `-=`, `*=`, `/=`, `%=`, `&&&=`, `|||=`, `^^^=`. **Places:** a `let mutable`, a `ref`'s `.Value`, an array or `Buffer` element, a `fixed` element, a field of a `let mutable` record, nested (`p.pos.x += 1`), and a `span`'s owner's `Buffer` through its window.
- **Evaluated once:** `a.[f ()] += 1` calls `f` once; the receiver and the index are bound to temporaries, then the read, the operation and the write happen in that order. `s += "x"` on a string is `s <- s + "x"`; reuse makes the loop linear when `s` is unique (track S item 4's measurement).
- **Types:** the operator's trait (`Add` for `+=`, `Num` for `-= *= /= %=`, the bitwise ones on integers and SIMD vectors). Overflow traps as for `+`.
- **Statement only,** like `<-`; not an expression.
- **Decision 34:** not F# syntax, so it had the discussion; decision 55 records it.

### `function`

- **Rule:** `function | p1 -> e1 | p2 -> e2` is `fun x -> match x with | p1 -> e1 | p2 -> e2`, with a fresh `x`. Typed as a lambda, so it's typed after the call's other arguments (decision 41) and gets its parameter type from the call: `xs |> List.map (function Some x -> x | None -> 0)`.
- **Exhaustiveness** as for `match`.

### List and array expressions

- **Forms:** `[ for x in xs -> e ]`, `[ for x in xs do if c then yield e ]`, nested `for`s, `let` inside, `match` and `if` with `yield` in branches, `yield! ys` to splice a list, and ranges `[ for i in 1 .. n -> e ]`. The same in `[| … |]` for arrays. `while` isn't included (F# allows it; a `while` that yields is a generator, which is phase 10's `seq { }`, [0002](0002-effect-handlers.md)).
- **Lowering:** to the pipeline forms fusion makes one loop of (DESIGN §9.1): a `for … ->` is `map`, an `if` is `filter`, a nested `for` is `collect`, `yield!` is `append`; a range is `List.init`. So `[ for x in xs do if p x then yield f x ]` builds only its result, in place when `xs` is unique. Pure lambdas only, as fusion requires (decision 36); a body with effects lowers to a loop that builds the list in order.
- **Element type:** from the `yield`s, unified.

### `?`'s scope and errors

- **`f x?`** applies `?` to the whole call `f x`, not to `x`; `(f x)?` is the same. The guide says so.
- **Errors** about `?` (in a function returning `unit`, on a non-`result`) point at the `?` itself. Today's caret is at the start of the `let`.

### Order of implementation

1. `?` on `option` and its error positions (the smallest, and the first an F# programmer meets).
2. `function`, compound assignment.
3. Generic constants and the library's empty collections.
4. List and array expressions over fusion.

## Drawbacks

- **Compound assignment is new syntax** that F# lacks; an F# programmer learns one thing more, and `zs fmt` must know eight more tokens. The alternative, writing the place twice, is the bug it prevents.
- **Generic constants** make a constant's type depend on its use; hover on `Map.empty` shows a scheme, not a type, which is what F# shows for `Map.empty` too.
- **List expressions' lowering** depends on purity: a body that prints lowers differently from one that doesn't, invisibly. The result is the same list either way.

## Alternatives

- **Leave `()` on empty collections:** what exists; the cost is one `()` per use and a question from every F# programmer.
- **`option { }` only** for optional steps: it exists; `?` is shorter for the common one-step case, as it is for `result`.
- **`x <- x + 1` only:** the place is written and evaluated twice.
- **`seq { }` for comprehensions** (F#'s general form): waits for phase 10 and is lazy; list expressions are eager and fused, and are F#'s own `[ … ]` syntax.

## Compatibility

- **Generic constants:** `Map.empty ()` stops compiling (`Map.empty` is a value): the one breaking change, in the library's own API, before any user has code. `zs fmt` could rewrite it; grep finds the uses.
- **`?` on `option`:** code that today gets an error gains a meaning; nothing that compiles changes.
- **Compound assignment, `function`, list expressions:** new syntax; nothing that parses today changes meaning. `+=` isn't a legal operator name today, so no custom operator collides.
- **Older compilers** reject each form at its line.

## Pragmatics

### Diagnostics

| Situation | Error |
|---|---|
| `?` on an `option` in a function returning `result` | `? on an option in a function returning result<_, _>: use Option.toResult, or option { }` |
| `?` in a function returning `unit` | `? needs the function to return a result or an option; this one returns unit` (the caret under `?`) |
| `+=` on something that isn't a place | `+= needs a place <- can assign: a let mutable, a ref's .Value, an element or a field` |
| `+=` with no `Add` | `+= on Point: Point doesn't implement Add` |
| a generic startup value | `a top-level value of type list<'a> must be a constant to be generic; make it a function, or give it a type` |
| a `yield` outside a list expression | `yield belongs in [ … ], [\| … \|] or seq { }` |

### Tooling

- **Hover** on a generic constant shows its scheme; inlay hints show a list expression's element type.
- **`zs fmt`** spaces the compound operators as `<-`.
- **The grammar** gains `function`, the compound operators, `yield`, `yield!` and `->` inside brackets.
- **Code actions** (track E, [0019](0019-syntax-tree.md)): "replace `match x with Some v -> v | None -> None` with `x?`".

### Performance

- **Existing code:** none.
- **New forms:** each lowers to what the optimizer handles already: `?` to a match simplified away, `+=` to a read and a write with temporaries, `function` to a lambda, list expressions to fused pipelines. The exit test: a list expression with a filter allocates only its result.

### Scaling

Nothing grows beyond the lists written; a list expression nests `for`s to depth 3 typically, 10 at most.

### Culture-aware formatting and parsing

None.

## Unresolved questions

1. **`?` in a lambda** inside a function: the lambda's own result type decides, as here; F# has no `?` to compare with. The alternative, the enclosing function's, can't be compiled (the lambda can't return from its enclosing function).
2. **`yield!` of an array in a list expression** (and a list in an array one): converted, or an error. Converted here.
3. **`+=` on `Atomic`** values: `Atomic.add` exists; sugar would hide a memory-order choice. Not here.

## History

- **2026-10-22:** drafted from DESIGN §2.1 and phase 9.6's scope.
