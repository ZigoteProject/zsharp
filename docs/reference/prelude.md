# prelude

## Traits

### `Add`

```zsharp
trait Add<'a>
```

`+` and a zero, for `List.sum`. Built in for numbers and `string` (concatenation, "").

#### `Add.add`

```zsharp
abstract add : 'a -> 'a -> 'a
```

`a + b`.

#### `Add.zero`

```zsharp
abstract zero : 'a
```

The value that `+` leaves unchanged: `0`, `0.0`, `""`.

### `Num`

```zsharp
trait Num<'a>
```

`-`, `*`, `/`, `%` and negation. Built in for the integer and floating-point types.

#### `Num.sub`

```zsharp
abstract sub : 'a -> 'a -> 'a
```

`a - b`.

#### `Num.mul`

```zsharp
abstract mul : 'a -> 'a -> 'a
```

`a * b`.

#### `Num.div`

```zsharp
abstract div : 'a -> 'a -> 'a
```

`a / b`. Integer division by zero panics.

#### `Num.rem`

```zsharp
abstract rem : 'a -> 'a -> 'a
```

`a % b`. Integer remainder by zero panics.

#### `Num.neg`

```zsharp
abstract neg : 'a -> 'a
```

`-a`.

### `Eq`

```zsharp
trait Eq<'a>
```

`=` and `<>`. Built in for primitives; derived structurally for records, unions and tuples.

#### `Eq.equal`

```zsharp
abstract equal : 'a -> 'a -> bool
```

`a = b`.

### `Ord`

```zsharp
trait Ord<'a>
```

`<`, `>`, `<=`, `>=` and `compare`. Built in for numbers and strings; derived for records,
unions (by case order, then fields) and tuples (lexicographically).

#### `Ord.compare`

```zsharp
abstract compare : 'a -> 'a -> int
```

A negative number, zero or a positive number as `a` is less than, equal to or greater than `b`.

### `Show`

```zsharp
trait Show<'a>
```

Text for a value: what `string x` and `$"{x}"` use. Built in for numbers, bools and
strings; derived for records (`{ x = 1; y = 2 }`) and unions (`Some 1`, `Rect (1, 2)`).

#### `Show.show`

```zsharp
abstract show : 'a -> string
```

The value as text.

### `Format`

```zsharp
trait Format<'a>
```

Text for a value under a format specifier: what `$"{x:F2}"` calls. Built in for numbers, with
.NET's standard specifiers: `F2` (fixed, two decimals), `E3`, `G`, `N0` (with commas), `D5`,
`X8` and `x`, `B8` (`D`, `X` and `B` for integers, `E` and `G` for floats).

#### `Format.format`

```zsharp
abstract format : 'a -> string -> string
```

The value as text, shaped by `spec` (`"F2"`, `"X8"`).

### `Hash`

```zsharp
trait Hash<'a>
```

A hash code, consistent with `Eq`: equal values hash the same.

#### `Hash.hash`

```zsharp
abstract hash : 'a -> int
```

The value's hash code.

### `Dispose`

```zsharp
trait Dispose<'a>
```

What `use x = e` gives back when its scope ends (and, in a task, when the task is cancelled):
a socket closed, a file shut, a handle released.

#### `Dispose.dispose`

```zsharp
abstract dispose : 'a -> unit
```

Releases what the value holds.

### `Iter`

```zsharp
trait Iter<'c, 'a>
```

What `for x in c do` walks (0017): a collection `'c` of elements `'a`. The collection's type
picks the impl, and the impl says what its elements are (`impl Iter<Map<'k, 'v>, 'k * 'v>`).
The module `Iter` has the functions over it.

#### `Iter.forEach`

```zsharp
abstract forEach : 'c -> ('a -> bool) -> bool
```

Calls `f` on each element in order until it returns false; whether it ran to the end.

### `Diff`

```zsharp
trait Diff<'a>
```

Where two values first differ, for a failed `assert` (0009): the path to it through records'
fields, unions' cases and collections' elements, and the two values there.

#### `Diff.diff`

```zsharp
abstract diff : 'a -> 'a -> option<string>
```

None when the values are equal; else the path to the first difference and the two values
there: `.items.[2].name: "a" vs "b"`.

## Effects

### `Yield`

```zsharp
effect Yield<'a>
```

The elements of a sequence, one at a time: what `yield` in a `seq { }` performs, and what
a `Seq`'s consumer handles (DESIGN §6.1).

