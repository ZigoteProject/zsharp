# Proposal 0040: declarative code: implicit yields, `open type` and trailing blocks

| | |
|---|---|
| **Status** | Draft |
| **Decided at** | not yet: a design review. Items 1 and 2 are F#'s (decision 34: missing F# syntax first); item 4 is new syntax and needs the discussion decision 34 asks for. Each item that's taken gets a decision row, numbered by the coordinator |
| **Builds** | after 0.7, in the steps under *Order of implementation*; the compiler's own code can use them only once stage 0 has them |
| **Rests on** | decisions 9 (no overloading), 10 (structural equality; functions have none), 14 (named and optional arguments on members only), 20 (no macros), 23 (effect handlers), 34 (surface syntax), 39 ("simple"), 46 (builders are modules), 58 (anonymous records declined) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §6.1](../../DESIGN.md#61-effect-handlers-phase-10-v3) (a clause that resumes last is a call) |
| **Related** | [0005 ergonomics](0005-ergonomics.md) (list expressions), [0002 effect handlers](0002-effect-handlers.md), [0017 iteration](0017-iteration.md) (list expressions over any `Iter`), [0019 the syntax tree](0019-syntax-tree.md) (`zs fmt`), [0021 warnings](0021-warnings.md) |
| **Changes** | DESIGN §2.1, §2.3 and §13; the specification's §2.4 (name resolution), §4.5 (members), §5.4 (records), §5.10 (lists) and §13 (grammar, §13.5's ambiguities); the guide's chapters on collections, functions and *Z# for F# programmers*; `src/Syntax/Lexer.zs`, `Parser.zs`, `Tree.zs`, `Format.zs`; `src/Infer/` (list expressions, method calls, `open`); the tree-sitter grammar and the Zed pin (two commits, AGENTS rule 8) |

- [ ] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

Code that describes a tree reads worse in Z# than in Compose, SwiftUI or Flutter. Examples are
a user interface, a test list, a document or a board's configuration. Four small changes close
most of the gap. Each lowers to what the language already has, and each can be decided apart
from the others:

| # | Form | Meaning | From |
|---|---|---|---|
| 1 | `[ header; if c then a; for x in xs -> row x ]` | a list expression: any `[ ]` or `[\| \|]` holding a `for`, `if`, `match` or `let` item; without an explicit `yield`, a statement that isn't `unit` is an element | F# 4.7 |
| 2 | `open type Ui` | `Ui`'s static members are names in scope: `Button("Save", onClick = Save)` | F# 5 |
| 3 | `connect {` at a line's end, then `port = 9000` on the next | a record argument, not a computation expression | a fix |
| 4 | `Column(spacing = 8) { … }` | a trailing block: the method's last argument, `fun () -> …` | Kotlin, Swift |

Together with effect handlers, which the language already has, they give this:

```fsharp
open type Ui

let view (m: Model) =                       // inferred: Model -> unit / Ui<Msg>
  Column(spacing = 8) {
    Text($"Count: {m.count}")
    if m.count > 0 then Button("Reset", onClick = Reset)
    for item in m.items do itemRow item
  }
```

No new kind of type, no builder protocol, no macro. `if`, `for` and `match` inside the block are
the language's own, because children come from an effect (`Ui.emit`), not from a builder.

## Motivation

### What it looks like today

A widget is a static member, since only members take named and optional arguments
(decision 14). Its children are a list, and a list that has a conditional child must be a list
expression. A list expression must begin with `for` or `yield` (spec §5.10), and every value
in it needs `yield`:

```fsharp
let view (m: Model) =
  Ui.Column(
    [ yield Ui.Text($"Count: {m.count}")
      if m.count > 0 then yield Ui.Button("Reset", onClick = Reset)
      for item in m.items -> itemRow item ],
    spacing = 8)
```

The same view with children from an effect needs a lambda as a positional argument, ahead of
the named ones:

```fsharp
let view (m: Model) =
  Ui.Column((fun () ->
    Ui.Text($"Count: {m.count}")
    if m.count > 0 then Ui.Button("Reset", onClick = Reset)
    for item in m.items do itemRow item), spacing = 8)
```

Each part is reasonable alone. Together they put noise on every line: `yield` on every child,
`Ui.` on every widget, the closing `)` and the configuration at the end of the tree, far from
the widget they configure.

### The scenarios

