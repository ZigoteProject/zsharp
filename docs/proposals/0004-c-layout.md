# Proposal 0004: C layout: fixed-size arrays, C unions and layout facts

| | |
|---|---|
| **Status** | Approved in principle: `fixed` (decision 53, phase 9.6); C unions and layout facts (decision 70, phase 12) |
| **Decided at** | the phase 9.6 design review (`fixed`); the third design review ([ROADMAP](../../ROADMAP.md#third-design-review-)) (the rest: by case with no zeroed form yet, `sizeof<'a>` in expressions only, no C bit-fields) |
| **Builds** | phase 9.6 and phase 12 ([ROADMAP](../../ROADMAP.md#phase-12-release-01)) |
| **Rests on** | decisions 20 (no compile-time evaluation beyond derive), 53 (`fixed`) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §11](../../DESIGN.md#11-c-interop) |
| **Related** | [0003 spans](0003-spans-and-slices.md), [0013 bit fields](0013-bit-fields.md), [0001 type providers](0001-type-providers.md) (`import c` is the compiler's own provider) |

- [x] Approved in principle (`fixed`)
- [x] Approved in principle (unions, layout facts)
- [ ] Implementation

## Summary

Three things let a `[<CLayout>]` record match any C struct and prove it:

- **`fixed<'a, N>`:** N elements inline, as C's `uint8_t data[16]`, a value indexed like an array. A number is a type argument there and nowhere else.
- **C unions:** a `[<CLayout>]` union has no tag and its cases share storage; it's built by case and read by case name inside `unsafe`. `import c` brings C unions in.
- **Layout facts:** `sizeof<T>`, `alignof<T>` and `offsetof<T> "field"` are constants, and a top-level `assert` on constants is checked at compile time, so a layout is checked against C's with the `assert` the language has.

```fsharp
[<CLayout>]
type CXCursor = { kind: i32; xdata: i32; data: fixed<cptr, 3> }     // libclang passes it by value

assert (sizeof<CXCursor> = 32)                                        // checked when compiling
```

## Motivation

- **`import c` leaves structs with array fields out** (DESIGN §11), and a function taking one by value is unusable. Phase 11 needs libclang, whose `CXCursor` holds `const void *data[3]` and is passed by value everywhere.
- **C unions** are in every event loop (`epoll_event`'s `data`, SDL's `SDL_Event`, X11's `XEvent`) and in hardware descriptions. Today such a header imports with those declarations missing.
- **A wrong layout is a silent bug.** A `[<CLayout>]` record that doesn't match its struct corrupts memory at the call; a compile-time `assert (sizeof<Packet> = 20)` fails when a field changes.

## Detailed design

### `fixed<'a, N>`

- **The type:** `fixed<'a, N>` holds N elements of `'a` inline. N is a positive integer literal; it's part of the type, so `fixed<u8, 16>` and `fixed<u8, 32>` differ. Type arguments that are numbers are allowed in `fixed` and nowhere else (decision 53): no type-level arithmetic, no generic N.
- **A value:** copied like a record; equality, ordering, hashing and printing are element-wise, derived as for records. Element types: any, with `[<CLayout>]` records restricted to C types as for other fields. A `fixed` of references (`fixed<string, 4>`) is four references inline, dup'd and dropped as four fields.
- **Reading and writing:** `f.[i]` reads with a bounds check; `f.[i] <- x` writes to a place, so `r.data.[3] <- x` works when `r` is `let mutable`, with the place evaluated once ([0005](0005-ergonomics.md)'s compound assignment applies too). `{ r with data = Fixed.set r.data 3 x }` is the functional form.
- **Functions:** `Fixed.init (fun i -> …)`, `Fixed.create x` (N from the expected type), `Fixed.get`, `set`, `length`, `toArray`, `ofArray` (a panic when the lengths differ), `iter`, `map`, `fold`; `for x in f do` iterates it.
- **`import c`:** `uint8_t data[16]` becomes `fixed<u8, 16>`; `int m[3][4]` becomes `fixed<fixed<i32, 4>, 3>`; an array parameter decays to `ptr<T>` as in C. Structs with array fields stop being left out.
- **Layout:** N times the element's size, the element's alignment, as C.
- **Spans:** a `fixed` has no heap owner, so no span windows it; `Fixed.toArray` copies, and in `unsafe` a `Span.ofPtr` over its address works for a call's duration.

### C unions

```fsharp
[<CLayout>]
type Data =                        // union { uint32_t u32; uint64_t u64; void *ptr; }
  | U32 of u32
  | U64 of u64
  | Ptr of cptr

let d = U64 (u64 7)
let low = unsafe d.U32             // the first four bytes, as C would read them
```

- **A `[<CLayout>]` union** has no tag: its size is its largest case's and its alignment the strictest, and each case is a view of the same bytes. Construction writes the case's field. Reading is `v.Case` inside `unsafe`, since the compiler can't know which case is there; `match` isn't allowed on it, and neither are equality, ordering, hashing or printing (there's nothing to compare case-wise), so `[<NoEquality>]` and `[<NoComparison>]` are implied.
- **Cases** have exactly one field each, named or not; a case without fields or with several is an error.
- **`import c`** brings a union in as this, named or `typedef`'d, and a struct with a union field keeps it. An anonymous union inside a struct becomes a union named after the struct and the field (`Event_data`).
- **Passing:** by value with the target's rules for a struct of its size and class, as C passes unions; on x86-64 System V a union's class is computed from all its members, which `Codegen` already does for structs.

### Layout facts

- **`sizeof<T>`, `alignof<T>`** are `int` constants for any type: a `[<CLayout>]` type's are C's; a plain value's are Z#'s; a heap type's (`string`, a list) are a pointer's. **`offsetof<T> "field"`** names a record's field, `[<CLayout>]` or not, and is an error for a field that doesn't exist.
- **Top-level `assert`:** an `assert` at the top level whose expression is a constant (literals, operators, these facts, other constants) is checked at compile time and is an error when false, at the assert. A top-level `assert` whose expression isn't constant stays a startup check, as top-level values run at startup (DESIGN §2.1), and the guide says which is which. No `static assert` keyword (DESIGN's phase 12 note).
- **Generated headers:** `zs build --lib` emits a `_Static_assert` of each exported `[<CLayout>]` type's size, so a C compiler on the other side checks the same fact.

### Order of implementation

1. `fixed`: the type, indexing, functions, derives, `import c`, the C ABI.
2. Layout facts and the compile-time `assert`.
3. C unions, and `import c` of them.

## Drawbacks

- **Numbers in types,** even in one place, invite requests for more (`fix<i, f>` in track M's fixed-point item asks already). Decision 53 draws the line at `fixed`, and 0015 keeps fixed-point formats to three named types.
- **Two kinds of union:** a `[<CLayout>]` union is a different thing from a Z# union under the same keyword. The attribute, the `unsafe` reads and the absence of `match` make the difference visible at every use.
- **Compile-time `assert`** is the first evaluation at compile time beyond constants and derives; it's limited to the constant expressions the compiler already folds, so it adds no evaluator.

## Alternatives

- **Type-level numbers and arithmetic** (Zig, C++): general and heavy; decision 53 rules them out, and nothing in the roadmap needs `fixed<'a, N + 1>`.
- **Arrays as values** (`array<u8>` inline when small): breaks the one representation of arrays and their copy-on-write semantics.
- **Tagged Z# unions for C unions,** with conversion functions: can't sit in a C struct field, which is where unions appear.
- **A `static_assert` form:** a second assert for the same meaning; `assert` on constants is checked at compile time without a new word.
- **`[<StructLayout>]`-style explicit offsets** (C#): more control than any header needs; `import c` computes offsets from clang, and `offsetof` lets a hand-written record check itself.

## Compatibility

- **Not breaking:** `fixed`, `sizeof`, `alignof` and `offsetof` are new names; a program using them as identifiers today would shadow them, as any name shadows a library's. `[<CLayout>]` on a union is new.
- **`import c` results change:** structs with array or union fields were left out and now import, with names that could collide with a program's (the program's win, as declared names do).
- **Older compilers** reject the new forms at the line.

## Pragmatics

### Diagnostics

| Situation | Error |
|---|---|
| `fixed<u8, 0>`, or a non-literal N | `fixed needs a positive number of elements, written as a literal` |
| a number as a type argument elsewhere | `only fixed takes a number as a type argument` |
| `Fixed.ofArray` with the wrong length | at run time: `panic: fixed<u8, 16> from an array of length 12` |
| reading a C union outside `unsafe` | `reading a case of a C union needs unsafe: Data has no tag` |
| `match` on a C union | `a C union can't be matched: read a case with unsafe v.U32` |
| a failed top-level `assert` on constants | `assert fails when compiling: sizeof<Packet> = 20 is false (sizeof<Packet> is 24)` |
| `offsetof` with an unknown field | `Packet has no field 'lenght' (length)` |

### Tooling

- **Hover** shows `fixed<u8, 16>` and, on a `[<CLayout>]` type, its size and alignment.
- **Debugging:** DWARF describes a `fixed` as an array and a C union as a union, so gdb shows both as C would.
- **`import c`'s hover** shows the C declaration for unions and array fields as it does for others.

### Performance

- **Existing code:** none.
- **`fixed`:** inline storage, no allocation; indexing is a bounds check and an add. Copying a record with a large `fixed` copies it; `let mutable` and in-place writes avoid that where it matters.
- **Layout facts:** constants.

### Scaling

| Dimension | Typical | Upper bound |
|---|---|---|
| elements in a `fixed` | 3–64 | 65,536 (a record of that size is copied whole; prefer a `Buffer`) |
| cases in a C union | 2–10 | 64 |
| top-level asserts | 1–10 | 1,000, each folded at compile time |

### Culture-aware formatting and parsing

None.

## Unresolved questions

1. **Constructing a `[<CLayout>]` union** whose case field is a `fixed` or a record: by case as here; whether a zeroed union (`Data.zero`) is wanted for C APIs that fill them.
2. **`sizeof` of generic types:** `sizeof<list<'a>>` is a pointer; `sizeof<'a>` inside a generic function is a constant after monomorphization, which the compile-time `assert` can't see before it. Allowed in expressions, not in top-level asserts.
3. **Bit fields in C structs** (`unsigned flags : 3`): `import c` leaves them out, as it does today; whether [0013](0013-bit-fields.md)'s `[<Bits>]` records can match a compiler's bit-field layout is that proposal's question, and the answer is likely no (the layout is implementation-defined).

## History

- **2026-10-22:** drafted from DESIGN §11, decision 53 and phase 12's deferred items.
