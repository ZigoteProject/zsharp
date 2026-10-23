# 2. Basics

## Values and functions

`let` names a value. Names are immutable: a `let` can't be assigned to later.

```zsharp
let square x = x * x

let hypot (a: f64) (b: f64) : f64 =
  let aa = a * a
  let bb = b * b
  aa + bb

let main () =
  let n = square 12
  println $"{n} {hypot 3.0 4.0}"
  0
```

```text
144 25
```

**Calling and defining:**
- **Calls:** a function is called by writing its arguments after it, separated by spaces: `square 12` or `hypot 3.0 4.0`. Parentheses are only for grouping: `square (square 2)`.
- **Types are inferred:** `square` works for any number type. `hypot` has annotations (`(a: f64)`, `: f64` for the result); they're optional, and useful as documentation.
- **Blocks:** a function's body is an expression. A block's lines run in order, and the last line is the value.

## Top-level values

A `let` without parameters at the top of a file is a value.
- **Constants:** built from literals, operators, constructors (`[]` too), records, tuples and other constants. They're inlined where used, so they cost nothing. A number constant without an annotation takes the type each use needs, like a literal, and one whose type has type variables is generic, as F#'s values are: `Map.empty` is an empty map of any type, at each use its own.
- **Other values:** anything that allocates or calls a function, such as an array, a list of elements or `Map.ofList …`. These are computed once when the program starts, in the order they're declared (dependencies' modules first), so each has one type; a generic one is an error that says to make it a function.
- **Order:** declarations are in order, as in F#, so a value can only use what's declared above it.

```zsharp
let width = 8
let area = width * width
let mask = 0xFF
let banner = "== report =="
let squares = Array.init 5 (fun i -> i * i)   // computed once, at startup

let main () =
  let low: u8 = mask
  println $"{banner} {area} {low} {mask * 1000} {squares.[3]} {(mask: int) + 1}"
  0
```

```text
== report == 64 255 255000 9 256
```

`(e: T)` gives an expression a type, here making `mask` an `int` for the addition.

## Numbers

| Type | What | Literal |
|---|---|---|
| `int` | signed integer, the machine word: 64 bits (32 on a Cortex-M) | `42`, `-7`, `0xFF`, `0b1010`, `1_000_000` |
| `i8` `i16` `i32` `i64` | signed integers of a fixed size | `i32 5` |
| `u8` `u16` `u32` `u64` | unsigned integers of a fixed size | `u8 255` |
| `usize` | unsigned, the machine word (sizes, addresses) | `usize 4096` |
| `f64` | 64-bit float (also `float`) | `3.14`, `1e-3` |
| `f32` | 32-bit float | `f32 1.5` |

**Literals and conversions:**
- **Integer literals:** take whatever integer type the context needs, so `let x: u8 = 200` is fine.
- **Float literals:** work the same way with `f64` and `f32`.
- **Converting:** done explicitly with the type's name used as a function, e.g. `float n`, `int 3.9` (which truncates), `u8 n`, `f32 x`.
- **Math:** `Math.sqrt` (one instruction where the hardware has it) and `Math.abs`; the C library's other functions come in with `import c "math.h"`.

```zsharp
let main () =
  let items = 7
  let price = 2.5
  let total = float items * price
  println $"{total} {int total} {7 / 2} {7 % 2} {7.0 / 2.0}"
  let small: u8 = 200
  println $"{small} {i32 70000} {f32 0.1 + f32 0.2}"
  0
```

```text
17.5 17 3 1 3.5
200 70000 0.3
```

