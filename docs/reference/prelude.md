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

### `ProcessResult`

```zsharp
type ProcessResult
```

What a finished process left: its exit code and everything it wrote to standard output.

### `Map`

```zsharp
type Map<'k, 'v>
```

A persistent map from keys (ordered with `Ord`) to values. Adding or removing gives a new
map and leaves the old one unchanged; both share most of their structure.

#### `MapLeaf`

```zsharp
| MapLeaf
```

The empty map.

#### `MapNode`

```zsharp
| MapNode of Map<'k, 'v> * 'k * 'v * Map<'k, 'v> * int
```

A node: left subtree, key, value, right subtree, height.

### `Set`

```zsharp
type Set<'a>
```

A persistent sorted set (a `Map` to unit underneath).

### `HashMap`

```zsharp
type HashMap<'k, 'v>
```

A hash map (keys with `Hash` and `Eq`). It is a value like an array: `HashMap.add` gives
the changed map, updated in place when nothing else refers to the old one.

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

### `Math.abs`

```zsharp
Math.abs : 'a -> 'a when 'a : Add, 'a : Num, 'a : Ord
```

The absolute value: `x` without its sign (named apart from C's `abs`, which programs often
import). For integers, the most negative value has none, so it overflows (and panics).

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

### `Char.isDigit`

```zsharp
Char.isDigit : char -> bool
```

Whether `c` is an ASCII digit, '0' to '9'.

### `Char.isLower`

```zsharp
Char.isLower : char -> bool
```

Whether `c` is an ASCII lower-case letter.

### `Char.isUpper`

```zsharp
Char.isUpper : char -> bool
```

Whether `c` is an ASCII upper-case letter.

### `Char.isLetter`

```zsharp
Char.isLetter : char -> bool
```

Whether `c` is an ASCII letter.

### `Char.isLetterOrDigit`

```zsharp
Char.isLetterOrDigit : char -> bool
```

Whether `c` is an ASCII letter or digit.

### `Char.isWhitespace`

```zsharp
Char.isWhitespace : char -> bool
```

Whether `c` is a space, tab, line feed or carriage return.

### `Char.toUpper`

```zsharp
Char.toUpper : char -> char
```

`c` in upper case (ASCII letters; others unchanged).

### `Char.toLower`

```zsharp
Char.toLower : char -> char
```

`c` in lower case (ASCII letters; others unchanged).

### `Char.digitValue`

```zsharp
Char.digitValue : char -> option<int>
```

The value of an ASCII digit: `Some 7` for '7', `None` for anything else.

### `String.decodeAt`

```zsharp
String.decodeAt : string -> int -> char * int
```

The character that starts at byte `i` of `s`, and the byte index after it (UTF-8 decoding;
a malformed sequence gives U+FFFD and moves one byte). `for c in s` uses it.

### `String.chars`

```zsharp
String.chars : string -> list<char>
```

The characters of `s`, in order (decoded from UTF-8).

### `String.charCount`

```zsharp
String.charCount : string -> 'a when 'a : Add
```

The number of characters in `s`. `String.length` counts bytes.

### `String.ofChar`

```zsharp
String.ofChar : char -> string
```

A string of one character (its UTF-8 encoding).

### `String.ofChars`

```zsharp
String.ofChars : list<char> -> string
```

A string of the characters, in order.

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

### `Console.readLines`

```zsharp
Console.readLines : unit -> list<string>
```

All of standard input, line by line (without the newlines).

### `Env.args`

```zsharp
Env.args : unit -> list<string>
```

The command-line arguments, without the program name.

### `Env.programName`

```zsharp
Env.programName : unit -> string
```

The program name as it was started (`argv[0]`).

### `Env.var`

```zsharp
Env.var : string -> option<string>
```

The environment variable `name`, or `None` when it isn't set.

### `File.read`

```zsharp
File.read : string -> result<string, string>
```

The whole file as a string, or the error (`cannot open data.txt: No such file or directory`).

### `File.lines`

```zsharp
File.lines : string -> result<list<string>, string>
```

The file's lines, without line endings; a final newline doesn't add an empty line.

### `File.write`

```zsharp
File.write : string -> string -> result<unit, string>
```

Replaces the file's contents with `text` (creating it if needed).

### `File.append`

```zsharp
File.append : string -> string -> result<unit, string>
```

Adds `text` to the end of the file (creating it if needed).

### `File.delete`

```zsharp
File.delete : string -> result<unit, string>
```

Deletes the file.

### `Dir.create`

```zsharp
Dir.create : string -> result<unit, string>
```

Creates the directory; an existing one is fine.

### `Dir.list`

```zsharp
Dir.list : string -> result<list<string>, string>
```

The names in the directory (not `.` or `..`), sorted.

### `Process.run`

```zsharp
Process.run : string -> list<string> -> result<ProcessResult, string>
```

Runs `program` (looked up on PATH) with the arguments, without a shell, and waits for it.
An `Error` means it couldn't start; a failing program is an `Ok` with a nonzero code.

### `Map.empty`

```zsharp
Map.empty : unit -> Map<'a, 'b>
```

The empty map.

### `Map.isEmpty`

```zsharp
Map.isEmpty : Map<'a, 'b> -> bool
```

Whether the map has no entries.

### `Map.add`

```zsharp
Map.add : 'a -> 'b -> Map<'a, 'b> -> Map<'a, 'b> when 'a : Ord
```

