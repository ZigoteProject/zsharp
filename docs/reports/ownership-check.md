# The ownership check: reference counting checked, not proved

**Date:** 2026-11-19.

**Question:** the reference counting pass (`src/Opt/Rc.zs`, Perceus with borrowing, reuse and
moves out of mutables) is the part of the compiler where a mistake makes safe code unsafe: a
drop too many is a use after free, one too few a leak. Can it be proved right, and is that the
way to harden it?

**Answer:** not the pass; its output. The pass is 1,000 lines and changes with every
optimization. What it must establish is small and doesn't change: every reference a function
gets is given away once on every path, and nothing is read once its last reference went. That
is a judgment on the pass's *output*, which a checker of 300 lines decides
(`Core.Check.owned`, run by `zs build --check-ir`, which `./test.sh` sets), and whose soundness
is proved once and covers whatever the pass becomes. The checker is built and runs in every
build of the suite. The proof is written for the judgment's core (`proofs/Ownership.v`, checked
by Rocq 9.3 with no axioms): a program the judgment accepts never touches a freed cell and
leaves none behind. What the proof's calculus leaves out is listed under *What it doesn't
cover*.

`src/ARCHITECTURE.md` said `Check` did this already. It checked that a `dup` or a `drop` named
a bound variable of its type, and no more.

## The judgment

A function's code is walked in the order it runs, with what it holds of each counted variable:

- **n**, the references of its own it has yet to give away. A parameter it owns, a `let` of a
  value, a join point's parameter and a reuse token start at 1; `dup` adds one; a use that
  takes the value (an argument, a field of a cell being built, the result, a `drop`) takes one,
  and must find one.
- **via**, where the variable is alive without a reference of its own: the caller (a borrowed
  parameter, a top-level value), or the variable it was read from (a pattern's variable is its
  scrutinee's; `let f = x.i` is `x`'s until `dup f`).
- A read that takes nothing (a scrutinee, a field, a closure applied, the array of
  `array.get#b`, an argument to a parameter the callee borrows) needs the variable **alive**:
  n above 0, or alive through `via`, however long the chain.

And:

- a `let`'s variable, a parameter and a token end at n = 0 (nothing leaks);
- the branches of an `if` or a `match` that don't end in a jump end holding the same, as do the
  jumps to one join point, and a loop's body leaves what it found;
- a guard changes nothing;
- `dropfields x keep I` takes `x`'s reference and gives one to each kept field's variable;
- a token is taken once, by a constructor built in it or by `free`;
- a `let mutable` holding a counted value is full, or moved out by `slot.take`, and only a
  `slot.moved` assignment fills one moved out; it's full where its scope ends.

Borrow inference needs no check of its own: any set of borrowed parameters is sound when the
callee and its callers are held to the same set, which is what the walk does. The pass's
rewrites (re-matching, aliases elided, moves, reuse placement) need none either: the walk sees
what they made.

## What it found

Nothing wrong in the pass. The check passes on the 249 programs of `tests/` that build, on the
compiler's own source (38,000 lines, built with `--check-ir` in 79 s; without it wasn't timed),
and on the 60 programs of `examples/`, `bench/` and `packages/` that link here.

## Does it catch anything

`tests/owned-mutants.sh` builds seven compilers, each with one mistake put into the pass, and
runs the check over `tests/`. All seven are caught:

| Mistake put in | Programs it's caught in, of 249 |
|---|---|
| a dead variable's drop left out | 189 |
| a borrowed variable given away without a dup | 199 |
| a field under a dying cell used without a dup | 26 |
| a reuse token not freed where nothing is built in it | 54 |
| a mutable filled as moved out that wasn't | 7 |
| an array dropped before its element is read | 154 |
| a record dropped before the field read from it is dup'ed | 93 |

The script takes ten minutes and isn't part of `./test.sh`: run it after a change to the pass
or to the check.

## What it doesn't cover

- **The proof is of a core, and of the judgment, not of the code that checks it.**
  `proofs/Ownership.v` has cells built from variables, borrowed field reads, `dup`, `drop`,
  reads and branches, over a heap of counted cells where a freed cell's fields are dropped in
  turn. Its theorems: `safe` (no read, dup or drop of a cell that isn't in the heap) and
  `no_leak` (the heap is empty when the program and its drops are done). Its invariant: a
  cell's count is the references to it from pending drops, variables and other cells, and a
  borrowed variable is a field of its holder's cell while that cell is in the heap. Not in the
  calculus: functions and borrowed parameters, join points, loops, `dropfields`, reuse tokens
  and `let mutable`. And `Core.Check.owned` is Z#, written to follow the judgment's rules by
  hand: nothing ties the two but reading them side by side, and the mutants.
- **A moved-out mutable's reads.** After `slot.take x`, `x` may still be read while the taker
  hasn't given the value away (`x <- f x (g x)`); the check allows any read of it until it's
  filled, and doesn't follow the taker.
- **What a task holds at a wait** (`task.held`): the variables a cancelled task drops should be
  exactly what its continuation owns. The walk skips the node. The pass keeps that set by hand
  (`hold`, `release`), and an `if`'s condition, a closure being applied and a lent argument
  don't add to it as a `let` does; whether a wait can stand there wasn't looked into.
- **A mutable's drop at a jump** out of its scope, and at its scope's end: code generation's,
  not this pass's.
- **Atomic counts, shared values and contained jobs:** the runtime's.
- **Code generation.** The check ends at Core; `Gen/` turning `dup`, `drop` and `dropfields`
  into the wrong calls would pass it. The suite's leak check and the sanitizers are what test
  that.

## Next

In the order of what they'd find for their cost: the `task.held` equation in the walk; the
taker of a moved-out mutable; then the calculus grown to what the checker has that it lacks
(calls with borrowed parameters first, then `dropfields` and tokens, which is where reuse in
place has to be shown not to change a cell something else still reads). `./test.sh` runs
`proofs/check.sh`, and skips it in an image built before Rocq was added to
`.devcontainer/Containerfile`.
