# 14. Evolution

This chapter is about change: what is stable, what is planned, what the current syntax
reserves for it, where the reference implementation deviates from this document, and what
was considered and declined. It is the part of the specification to update first when a
feature is proposed.

## 14.1 Stability

- **Before 1.0** the language and the library may change in any release. Each change is in
  [CHANGELOG.md](../../CHANGELOG.md) with what to rewrite.
- **1.0** freezes the language and the library's names. From then on a rename is preceded by
  one release in which the old name carries `[<Deprecated "use X">]` and its use gives the
  `deprecated` warning ([§14.2](#142-planned-features)).
- **This document** carries the language version it describes on its first page. A change to
  the language changes the affected chapters in the same commit, and a feature is not
  "implemented" until they do.

**How a feature enters the language.** A proposal in [docs/proposals](../proposals/README.md)
states the design and its alternatives; a design review decides it, and the decision gets a
row in [DESIGN.md §13](../../DESIGN.md#13-decisions); the implementation lands with its tests
and with its text here. A proposal answers, before any code: what existing programs change
meaning or stop compiling; what the diagnostics say; what tools need.

## 14.2 Planned features

Features designed or decided but not built at 0.7, with the syntax already fixed for them
where there is any. An implementation of 0.7 must reject the syntax listed as *reserved*
rather than give it another meaning.

### Language

The table below is what has a decision or a proposal. The open design questions this
specification raised (effects across tasks and threads, written constraints, what safe code
guarantees around `extern`, and others) are track G of [ROADMAP.md](../../ROADMAP.md), each
awaiting a proposal.

| Feature | Status | Syntax and effect on this document |
|---|---|---|
| **`[<Align n>]` on a type** | decided (decision 69, proposal 0014); built for values only | *Reserved:* `[<Align n>]` before a `type`. Every value of the type is aligned to `n` bytes. Extends [§4.4](04-declarations.md#44-representation-attributes), [§11.3](11-low-level.md#113-layout) |
| **`[<Deprecated "use X">]`** and the `deprecated` warning | decided (decision 61, proposal 0021); built at the 1.0 freeze | *Reserved:* the attribute name on any declaration. A use of the declaration warns. Extends [§12.3](12-builtins.md#123-attributes), [§12.4](12-builtins.md#124-warnings) |
| **Field attributes for derives** (renaming a JSON key, skipping a field) | wanted; not designed | The position exists: attributes before a record field ([§4.3](04-declarations.md#43-type-declarations)), used today only by `[<Bit>]` and `[<Width>]`. A design must say how a derive reads them (`f.attributes` in [§7.5](07-traits.md#75-derive)) |
| **Disposal under every stop** | in part (roadmap S10) | No syntax. Removes the two exceptions of [§8.4](08-effects.md#84-handlers): a kept resumption never called, and a stop passing a `use` in a `task { }` body. Programs must not rely on the exceptions |
| **Multi-shot resumptions** | possible later, opt-in (decision 23, proposal 0002) | Not designed. Today a second call of a resumption panics ([§8.4](08-effects.md#84-handlers)); a future opt-in kind of effect or handler would allow it. One-shot stays the default, since in-place reuse depends on it |
| **Named handlers, `mask`** | deferred until a program needs them (proposal 0002) | Not designed. Today an operation always goes to the innermost handler of its effect |
| **Operations polymorphic in their parameters** | not built (proposal 0002) | Today an operation's own type variable may occur in its result only ([§8.1](08-effects.md#81-declaring-an-effect)) |
| **Fixed point on vectors**; C's view of a one-case union | planned (proposal 0015) | Library and ABI: SIMD arithmetic for `q7`, `q15`, `q31`; an untagged one-case union crossing to C as its field ([§11.1](11-low-level.md#111-c-interop)) |
| **Integer literal range errors** | a defect to fix | [§3.9](03-types.md#39-literals) |
| **`testTask`**, properties of curried parameters, more `Arbitrary` impls | planned (proposals 0009, 0010) | Library only |

### Targets

| Feature | Status |
|---|---|
| RISC-V microcontrollers (ESP32-C3), more boards (RP2040, nRF52840) | planned (track M, proposal 0027) |
| WebAssembly with WASI | planned (track T) |
| Completion-based I/O (io_uring, IOCP, kqueue) behind `Task` | planned (track S) |

A new 32-bit target changes nothing in this document: `int` follows the machine word
([§3.2](03-types.md#32-numbers)).

### Optimizations that this document already permits

These change performance only. They are listed because the specification is written so that
they need no change to it ([§10.1](10-execution.md#101-values)): fusing `Seq` pipelines into
one loop as list pipelines are; proving more bounds checks before loops; in-place updates of
more shapes. A program cannot observe them except through `[<NoAlloc>]`, which may then
accept more programs, never fewer.

### Tooling and library

Outside the language, and so outside this document: the package index and `zs publish`,
profiles and traces, debugger pretty-printers, a JSON Schema as the `json` provider's input,
`rows = "sqlite"` for the `sql` provider, `Duration` and `DateTime` arithmetic. See
[ROADMAP.md](../../ROADMAP.md).

## 14.3 Known deviations

Where the reference implementation at 0.7 differs from this document or from
[DESIGN.md](../../DESIGN.md). Programs must not rely on the deviating behaviour.

| Area | This document | The implementation at 0.7 |
|---|---|---|
| Integer literals ([§3.9](03-types.md#39-literals)) | a literal outside its type's range is an error | not checked where the type is a generic function's variable (`let f x = x + 300` at `u8`) |
| `use` and stops ([§8.4](08-effects.md#84-handlers)) | every abandoned `use` is disposed | not for a kept resumption never called, nor for a `use` in a `task { }` body |
| The `cycle` warning ([§10.4](10-execution.md#104-lifetime)) | best effort | cycles through closures and `dyn` values are not detected |
| `[<Section>]` ([§11.4](11-low-level.md#114-bare-metal)) | places the storage in the named section | on macOS and Windows the name is dropped and the alignment kept |
| Stack overflow ([§10.5](10-execution.md#105-panics)) | a panic where the platform reports it | reported on Linux, macOS and Cortex-M chips; a platform fault elsewhere |

## 14.4 Room for growth

How the present syntax leaves room, so that additions need not break programs.

- **Contextual words, not keywords.** New constructs since the first design (`handle`, `use`,
  `import`, `assert`, `yield`) were added as contextual words
  ([§1.4](01-lexical.md#14-keywords)), which keeps existing identifiers valid. A new
  construct should do the same unless it cannot be parsed that way.
- **Attributes are a closed set** ([§12.3](12-builtins.md#123-attributes)): an unknown
  attribute is an error, so a new attribute never changes the meaning of an accepted
  program. Programs cannot define attributes, and that is to stay so (no macros, §14.5).
- **Unused symbols.** `!`, `?` (prefix), `<|`, `<<`, `**`, `:=`, `&`, `#`, `` ` `` (single),
  `(* *)` have no built-in meaning. The operator characters among them are available to
  programs as custom operators ([§5.7](05-expressions.md#57-custom-operators)); giving one a
  built-in meaning later is a breaking change and needs a deprecation cycle after 1.0.
- **Rows are open-ended.** Adding a built-in effect adds a name to the prelude and nothing to
  the type system ([§3.8](03-types.md#38-effect-rows)).
- **Function kinds** ([§3.7](03-types.md#37-function-types)) are type constructors over a
  function type; a further kind is a further constructor.
- **Providers** ([§4.9](04-declarations.md#49-imports-and-providers)) are named by an
  identifier after `import`; a new built-in provider takes a name that an external
  `zs-provider-<name>` could have had, so built-in names win and should be added sparingly.
- **Patterns.** `&` (and-patterns), ranges in patterns, array patterns and float literals in
  patterns are not in the language and their syntax is free.
- **Type-level numbers** appear only in `fixed<'a, N>`, and `N` is a literal. Generalizing
  this (a length variable) would touch [§3.4](03-types.md#34-structured-types) and inference;
  it was declined for now (§14.5).

## 14.5 Declined

Features considered and decided against, or left out by design, so that the question is
reopened only with new facts. The decision numbers are DESIGN.md §13's; a row without one
records what the language does not have.

| Feature | Instead | Why |
|---|---|---|
| Classes, inheritance, interfaces | records, unions, modules, traits | decision 9; inference stays predictable |
| Member and function overloading | one member per name; traits | decision 9 |
| Named and optional arguments on curried functions | on members; records with default fields | decision 14; function types stay plain |
| Defaults on union fields | | decision 17 |
| Anonymous records | a declared record | decision 58, proposal 0006: they replace one line, and give records two spellings |
| Higher-kinded types, functors | builders as modules; traits over one type | a non-goal of v1 |
| Macros, general compile-time evaluation | `derive`; providers; constant folding | decision 20 |
| Exceptions, `try … with`, catching a panic | `result` and `?`; `Throw`; a panic stops | decisions 5 and 4 |
| Silent integer overflow | a panic; `[<Wrapping>]`; `Int.wrapping*` | decision 4 |
| `null` | `option` | |
| A tracing or cycle-collecting garbage collector | reference counting; `weak`; the leak report | decision 40 |
| Mutable record fields; closures capturing `let mutable` | `ref`; `{ r with … }` | data-race freedom and in-place reuse rest on it |
| `async`/`await` keywords; `Task` as an effect | `task { }` | decision 72: measured at seven allocations a wait against none |
| A `noalloc<F>` function kind | `[<NoAlloc>]`, with calls through closures counted | decision 67, proposal 0012 |
| Type-level numbers in general; `fix<i, f>` | `fixed<'a, N>` with a literal; `q7`, `q15`, `q31` | decision 53 |
| Generic functions over SIMD vector types | a module per vector type | decision 49: needs type families |
| C bit-fields in `[<CLayout>]` | `[<Bits>]` for registers | decision 70: their layout is the C compiler's |
| Sized integers such as `u2`, `u5` | `[<Bits>]` fields with `[<Width>]` | |
| Explicit allocator parameters | arenas; `[<NoAlloc>]` | decision 26 |
| A `[<Test>]` attribute on functions | tests as values, `[<Tests>]` | proposal 0009 |
| Block comments | `//` | |
| `break`, `continue`, `return` in functions | recursion; conditions; effects | |