The map with `key` bound to `value` (replacing an existing binding).

### `Map.tryFind`

```zsharp
Map.tryFind : 'a -> Map<'a, 'b> -> option<'b> when 'a : Ord
```

The value bound to `key`, or `None`.

### `Map.find`

```zsharp
Map.find : 'a -> Map<'a, 'b> -> 'b when 'a : Ord
```

The value bound to `key`. Panics when there is none; see `Map.tryFind`.

### `Map.containsKey`

```zsharp
Map.containsKey : 'a -> Map<'a, 'b> -> bool when 'a : Ord
```

Whether the map binds `key`.

### `Map.remove`

```zsharp
Map.remove : 'a -> Map<'a, 'b> -> Map<'a, 'b> when 'a : Ord
```

The map without `key` (the same map when `key` isn't bound).

### `Map.fold`

```zsharp
Map.fold : ('a -> 'b -> 'c -> 'a) -> 'a -> Map<'b, 'c> -> 'a
```

Combines the entries in ascending key order: `f state key value`.

### `Map.count`

```zsharp
Map.count : Map<'a, 'b> -> 'c when 'c : Add
```

The number of entries. O(n).

### `Map.toList`

```zsharp
Map.toList : Map<'a, 'b> -> list<'a * 'b>
```

The entries as (key, value) pairs in ascending key order.

### `Map.ofList`

```zsharp
Map.ofList : list<'a * 'b> -> Map<'a, 'b> when 'a : Ord
```

A map with the pairs' bindings (a later pair wins over an earlier one with the same key).

### `Map.keys`

```zsharp
Map.keys : Map<'a, 'b> -> list<'a>
```

The keys in ascending order.

### `Map.values`

```zsharp
Map.values : Map<'a, 'b> -> list<'b>
```

The values in ascending key order.

### `Map.iter`

```zsharp
Map.iter : ('a -> 'b -> 'c) -> Map<'a, 'b> -> unit
```

Calls `f key value` on every entry in ascending key order.

### `Map.map`

```zsharp
Map.map : ('a -> 'b -> 'c) -> Map<'a, 'b> -> Map<'a, 'c>
```

The map with `f key value` as every value.

### `Map.filter`

```zsharp
Map.filter : ('a -> 'b -> bool) -> Map<'a, 'b> -> Map<'a, 'b> when 'a : Ord
```

The entries for which `f key value` is true.

### `Set.empty`

```zsharp
Set.empty : unit -> Set<'a>
```

The empty set.

### `Set.add`

```zsharp
Set.add : 'a -> Set<'a> -> Set<'a> when 'a : Ord
```

The set with `x` added.

### `Set.remove`

```zsharp
Set.remove : 'a -> Set<'a> -> Set<'a> when 'a : Ord
```

The set without `x`.

### `Set.contains`

```zsharp
Set.contains : 'a -> Set<'a> -> bool when 'a : Ord
```

Whether the set contains `x`.

### `Set.count`

```zsharp
Set.count : Set<'a> -> 'b when 'b : Add
```

The number of elements. O(n).

### `Set.isEmpty`

```zsharp
Set.isEmpty : Set<'a> -> bool
```

Whether the set has no elements.

### `Set.toList`

```zsharp
Set.toList : Set<'a> -> list<'a>
```

The elements in ascending order.

### `Set.ofList`

```zsharp
Set.ofList : list<'a> -> Set<'a> when 'a : Ord
```

A set of the list's elements.

### `Set.union`

```zsharp
Set.union : Set<'a> -> Set<'a> -> Set<'a> when 'a : Ord
```

The elements in either set.

### `Set.intersect`

```zsharp
Set.intersect : Set<'a> -> Set<'a> -> Set<'a> when 'a : Ord
```

The elements in both sets.

### `Set.difference`

```zsharp
Set.difference : Set<'a> -> Set<'a> -> Set<'a> when 'a : Ord
```

The elements of `a` that aren't in `b`.

### `HashMap.empty`

```zsharp
HashMap.empty : unit -> HashMap<'a, 'b>
```

An empty hash map.

### `HashMap.tryFind`

```zsharp
HashMap.tryFind : 'a -> HashMap<'a, 'b> -> option<'b> when 'a : Eq, 'a : Hash
```

The value bound to `key`, or `None`.

### `HashMap.containsKey`

```zsharp
HashMap.containsKey : 'a -> HashMap<'a, 'b> -> bool when 'a : Eq, 'a : Hash
```

Whether the map binds `key`.

### `HashMap.count`

```zsharp
HashMap.count : HashMap<'a, 'b> -> int
```

The number of entries.

### `HashMap.toList`

```zsharp
HashMap.toList : HashMap<'a, 'b> -> list<'a * 'b>
```

The entries as (key, value) pairs, in no particular order.

### `HashMap.add`

```zsharp
HashMap.add : 'a -> 'b -> HashMap<'a, 'b> -> HashMap<'a, 'b> when 'a : Eq, 'a : Hash
```

The map with `key` bound to `value` (replacing an existing binding).

### `HashMap.remove`

```zsharp
HashMap.remove : 'a -> HashMap<'a, 'b> -> HashMap<'a, 'b> when 'a : Eq, 'a : Hash
```

The map without `key`.

### `HashMap.ofList`

```zsharp
HashMap.ofList : list<'a * 'b> -> HashMap<'a, 'b> when 'a : Eq, 'a : Hash
```

A hash map with the pairs' bindings.

