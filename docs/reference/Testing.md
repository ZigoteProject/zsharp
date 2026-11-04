# Testing

Tests as values (0009): `test "name" (fun () -> …)` is a `Test`, `testList` groups them, and
a top-level value marked `[<Tests>]` is what `zs test` runs, each test in its own process.

## Traits

### `Testing.Outcome`

```zsharp
trait Outcome<'r>
```

What a test's body gives back: nothing (a panic fails it), a `result` (an `Error` fails it),
or a task (Std's impl runs it on the event loop).

#### `Testing.Outcome.finish`

```zsharp
abstract finish : 'r -> unit
```

Panics when the outcome is a failure.

### `Testing.Arbitrary`

```zsharp
trait Arbitrary<'a>
```

A type with a default generator: what `testProperty` draws its parameters with. Core's types
have it, and `[<Derive(Arbitrary)>]` gives it to a record or union: a record draws each field,
a union a case and then its fields, each field at half the size. At size 0, and past a
replayed stream's end, a union takes a case that ends a value, so a recursive type's values
are finite (see the derive).

#### `Testing.Arbitrary.arbitrary`

```zsharp
abstract arbitrary : unit -> Gen<'a>
```

The type's generator.

### `Testing.Checks`

```zsharp
trait Checks<'r>
```

What a property's body gives back, checked against the case's source: `unit` passes, `false`
and an `Error` fail, and a `Prop` runs on the source (drawing more, discarding, labelling).

#### `Testing.Checks.check`

```zsharp
abstract check : 'r -> Source -> option<string>
```

`None` when the case passed; the failure's message otherwise.

## Types

### `Testing.Focus`

```zsharp
type Focus
```

Whether a test runs: as usual; only with the other focused ones while any are (`ftest`); or
not, and said so (`ptest`).

#### `Testing.Normal`

```zsharp
| Normal
```

Runs as usual.

#### `Testing.Focused`

```zsharp
| Focused
```

Runs, and while any test is focused only the focused ones do.

#### `Testing.Pending`

```zsharp
| Pending
```

Doesn't run, and is listed as skipped.

### `Testing.Test`

```zsharp
type Test
```

A test, or a group of them. A test's path is the names down to it: `parser/parses`.

#### `Testing.Case`

```zsharp
| Case of name: string * run: (unit -> unit) * focus: Focus * timeout: int
```

One test: its name, its body (a failure panics), its focus and its time limit (ms).

#### `Testing.Group`

```zsharp
| Group of name: string * tests: list<Test> * focus: Focus * sequenced: bool
```

A group: its name, its tests, its focus, and whether they run one at a time.

#### `Testing.Bench`

```zsharp
| Bench of name: string * run: (unit -> unit)
```

A benchmark: its name and its body, which `zs bench` times (`zs test` runs it once).

#### `Testing.Property`

```zsharp
| Property of name: string * run: (PropertyDriver -> unit)
```

A property (`testProperty`): its name and its run, driven by the test binary's runner
(which records each case for `zs test`, or replays one).

### `Testing.Source`

```zsharp
type Source
```

Where a generator's bytes come from (0010): a random stream from a seed, recorded as it's
drawn, so a failing case can be shrunk and replayed, or a stream given (a shrink candidate).
Drawing past a given stream's end is an overrun, which discards the case. All-zero bytes mean
the simplest value, and a shorter or smaller stream a simpler one.

### `Testing.Gen`

```zsharp
type Gen<'a>
```

A generator: a function from a source of bytes to a value. Every one shrinks, since shrinking
the bytes it reads shrinks what it makes.

### `Testing.CaseInfo`

```zsharp
type CaseInfo
```

A union's case as a derive sees it (`Shape.cases`): its name, its index, how many fields, and
its rank, how readily a generated value of it ends: 0 when no field can hold a value of the
type, 1 when only lists, arrays and options can (empty at size 0 and from zero bytes), 2 when
the others only might (a type parameter, which may be the type: `Plain of 'a` in `Labeled<'a>`
drawn for a `T` that holds a `Labeled<T>`), 3 otherwise (a field that is the type, or holds
it in a record, a tuple, a result or another union).

### `Testing.Verdict`

```zsharp
type Verdict
```

How a case of a `Prop` ended.

#### `Testing.Passed`

```zsharp
| Passed
```

The checks held.

#### `Testing.Failed`

```zsharp
| Failed of string
```

A check failed: its message.

#### `Testing.Discarded`

```zsharp
| Discarded
```

The case doesn't count (`Prop.assume` was false, or a filter never held).

### `Testing.Prop`

```zsharp
type Prop
```

A property that draws as it goes: `prop { let! x = Gen.int … do! Prop.assume (x <> 0) …
return x / x = 1 }`. Its draws come from the case's source, after the parameters', so they
shrink with them.

### `Testing.Model`

```zsharp
type Model<'c, 's, 'm>
```

A system checked against a model by a sequence of commands (`Prop.model`): `init` makes the
two, and `step` applies a command to both, or says how they disagree.

### `Testing.PropertySettings`

```zsharp
type PropertySettings
```

A property's settings: `testPropertyWith { runs = 1000 } "name" …` names what changes.

## Derives and impls

### `impl Outcome<unit>`

```zsharp
impl Outcome<unit>
```

A body that returns: it passed.

### `impl Outcome<result<'a, 'e>>`

```zsharp
impl Outcome<result<'a, 'e>>
```

An `Error` fails the test, shown.

### `impl Arbitrary<unit>`

```zsharp
impl Arbitrary<unit>
```

`()`.

### `impl Arbitrary<bool>`

```zsharp
impl Arbitrary<bool>
```

`Gen.bool`.

### `impl Arbitrary<char>`

```zsharp
impl Arbitrary<char>
```

`Gen.char`.

### `impl Arbitrary<string>`

```zsharp
impl Arbitrary<string>
```

`Gen.string`.

### `impl Arbitrary<int>`

```zsharp
impl Arbitrary<int>
```

`Gen.int`: `-size .. size`.

### `impl Arbitrary<i8>`

```zsharp
impl Arbitrary<i8>
```

`Gen.i8`.

### `impl Arbitrary<i16>`

```zsharp
impl Arbitrary<i16>
```

`Gen.i16`.

### `impl Arbitrary<i32>`

```zsharp
impl Arbitrary<i32>
```

`Gen.i32`.

### `impl Arbitrary<i64>`

```zsharp
impl Arbitrary<i64>
```

`Gen.i64`.

### `impl Arbitrary<u8>`

```zsharp
impl Arbitrary<u8>
```

`Gen.u8`.

### `impl Arbitrary<u16>`

```zsharp
impl Arbitrary<u16>
```

`Gen.u16`.

### `impl Arbitrary<u32>`

```zsharp
impl Arbitrary<u32>
```

`Gen.u32`.

### `impl Arbitrary<u64>`

```zsharp
impl Arbitrary<u64>
```

`Gen.u64`.

### `impl Arbitrary<f64>`

```zsharp
impl Arbitrary<f64>
```

`Gen.float`.

### `impl Arbitrary<f32>`

```zsharp
impl Arbitrary<f32>
```

`Gen.f32`.

### `impl Arbitrary<list<'a>>`

```zsharp
impl Arbitrary<list<'a>>
```

A list of the element's values, up to the size long.

### `impl Arbitrary<array<'a>>`

```zsharp
impl Arbitrary<array<'a>>
```

An array of the element's values.

### `impl Arbitrary<option<'a>>`

```zsharp
impl Arbitrary<option<'a>>
```

`None` first.

### `impl Arbitrary<result<'a, 'e>>`

```zsharp
impl Arbitrary<result<'a, 'e>>
```

`Ok` first.

### `impl Arbitrary<'a * 'b>`

```zsharp
impl Arbitrary<'a * 'b>
```

A pair of the parts' values, drawn in order.

### `impl Arbitrary<'a * 'b * 'c>`

```zsharp
impl Arbitrary<'a * 'b * 'c>
```

A triple of the parts' values, drawn in order.

### `impl Arbitrary<'a * 'b * 'c * 'd>`

```zsharp
impl Arbitrary<'a * 'b * 'c * 'd>
```

Four values, drawn in order.

### `derive Arbitrary`

```zsharp
derive Arbitrary
```

A record draws each field; a union draws a case, then its fields; a field is drawn at half the
size. The cases come in order of rank, so zero bytes take one of the lowest; at size 0 and past
a replayed stream's end the choice is the lowest rank's cases with the fewest fields. So a
value ends when every type on its way has a case below rank 3 that ends it (a generic one's
type-parameter case ends it once the parameter's own type does); a type whose every case
holds it outright (rank 3) may not, and a case holding a type parameter comes after those
that hold nothing.

### `impl Checks<unit>`

```zsharp
impl Checks<unit>
```

A body that returns: the case passed.

### `impl Checks<bool>`

```zsharp
impl Checks<bool>
```

`false` fails the case.

### `impl Checks<result<'a, 'e>>`

```zsharp
impl Checks<result<'a, 'e>>
```

An `Error` fails the case, shown.

### `impl Checks<Prop>`

```zsharp
impl Checks<Prop>
```

A `Prop` runs on the case's source: a `Failed` fails the case, a `Discarded` discards it.

## Functions

### `Testing.test`

```zsharp
Testing.test : string -> (unit -> 'a / <>) -> Testing.Test when 'a : Testing.Outcome
  body must perform nothing
```

A test: its name and its body (a panic or an `Error` fails it). It may take 60 s.

### `Testing.testWithTimeout`

```zsharp
Testing.testWithTimeout : int -> string -> (unit -> 'a / <>) -> Testing.Test when 'a : Testing.Outcome
  body must perform nothing
```

A test that may take `ms` milliseconds.

### `Testing.ftest`

```zsharp
Testing.ftest : string -> (unit -> 'a / <>) -> Testing.Test when 'a : Testing.Outcome
  body must perform nothing
```

A focused test: while any test is focused, only those run (`zs test --fail-on-focused` fails
a run that has one).

### `Testing.ptest`

```zsharp
Testing.ptest : string -> (unit -> 'a / <>) -> Testing.Test when 'a : Testing.Outcome
  body must perform nothing
```

A pending test: not run, and listed as skipped.

### `Testing.testList`

```zsharp
Testing.testList : string -> list<Testing.Test> -> Testing.Test
```

A group of tests, run at once (each in its own process).

### `Testing.testSequenced`

```zsharp
Testing.testSequenced : string -> list<Testing.Test> -> Testing.Test
```

A group of tests run one at a time: tests that share a file or a port.

### `Testing.ftestList`

```zsharp
Testing.ftestList : string -> list<Testing.Test> -> Testing.Test
```

A focused group.

### `Testing.ptestList`

```zsharp
Testing.ptestList : string -> list<Testing.Test> -> Testing.Test
```

A pending group.

### `Testing.bench`

```zsharp
Testing.bench : string -> (unit -> 'a / <>) -> Testing.Test
  body must perform nothing
```

A benchmark: `zs bench` warms it up, times enough runs for a median and a confidence
interval, and reports a change from the last run beyond the noise; `zs test` runs it once.

### `Testing.testFaster`

```zsharp
Testing.testFaster : string -> (unit -> 'a / <>) -> (unit -> 'b / <>) -> Testing.Test
  fast must perform nothing, slow must perform nothing
```

A test that passes when `fast` is faster than `slow` with statistical confidence: the two
run in paired rounds, in alternating order, and `fast` must win 19 of 25 (a sign test at
1%), so a performance claim can't silently regress. Both run once each per round: give each
enough work to time.

### `Testing.expectAt`

```zsharp
Testing.expectAt : 'a -> string -> string -> int -> unit when 'a : Show
```

Compares the value's text (through Show) with the literal next to it, which
`zs test --update` rewrites when they differ (an expect test, 0009). The compiler gives it
its place: `expect` is `expectAt` with the file and line.

### `Testing.expect`

```zsharp
Testing.expect : 'a -> string -> unit when 'a : Show
```

An expect test: `expect (parse "1 + 2") """Add (Num 1, Num 2)"""`.

### `Testing.runAll`

```zsharp
Testing.runAll : list<Testing.Test> -> int
```

Runs every test in order, in this process: what `zs test --target <chip>` builds into the
image (a chip has no processes, 0009 D11). Prints `test path` before each, `ok   path` after,
`skip path` for a pending one (or one left out while others are focused), and the counts; a
failure's panic ends the run after `test path`, which names it.

### `Testing.Source.randomWith`

```zsharp
Testing.Source.randomWith : Random -> int -> option<array<u8> -> unit> -> Testing.Source
```

A random stream from `r`, recording what's drawn, at `size`; `onDraw` is told each block.

### `Testing.Source.random`

```zsharp
Testing.Source.random : Random -> int -> Testing.Source
```

A random stream from `r`, recording what's drawn, at `size`.

### `Testing.Source.ofBytes`

```zsharp
Testing.Source.ofBytes : array<u8> -> int -> Testing.Source
```

A given stream (a shrink candidate, a saved case), at `size`.

### `Testing.Source.draw`

```zsharp
Testing.Source.draw : int -> Testing.Source -> array<u8>
```

`n` bytes from the stream: the next of the given or recorded ones, else drawn at random and
recorded, else (a given stream used up) zeros, and the source has overrun.

### `Testing.Source.rejected`

```zsharp
Testing.Source.rejected : Testing.Source -> bool
```

Whether the case is to be discarded: a filter that never held, or an overrun.

### `Testing.Gen.draw`

```zsharp
Testing.Gen.draw : Testing.Gen<'a> -> Testing.Source -> 'a
```

Runs `g` on a source.

### `Testing.Gen.constant`

```zsharp
Testing.Gen.constant : 'a -> Testing.Gen<'a>
```

Always `x`; draws nothing.

### `Testing.Gen.map`

```zsharp
Testing.Gen.map : ('a -> 'b / <>) -> Testing.Gen<'a> -> Testing.Gen<'b>
  f must perform nothing
```

`f` of what `g` makes.

### `Testing.Gen.bind`

```zsharp
Testing.Gen.bind : ('a -> Testing.Gen<'b> / <>) -> Testing.Gen<'a> -> Testing.Gen<'b>
  f must perform nothing
```

`g`, then the generator `f` chooses from its value.

### `Testing.Gen.range`

```zsharp
Testing.Gen.range : int -> int -> Testing.Gen<int>
```

An integer from `lo` to `hi` (both in): `lo` is the simplest.

### `Testing.Gen.elements`

```zsharp
Testing.Gen.elements : list<'a> -> Testing.Gen<'a>
```

One of `xs`, the first the simplest.

### `Testing.Gen.frequency`

```zsharp
Testing.Gen.frequency : list<int * Testing.Gen<'a>> -> Testing.Gen<'a>
```

One of the generators, each as likely as its weight; the first the simplest.

### `Testing.Gen.oneOf`

```zsharp
Testing.Gen.oneOf : list<Testing.Gen<'a>> -> Testing.Gen<'a>
```

One of the generators, each as likely as the others.

### `Testing.Gen.filter`

```zsharp
Testing.Gen.filter : ('a -> bool / <>) -> Testing.Gen<'a> -> Testing.Gen<'a>
  p must perform nothing
```

`g` again, up to a hundred times, until `p` holds; then the case is discarded. Generate
valid values where you can: a filter that rejects most of them discards most cases.

### `Testing.Gen.listOfLength`

```zsharp
Testing.Gen.listOfLength : int -> Testing.Gen<'a> -> Testing.Gen<list<'a>>
```

`n` of `g`.

### `Testing.Gen.list`

```zsharp
Testing.Gen.list : Testing.Gen<'a> -> Testing.Gen<list<'a>>
```

A list of `g`: before each element one byte, "another?", then the element; a zero stops,
so the empty list is one zero byte, and zeroing a byte in a failing case ends the list
there, which is how a list shrinks to its first elements. The chance of another falls with
the size, and the list stops at the size's length.

### `Testing.Gen.array`

```zsharp
Testing.Gen.array : Testing.Gen<'a> -> Testing.Gen<array<'a>>
```

An array of `g`, as `list`.

### `Testing.Gen.bytes`

```zsharp
Testing.Gen.bytes : unit -> Testing.Gen<array<u8>>
```

Raw bytes: at random, up to the size many; from a given stream (a replay, or `zs fuzz`'s
input), all that's left, so a property over bytes takes the fuzzer's input as it is.

### `Testing.Gen.option`

```zsharp
Testing.Gen.option : Testing.Gen<'a> -> Testing.Gen<option<'a>>
```

`None` first (always at size 0, so a recursive type through an option ends), else `g`.

### `Testing.Gen.sized`

```zsharp
Testing.Gen.sized : (int -> Testing.Gen<'a> / <>) -> Testing.Gen<'a>
  f must perform nothing
```

What `f size` draws: a generator that depends on the size.

### `Testing.Gen.scale`

```zsharp
Testing.Gen.scale : (int -> int / <>) -> Testing.Gen<'a> -> Testing.Gen<'a>
  f must perform nothing
```

`g` at the size `f size`: `Gen.scale (fun n -> n / 2) g` for a field of a recursive type.

### `Testing.Gen.sample`

```zsharp
Testing.Gen.sample : u64 -> int -> Testing.Gen<'a> -> list<'a>
```

`n` values from `g`, from a seed, at sizes growing to 100: to look at what a generator makes.

### `Testing.Gen.unit`

```zsharp
Testing.Gen.unit : unit -> Testing.Gen<unit>
```

`()`; draws nothing.

### `Testing.Gen.bool`

```zsharp
Testing.Gen.bool : unit -> Testing.Gen<bool>
```

`true` or `false`; `false` first.

### `Testing.Gen.char`

```zsharp
Testing.Gen.char : unit -> Testing.Gen<char>
```

A character: printable ASCII first (space the simplest), then any scalar value, from U+00A0
on (the controls below it last, so a case shrinks to a printable one; the surrogates,
which aren't characters, skipped).

### `Testing.Gen.string`

```zsharp
Testing.Gen.string : unit -> Testing.Gen<string>
```

A string of `char`s, up to the size long.

### `Testing.Gen.int`

```zsharp
Testing.Gen.int : unit -> Testing.Gen<int>
```

An integer in `-size .. size`: zero the simplest, then small ones.

### `Testing.Gen.i8`

```zsharp
Testing.Gen.i8 : unit -> Testing.Gen<i8>
```

An `i8` as `int`, within the width.

### `Testing.Gen.i16`

```zsharp
Testing.Gen.i16 : unit -> Testing.Gen<i16>
```

An `i16` as `int`.

### `Testing.Gen.i32`

```zsharp
Testing.Gen.i32 : unit -> Testing.Gen<i32>
```

An `i32` as `int`.

### `Testing.Gen.i64`

```zsharp
Testing.Gen.i64 : unit -> Testing.Gen<i64>
```

An `i64` as `int`.

### `Testing.Gen.u8`

```zsharp
Testing.Gen.u8 : unit -> Testing.Gen<u8>
```

A `u8` from 0 to the size (255 at most): zero the simplest.

### `Testing.Gen.u16`

```zsharp
Testing.Gen.u16 : unit -> Testing.Gen<u16>
```

A `u16` from 0 to the size.

### `Testing.Gen.u32`

```zsharp
Testing.Gen.u32 : unit -> Testing.Gen<u32>
```

A `u32` from 0 to the size.

### `Testing.Gen.u64`

```zsharp
Testing.Gen.u64 : unit -> Testing.Gen<u64>
```

A `u64` from 0 to the size.

### `Testing.Gen.float`

```zsharp
Testing.Gen.float : unit -> Testing.Gen<f64>
```

A float: integer-valued first, then with a fraction, and now and then NaN or an infinity.

### `Testing.Gen.f32`

```zsharp
Testing.Gen.f32 : unit -> Testing.Gen<f32>
```

`float`, single precision.

### `Testing.Prop.run`

```zsharp
Testing.Prop.run : Testing.Prop -> Testing.Source -> Testing.Verdict
```

Runs the property's checks on a source.

### `Testing.Prop.assume`

```zsharp
Testing.Prop.assume : bool -> Testing.Gen<unit>
```

`do! Prop.assume cond`: a false condition discards the case, and nothing after it runs
(FsCheck's `==>`). Generate valid values where you can: discards cost cases.

### `Testing.Prop.label`

```zsharp
Testing.Prop.label : string -> Testing.Gen<unit>
```

`do! Prop.label name`: names the case; a failure shows its labels, and a passing property
reports how its cases were labelled.

### `Testing.Prop.classify`

```zsharp
Testing.Prop.classify : bool -> string -> Testing.Gen<unit>
```

`do! Prop.classify cond name`: labels the case `name` when `cond` holds.

### `Testing.Prop.collect`

```zsharp
Testing.Prop.collect : 'a -> Testing.Gen<unit> when 'a : Show
```

`do! Prop.collect value`: labels the case with the value's text.

### `Testing.Prop.model`

```zsharp
Testing.Prop.model : list<'a> -> Testing.Model<'a, 'b, 'c> -> result<unit, string> when 'a : Show
```

Applies each command to the system and the model, in turn; the first disagreement is the
failure, with the commands before it, so a failing sequence shrinks to the fewest commands
with the smallest arguments.

### `Testing.testPropertyWith`

```zsharp
Testing.testPropertyWith : Testing.PropertySettings -> string -> ('a -> 'b / <>) -> Testing.Test when 'a : Show, 'a : Testing.Arbitrary, 'b : Testing.Checks
  prop must perform nothing
```

A property with its settings: `prop` runs on `runs` cases drawn with `Arbitrary` at its
parameter's type (a tuple for several), the cases growing from size 0 to `maxSize`; `unit`,
`true`, `Ok` or a `Prop` that passes passes a case (a `Prop` draws more as it goes, and may
discard the case or label it). A case that returns `false` or an `Error` fails the property:
it's shrunk to a smallest failing case (shorter bytes, then smaller), which the failure
shows, with the seed to replay the run. A case that panics ends the test at once, with the
panic: `testPropertyWith { seed = Some s }` replays it.

### `Testing.testProperty`

```zsharp
Testing.testProperty : string -> ('a -> 'b / <>) -> Testing.Test when 'a : Show, 'a : Testing.Arbitrary, 'b : Testing.Checks
  prop must perform nothing
```

A property with the default settings: 100 cases, growing to size 100, shrunk on failure.

