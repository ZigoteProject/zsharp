# Proposal 0034: C calls, registers and CPU features inside `unsafe`

| | |
|---|---|
| **Status** | Draft |
| **Decided at** | not yet: track G's item 5 ([ROADMAP](../../ROADMAP.md#language-g)), a design review |
| **Builds** | after 0.7.1: a warning in one release, an error in the next |
| **Rests on** | [DESIGN §5.3](../../DESIGN.md#53-what-code-without-unsafe-guarantees) (what code without `unsafe` guarantees, and "unsafe on purpose") and §11; the specification's [§10.7](../spec/10-execution.md), [§11.1 and §11.2](../spec/11-low-level.md#112-unsafe); [0021 warnings](0021-warnings.md) |
| **Related** | [0032 first-party packages](0032-first-party-packages.md) (53 externs, each already behind a function); [0031 stability](0031-stability-and-support.md) (a breaking change, so before 1.0); [0018 packages](0018-packages.md) |
| **Changes** | DESIGN §5.3 and §11; the specification's §10.7, §11.1, §11.2, §11.4 and §11.5; the guide's chapters on C and on microcontrollers; the C calls of `lib/`, `src/`, `packages/`, `examples/` and `tests/`. No syntax |

- [ ] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

Three things are written in safe code today and are unchecked: a call of an `extern` (or of an
`import c` module's function), an `Mmio` access, and a call of a `[<Target>]` function on a
CPU without its features. The proposal puts each inside `unsafe`, where raw pointers and
`fnptr` calls already are, so the guarantee is about one word:

> A program with no `unsafe` in it, and none in what it depends on that is wrong, has no
> undefined behaviour.

```fsharp
extern abs : c_int -> c_int

let distance (a: int) (b: int) = int (unsafe (abs (c_int (a - b))))   // was: abs (c_int (a - b))
let lit () = unsafe (Mmio.write32 odr 1u)                             // was: Mmio.write32 odr 1u
```

Declaring an extern stays free. Nothing changes in the code generated.

## Motivation

**The guarantee is worded four ways.** The README says "code without `unsafe`"; the
contributors' security page "no `unsafe` and no `extern`"; the specification's §10.7 "no
`unsafe` expression, no `extern` and no `Mmio` function"; DESIGN §5.3 lists `extern` and
`Mmio` as "unsafe on purpose". None mentions `[<Target>]`, whose call on another CPU §11.5
calls undefined. The README's is the one a reader takes away, and the one that isn't true.

**"No `extern`" can't be checked by reading a program.**

- **A call of C looks like any call.** `sqlite3_finalize p` and `List.rev p` differ in nothing
  a reader or a search sees. A review of a package for what could break memory has to find
  every extern's name first, then every use.
- **A C name is global** (§11.1: "reachable bare from any module"). A program that declares no
  extern can call a dependency's: with `packages/http` in its `zs.toml`, safe code may write
  `zs_http_free p` twice. "My program has no `extern`" is true of it and promises nothing.
- **`import c` brings a header's functions in by the hundred,** each callable from anywhere
  that can name the module (`Sqlite.Native.sqlite3_close` is public, for "a connection of
  one's own, in `unsafe` code that keeps SQLite's rules itself": the comment asks for what
  the compiler doesn't).

**The cost of the line being thin was seen.** A hardening pass in November 2026 found that
the three first-party packages kept their C pointers in public fields, so a program without
`unsafe` or `extern` could put a freed one back (fixed, with tests, apart from this proposal).
The packages' authors had wrapped every extern in a checking function, and the hole was
beside the wrappers. With C calls inside `unsafe`, the reviewer of a package reads its
`unsafe` expressions and what reaches them, and that is the whole of the question.

**Without the change:** the wording is made the same everywhere ("no `unsafe`, no `extern`
call, no `Mmio`, no `[<Target>]`": alternative A), and a tool lists a program's C calls.

## Detailed design

### 1. Calling C

A call of a function declared by `extern`, or of a function of an `import c` module, compiles
only inside an `unsafe` expression, as a call through a `fnptr` does (§11.2). The rule is on
the call, with all its arguments or fewer:

- `extern f : …` and `module M = import c "h.h"` are declarations: allowed anywhere.
- Naming an extern without calling it (`List.map abs xs`, `let f = abs`) is a call's
  equivalent, since the value can be called anywhere: inside `unsafe` too.
- A header's constants, structs and enums are values and types: safe, as now.
- The library's own externs follow the rule (`lib/` has three). `Native.*` keeps its own
  (§11.2: unsafe outside the library).

A C function that is safe for every argument gets a function, which is where its name and
its types for Z# were going to be written anyway:

```fsharp
extern c_abs : c_int -> c_int
let abs (x: int) : int = int (unsafe (c_abs (c_int x)))
```

### 2. Registers

`Mmio.read8`, `read32`, `write8` and `write32` join the built-ins only `unsafe` code may call
(`unsafeBuiltins` in `src/Infer/Builtins.zs`). A board's file wraps its registers once:

```fsharp
let private odr: usize = 0x40020014
let led (on: bool) = unsafe (Mmio.write32 odr (if on then 32u else 0u))
```

The accessors an `import svd` module generates contain their `unsafe` and are safe to call:
the description is a file the project names in its own `zs.toml`, trusted as its linker script
is (question 1).

### 3. CPU features

A `[<Target "f">]` function is called from a function that has the features (its own
`[<Target>]` naming them, a `[<Multiversion>]` version that includes them, or a build whose
`--cpu` does), or inside `unsafe`. This is the rule §11.5 already has for an intrinsic
"beyond the target's baseline", applied to the functions that use them. A `[<Multiversion>]`
function selects by the running CPU and stays safe to call.

### Order of implementation

1. **A warning,** `unsafe-call` (0021), on each such call outside `unsafe`. `--strict` makes
   it an error, so the repository's own code moves in the same release: `unsafe (abs x)`
   compiles under stage 0 as it is (0.7.1 takes `unsafe` around any expression, checked), so
   `src/` needs no new stage 0.
2. **The repository:** `lib/` (3 externs), `src/` (17), `packages/` (53, and two imported
   headers: every call is in a wrapper already), `examples/` and `tests/` (26 externs, a
   dozen imported headers, 194 `Mmio` accesses, most of them in board files and register
   tests), the guide (5 externs, 13 accesses).
3. **An error,** in the release after, with the specification's §10.7 reduced to "no
   `unsafe` expression".

## Drawbacks

- **Every program that calls C changes,** once, mechanically. Before 1.0 is when it can.
- **Firmware reads worse where it touches registers by hand.** `examples/` has 118 `Mmio`
  accesses; after the change each is in `unsafe` or behind a board function. Typed registers
  (`[<Bits>]`, `import svd`) are what the guide teaches, and they're unaffected.
- **`unsafe` around a whole body hides the call that matters.** The style rule (the
  contributors' security page has it already) is the small expression: `unsafe (f x)`.
- **A word doesn't make C correct.** The wrapper's check is still the author's to write.

## Alternatives

- **A. Keep the rule, fix the wording:** the guarantee is "no `unsafe`, no extern call, no
  `Mmio`, no `[<Target>]`" in every document. Costs nothing and breaks nothing. Not chosen as
  the proposal because the property stays one that only a tool can check, and a dependency's
  externs stay callable by name. It is what happens if this is declined, and should be done
  then.
- **B. Rust 2024's form:** `unsafe extern` blocks whose items are `safe` or `unsafe`. Says
  the same with a new keyword position and a per-item marker. Z# has `[<Unsafe>]` and wrapper
  functions; a second way to say "trusted" isn't needed yet (question 2).
- **C. Private externs:** an extern is visible in its module only, unless exported by a
  function. Narrows who can call C, and the call still looks like any call inside the module.
  Worth having beside the proposal (question 3), not instead.
- **D. `[<Unsafe>]` on `import c` modules only,** externs as now. Half the rule: the 53
  externs of the packages are hand-declared, not imported.

## Compatibility

- **Breaking,** in two steps: a warning for one release, then an error. The rewrite is
  `unsafe ( … )` around each call, or a wrapper function.
- **Older compilers** take the new code: `unsafe` around a C call compiles since `unsafe`
  exists.
- **The library's API** doesn't change: no public function of `lib/` is an extern.
- **Packages:** a published package (after 0018's registry) built with an older rule compiles
  with a warning, then not: its `zs.toml`'s edition, when 0031 gives it one, could carry the
  old rule.

## Pragmatics

- **Diagnostics:** in the form of the existing ones. `calling the C function 'abs' is unsafe:
  call it inside ``unsafe``, or through a function that checks its arguments`;
  `'Mmio.write32' is unsafe: use it inside ``unsafe```; `'dot8' is compiled for avx2, which
  this function isn't: give it [<Target "avx2">], or call it inside ``unsafe```.
- **Tooling:** the language server offers "wrap in `unsafe`" on the warning. `zs doc` shows
  nothing new (no public extern is documented as a function). A count of `unsafe` expressions
  by package (`zs tree --unsafe`) becomes meaningful, and is its own small proposal.
- **Performance:** none; `unsafe` generates no code.
- **Scaling:** the check is a set lookup where a name is resolved, as `[<Unsafe>]`'s is.

## Unresolved questions

1. **`import svd`'s accessors:** safe (the proposal), or `[<Unsafe>]` with the board's
   functions as the safe layer? A wrong address in a description writes anywhere.
2. **A C function declared safe:** for a header of pure functions (`math.h` through
   `import c`), are wrappers enough, or does the import take a list (`safe = "sin, cos"`)?
3. **An extern's name:** still global to the program (§11.1), or its module's, and private
   with `private`? With rule 1 a stray call needs `unsafe`, so this matters less.
4. **Rule 3's scope:** with this proposal, or on its own? It touches no C.
5. **Tests of C interop** (`tests/cimport`, `tests/cunion`): rewritten with the rest, which
   makes them longer, or exempt by a file attribute? The proposal: rewritten.
6. **The warning's length:** one release, or until 1.0's freeze?

## History

- 2026-11-14: drafted, from track G's item 5 and a pass over what safe code can reach.
