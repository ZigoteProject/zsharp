# The Z# Language Specification

**Language version:** 0.7 (compiler `zs 0.7.0`, 2026-11-05, with the corrections merged since).
**Status:** descriptive. Z# is pre-1.0; the language may change between releases, and every
change is listed in [CHANGELOG.md](../../CHANGELOG.md). 1.0 is the release that freezes the
language ([chapter 14](14-evolution.md)).

This document defines the Z# language: the text of a program, what it means, and what a
conforming implementation must accept, reject and do. It is the reference;
[the guide](../guide/README.md) teaches the language, [DESIGN.md](../../DESIGN.md) gives the
reasons for it, and [the library reference](../reference/README.md) documents the library.

## Chapters

| | Chapter | Defines |
|---|---|---|
| 1 | [Lexical structure](01-lexical.md) | source text, tokens, literals, the offside rule |
| 2 | [Program structure](02-programs.md) | files, modules, namespaces, name resolution, startup, `main` |
| 3 | [Types](03-types.md) | the types, units of measure, function kinds, rows, inference |
| 4 | [Declarations](04-declarations.md) | `let`, `type`, members, attributes, constants |
| 5 | [Expressions](05-expressions.md) | every expression form, precedence, evaluation order |
| 6 | [Patterns](06-patterns.md) | pattern forms, exhaustiveness, active patterns |
| 7 | [Traits](07-traits.md) | `trait`, `impl`, `dyn`, `derive`, the operator traits |
| 8 | [Effects](08-effects.md) | `effect`, `handle`, rows, where effects must be handled |
| 9 | [Computation expressions](09-computations.md) | builders, `task { }`, `seq { }` |
| 10 | [Execution model](10-execution.md) | values and identity, memory, panics, threads and `Share` |
| 11 | [Low-level programming](11-low-level.md) | C interop, `unsafe`, layout, SIMD, bare metal |
| 12 | [Built-in names](12-builtins.md) | the prelude, the attributes, the warnings |
| 13 | [Grammar](13-grammar.md) | the collected grammar |
| 14 | [Evolution](14-evolution.md) | stability, planned features, reserved syntax, what was declined |

## Conformance

The key words **must**, **must not**, **may** and **should** are requirements on a program or
on an implementation, as the sentence says.

- **A compile-time error** ("is an error", "is rejected") is a program an implementation
  must not translate. An implementation should report every error of a compilation in one
  run, each with `file:line:col` and the source line. Message texts quoted in this document
  are the reference implementation's and are informative.
- **A warning** is a diagnostic about a program that is translated all the same
  ([§12.4](12-builtins.md#124-warnings)).
- **A panic** is the defined run-time response to a bug ([§10.5](10-execution.md#105-panics)):
  the program stops. Z# has no undefined behaviour outside `unsafe` code and `extern` calls
  ([§11.2](11-low-level.md#112-unsafe)).
- **Implementation-defined** behaviour is a choice an implementation documents; the reference
  implementation's choice is given each time.
- **Target-dependent** properties are fixed by the compilation target: the width of `int`
  and `usize`, which library tier is available, C's calling convention and layout.

Paragraphs marked *Note* and all examples are informative. A paragraph marked
*Implementation* describes the reference implementation where it does not have to be imitated
(representation, optimizations), and one marked *Deviation* records where the reference
implementation at 0.7 differs from the design, so that a program relying on either is warned.

## Notation

Grammar productions are written in an extended BNF:

```text
name       = definition ;      a production
'let'                          a terminal: this token
INT  ID  NEWLINE               a token class (chapter 1), layout tokens included
a b                            a, then b
a | b                          a or b
[ a ]                          a, optional
{ a }                          a, zero or more times
( a | b )                      grouping
```

`NEWLINE`, `INDENT` and `DEDENT` are the layout tokens of
[§1.9](01-lexical.md#19-layout-the-offside-rule). A production named `block(x)` stands for
"either `x` on the same line, or `INDENT x-sequence DEDENT`", as each chapter states.

Types in running text are written as programs write them (`list<'a>`, `'a -> 'b / E`).
*e*, *p* and *T* stand for an expression, a pattern and a type.

## Sources of truth

Where this document and the reference implementation disagree, that is a defect in one of
them, to be reported; neither wins silently. The chapters were written against:

- the lexer and parser (`src/Syntax/Lexer.zs`, `Parser.zs`, `Ast.zs`) for chapters 1, 5, 6
  and 13;
- the checker (`src/Infer/`, `src/Types/`) and `lib/prelude.zs` for chapters 3, 4, 7, 8, 12;
- [DESIGN.md](../../DESIGN.md) and its decisions (§13) for meaning and intent;
- programs run through `zs 0.7.0` for the edge cases stated as rules (overflow, conversion,
  evaluation order, the value restriction).