#### `Yield.yield`

```zsharp
abstract yield : 'a -> unit
```

Gives the element `x` to the consumer, which resumes the sequence for the next one (or
doesn't, when it needs no more).

### `Throw`

```zsharp
effect Throw<'e>
```

Typed exceptions: a function that may fail says so in its type (`int / Throw<string>`), and
`Throw.catch` turns the failure back into a `result` where it's handled. A boundary between
modules returns `result` instead, as it always has.

#### `Throw.throw`

```zsharp
abstract throw : 'e -> 'a
```

Stops what was running with the error `e`: nothing after it runs, and the handler's clause
gives the result.

## Types

### `ShapeKind`

```zsharp
type ShapeKind
```

What `match Shape.kind with` distinguishes inside a `derive`.

#### `RecordKind`

```zsharp
| RecordKind
```

The type being derived for is a record.

#### `UnionKind`

```zsharp
| UnionKind
```

The type being derived for is a union.

### `option`

```zsharp
type option<'a>
```

A value that may be missing. Use it instead of null: `Some x` or `None`.

#### `None`

```zsharp
| None
```

No value.

#### `Some`

```zsharp
| Some of 'a
```

A value.

### `result`

```zsharp
type result<'a, 'e>
```

The outcome of something that can fail: `Ok value` or `Error err`. The `?` operator
returns early with the `Error`.

#### `Ok`

```zsharp
| Ok of 'a
```

Success, with its value.

#### `Error`

```zsharp
| Error of 'e
```

Failure, with its error.

## Derives and impls

### `derive Eq`

```zsharp
derive Eq
```

Structural equality for records and unions: same case and equal fields. Applied the first
time a type needs `=`; an explicit `impl Eq` or `[<NoEquality>]` takes precedence.

### `derive Ord`

```zsharp
derive Ord
```

Structural ordering for records and unions: by case (in declaration order), then field by
field. Applied the first time a type needs it; `[<NoComparison>]` opts out.

### `derive Hash`

```zsharp
derive Hash
```

A structural hash for records and unions, consistent with the derived `Eq`.

### `derive Show`

```zsharp
derive Show
```

F#-style text for records (`{ x = 1; y = 2 }`) and unions (`Leaf`, `Some 1`, `Rect (1, 2)`).

### `derive Diff`

```zsharp
derive Diff
```

The first difference inside records and unions: a record's field by name, a union's case
and field (`.Some`, `.Node[2]`); two cases differ as a whole. Applied the first time a type
needs it, as `Show` is.

### `impl Show<list<'a>>`

```zsharp
impl Show<list<'a>>
```

Lists print as `[1; 2; 3]`.

## Functions

### `diffShown`

```zsharp
diffShown : 'a -> 'a -> option<string> when 'a : Eq, 'a : Show
```

Two values that differ as a whole (`: 1 vs 2`), or None when they're equal: Diff on numbers,
strings, chars and bools.

### `id`

```zsharp
id : 'a -> 'a
```

Returns its argument unchanged.

### `fst`

```zsharp
fst : 'a * 'b -> 'a
```

The first component of a pair.

### `snd`

```zsharp
snd : 'a * 'b -> 'b
```

The second component of a pair.

### `max`

```zsharp
max : 'a -> 'a -> 'a when 'a : Ord
```

The larger of two values.

### `min`

```zsharp
min : 'a -> 'a -> 'a when 'a : Ord
```

The smaller of two values.

### `assert`

```zsharp
assert : bool -> unit
```

Panics with "assertion failed" when the condition is false; for a comparison (`assert (a = b)`), the message shows both sides and where they first differ.

### `eprintln`

```zsharp
eprintln : string -> unit
```

Writes the string and a newline to standard error.

### `failwith`

```zsharp
failwith : string -> 'a
```

Same as `panic`.

### `ignore`

```zsharp
ignore : 'a -> unit
```

Discards a value.

### `panic`

```zsharp
panic : string -> 'a
```

Stops the program with the message (and a backtrace). For bugs, not for errors a caller should handle.

### `print`

```zsharp
print : string -> unit
```

Writes the string to standard output, without a newline.

### `println`

```zsharp
println : string -> unit
```

Writes the string and a newline to standard output.

### `ref`

```zsharp
ref : 'a -> ref<'a>
```

A mutable cell holding the value; read and write it with `r.Value`.

