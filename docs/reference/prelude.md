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

#### `string#Length`

```zsharp
member s.Length
```

The length in bytes (UTF-8).

#### `array#Length`

```zsharp
member a.Length
```

The number of elements.

#### `list#Length`

```zsharp
member xs.Length
```

The number of elements. O(n).

#### `list#Head`

```zsharp
member xs.Head
```

The first element. Panics on an empty list.

#### `list#Tail`

```zsharp
member xs.Tail
```

Everything after the first element. Panics on an empty list.

#### `list#IsEmpty`

```zsharp
member xs.IsEmpty
```

Whether the list has no elements.

#### `option#IsSome`

```zsharp
member o.IsSome
```

Whether the option holds a value.

#### `option#IsNone`

```zsharp
member o.IsNone
```

Whether the option is `None`.

#### `string#Contains`

```zsharp
member s.Contains(sub: string)
```

Whether `sub` occurs in the string.

#### `string#StartsWith`

```zsharp
member s.StartsWith(p: string)
```

Whether the string begins with `p`.

#### `string#EndsWith`

```zsharp
member s.EndsWith(p: string)
```

Whether the string ends with `p`.

#### `string#IndexOf`

```zsharp
member s.IndexOf(sub: string)
```

The byte index of the first `sub`, or `None`.

#### `string#Split`

```zsharp
member s.Split(sep: string)
```

The pieces between occurrences of `sep`.

#### `string#Substring`

```zsharp
member s.Substring(start: int, len: int)
```

The `len` bytes starting at byte `start`. Panics if out of range.

#### `string#Trim`

```zsharp
member s.Trim()
```

The string without leading and trailing spaces, tabs and line breaks.

#### `string#ToUpper`

```zsharp
member s.ToUpper()
```

The string with ASCII letters in upper case.

#### `string#ToLower`

```zsharp
member s.ToLower()
```

The string with ASCII letters in lower case.

#### `string#Replace`

```zsharp
member s.Replace(old: string, by: string)
```

The string with every `old` replaced by `by`.

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

### `impl Show<list<'a>>`

```zsharp
impl Show<list<'a>>
```

Lists print as `[1; 2; 3]`.

## Functions

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

### `List.rev`

```zsharp
List.rev : list<'a> -> list<'a>
```

The list in reverse order. Reuses the cells when the list is unique.

### `List.length`

```zsharp
List.length : list<'a> -> 'b when 'b : Add
```

The number of elements. O(n).

### `List.isEmpty`

```zsharp
List.isEmpty : list<'a> -> bool
```

Whether the list has no elements.

### `List.head`

```zsharp
List.head : list<'a> -> 'a
```

The first element. Panics on an empty list; see `List.tryHead`.

### `List.tail`

```zsharp
List.tail : list<'a> -> list<'a>
```

Everything after the first element. Panics on an empty list.

### `List.map`

```zsharp
List.map : ('a -> 'b) -> list<'a> -> list<'b>
```

Applies `f` to every element: `List.map f [a; b] = [f a; f b]`.

### `List.filter`

```zsharp
List.filter : ('a -> bool) -> list<'a> -> list<'a>
```

The elements for which `f` returns true, in order.

### `List.fold`

```zsharp
List.fold : ('a -> 'b -> 'a) -> 'a -> list<'b> -> 'a
```

Combines the elements from the left: `List.fold f s [a; b] = f (f s a) b`.

### `List.iter`

```zsharp
List.iter : ('a -> 'b) -> list<'a> -> unit
```

Calls `f` on every element, in order.

### `List.append`

```zsharp
List.append : list<'a> -> list<'a> -> list<'a>
```

The elements of `xs` followed by those of `ys` (also written `xs @ ys`).

### `List.exists`

```zsharp
List.exists : ('a -> bool) -> list<'a> -> bool
```

Whether `f` is true for some element. Stops at the first.

### `List.forall`

```zsharp
List.forall : ('a -> bool) -> list<'a> -> bool
```

Whether `f` is true for every element. Stops at the first false.

### `List.contains`

```zsharp
List.contains : 'a -> list<'a> -> bool when 'a : Eq
```

Whether the list contains `x` (compared with `=`).

### `List.tryFind`

```zsharp
List.tryFind : ('a -> bool) -> list<'a> -> option<'a>
```

The first element for which `f` is true, or `None`.

### `List.sum`

```zsharp
List.sum : list<'a> -> 'a when 'a : Add
```

The sum of the elements (`Add.zero` for an empty list).

### `List.init`

```zsharp
List.init : 'a -> ('a -> 'b) -> list<'b> when 'a : Num, 'a : Ord
```

A list of `n` elements: `[f 0; f 1; …; f (n - 1)]`.

### `Option.map`

```zsharp
Option.map : ('a -> 'b) -> option<'a> -> option<'b>
```

Applies `f` to the value of `Some`; `None` stays `None`.

### `Option.bind`

```zsharp
Option.bind : ('a -> option<'b>) -> option<'a> -> option<'b>
```

Applies `f`, which itself returns an option, to the value of `Some`.

### `Option.defaultValue`

