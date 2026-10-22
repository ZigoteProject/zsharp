# Proposal 0021: warnings

| | |
|---|---|
| **Status** | Approved in principle |
| **Decided at** | phase 12's list of deferred features ([ROADMAP](../../ROADMAP.md#phase-12-release-01), "From phase 9.5, cycle warnings"), under decision 40 |
| **Builds** | phase 12 ([ROADMAP](../../ROADMAP.md#phase-12-release-01)) |
| **Rests on** | decisions 40 (cycles aren't collected: `weak` for back-pointers, `ZS_LEAKCHECK=1` to find leaks), 32 (editor support through `zs lsp` and `zs mcp`) and 6 (an unreachable match case is an error) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §5.2](../../DESIGN.md#52-perceus-reference-counting) (cycles) and [§12](../../DESIGN.md#12-tooling) (diagnostics) |
| **Related** | [0011 debug info, profiles and traces](0011-debug-info-profiles-traces.md) (hints are not warnings), [0001 type providers](0001-type-providers.md) (the stale-input diagnostic becomes a warning), [0019 the syntax tree](0019-syntax-tree.md) (a code action adding `[<Cyclic>]` or `weak`), [0012 interrupts, `[<NoAlloc>]` and intrinsics](0012-interrupts-noalloc-intrinsics.md) (`[<NoAlloc>]` stays an error), [0020 self-hosting](0020-self-hosting.md) (carries the diagnostic record over), [0024 the library API](0024-library-api.md) (`[<Deprecated>]`) |
| **Changes** | DESIGN §5.2's "Warning about them (planned, phase 12)" becomes design text; §12 gains the severity; §13 gains a new decision row, numbered by the coordinator |

- [x] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

The compiler has only errors: `Diagnostic` has no severity, the language server sends every
diagnostic as severity 1, and `printError` prints `error:` (facts sheet §3). This proposal
gives a diagnostic a severity, `Error` or `Warning`, and every warning a name. A warning prints
as `file:line:col: warning: … [name]` and the build goes on; `zs build --strict` makes warnings
errors, for CI and for `./test.sh`; `zs lsp` sends them at severity 2 with the name as the code,
and `zs mcp` returns them. A declaration silences a kind with `[<NoWarn "cycle">]`; a type that
forms cycles on purpose says so with `[<Cyclic>]`.

Phase 12 brings one warning, `cycle`: a type whose objects can form a reference cycle through a
mutable field, which reference counting never frees (DESIGN §5.2, decision 40):

```fsharp
type Node = { value: int; next: ref<option<Node>>; prev: ref<option<Node>> }
```

```text
list.zs:1:6: warning: 'Node' can reach itself through 'next: ref<option<Node>>' and 'prev: ref<option<Node>>', so its objects can form a cycle that reference counting never frees; make the back-pointer 'weak<Node>', or mark the type [<Cyclic>] when the program breaks its cycles, or [<NoWarn "cycle">] when it can't form one [cycle]
 1 | type Node = { value: int; next: ref<option<Node>>; prev: ref<option<Node>> }
   |      ^
```

With `prev: ref<option<weak<Node>>>`, or `[<Cyclic>]` on the type, there is no warning. The
record the compiler keeps for a diagnostic (severity, name, position, message, notes) is
defined here, and [0020](0020-self-hosting.md) carries it into the compiler written in Z#.

## Motivation

**A back-pointer that isn't weak.** A doubly linked list, a tree whose nodes know their parent,
a subject with a list of observers: each is a cycle through a `ref`, and each leaks whole once
it's built, silently, in every build (DESIGN §5.2). The mistake is made in one line, the type
declaration, and today nothing says so there. `ZS_LEAKCHECK=1` reports the objects left at exit,
after a test that builds the structure has run, and the programmer works back from counts to
the type. [The guide's memory page](../guide/12-memory.md) shows the right shape
(`parent: ref<option<weak<Node>>>`) and `tests/weak.zs` tests it, but a programmer who hasn't
read them finds out from a growing process. The warning moves the finding to the declaration,
in the editor as it's typed, with the fix in the message.

**Why a warning and not an error.** A cycle a program breaks by hand is legitimate: a doubly
linked list whose `clear` unlinks every node, a graph freed by a function that walks it. Swift
allows those and Z# does too ("breaking a cycle is the program's job, as in Swift", DESIGN
§5.2). An error would reject them, and an attribute that turns an error off is a warning under
another name. Decision 6 went the other way for an unreachable match case, and that stays an
error: a clause that can never match (`this match case is never reached`, `Match.fs:137`, main
tree) is dead code written by mistake, nothing legitimate needs it, and the fix is to delete
it. F# warns there (FS0026) and the warning is routinely left in place; Z# has the error because
nothing is lost by it. A cycle-capable type loses something: the structure the programmer meant.

**Why the compiler has had no warnings.** Every diagnostic so far names something that can't
compile, so a severity was never needed. The cycle warning is the first thing the compiler
knows that isn't an error, and phase 12 says what that costs: "the compiler has only errors so
far, so this brings a warning severity to the CLI, `zs lsp` and `zs mcp`". Two more kinds wait
for it: [0001](0001-type-providers.md)'s "input changed; the types shown are from the last
build", in an editor that can't run a provider (an error until phase 12, its open question 6),
and [0024](0024-library-api.md)'s `[<Deprecated>]` for the freeze before 0.1. This proposal
builds the severity once; each kind is a row in a table.

**What is not a warning.** [0011](0011-debug-info-profiles-traces.md)'s hints (where code
allocates, copies on write or counts atomically) are inlay hints an editor turns on: facts about
good code, never printed by a build, never errors under `--strict`.
[0012](0012-interrupts-noalloc-intrinsics.md)'s `[<NoAlloc>]` is an error: the function asked
for it. A warning is for code that is probably wrong and may be right.

**Without the feature:** the leak check at exit, a test that happens to build the cycle, and the
guide's page. `tests/weak.zs` got its weak parent pointer because its author knew; a newcomer's
doubly linked list doesn't.

## Detailed design

### The diagnostic record

Today a diagnostic is `{ file; line; col; msg }` (`Core.fs:650–654`, main tree), and
`Program.errors` holds the ones collected in collect mode (facts sheet §3). The record gains
three fields:

```fsharp
type Severity = Error | Warning

type Note = { file: string; line: int; col: int; text: string }   // a related place: a step of a cycle's path

type Diagnostic =
  { severity: Severity
    name: string          // the warning's kind: "cycle"; "" for an error
    file: string
    line: int
    col: int              // 0 = unknown, as today
    msg: string
    notes: list<Note> }   // empty for every error today
```

- **Severity** decides three things: the word printed, whether the command fails, and the editor's severity. Nothing else reads it: a warning flows through the same `report`, the same `Program` field and the same cache entry as an error.
- **The name** is the warning's kind: the word `[<NoWarn "…">]` takes, printed in brackets after the message. An error has none.
- **Notes** are the other places a diagnostic is about, each with a position and a line of text: the fields on a cycle's path. The CLI prints them under the message; the language server sends them as `relatedInformation`. Errors have none today; an error with a chain to show can use them when its proposal wants to ([0012](0012-interrupts-noalloc-intrinsics.md)'s call chain, say).
- **`Program.errors` becomes `Program.diagnostics`,** both severities in the order found. `Driver.lift` stops on the first `Error` (today `match prog.errors with first :: _`, `Driver.fs:976`, main tree), and `Driver.build` returns the warnings with success: `Result<Diagnostic list, Diagnostic list>`. In the module cache ([0007](0007-incremental-builds.md)) a module's warnings are part of its checked result, so a module restored from the cache reports them again without being checked; a module with errors is still not kept (DESIGN §9).
- **In Z#** ([0020](0020-self-hosting.md)) it is the same record: `Severity` a union of two cases without fields, `notes` a `list<Note>`.

### The kinds

| Name | Warns about | Where | Proposal |
|---|---|---|---|
| `cycle` | a type whose objects can form a reference cycle through a mutable field | the type's declaration | this one, phase 12 |
| `stale-input` | a provider's input changed and the provider can't run here, so the types shown are from its last output | the `import` line, in editors | [0001](0001-type-providers.md) |
| `deprecated` | a use of a declaration marked `[<Deprecated "…">]` | the use | [0024](0024-library-api.md), the freeze before 0.1 |

- **One in phase 12.** `cycle` is built with the severity; the other two arrive with their proposals and register a row here. Every new kind is a design discussion with its own row: a warning that fires on correct code is noise, and noise is how warnings end up ignored.
- **Candidates for the third design review, not proposed:** an unused variable, an unused `open`, a `let mutable` never assigned, a `[<NoWarn>]` that silences nothing. Each is an ordinary analysis over the checker's output; what each needs is a decision that it's worth the attention it asks for.
- **Always on.** There is no `-W` family and no level: every kind is on in every build, and silencing is written in the source next to what it's about, where a reader sees it.

### Printing

```text
tree.zs:4:6: warning: 'Child' can reach itself through 'parent: ref<option<Parent>>' and 'Parent.kids: ref<list<Child>>', so its objects can form a cycle that reference counting never frees; make the back-pointer 'weak<Parent>', or mark the type [<Cyclic>] when the program breaks its cycles, or [<NoWarn "cycle">] when it can't form one [cycle]
 4 | type Child = { name: string; parent: ref<option<Parent>> }
   |      ^
tree.zs:1:17: note: 'Parent.kids: ref<list<Child>>' is on the cycle
 1 | type Parent = { kids: ref<list<Child>> }
   |                 ^
```

- **The line** is an error's (`printError`, `Main.fs:12–33`, main tree) with `warning:` for `error:` and the kind in brackets at the end, so what to write in `[<NoWarn>]` is on the line. Then the source line and the caret, as for an error.
- **Notes** follow, one per step of the path outside the warned declaration, each as `file:line:col: note: text` with its own source line and caret.
- **The count line** names both: `3 errors, 1 warning`, printed when there is more than one diagnostic in all, as `N errors` is today for more than one error (about `Main.fs:48–52`, main tree).
- **Standard error,** as errors are. A build with warnings prints them before `built …`.
- **`zs check`** prints warnings and exits 0 when there is no error. **`zs test`** prints its build's warnings once, before the tests' lines.

### `--strict`

- **`zs build --strict`, `zs run --strict`, `zs check --strict`, `zs test --strict`:** a warning fails the command as an error does. The warnings print unchanged, then one line names the reason, and the exit code is 1:

```text
2 warnings, errors under --strict
```

- **Nothing is built:** phase 12's warnings come from the checker, so a strict build stops where a build with errors stops.
- **For CI and the repository.** `./test.sh` passes `--strict` to every build and check it runs, which is phase 12's exit test that the repository's own code has no warnings. A project's CI does the same; a developer's build doesn't, so a warning never stops work on a machine.
- **The name.** `--strict`, not `-Werror`: Z#'s flags are words (`--time`, `--lib`, `--emit-llvm`, `--sanitize=thread`), and `-W` names a family (`-Wall`, `-Wextra`, `-Wno-cycle`) Z# doesn't have, since every kind is on and silencing is in the source. The alternatives are in *Unresolved questions*.
- **Not in `zs.toml`.** A manifest setting (`strict = true` under `[package]`) is one line to add when a project wants it always on; until then CI passes the flag. The language server never applies it.

### In editors

- **`zs lsp`** sends a warning as a diagnostic of severity 2, `source` `zs`, `code` the kind (`cycle`), so Zed underlines it in the warning color with the name, and its notes as `relatedInformation`, one entry per note with its position: a click goes to the field on the cycle. The range is the type's name (the checker has the identifier's length from `Syntax.positions`), where an error's range today runs from its column to the end of the line (`Lsp.fs:105–120`, main tree).
- **Only in its own file.** An error in another file shows on the first line of the open one (facts sheet §1), because it stops the build. A warning doesn't: a dependency's warning shows when that file is open and nowhere else.
- **Live:** the server re-checks the edited module on every change (facts sheet §1); a type declaration typed with its back-pointer gets the warning at once, and `weak` removes it at once. No build runs.
- **`zs mcp`:** `check` returns every diagnostic as `file:line:col: warning: … [cycle]` with its `note:` lines, and `no errors` when there is none of either; `build` and `run` return the warnings in their text and go on, so an agent sees them. There is no strict argument: an agent that sees a warning fixes it or leaves it, as a person would.
- **Code actions** come with track E's lossless tree ([0019](0019-syntax-tree.md)): "make `prev` weak" (`ref<option<Node>>` to `ref<option<weak<Node>>>`, at the note's position) and "mark `Node` [<Cyclic>]". The warning carries both positions, so 0019 adds the edits and nothing here changes.

