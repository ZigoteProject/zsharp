# Diagnostics

Error and warning messages are part of the product: they're what a user reads most, their text
is tested exactly, and the specification quotes them. This page is how to write one.

## Form

```
tests/err_neg_unsigned.zs:3:3: error: value of 'x': expected u8, got int: numbers don't convert on their own; write u8 x
```

`file:line:col: error: message`, then the source line. A warning has `warning:` and its name
([proposal 0021](../proposals/0021-warnings.md)). Paths use `/` on every operating system.

## A message has three parts

1. **What is wrong,** in terms of the program: the name, the types, the construct.
2. **Why,** when the rule isn't obvious: the reason is the language's, said in a clause.
3. **What to write instead,** when there is a usual fix.

```
Bits.toU16 needs a record of 16 bits, and Reg is 32: Bits.toU32, or Bits.raw
put is [<NoAlloc>], but put overwrites a Buffer element, which drops the old one (it may be the last reference)
package 'logger' uses File, part of Std, which needs an operating system; a build for cortex-m4 has none, so it can't depend on this package
Box.Internal.Secret is internal to box; use its public modules (Box, Box.Pub)
```

## Rules

- **The user's words.** Name things as the program does (`'x'`, `Reg`, `put`) and as the guide
  does (`a closure`, `a let mutable`, `Share`). Never a compiler term: no `unification`, `TVar`,
  `Core`, pass names or internal codes.
- **Types as written.** Print a type as the user would write it; hide what they didn't write
  (the ambient effect row).
- **One sentence, lower case, no final full stop.** A colon introduces the detail, a semicolon
  the fix.
- **Point at the smallest place:** the expression at fault, not the function around it.
- **Say the cause, not a consequence.** One mistake gives one error. The checker recovers per
  statement, so a failed binding shouldn't produce errors at each of its uses.
- **Every error in one run.** Report through the `Report` effect and go on; the parser recovers
  into error nodes.
- **Name the chain** when the cause is far away: `[<NoAlloc>]`'s error names the calls down to
  the allocation; a `Share` error names what was captured.
- **Never a panic.** A compiler panic on any input is a bug, and it names its pass so the report
  is useful.
- **No blame, no jokes, no "please".**

## Warnings

A warning is about a program that's translated all the same. Each has a name (`unused-value`,
`cycle`) so it can be discussed and tested. Add one only when it's nearly always a mistake and
there's a clear way to say "I meant it"; the repository itself builds `--strict`, where a warning
is an error.

## Testing one

Every diagnostic has a test with its exact text: `tests/err_<what>.zs` and `.err` (the message
lines, without the quoted source). Changing a message's wording changes its test, and the guide
or the specification where they quote it: search for the old text.

## Run-time messages

A panic says what happened in the same style, `panic: stack overflow (recursion too deep)`, and
is the same text on every target. Library functions return `Error` with a message that names the
input: `a height isn't a number: x`.