```zsharp
Option.defaultValue : 'a -> option<'a> -> 'a
```

The value of `Some`, or `d` for `None`.

### `Option.isSome`

```zsharp
Option.isSome : option<'a> -> bool
```

Whether the option holds a value.

### `Option.isNone`

```zsharp
Option.isNone : option<'a> -> bool
```

Whether the option is `None`.

### `Option.get`

```zsharp
Option.get : option<'a> -> 'a
```

The value of `Some`. Panics on `None`; prefer a match or `Option.defaultValue`.

### `Result.map`

```zsharp
Result.map : ('a -> 'b) -> result<'a, 'c> -> result<'b, 'c>
```

Applies `f` to the value of `Ok`; an `Error` passes through.

### `Result.bind`

```zsharp
Result.bind : ('a -> result<'b, 'c>) -> result<'a, 'c> -> result<'b, 'c>
```

Applies `f`, which itself returns a result, to the value of `Ok`.

### `Array.init`

```zsharp
Array.init : int -> (int -> 'a) -> array<'a>
```

An array of `n` elements: `[| f 0; …; f (n - 1) |]`.

### `Array.map`

```zsharp
Array.map : ('a -> 'b) -> array<'a> -> array<'b>
```

A new array with `f` applied to every element.

### `Array.iter`

```zsharp
Array.iter : ('a -> unit) -> array<'a> -> unit
```

Calls `f` on every element, in order.

### `Array.fold`

```zsharp
Array.fold : ('a -> 'b -> 'a) -> 'a -> array<'b> -> 'a
```

Combines the elements from the left, like `List.fold`.

### `Array.sum`

```zsharp
Array.sum : array<'a> -> 'a when 'a : Add
```

The sum of the elements (`Add.zero` for an empty array).

### `Array.ofList`

```zsharp
Array.ofList : list<'a> -> array<'a>
```

An array with the list's elements, in order.

### `Array.toList`

```zsharp
Array.toList : array<'a> -> list<'a>
```

A list with the array's elements, in order.

### `List.mapi`

```zsharp
List.mapi : ('a -> 'b -> 'c) -> list<'b> -> list<'c> when 'a : Add
```

Like `List.map`, with each element's index: `f i x`.

### `List.indexed`

```zsharp
List.indexed : list<'a> -> list<'b * 'a> when 'b : Add
```

Each element paired with its index: `[(0, a); (1, b)]`.

### `List.choose`

```zsharp
List.choose : ('a -> option<'b>) -> list<'a> -> list<'b>
```

Applies `f` to every element and keeps the values of the `Some` results.

### `List.collect`

```zsharp
List.collect : ('a -> list<'b>) -> list<'a> -> list<'b>
```

Applies `f` to every element and concatenates the resulting lists.

### `List.zip`

```zsharp
List.zip : list<'a> -> list<'b> -> list<'a * 'b>
```

Pairs up the elements of two lists; stops at the end of the shorter one.

### `List.unzip`

```zsharp
List.unzip : list<'a * 'b> -> list<'a> * list<'b>
```

Splits a list of pairs into a pair of lists.

### `List.tryHead`

```zsharp
List.tryHead : list<'a> -> option<'a>
```

The first element, or `None` for an empty list.

### `List.last`

```zsharp
List.last : list<'a> -> 'a
```

The last element. Panics on an empty list.

### `List.item`

```zsharp
List.item : 'a -> list<'b> -> 'b when 'a : Eq, 'a : Num
```

The element at index `n` (from 0). Panics if the list is too short. O(n).

### `List.take`

```zsharp
List.take : 'a -> list<'b> -> list<'b> when 'a : Num, 'a : Ord
```

The first `n` elements (fewer if the list is shorter).

### `List.skip`

```zsharp
List.skip : 'a -> list<'b> -> list<'b> when 'a : Num, 'a : Ord
```

The list without its first `n` elements.

### `List.reduce`

```zsharp
List.reduce : ('a -> 'a -> 'a) -> list<'a> -> 'a
```

Combines the elements from the left, starting with the first. Panics on an empty list.

### `List.partition`

```zsharp
List.partition : ('a -> bool) -> list<'a> -> list<'a> * list<'a>
```

The elements for which `f` is true, and the others, both in order.

### `List.max`

```zsharp
List.max : list<'a> -> 'a when 'a : Ord
```

The largest element. Panics on an empty list.

### `List.min`

```zsharp
List.min : list<'a> -> 'a when 'a : Ord
```

The smallest element. Panics on an empty list.

### `List.sumBy`

```zsharp
List.sumBy : ('a -> 'b) -> list<'a> -> 'b when 'b : Add
```

The sum of `f x` over the elements.

### `List.distinct`

```zsharp
List.distinct : list<'a> -> list<'a> when 'a : Eq
```

The list without repeated elements, keeping first occurrences.

### `List.sortWith`

```zsharp
List.sortWith : ('a -> 'a -> 'b) -> list<'a> -> list<'a> when 'b : Ord
```

The list sorted with `cmp` (negative, zero or positive, like `compare`). Stable.

### `List.sort`

```zsharp
List.sort : list<'a> -> list<'a> when 'a : Ord
```