### Silencing

- **`[<NoWarn "cycle">]`** on a declaration silences that kind among the diagnostics reported at that declaration: a type, a function, a value or an `import`. Several kinds: `[<NoWarn("cycle", "deprecated")>]`, the attribute syntax the parser has (`[<Name "s">]` and `[<Name(a, b)>]`, facts sheet §5). It combines with other attributes as `[<Derive(Json); NoWarn "cycle">]`.
- **The name is checked:** an unknown one is an error naming the kinds, so a typo can't silence nothing silently.
- **Only declarations.** Not files and not modules: a module-wide `NoWarn` hides the next cycle too. *Unresolved questions* has the `module M =` form.
- **Where the warning lands** is where the attribute goes: `deprecated` is reported at the use, so `[<NoWarn "deprecated">]` goes on the function that makes the use.
- **Attributes on functions and values.** Today a function takes `Export`, `Test`, `Wrapping`, `FastMath`, `Target` and `Multiversion` and nothing else, and a value takes none ("attributes are only supported on type declarations yet", `Typer.fs:3631`, main tree). `NoWarn` opens that path, which [0009](0009-tests-as-values.md)'s `[<Tests>]` and [0024](0024-library-api.md)'s `[<Deprecated>]` need as well.
- **`[<Cyclic>]`** on a type says what `[<NoWarn "cycle">]` doesn't: the type forms cycles, and the program breaks them. It silences every cycle through that type, wherever the warning would have landed (the type declared last on the cycle, below), so one attribute covers a `Parent`/`Child` pair, on whichever type's documentation explains it. `[<NoWarn "cycle">]` is for the other case, a type the analysis is wrong about (a mutable binary tree, below), and silences the warning at its own declaration only. `[<Cyclic>]` is DESIGN §5.2's choice; the general mechanism exists for the next kinds.
- **A silence that silences nothing** is accepted without a diagnostic: `[<Cyclic>]` documents a type whether or not the analysis sees its cycle (one through a closure, say). A warning for a stale `[<NoWarn>]` is on the candidates list.

