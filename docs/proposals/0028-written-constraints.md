# Proposal 0028: written constraints

| | |
|---|---|
| **Status** | Approved in principle (2026-11-11); not built |
| **Decided at** | not yet: track G's item 6 ([ROADMAP](../../ROADMAP.md#language-g)), found by the specification |
| **Builds** | after 0.7, before the first-party packages (track K) publish signatures |
| **Rests on** | [DESIGN §2.1](../../DESIGN.md) (inference, annotations) and §4 (traits: requirements are inferred); decision 57 (a requirement carries a trait's other parameters, `'c : Iter<int>`) |
| **Related** | track G's items 7 (local functions have one type) and 9 (supertraits), which this doesn't decide; [0025 reading effects](0025-reading-effects.md) (how a type is shown) |
| **Changes** | DESIGN §2.1 and §4; the specification's §3 and §4.1; `zs doc` and hover print what can now be written |

- [x] Approved in principle (2026-11-11; open question 1 answered: an integer literal is allowed at a rigid `'a : Num`, a float literal isn't for now)
- [ ] Discussion
- [ ] Implementation

## Summary

A function's requirements on its type variables are inferred and can't be written, and a type
variable in an annotation isn't held generic. This proposal gives both a syntax, F#'s:

```fsharp
let largest (xs: list<'a>) : 'a when 'a : Ord = List.reduce max xs
let describe (x: 'a) (y: 'b) : string when 'a : Show and 'b : Show and 'b : Eq = …
```

and one rule: **a type variable written in a declaration's annotations is rigid.** The body
must work for every type that meets the written constraints, so an annotation that says more
than the body allows is an error where it's written.

## Motivation

Both halves were reproduced with `zs 0.7.0`:

- `let f (x: 'a) : 'a = x + 1` compiles. `'a` was unified with the literal's kind, so `f` is a
  function on numbers that says it's a function on anything. The annotation checked nothing.
- There's no way to write `'a : Show`. A package's public function can't state its own type:
  the reader gets it from hover or `zs doc`, which print a form the language can't parse back.

What it costs later: every package published before this has signatures that are whatever
inference gave them. A change to a body that drops generality (or adds a requirement) changes
the public type silently, and the break shows in a dependent's build, not the package's. Rust
and F# both let the signature be the contract; this is the piece Z# lacks to do the same.

## Design

**Syntax.** After the result type of a `let`, a member, a trait method or an `extern`:
`when` *constraint* { `and` *constraint* }, where a constraint is `'a : Trait` or
`'a : Trait<T, …>` for a trait with several parameters (decision 57: `'c : Iter<int>`). `when`
is already a keyword (guards), and no expression can follow a result type, so there's no
ambiguity. On a declaration without a result type the clause follows the last parameter.
Types (`type Box<'a> when …`) and impls take none: an impl's requirements stay inferred, as
its methods' bodies decide them.

**Rigid variables.** Each `'a` in a declaration's annotations is a variable the body can't
refine: unifying it with a type, another written variable or a kind it doesn't have is an
error at the expression that tried.

```text
f.zs:1:27: error: 'a is any type here, but '+' needs 'a : Add: write `when 'a : Add`, or a type
 1 | let f (x: 'a) : 'a = x + 1
   |                        ^
```

A requirement the body needs and the clause lacks is that error; a constraint the body doesn't
need is allowed (a signature may promise less than the body could). A declaration with no
written variables is inferred whole, as today: nothing changes for code without `'a`.

**The numeric kinds.** A literal's type is a kinded variable (`kInt`, `kFloat`, `kNumeric`),
which no trait names. `x + 1` at a rigid `'a` needs "a type an integer literal can be". The
proposal: the prelude traits `Num` and `Add` stay what's written, and a literal at a rigid
`'a : Num` is allowed, converted as at any numeric type. A float literal needs a narrower
constraint; see the open questions.

**What's shown.** `zs doc`, hover and errors print a generic function's type with the same
clause, so what's shown can be pasted as an annotation. A test checks it round-trips for the
library's public functions.

**The editor.** The check is the checker's, so it's live. A code action writes the inferred
signature, with its clause, on a function (E2b's "add an annotation").

## What breaks

Code that writes `'a` and relies on it being refined: `let f (x: 'a) : 'a = x + 1`. The fix is
in the message. The library and `src/` are checked first; the count of such sites decides
whether a release warns before it errors.

## Alternatives

- **Inferred only, as today.** Keeps the language smaller; leaves a package without a contract.
- **Flexible variables that only name a type** (OCaml's `'a` in an annotation). It's today's
  behaviour, and what G6 reports as the defect.
- **Rust's `where` or bounds in the angle brackets** (`<'a : Ord>`). Z# reads as F#, and
  functions have no type-parameter list to put them in.

## Open questions

1. **Float and integer literals at a rigid variable:** is `Num` enough for `x + 1`, with a
   separate trait (or none) for `x * 0.5`? Or do literals stay unavailable at rigid variables,
   so generic numeric code writes `Num.one`/`Add.zero`?
2. **A wildcard for the rest:** F#'s `_` in an annotation (`list<_>`) stays inferred. Should a
   clause allow "and whatever else is inferred", or is a written signature always complete?
3. **Effect rows:** a written row variable is already rigid in practice; does this proposal
   state it, or leave rows to 0025?
4. **Item 7 (local functions):** if they generalize later, the same rule applies to their
   annotations. Nothing here blocks either answer.

## Exit tests

- `tests/constraints.zs`: the summary's two functions, a multi-parameter trait's constraint,
  a member and a trait method with a clause.
- `tests/err_rigid.zs`: `let f (x: 'a) : 'a = x + 1`; a body needing `Show` under `when 'a : Eq`;
  two written variables unified.
- `tests/doc/roundtrip.sh`: every public signature `zs doc` prints for Core and Std parses and
  checks as that function's annotation.
- The specification's §14 loses "written constraints" from its open questions.