The list sorted in ascending order. Stable.

### `List.sortBy`

```zsharp
List.sortBy : ('a -> 'b) -> list<'a> -> list<'a> when 'b : Ord
```

The list sorted by the key `f x`. Stable.

### `Array.copy`

```zsharp
Array.copy : array<'a> -> array<'a>
```

A new array with the same elements.

### `Array.mapi`

```zsharp
Array.mapi : (int -> 'a -> 'b) -> array<'a> -> array<'b>
```

Like `Array.map`, with each element's index: `f i x`.

### `Array.exists`

```zsharp
Array.exists : ('a -> bool) -> array<'a> -> bool
```

Whether `f` is true for some element.

### `Array.contains`

```zsharp
Array.contains : 'a -> array<'a> -> bool when 'a : Eq
```

Whether the array contains `x` (compared with `=`).

### `Array.filter`

```zsharp
Array.filter : ('a -> bool) -> array<'a> -> array<'a>
```

A new array with the elements for which `f` is true.

### `Array.append`

```zsharp
Array.append : array<'a> -> array<'a> -> array<'a>
```

A new array with the elements of `a` followed by those of `b`.

### `Array.sub`

```zsharp
Array.sub : array<'a> -> int -> int -> array<'a>
```

A new array of `len` elements starting at index `start`.

### `Array.rev`

```zsharp
Array.rev : array<'a> -> array<'a>
```

A new array in reverse order.

### `Array.sort`

```zsharp
Array.sort : array<'a> -> array<'a> when 'a : Ord
```

A new array sorted in ascending order. Stable.

### `Array.sortWith`

```zsharp
Array.sortWith : ('a -> 'a -> 'b) -> array<'a> -> array<'a> when 'b : Ord
```

A new array sorted with `f` (like `compare`). Stable.

### `Option.toList`

```zsharp
Option.toList : option<'a> -> list<'a>
```

`[x]` for `Some x`, `[]` for `None`.

### `Option.orElse`

```zsharp
Option.orElse : option<'a> -> option<'a> -> option<'a>
```

The option itself if it is `Some`, otherwise `other`.

### `Option.iter`

```zsharp
Option.iter : ('a -> unit) -> option<'a> -> unit
```

Calls `f` on the value of `Some`; does nothing for `None`.

### `Option.toResult`

```zsharp
Option.toResult : 'a -> option<'b> -> result<'b, 'a>
```

`Ok x` for `Some x`, `Error err` for `None`.

### `Result.mapError`

```zsharp
Result.mapError : ('a -> 'b) -> result<'c, 'a> -> result<'c, 'b>
```

Applies `f` to the error of `Error`; an `Ok` passes through.

### `Result.defaultValue`

```zsharp
Result.defaultValue : 'a -> result<'a, 'b> -> 'a
```

The value of `Ok`, or `d` for an `Error`.

### `Result.isOk`

```zsharp
Result.isOk : result<'a, 'b> -> bool
```

Whether the result is `Ok`.

### `Result.isError`

```zsharp
Result.isError : result<'a, 'b> -> bool
```

Whether the result is `Error`.

### `Result.toOption`

```zsharp
Result.toOption : result<'a, 'b> -> option<'a>
```

`Some x` for `Ok x`, `None` for an `Error`.

### `String.isEmpty`

```zsharp
String.isEmpty : string -> bool
```

Whether the string has no bytes.

### `String.contains`

```zsharp
String.contains : string -> string -> bool
```

Whether `sub` occurs in `s`.

### `String.indexOf`

```zsharp
String.indexOf : string -> string -> option<int>
```

The byte index of the first `sub` in `s`, or `None`.

### `String.startsWith`

```zsharp
String.startsWith : string -> string -> bool
```

Whether `s` begins with `p`.

### `String.endsWith`

```zsharp
String.endsWith : string -> string -> bool
```

Whether `s` ends with `p`.

### `String.split`

```zsharp
String.split : string -> string -> list<string>
```

The pieces of `s` between occurrences of `sep`: `String.split ", " "a, b" = ["a"; "b"]`.

### `String.join`

```zsharp
String.join : string -> list<string> -> string
```

The strings with `sep` between them.

### `String.concat`

```zsharp
String.concat : list<string> -> string
```

The strings joined with nothing between them.

### `String.repeat`

```zsharp
String.repeat : 'a -> string -> string
```

`s` repeated `n` times.

### `String.parseInt`

```zsharp
String.parseInt : string -> option<int>
```

The integer written in `s` (optional sign, decimal digits), or `None`.

### `String.parseFloat`

```zsharp
String.parseFloat : string -> option<f64>
```

The floating-point number written in `s`, or `None`.

### `Console.print`

```zsharp
Console.print : string -> unit
```

Writes the string to standard output, without a newline.

### `Console.println`

```zsharp
Console.println : string -> unit
```

Writes the string and a newline to standard output.

### `Console.eprintln`

```zsharp
Console.eprintln : string -> unit
```

Writes the string and a newline to standard error.

### `Console.readLine`

```zsharp
Console.readLine : unit -> option<string>
```

The next line of standard input without its newline, or `None` at the end.