- **User interfaces.** Decision 30 puts games over C libraries next after the first three
  audiences. A game has a HUD and menus, and a desktop or embedded display has screens. Z# runs
  on Cortex-M, where a declarative UI over a small display is a good fit.
- **Test lists.** `testList "posix" [ … ]` with a test only on some targets is a list
  expression today (`yield` on every test). With item 1 it's
  `[ test "a" …; if not Native.isWindows then test "b" … ]`.
- **Documents and configuration:** HTML, a report, a menu, a board's pins. Each is a tree of
  values with conditionals and loops in it.

### What the others do, and why Z# can do it with less

- **Compose** marks a function `@Composable`. A compiler plugin then threads a hidden
  `Composer` through it, and children are emitted into it. That is an effect, bolted on.
- **SwiftUI's result builders** rewrite a closure's statements into `buildBlock`, `buildEither`
  and `buildOptional` calls, so that `if` and `for` work inside a view. That is type-level
  machinery for control flow.
- **Flutter** passes lists of children (`children: [ … ]`, with collection `if` and `for`).
  That is Dart's version of item 1.

Z# already has typed effects whose clauses cost a call when they resume last (DESIGN §6.1,
spec §8's cost model). A widget performs `Ui.emit`, and a container handles it for its
children. So the `if`, `for`, `match`, `let` and helper functions inside a view are plain
code. The type says which functions build UI (`/ Ui<Msg>`), which is what `@Composable`
says, but here the checker enforces it. The syntax is missing, not the semantics.

## Detailed design

### 1. Implicit yields in list and array expressions

**Which brackets are list expressions.**
- A `[ ]` or `[| |]` whose items include a `for`, `if`, `match`, `let` or `yield` item is a list
  expression, wherever that item is.
- Today only one that *begins* with `for` or `yield` is (spec §5.10, §13.5).
- A bracket of plain expressions stays a literal, and so does a range.
- A parenthesized `if` (`[ (if c then a else b) ]`) is a plain expression, so it stays a
  literal's element.

**Which statements are elements.** In a list expression with no explicit `yield` or `yield!`
in its own statements, each statement in statement position is checked first, then classified:

- A statement of type `unit` runs for its effect, as now.
- Any other statement, including one whose type is still a type variable, is an element: it's
  `yield` of it.

This is F#'s rule (RFC FS-1069).

- **Where it applies:** the statement positions of the list expression itself: its body, and
  the bodies of its `for`, `if`, `match` and `let`. Not inside a lambda written in it, which is
  a function of its own.
- **With an explicit `yield`:** an expression that has any explicit `yield` keeps today's rule.
  A statement that isn't a yield must be `unit`. Mixing the two forms would make a reader check
  each line's type to know what the list holds.

```fsharp
let row (i: Item) = Ui.Text(i.name)

let items (m: Model) =
  [ header m                               // an element
    log "rendering"                        // unit: runs, not an element
    if m.count > 0 then badge m.count      // an element when m.count > 0
    for i in m.items -> row i              // `->` is yield, as before
    match m.footer with
    | Some f -> footer f
    | None -> () ]                         // unit: no element
```

**Lowering.** The parser builds the `Ast.ListComp` it builds today. The checker marks each
classified statement as an `Ast.Yield`. So an implicit list expression and its explicit form
compile to identical IR, and a `.same-ir` test pins that.

### 2. `open type`

`open type T` brings the static members of `T` into scope as unqualified names, at the
precedence `open` gives a module's names (spec §2.4: nearer scopes first).

- **Scope:** only static members. A union's cases and a record's fields are already reached
  through their module. Instance members are reached through a value.
- **What can be opened:** a type that's declared with members only, which groups static members
  (spec §4.5), or any record or union. It names the type as `open` names a module, qualified
  where needed (`open type Widgets.Ui`).
- **Calls:** an opened method is called as it would be qualified, with its named, optional and
  default arguments: `Button("Save", onClick = Save)` is `Ui.Button("Save", onClick = Save)`.
- **Clashes:** a name that's both an opened static member and a nearer union case or value
  resolves as names do, the nearest first. Hover says which was meant.

### 3. A record argument after a line break

Today a record argument whose opening brace ends a line, after a name, is parsed as a
computation expression:

```fsharp
connect {
  port = 9000
  tls = None }
```

- **Why:** the lexer opens a block after a `{` that ends a line and follows a name
  (`Lexer.zs`, for `task {`). `ceAhead` (`Parser.zs`) then takes the indented block for a
  computation's body.