### The cycle analysis

The analysis runs in the type checker at the end of each module's declarations.

- **The graph:** a node per declared record or union type; an edge per field (a union case's fields count) to each declared type the field's type mentions, looking through `option`, `list`, `array`, tuples, `Map` and the other immutable containers, and through a generic type at its arguments (`Cell<Node>` is unfolded, as `needsRc` and `shareBlocker` unfold them, `Core.fs:681–748`, main tree). A type variable, a function type (`'a -> 'b`, `share<F>`, `callback<F>`), a `dyn Trait` and a C pointer make no edge: what they hold isn't in the type.
- **`weak<T>` makes no edge:** that is what it's for.
- **A mutable edge** passes through a cell on the way: `ref<T>`, `Buffer<T>`, and the thread cells `Mutex<T>` and `Channel<T>`, which hold a value that `Mutex.set`, `Mutex.update` and `Channel.send` replace or add to (`Core.isCellType` lists the cells, `Core.fs:147`, main tree). `Atomic<T>` holds numbers, bools and chars, so it makes no edge. Everything else in Z# is immutable, and an immutable value points only to values built before it (DESIGN §5.2): no cycle without a cell.
- **The rule:** a type is warned when it lies on a cycle of the graph with a mutable edge, **except a cycle of one type through one field.** `type Node = { next: ref<option<Node>> }` is a list, `children: ref<list<Node>>` with a weak parent is a tree, `edges: ref<list<Node>>` is a graph: a loop there is made by use, not by the type, and a type with one way back to itself has no back-pointer to make weak. Two fields of a type that reach it (`next` and `prev`), or two types that reach each other (`Parent.kids`, `Child.parent`), are a forward link and a back link: the shape the warning is for.
- **Where:** one warning per cycle, at the type declared last among the cycle's types, the declaration that closes it, so it appears when that line is typed. The path is in the message (the warned type's own fields first) and in the notes (the other types' fields, each at its position).
- **Per module, and so per cache entry.** A cycle can't cross modules: a type names only types in scope, modules are checked in dependency order, and an import cycle is an error (`Driver.fs:635`, main tree). So the graph is the module's types plus edges leaving to earlier modules' types, which never come back; one Tarjan pass over it per module, linear in the module's types and fields; and a module's warnings depend on its own source and its dependencies' interfaces, which is the module cache's key ([0007](0007-incremental-builds.md)).
- **What it misses:** a cycle made by use through one field (a list linked into a loop), a cycle through a closure (a `ref<option<unit -> unit>>` whose function captures the record holding it), a cycle through `dyn`. `ZS_LEAKCHECK=1` stays the backstop (decision 40), and `./test.sh` runs with it.
- **What it over-reports:** a mutable binary tree, `left: ref<option<Tree>>` and `right: ref<option<Tree>>`, has two fields reaching `Tree` and no back-pointer; the type graph can't tell it from a doubly linked list. The message names the three answers, and `[<NoWarn "cycle">]` is this one's. A mutable union, `Add of ref<Expr> * ref<Expr>`, is the same case.
- **The repository today** has `tests/weak.zs`'s tree (one field back, `children`, with a weak parent) and `lib/std/Threading/Task.zs`'s `Cancel`, `Scope` and `Promise` (`ref` fields holding numbers, bools and functions): no warnings, so phase 12's exit test holds without an attribute anywhere.

### Order of implementation

1. **The record and the printing:** `Severity`, `name`, `notes`; `Program.diagnostics`; `printDiagnostic` for `printError`; the count line; `zs lsp`'s severity, code and related information; `zs mcp`'s text; `--strict` on the four commands. No warning exists yet, so no output changes.
2. **`cycle`:** the graph and the Tarjan pass at the end of each module; `[<Cyclic>]`; `[<NoWarn>]` on type declarations with the name check. Tests under `tests/`: the doubly linked list, the `Parent`/`Child` pair, the observer pair, each an `.err` test under `--strict` (the expected lines are the warning, its notes and the strict line; an `.err` test compares the compiler's lines, facts sheet §14), and the list and the weak tree as `.out` tests that build in silence.
3. **`[<NoWarn>]` on functions, values and imports:** the attribute path in `Typer` opened past type declarations, shared with 0009 and 0024.
4. **`./test.sh` with `--strict`** on every build and check: the exit test.
5. **Later kinds** register their rows: `stale-input` with 0001, `deprecated` with 0024. **Code actions** with 0019.

## Drawbacks

- **The analysis is a type-level approximation.** It misses what it can't see (closures, `dyn`, loops made by use) and over-reports mutable trees with two child links. Both are stated in the message and the guide; the first keeps `ZS_LEAKCHECK=1` necessary, the second asks for an attribute on correct code.
- **Two attributes for one warning.** `[<Cyclic>]` and `[<NoWarn "cycle">]` mean different things (the cycle is real and handled; the analysis is wrong here), and the difference has to be learned.
- **Warnings accumulate** if kinds are added freely, and a project with fifty reads none: C's experience. The gate is that every kind is a design discussion, and phase 12 adds one.
- **`--strict` ties CI to the compiler's version:** a new kind in a newer compiler fails a build that passed, which is why Cargo doesn't make `-D warnings` the default. In 0.x each new kind is a `CHANGELOG.md` entry (phase 12), and a project adds the `[<NoWarn>]` or drops the flag for the upgrade.
- **Every printer changes:** the CLI, the language server, the MCP tools and `./test.sh`'s `.err` comparisons all learn the second severity, in one phase.

## Alternatives

- **An error.** Rejects the cycles a program breaks by hand, which DESIGN §5.2 allows as Swift does; an attribute that turns the error off would be this proposal under another name. Not chosen.
- **A lint tool outside the compiler** (`zs lint`, as `go vet` and clippy). The analysis needs the checker's type graph, so the tool would re-run the checker or share it; editors would run two programs; and the one cache ([0007](0007-incremental-builds.md)) would serve the compiler's own diagnostics for nothing. Not chosen; a `zs lint` for style checks that need no types can come later.
- **F#'s `#nowarn "40"` pragmas and `--nowarn` flags.** A pragma is file-scoped and numbered; a flag is invisible from the source. An attribute sits on the declaration it's about, with a name, as Z#'s other per-declaration choices do (`[<Wrapping>]`, `[<Derive>]`). Not chosen.
- **Warning numbers** (`FS0040`, `C4996`, `E0308`). A number needs a table to read; a name is read where it's printed and typed into `[<NoWarn>]`. Not chosen; whether numbers come in addition is in *Unresolved questions*.
- **`-Werror` or `--warnaserror`.** The same switch under C's and F#'s names; `-Werror` implies a `-W` family and `--warnaserror` is a sentence. Not chosen; the question stays open below.
- **Warning levels or `-Wall`.** Levels exist to keep noisy kinds off by default; a kind not worth being on isn't worth adding. Not chosen.
- **A cycle collector,** or a runtime leak detector that names the type at exit. Decision 40 chose not to collect cycles, and a tracer is a GC's. Not chosen; `ZS_LEAKCHECK=1` already reports the live objects.
- **The broader rule,** ROADMAP's wording taken literally: warn on every type that reaches itself through a mutable field, one field included. It warns on every mutable list, tree and graph, `tests/weak.zs`'s tree among them, so the exit test that the repository has no warnings would need an attribute on the example of doing it right, and programmers would add the attribute by reflex. Not chosen; it is the alternative in *Unresolved questions*.
- **Doing nothing.** The leak check at exit and the guide's page. Not chosen: both stay, and the warning puts the finding where the mistake is made, which neither can.

## Compatibility

- **Not a breaking change.** A program that now gets a warning still builds, with exit code 0; only `--strict` changes an exit code, and only when asked. No existing program has `[<Cyclic>]` or `[<NoWarn>]`: an unknown attribute is an error today (`unknown attribute '…'`, `Typer.fs:3630`, main tree).
- **An older compiler** meeting the new source stops at `[<Cyclic>]` with `unknown attribute 'Cyclic'`, and at `[<NoWarn "cycle">]` on a function with `attributes are only supported on type declarations yet`; both name the line. An older `zs build --strict` ignores the flag without a message, since flags are looked up by name and the rest passed over (`Main.fs:274–290`, main tree).
- **Compiled binaries:** none to consider; packages are source (decision 27), and nothing of a warning reaches a binary.
- **The library** is unchanged and warning-free under the rule (its `ref` fields hold numbers, bools and functions). It uses neither attribute.
- **Dependencies:** a dependency's warnings print with the project's build and fail it under `--strict`; a dependency meant for strict builds silences its own warnings in its source, as it fixes its errors.
- **Microcontrollers:** nothing differs by target; `ref` and `Buffer` exist on Cortex-M and the rule is the same, and a warning costs a microcontroller build nothing.
- **Tests:** `.err` tests keep their format; `./test.sh` adds `--strict`.
- **The compiler in Z#** ([0020](0020-self-hosting.md)) takes the record as it is.

## Pragmatics

### Diagnostics

| Situation | Error |
|---|---|
| two fields of a type reach it, one through a cell | `list.zs:1:6: warning: 'Node' can reach itself through 'next: ref<option<Node>>' and 'prev: ref<option<Node>>', so its objects can form a cycle that reference counting never frees; make the back-pointer 'weak<Node>', or mark the type [<Cyclic>] when the program breaks its cycles, or [<NoWarn "cycle">] when it can't form one [cycle]` |
| two types reach each other | at the later type, as above with `'parent: ref<option<Parent>>' and 'Parent.kids: ref<list<Child>>'`, then `tree.zs:1:17: note: 'Parent.kids: ref<list<Child>>' is on the cycle` |
| a mutable tree with two child links | the same warning; `[<NoWarn "cycle">]` is its answer |
| warnings under `--strict` | the warnings as above, then `2 warnings, errors under --strict` (or `1 warning, an error under --strict`), exit code 1 |
| `[<NoWarn "cycles">]` | `unknown warning 'cycles' (the kinds are cycle, stale-input and deprecated)` |
| `[<NoWarn>]` without a name | `[<NoWarn>] takes the warning's name: [<NoWarn "cycle">]` |
| `[<Cyclic>]` on a function or a value | `[<Cyclic>] goes on a type declaration; [<NoWarn "cycle">] silences the warning on any declaration` |
| `[<Cyclic>]` on a type with no cycle the analysis sees | nothing: the attribute documents the type |

### Tooling

- **`zs lsp`:** diagnostics while editing: a warning underlined at the type's name at severity 2 with the code `cycle`, its notes as related information, published on each change with no build run, in the file it belongs to only. Hover, completion, definition, references and inlay hints are unchanged: a warning adds no names. Code actions ("make `prev` weak", "mark `Node` [<Cyclic>]") come with [0019](0019-syntax-tree.md).
- **`zs mcp`:** `check` returns the lines above; `build` and `run` include them and go on.
- **The tree-sitter grammar** gains nothing: `[<Cyclic>]`, `[<NoWarn "cycle">]` and `[<NoWarn("cycle", "deprecated")>]` are the `attribute` rule it has (`grammar.js:83–87`), highlighted as attributes are. `zs fmt` leaves attributes as written.
- **`zs doc`** shows `[<Cyclic>]` with a type's declaration, since it says something about using the type; `[<NoWarn>]` isn't shown.
- **Zed:** a warning in the problems panel with its name, and the related places under it.

### Performance

- **Existing code:** nothing at run time, and nothing in a binary. In the compiler, one record grows by three fields, and printing costs what it did.
- **The analysis:** one pass over a module's types and fields per check, with generic unfolding of the shape `needsRc` and `shareBlocker` already do per type; linear, and small next to type checking. Estimate: under a millisecond for a module of a hundred types.
- **In the editor:** the pass runs on each re-check of the edited module only (the rest is restored from the cache with its warnings), inside track E's 100 ms budget.
- **`--strict`:** the same work; a strict build with warnings stops before code generation.

### Scaling

Estimates:

| Dimension | Typical | Upper bound |
|---|---|---|
| types per module | 5–30 | 5,000 (one linear pass) |
| fields per type on the graph | 1–10 | 500 |
| types on one cycle | 1–2 | 50 (one warning, one note per other type) |
| warnings per build | 0 | 10,000 (printing stays linear; the editor publishes per file) |
| names in one `[<NoWarn>]` | 1 | the number of kinds |
| warning kinds | 1 in phase 12, 3 with 0001 and 0024 | tens; each a design discussion |

### Culture-aware formatting and parsing

- **Invariant.** Messages are English, as errors are; counts are plain integers; positions are `file:line:col` with the file as written on the command line. A kind's name is ASCII and lower case, the same in the message, the attribute and the editor's code.
- **Nothing is parsed from the user** but the attribute's string, compared exactly.

## Unresolved questions

1. **The strict flag's name:** `--strict` (this proposal), `-Werror` (C; Rust's `-D warnings` is the same idea) or `--warnaserror` (F#). And whether `zs.toml` gets `strict = true` under `[package]`: not now; one line when a project asks.
2. **Numbers for documentation:** names only (this proposal), or a number per kind in addition (`W001 cycle`) for a stable page per warning. A page per name in `docs/reference` serves the same purpose while names don't change.
3. **`[<NoWarn>]` on modules:** declarations only (this proposal), or also `module M =` blocks, silencing a kind in every declaration inside. Chosen later if the repository's own code needs it.
4. **The one-field exemption:** keep it (this proposal), or ROADMAP's broader rule that warns on every mutable self-reach, lists, trees and graphs included, with `[<NoWarn "cycle">]` on each.
5. **The next kinds:** none beyond `cycle` in phase 12 (this proposal), or one or more of the candidates (unused variable, unused `open`, `let mutable` never assigned, stale `[<NoWarn>]`) if the third design review wants them; each with its own row and discussion.
6. **`Mutex` and `Channel` as mutable edges:** counted (this proposal), since they hold values that are replaced, or `ref` and `Buffer` only, as ROADMAP words it.

## History

- **2026-10-22:** drafted from phase 12's deferred item "From phase 9.5, cycle warnings" (ROADMAP), DESIGN §5.2's "Warning about them (planned, phase 12)" and §12, and the facts sheet's §1 and §3 (no severity today).
