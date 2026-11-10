# Proposal 0029: leaving a loop

| | |
|---|---|
| **Status** | Implemented (2026-11-11): `src/Infer/Leave.zs`; not in computation expressions, and a range loop left early needs a literal step |
| **Decided at** | not yet: track G's item 12 ([ROADMAP](../../ROADMAP.md#language-g)), found by the specification |
| **Builds** | after 0.7 |
| **Rests on** | [DESIGN §2.1](../../DESIGN.md) (`?` returns early) and §4 (`for x in c do body` is `Iter.forEach c (fun x -> body; true)`: a `false` stops the loop); decision 57 (iteration); decision 5 (no unwinding) |
| **Related** | [0017 iteration](0017-iteration.md); [0002 effect handlers](0002-effect-handlers.md) (a stop disposes the `use` values it passes); track S's item 10 (`use` under effects) |
| **Changes** | DESIGN §2.1; the specification's §5 (expressions) and §14.2 (three reserved words); the grammar and the editors' keyword lists |

- [x] Approved in principle (2026-11-11, with the open questions answered: `return` in a lambda leaves the lambda; no labels and no `break` with a value; all three are errors in a computation expression for now)
- [ ] Discussion
- [x] Implementation (as designed, with three things the design didn't say: the three are written as a statement, a branch of an `if` or a `match`, or a `let`'s value, and are an error elsewhere; a `for` over a range left early becomes a `while`, so its step must be a literal; and `?` returns from the function only as a statement of a loop's body, since elsewhere a block's `?` gives the block its failure, which programs rely on. Measured: a linear search with `return` executes the instruction count of the same search as a recursive function, 2,629,174,671 for 2,000,000 searches of 1,000 elements)

## Summary

Z# has no `break`, `continue` or early `return`, and `?` inside a `for` body leaves the body,
not the function. This proposal adds the three, and makes `?` in a loop leave the function:

```fsharp
let firstError (lines: list<string>) : result<int, string> =
  let mutable total = 0
  for line in lines do
    if line = "" then continue
    if line = "end" then break
    total <- total + parse line?      // an Error leaves firstError
  Ok total

let find (xs: array<int>) (x: int) : option<int> =
  for i in 0 .. Array.length xs - 1 do
    if xs.[i] = x then return Some i
  None
```

## Motivation

A loop that stops early is written today as a recursive function, a mutable flag tested in a
`while`, or `Iter.tryFind` with the work folded into its predicate. Each works; none is what a
programmer coming from F#'s imperative side, C or Rust writes first, and the flag version is
what microcontroller code ends up with. F# itself lacks `break` and `return`, and it's among
its most asked-for features: this is a place where reading as F# isn't the goal.

The `?` case is a trap, not a gap: `parse line?` in a loop compiles, and an `Error` skips the
rest of that iteration and goes on. It should do what it does everywhere else.

## Design

**Meaning.**
- `continue` ends the current iteration of the innermost `for` or `while`.
- `break` ends the innermost loop. Loops are of type `unit`, so neither carries a value.
- `return e` ends the enclosing function (or lambda) with `e`; `return` alone is `return ()`.
  `e` has the function's result type.
- `?` in a loop body is `match … with Error e -> return (Error e)` (and `None` for an option).
- Each is of any type, as a panic is, so `if c then break` needs no `else`.

**Where they're allowed.** `break` and `continue` only inside a loop of the same function: not
in a lambda written inside the loop (`List.iter (fun x -> break)` is an error that says a
lambda is its own function). `return` anywhere in a function or lambda body, and it leaves the
innermost one. Inside a computation expression (`task { }`, `result { }`, `seq { }`) all three
are errors in this proposal: the builder's own `return` and `let!` are what leaves a block.

**Disposal.** Leaving passes over scopes. A `use` value bound in a scope that's left is
disposed, innermost first, as at the scope's normal end; this is the rule a stop already
follows (S10), and reference counts are dropped by Perceus as on any branch.

**Lowering.** No new Core node and no unwinding; the three desugar in the checker to what the
language already has, the way `?` does:
- In a `for` over `Iter`, the body is already a lambda returning `true`. `continue` is that
  lambda returning `true` from where it's written, `break` returning `false`: the statements
  after it become the other branch of its condition, which is `?`'s transform.
- In a `for` over a range and in a `while`, a compiler-made flag joins the loop's condition;
  `break` sets it and skips the rest of the body.
- `return e` inside a loop stores `e` in a slot, breaks every loop it's in, and the code after
  each loop returns the slot when it's set. Outside a loop it's `?`'s transform alone.

Since `forEach` is inlined and Simplify applies the body in place (DESIGN §4), the flags and
slots are locals LLVM's jump threading removes. The exit tests hold it to that.

**Syntax.** `break`, `continue` and `return` become keywords. `return` is contextual inside a
computation expression, where it keeps the builder's meaning. A program that uses any of the
three as a name is the break: `CHANGELOG.md` says to rename it.

**The editor.** The grammar, the three keyword lists (tree-sitter, TextMate, Rider), and `zs
fmt`. Each error above is the checker's, so it's live.

## Alternatives

- **`break` and `continue` only.** Smaller, and `return` is the one F# programmers least
  expect. But `find` above is the commonest early exit, and `?` in a loop needs `return`'s
  machinery whether or not the word exists.
- **A `Break` effect in the library** (`Throw`-like, handled by the loop). No syntax, but a
  handler per loop, an effect in every such function's row, and nothing for `while`.
- **A Core node for a labelled exit** (`CLeave`), lowered to a branch. Cleaner IR for nested
  loops and cheaper to compile, at the price of teaching Perceus, Lift, Evidence and the
  verifier a new control edge. Worth it only if the flags turn out to cost.

## Open questions

1. **`return` in a lambda:** leaving the lambda is the simple rule and Rust's. Kotlin leaves
   the enclosing function from an inlined lambda; Z# can't in general (the lambda may escape).
   Is the simple rule clear enough, or should `return` in a lambda be an error for now?
2. **Labels** (`break outer`): left out. A nested search is a function with `return`.
3. **`break` with a value** (Rust's `loop`): left out, since loops are `unit`.
4. **In computation expressions:** an error here. `seq { }` with `break` reads naturally
   (stop yielding); should a later proposal give builders a say?

## Exit tests

- `tests/loop_leave.zs`: the summary's two functions; `continue` and `break` in a `for` over a
  list, a map, a range and a `Seq`, and in a `while`; nested loops; `return` from two loops deep.
- `tests/loop_leave_use.zs`: a `use` value in a loop body is disposed on `break`, `continue`
  and `return`, under `ZS_LEAKCHECK=1` with nothing left.
- `tests/err_loop_leave.zs`: `break` outside a loop, in a lambda inside one, and in `task { }`;
  `return` of the wrong type; code after a `break` in the same block (unreachable).
- `bench/host`: a linear search with `return` executes C's instructions for the same loop
  with a `return`, within the suite's bound.
- `tests/fsharp_habits.zs` keeps passing: no existing program in the repository uses the three
  words as names, or the count is in the proposal before it's approved.