- **Result:** `connect` becomes `Connect.Builder`, which doesn't exist. The record literal F#'s
  Stroustrup style writes doesn't compile. The same happens after any argument, for example
  `send msg {`.

**The rule:** after `{`, and after the block's indentation if one opened, a body that begins
with a field name, optionally qualified, and then `=` is a record literal. So is one that begins
with an atom and then `with`.

- **Why it's safe:** a statement `x = e` is never meant as a statement (spec §13.5: equality,
  and an error that advises `<-`), so the rule takes nothing from computation expressions.
- **What else changes:** the record parser accepts the block layout: fields separated by line
  breaks at the block's indentation, ending at a dedent or at `}`.

This item is a fix, and it can land on its own. Item 4 needs it, since a trailing block and a
record argument are told apart the same way.

### 4. Trailing blocks

**Form.** A method call's closing parenthesis, followed on the same line by `{`, opens a
**trailing block**:

```fsharp
Column(spacing = 8) { Text("a"); Text("b") }

Column(spacing = 8) {
  Text("a")
  if wide then Text("b")
}
```

- **Exception:** the brace's contents begin as a record literal (item 3's rule). Then it's an
  application to a record, as now.
- **Layout:** the lexer opens a block after a `{` that ends a line and follows `)`, as it does
  after a name. The block ends at its `}` or at a line left of it, as a computation's does.

**Meaning.** `M(args) { body }` is `M(args, p = fun () -> body)`, where `p` is `M`'s last
parameter.

- **Errors:**
  - `p` must be a function from `unit`.
  - It must not also be given in the parentheses.
  - A required parameter other than `p` that isn't given is an error, as now.
- **Zero arguments:** `M() { body }` calls a method whose only argument is the block.
- **Typing:** the block is a lambda with no annotation. It's typed last (decision 41), with
  the type the parameter has, effect row included. So the block performs what the parameter
  allows, and a block that performs `Ui` passes where `content: unit -> unit / Ui<'msg>` is
  expected.
- **Lowering:** none beyond the lambda. Inlining treats it as the lambda it is.

**Where it doesn't apply:**

- **A function application** (`f (x) { … }`, `f x { … }`): a curried function has no "last
  parameter" until it's applied. `f x { … }` is also the form a record argument already has.
  It's an error that names the fix: `(fun () -> …)`. Unresolved question 2 asks whether to
  widen it.
- **A bare name** (`Column { … }`): `w { … }` is a computation expression whose builder is
  `W.Builder` (decision 46). `Column() { … }` is the form with no arguments.

### The library this is for (not proposed here)

The design is checked against this shape. No UI library is part of this proposal.

```fsharp
type Node<'msg> =                            // structural equality, derived: no closures in it
  | TextNode of string
  | ButtonNode of label: string * onClick: 'msg * enabled: bool
  | ColumnNode of spacing: int * children: array<Node<'msg>>

effect Ui<'msg> =
  abstract emit : Node<'msg> -> unit

// what content emits, in order; the clause resumes last, so each emit is a call
let children (content: unit -> unit / Ui<'msg>) : array<Node<'msg>> =
  let kids = Buffer.empty
  handle content () with
  | Ui.emit n, k ->
    Buffer.push n kids
    k ()
  | return () -> Buffer.toArray kids

type Ui =
  static member Text(s: string) = Ui.emit (TextNode s)
  static member Button(label: string, onClick: 'msg, ?enabled: bool = true) =
    Ui.emit (ButtonNode(label, onClick, enabled))
  static member Column(?spacing: int = 0, content: unit -> unit / Ui<'msg>) =
    Ui.emit (ColumnNode(spacing, children content))   // the outer handler gets the column
```