**Operators:**
- **Arithmetic:** `+ - * / %`. Integer `/` rounds toward zero.
- **Overflow:** integer arithmetic that overflows stops the program with a panic, in every build. [Errors](07-errors.md#overflow) shows the wrapping operations to use when wrap-around is what you want.
- **Width of `int`:** `int` is as wide as the machine's word, as in Swift and Go. That's 64 bits on a desktop or phone, and 32 bits on a microcontroller, where 64-bit arithmetic costs two instructions per operation. Use `i64` when a value needs 64 bits everywhere.

## Bitwise operators

`&&&` (and), `|||` (or), `^^^` (xor), `<<<` and `>>>` (shifts) and `~~~` (not) work on every integer type, as in F#.
- **Precedence:** they bind tighter than comparison, so `flags &&& mask <> 0` needs no parentheses.
- **Shifts:** `>>>` keeps the sign for signed types and fills with zeros for unsigned ones. The shift amount is taken modulo the width.

```zsharp
let main () =
  let flags = 0b0101
  println $"{flags &&& 0b0100 <> 0} {flags ||| 0b0010} {flags ^^^ 0xF} {1 <<< 10} {-16 >>> 2} {~~~0}"
  let b = u8 0xF0
  println $"{b >>> u8 4} {~~~b} {(b <<< u8 1) &&& u8 0xFF}"
  0
```

```text
true 7 10 1024 -4 -1
15 15 224
```

## Booleans and comparison

**Comparison:**
- `=` and `<>` compare for equality, and `< > <= >=` compare order. They work on numbers and strings, and on records, unions, tuples and lists too ([Traits](06-traits.md)).
- `compare a b` gives a negative number, zero or a positive number.

**Logic:** `&&`, `||` and `not`.

```zsharp
let main () =
  let a = 3
  let b = 5
  println $"{a = b} {a <> b} {a < b && b < 10} {not (a > b)} {compare a b}"
  println $"{"apple" < "banana"} {[ 1; 2 ] = [ 1; 2 ]}"
  0
```

```text
false true true true -1
true true
```

## Strings

**What a string is:** an immutable sequence of UTF-8 bytes. `+` joins two strings.

**Interpolation:** `$"..."` evaluates the expressions in braces and inserts their text. Any value with a `Show` impl can go in a hole: numbers, strings, records, unions, lists and options all have one.
- **Formats and widths,** as in .NET: `{ratio:F2}` (fixed, two decimals), `{n:N0}` (with commas), `{flags:X8}` (hex), `{id:D5}`, `{x:E2}`, `{bits:B8}`; `{name,10}` pads on the left to 10 characters and `{name,-10}` on the right, and `{x,8:F1}` does both. A specifier a number doesn't have is a compile error. A tuple in a hole is written `{(a, b)}`.

**Escapes:** `\n`, `\r`, `\t`, `\0`, `\"`, `\'`, `\\`, and `\u{e9}` for any Unicode character by its hex code.
- **Over several lines:** a string can span lines, and the line breaks are part of it.
- **Raw strings:** `"""…"""` keeps quotes and backslashes as written: `"""{ "path": "C:\new" }"""`.

```zsharp
let main () =
  let name = "Ada"
  let langs = [ "F#"; "OCaml" ]
  println ("Hello, " + name + "!")
  println $"{name} has {String.length name} letters and knows {langs}"
  println $"tab:\t| quote: \" | sum: {1 + 2}"
  let s = "  Hello, World  "
  let t = s.Trim()
  println $"[{t}] {t.ToUpper()} {t.Contains("World")} {t.Replace("l", "L")}"
  println $"{String.split ", " t} {String.join "-" [ "a"; "b"; "c" ]}"
  println $"{String.parseInt "42"} {String.parseInt "4x2"} {string 3.5}"
  println $"[{name,-6}] [{3.14159:F2}] [{255:X4}] [{1234567:N0}]"
  0
```

```text
Hello, Ada!
Ada has 3 letters and knows [F#; OCaml]
tab:	| quote: " | sum: 3
[Hello, World] HELLO, WORLD true HeLLo, WorLd
[Hello; World] a-b-c
Some 42 None 3.5
[Ada   ] [3.14] [00FF] [1,234,567]
```

- **Parsing numbers:** `Int.parse "42"` and `Float.parse "2.5"` give an `option`; the result's type decides the width (`let b: option<u8> = Int.parse s` is `None` above 255), and `Int.parseRadix 16 "ff"` reads another base.

- **Converting to text:** `string x` gives any showable value's text.
- **Characters:** `char` is one Unicode character (a code point), written `'a'`, `'\n'` or `'\u{e9}'`.
  - **Iterating:** `for c in s` goes over a string's characters, decoding its UTF-8. `String.length` counts bytes and `String.charCount` counts characters.
  - **Converting:** `int c` gives the code point, and `char 65` the character.
  - **Testing and changing:** `Char.isDigit`, `isLetter`, `isWhitespace`, `toUpper` and the others work on ASCII.
- **String functions:** the `String.*` functions and the members (`s.Length`, `s.Trim()`, `s.Split(sep)`, …) are listed in [the reference](../reference/Text.String.md).

**Printing:**
- `print` and `println` write to standard output.
- `eprintln` writes to standard error.

```zsharp
let vowels (s: string) =
  let mutable n = 0
  for c in s do
    match Char.toLower c with
    | 'a' | 'e' | 'i' | 'o' | 'u' -> n <- n + 1
    | _ -> ()
  n

let main () =
  let word = "Crème brûlée"
  println $"{String.length word} bytes, {String.charCount word} characters, {vowels word} plain vowels"
  println $"{String.chars "abc"} {int 'A'} {char 97} {String.ofChars [ 'h'; 'i' ]} {'\u{e9}'}"
  0
```

```text
15 bytes, 12 characters, 2 plain vowels
[a; b; c] 65 a hi é
```

## if, while, for

`if` is an expression: both branches give a value of the same type. Without an `else`, the branch must be `unit` (a statement).

```zsharp
let sign n = if n < 0 then -1 else if n = 0 then 0 else 1

let main () =
  println $"{sign -5} {sign 0} {sign 9}"
  for i in 1 .. 3 do
    print $"{i} "
  for i in 10 .. -5 .. 0 do
    print $"{i} "
  println ""
  for w in [ "a"; "b" ] do
    print $"{w}! "
  println ""
  let mutable n = 1
  while n < 100 do
    n <- n * 3
  println $"{n}"
  0
```

```text
-1 0 1
1 2 3 10 5 0 
a! b! 
243
```

**Loops:**
- `for i in a .. b` counts up to `b` inclusive, and `a .. step .. b` uses a step, which can be negative.
- `for x in xs` goes over any collection: a list, an array, a Buffer, a string's characters, an option, a `Map`'s entries (`for (k, v) in m`), a `Set`, a `HashMap` or a `Seq`, and a type of your own with an `Iter` impl ([traits](06-traits.md#traits-with-several-parameters)). Each compiles to one loop with the body in place, and the body may assign the function's mutable variables.
- There's no `break`: to stop at the first match use `Iter.exists`, `Iter.tryFind` or `List.tryFind`.

## Mutation

Values are immutable unless declared otherwise.
- **`let mutable`:** a variable that `<-` can assign to.
- **Compound assignment:** `x += e` is `x <- x + e`, and so are `-=`, `*=`, `/=`, `%=`, `&&&=`, `|||=` and `^^^=`, on anything `<-` assigns: a mutable variable, a `ref`'s `.Value`, an array element, a field of a mutable record. The place is evaluated once, so `a.[next ()] += 1` calls `next` once.
- **Closures:** a mutable variable can't be captured by a closure. Use a `ref` cell for that: `r.Value` reads it and `r.Value <- x` writes it.

```zsharp
let counter () =
  let count = ref 0
  fun () ->
    count.Value += 1
    count.Value

let main () =
  let mutable total = 0
  for i in 1 .. 10 do
    total += i
  let next = counter ()
  next () |> ignore
  println $"{total} {next ()}"
  0
```

```text
55 2
```

`ignore` discards a value. A statement whose value isn't `unit` must be ignored explicitly, so a forgotten result doesn't go unnoticed.
