# Proposal 0006: anonymous records and top-level patterns

| | |
|---|---|
| **Status** | Draft |
| **Decided at** | the third design review ([ROADMAP](../../ROADMAP.md#third-design-review)): anonymous records are the first candidate for its "Simple" check |
| **Builds** | phase 12's deferred features ([ROADMAP](../../ROADMAP.md#phase-12-release-01)) |
| **Rests on** | decisions 10 (structural equality, ordering, hashing, printing), 18 (record literal types), 39 ("Simple") in [DESIGN §13](../../DESIGN.md#13-decisions) |
| **Related** | [0005 ergonomics](0005-ergonomics.md) |

- [ ] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

Two F# forms deferred from phase 9.6:

- **Anonymous records:** `{| x = 1; name = "a" |}` has the type `{| name: string; x: int |}`, given by its fields, with equality, ordering, hashing and printing as a record's. For a value that's returned once and read twice, with no declaration.
- **Top-level patterns:** `let (lo, hi) = bounds` and other irrefutable patterns at the top level, as inside functions.

Both lower to what exists (a record with a generated name, a hidden value and projections), so
the compiler's later passes see nothing new.

## Motivation

- **A function returning several named values** declares a record today, used once: `type Stats = { mean: f64; sd: f64 }`. `{| mean = m; sd = s |}` says the same at the return and at the use.
- **Projections in pipelines:** `people |> List.map (fun p -> {| name = p.name; age = p.age |})` where a tuple would lose the names.
- **Test data and examples** that aren't worth a type.
- **Top-level patterns:** `let (width, height) = size ()` at the top of a file is written as two lets with `fst` and `snd` today.

Against: a record declaration is one line, and a type with a name is something a reader can
find. The third design review weighs this; the proposal gives it the full design to weigh.

## Detailed design

### Anonymous records

- **Syntax:** `{| f1 = e1; f2 = e2 |}` for values, `{| f1: t1; f2: t2 |}` for types, `{| r with f1 = e |}` for copy-and-update, where `r` is an anonymous or a named record (a named record's fields are copied into the result).
- **Type identity:** the sorted set of field names and their types. Two literals with the same fields and types have one type, in any module; field order in a literal doesn't matter, and the type prints its fields sorted, as F# does.
- **Access:** `v.f` is type-directed as for records (DESIGN §2.1). A literal's type is known from its fields, so `.f` works on it without annotation; a parameter of anonymous record type needs its annotation, since inference doesn't guess record types from field use (no row polymorphism, as for named records).
- **Derived traits:** `Eq`, `Ord`, `Hash` and `Show` apply automatically, as to records. Library derives need an attribute on a declaration, which there isn't, so a `Json` for an anonymous record is written as an `impl` on its type or isn't; the guide says to declare a record for anything that crosses an API.
- **Representation:** a record with a generated name (`{| name: string; x: int |}` is `$Anon_name_x` at those types), monomorphized by shape. A plain value when its fields are (DESIGN §5.1).
- **Not supported,** as in F#: patterns on anonymous records, members, `[<CLayout>]`, and subtyping between widths (`{| x; y |}` isn't a `{| x |}`).

### Top-level patterns

- **Forms:** `let (a, b) = e`, `let { x = x; y = y } = e`, nested tuples and records, `_`, and `as`. Irrefutable patterns only: a union case of a union with several cases, a list pattern or a literal is an error, as a `let` with an incomplete pattern is inside a function.
- **Constants:** when `e` is a constant and the pattern takes constructors the constant has, each bound name is a constant (inlined at use, DESIGN §2.1). Otherwise `e` is a hidden startup value and each name a startup value projecting from it, in declaration order.
- **`private`** applies to each name as `let private` does; type annotations go in the pattern (`let (a: int, b) = …`).

## Drawbacks

- **Two spellings for a record.** The review's question. The guide's rule (anonymous for values that stay local; declared for anything named in an API or stored) is advice, not a check.
- **Error messages** carry the full field list of an anonymous type, which is long for wide ones.
- **No patterns** on anonymous records, so a function taking one reads it by dot access only.

## Alternatives

- **Tuples:** lose the names; F# programmers reach for anonymous records to avoid exactly that.
- **Declared records everywhere:** what exists, one line each; the review may decide that's the answer.
- **Row-polymorphic records** (OCaml objects, Elm): inference from field use, at the cost of a type system feature DESIGN §2.1 rules out for records.
- **Top-level `let` with `fst`/`snd`:** what exists.

## Compatibility

- **Not breaking:** `{|` doesn't lex today, and a pattern after a top-level `let` is a parse error.
- **Older compilers** reject both at the line.

## Pragmatics

### Diagnostics

| Situation | Error |
|---|---|
| a field missing in `.f` | `{\| name: string; x: int \|} has no field 'y'` |
| `.f` on an unannotated parameter | `annotate p: its type isn't known here (an anonymous record is named by its fields)` |
| a refutable top-level pattern | `a top-level let needs a pattern that always matches: Some x can be None` |
| a pattern on an anonymous record | `anonymous records have no patterns: read the fields with .x` |

### Tooling

- **Hover** shows the full anonymous type; completion after `.` lists its fields.
- **The grammar** gains `{|` and `|}`; `zs fmt` treats them as record braces.

### Performance

None at run time: a record by another name. Monomorphizing by shape makes one instance per distinct field set.

### Scaling

Fields per anonymous record: 2–5 typical, 50 at most; distinct shapes per program: hundreds at most.

### Culture-aware formatting and parsing

None.

## Unresolved questions

1. **Whether to build either at all:** the third design review's "Simple" check, against the one-line declaration they replace.
2. **Printing order:** sorted field names (F#) or the literal's order (readable, but then two equal values could print differently). Sorted here.
3. **Library derives on anonymous records:** an `impl` by hand, or `[<Derive(Json)>]` allowed on an expression's type annotation (`({| … |} : Json)`). Neither here.

## History

- **2026-10-22:** drafted from phase 12's deferred items and F#'s anonymous records (F# 4.6).