- **Diffing:** a button carries a message value, Elm's way, not a closure. So `Node<'msg>` has
  derived equality, and a renderer can diff the tree it gets against the last one. It can skip
  a subtree that's the same object.
- **State:** it lives in the model (MVU), not in the view. Compose's `remember` needs an
  identity per call site, which Z# doesn't have, and this proposal doesn't add one.

### Order of implementation

1. **Item 3**, the record layout fix: `tests/record_after_break.zs`, and the parser's tree
   (`Tree.Record` in block layout) for `zs fmt`.
2. **Item 1:** the parser's choice of list expression, then the checker's classification.
   - `tests/implicit_yield.zs` covers each statement form, nested `for` and `match`, and
     arrays.
   - `tests/err_implicit_yield.zs` covers a mixed list, an element of the wrong type, and a
     `unit` statement where an element was meant.
   - A `.same-ir` pair checks implicit against explicit.
3. **Item 2:** `Ast.Open` takes a type, and name resolution gains a type's static members.
   `tests/open_type.zs` and `tests/err_open_type.zs`.
4. **Item 4:** the lexer's layout after `) {`, `Ast.TrailingBlock`, and the checker filling the
   last parameter.
   - `tests/trailing_block.zs`.
   - `tests/err_trailing_block.zs`: a function, a parameter given twice, a parameter that
     isn't a function from `unit`.
5. **The measurement**, before the design review decides item 4. The library shape above goes
   in `bench/ui/`, building a view of 10,000 nodes nested 6 deep two ways: through `Ui`, and as
   lists with implicit yields. `ZS_STATS=1` gives the allocations, and cachegrind counts the
   instructions, as `bench/host` does. `bench/effects/` has the same kind of measurement for
   `seq { }` and `Task`.
   - **The criterion:** through `Ui`, nothing is allocated per `emit` beyond the node and the
     buffers' growth, and the instruction count is within 1.5× of the lists'.
   - **If it fails:** the report says why, and items 1–4 still stand, with a UI library on
     lists.
6. **The grammar:** the tree-sitter grammar and its corpus, then the Zed pin, in two commits.
   Then the guide (collections: implicit yields; functions: trailing blocks; *Z# for F#
   programmers*: `open type`), DESIGN §2.1 and §2.3, the specification and `CHANGELOG.md`.

## Drawbacks

- **Implicit yields are type-directed.** A statement's meaning depends on its type: in
  `[ for x in xs do f x ]` the list holds `f x` or nothing, depending on what `f` returns. F#
  accepted this, and the diagnostics below name the statement taken for an element. Hover on a
  statement in a list expression should say "an element" or "runs for its effect".
- **Two ways to write a list expression,** with and without `yield`. F# has both.
- **A third meaning for `{` after an expression:** a record, a computation's body, or a block.
  The rule is syntactic and local: what precedes the brace (a name, or `)`), and whether the
  contents begin `ID =` or `e with`.
- **`open type` adds unqualified names,** as `open` does. A project with many opened types can
  shadow its own names. The nearest-first rule and hover keep that readable.
- **In the effect style, a widget is a statement, not a value.** So modifiers can't be a
  pipeline (`Text("Hi") |> padding 16` has nothing to pipe). They are named arguments
  (`Text("Hi", padding = 16)`), Compose's `modifier` parameter, or wrapping containers
  (`Padding(16) { Text("Hi") }`), Flutter's. A library on lists keeps pipelines.
- **The row shows up:** every view function's type carries `/ Ui<'msg>`. That's the point
  (the checker knows which functions build UI), but it's one more thing in hover. Decision 80
  hides only rows that connect function arguments to results.

## Alternatives

- **User builders with `yield`, `combine` and arguments**, as Fabulous builds SwiftUI's look
  on F#'s computation expressions (`VStack(spacing = 8) { … }` with `[<CustomOperation>]`).
  - Builders are modules (decision 46), so a builder can't carry `spacing`.
  - `combine` makes a closure per statement for the optimizer to remove.
  - Custom operations are syntax defined by attributes.
  - Effects give the same control flow with none of it.
- **Swift's result builders:** `buildEither` and `buildOptional` exist to make `if` work inside
  a closure whose statements become values. In Z#, `if` already works, because the statements
  stay statements.
- **Named arguments on curried functions.** Decision 14 keeps curried functions' types plain.
  Members already have named arguments, and `open type` makes members read like functions.
- **Anonymous records for a widget's properties:** declined in 0006 (decision 58). Optional
  arguments and records with defaults cover them.
- **Macros or a compiler plugin,** as Compose has: decision 20.
- **Scala 3's colon blocks** (`Column(spacing = 8):` and an indented block): in Z#, `:` is an
  annotation (`(e: T)`). Braces match `task { }` and read as Kotlin's and Swift's.
- **Implicit yields with an explicit `yield` present:** F# doesn't do this, and a reader would
  have to know each statement's type to read the list.
- **Trailing blocks after any application:** see unresolved question 2.

## Compatibility

Not breaking, with one exception in item 1.

- **Item 1:** a list expression that has a statement neither `unit` nor a yield is an error
  today (spec §5.10), so no list that compiles today changes meaning, with one exception. A
  literal whose element is an `if`, `match` or `let` expression becomes a list expression with
  the same value (`[ if c then a else b ]`), unless that element is `unit`:
  `[ if c then () else () ]` was `[()]` and becomes `[]`. F# had the same change.
  `CHANGELOG.md` says so, and the fix is parentheses: `[ (if c then () else ()) ]`.
- **Item 2:** `type` is a keyword, so `open type` is an error today.
- **Item 3:** the bodies it changes were computation expressions whose first statement is an
  equality, an error today.
- **Item 4:** `) {` followed by anything but a record literal is a parse error today.
- **Older compilers:** a program that uses these doesn't build with 0.7.1. `src/` can use them
  only once stage 0 has them, and moving stage 0 is a pin change that needs asking first.
- **The library:** unchanged. `lib/` may adopt implicit yields later; this proposal doesn't
  reformat anything.

## Pragmatics

### Diagnostics

Proposed wording, in [the diagnostics page](../contributing/diagnostics.md)'s form:

```text
this list has a yield, so a statement that isn't one must be unit, and this is string; yield it, or take out the list's yields
this statement is an element of the list (it isn't unit), of type string, and the list's elements are int; ignore it with |> ignore, or make it an int
open type Ui: Ui has no static members
a block after a call is the last argument of a method, and f is a function; pass it as (fun () -> …)
the block is Column's last argument, content, which is also given in the parentheses
the block is Column's last argument, spacing: int, which isn't a function from unit
```

### Tooling

- **The lossless tree** (0019) gains `Tree.OpenType` and `Tree.TrailingBlock`. `zs fmt` keeps a
  one-line block on one line and puts a block that doesn't fit after `{` at the line's end, as
  it does for `task { }`.
- **The LSP:**
  - Completion after `open type ` lists types.
  - Hover on an opened member shows its type.
  - Hover on a list expression's statement says whether it's an element.
  - Signature help inside a trailing block shows the parameter it fills.
- **The grammar:** tree-sitter needs the two forms and the wider list-expression rule. That's
  two commits under AGENTS rule 8.

### Performance

- **Items 1–4:** nothing at run time. They lower to forms the optimizer already sees: a list
  expression, a qualified call, a record, a lambda.
- **The `Ui` effect's cost** is step 5's measurement, and item 4's decision waits for it.

### Scaling

- **Item 1:** one classification per statement, after its check, which the checker already
  does to warn about a value left unused.
- **Item 2:** adds a type's static members to a scope, as `open` adds a module's names.

### Culture-aware formatting and parsing

None.

## Unresolved questions

1. **Implicit yields in `seq { }`,** which F# also has. The same rule would apply to the seq's
   own statement positions, and not to a lambda's, where `yield` works today. Proposed: not
   now; a seq is rarely a tree.
2. **Trailing blocks after a function application** (`column [ spacing 8 ] { … }`), as one more
   argument. This would serve UI libraries written as modules of curried functions, but it
   collides with `f x { record }` more often. Proposed: methods only until a library asks.
3. **A required block parameter after optional ones** (`?spacing`, then `content`). Kotlin
   allows it. Step 4 checks whether the checker's parameter order allows it now; if not, the
   block's parameter is the one exception.
4. **A member's function parameter with an open row** (`unit -> unit / <Ui<'msg> | 'e>`), so a
   view can also log or throw. Step 5 checks that a static member generalizes it as a function
   does (spec §8: members may have effectful function types).
5. **`open type` and union cases:** F# opens them too. Proposed: static members only, since a
   type's cases come with its module.
6. **A UI library:** whether it's a first-party package, what it renders to (a display on a
   chip, a window over a C library), and keyed lists for diffing. Out of scope: this proposal
   is the syntax and the measurement.

## History

- **2026-11-27:** drafted from a review of how UI and other tree-shaped code reads in Z#
  against Compose, SwiftUI and Flutter. The current rules were read from the parser
  (`ceAhead`, `compStmt`, the list-expression choice in `atom`), the lexer's brace layout and
  the specification; none was run, since no compiler was built while it was written. Item 3's
  defect follows from `Lexer.zs`'s block after `name {` and `ceAhead`'s `Indent` case;
  step 1's test confirms or corrects it.
