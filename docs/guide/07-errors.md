# 7. Errors

Z# separates two kinds of failure:
- **Expected failures:** a missing file, bad input. These are values, `result<'a, 'e>`, that the caller has to handle. Inside a module, a function may instead throw a typed exception, the `Throw` effect, which its type shows and `Throw.catch` turns back into a `result` ([chapter 16](16-effects.md#typed-exceptions-throw)).
- **Bugs:** an index out of bounds, an overflow, a failed assertion. These are **panics**, which stop the program at once.

## result and `?`

**`result` holds either outcome:** `Ok value` or `Error err`. The `?` operator after an expression unwraps an `Ok`, or returns the `Error` from the enclosing function right away. A chain of fallible steps reads like straight-line code.

```zsharp
let parseAge (s: string) =
  match String.parseInt s with
  | Some n when n >= 0 -> Ok n
  | Some n -> Error $"negative age: {n}"
  | None -> Error $"not a number: {s}"

let totalAge a b =
  let x = parseAge a?
  let y = parseAge b?
  Ok (x + y)

let main () =
  for (a, b) in [ ("36", "41"); ("36", "x"); ("-1", "2") ] do
    match totalAge a b with
    | Ok n -> println $"total {n}"
    | Error e -> println $"error: {e}"
  0
```

```text
total 77
error: not a number: x
error: negative age: -1
```

**`?` on an `option`:** in a function that returns an `option`, `x?` is the value in a `Some`, or returns `None` right away. Which `?` it is comes from the operand; a `result` under `?` in a function returning an `option` (or the reverse) is an error that names the conversion (`Result.toOption`, `Option.toResult`).

```zsharp
let initials (first: string) (last: string) =
  let f = List.tryHead (String.chars first)?
  let l = List.tryHead (String.chars last)?
  Some $"{f}.{l}."

let main () =
  println $"{initials "Ada" "Lovelace"} {initials "" "Hopper"}"
  0
```

```text
Some A.L. None
```

**How far `?` reaches:** `?` applies to the whole call before it, so `parseAge a?` is `(parseAge a)?`. It's allowed in `let x = e?` and as a statement of its own, and an error about it (in a function returning `unit`, say) points at the `?`.

**Working with results without matching:**
- `Result.map`, `Result.bind`, `Result.mapError` and `Result.defaultValue` transform or unwrap a result.
- `Option.toResult` turns a `None` into an error.
- **`result { }`:** a block whose `let!` stops at the first error, the way `?` stops a function ([Computation expressions](13-tasks.md#computation-expressions)); `option { }` does the same for `None`.

## Panics

A panic prints a message to standard error and ends the program with exit status 134.
- **No unwinding:** nothing is cleaned up, and a panic can't be caught.
- **When to use one:** for bugs, not for errors a caller should handle.

**What panics:**
- indexing out of bounds;
- integer division by zero;
- integer overflow;
- `List.head` of an empty list and similar;
- `assert` with a false condition, which names its file and line;
- `panic "message"` (or `failwith`), called explicitly.

```zsharp
let main () =
  println "checking"
  assert (1 + 1 = 2)
  let xs: list<int> = []
  println $"{List.tryHead xs}"
  println $"{List.head xs}"
  0
```

```text
checking
None
panic: List.head: empty list
```

**In a C program:** a panic in a Z# library ends the host process too. The host can set a hook that runs first ([C interop](09-c-interop.md)).

**Backtraces:** a panic also prints a backtrace. Set `ZS_BACKTRACE=0` to leave it out, as these examples do. In a test run with `zs test`, a panic fails that one test only ([Programs](08-programs.md#tests)).

## Overflow

**Integer arithmetic is checked:** `+`, `-`, `*`, negation and `MIN / -1` panic on overflow, in optimized builds too, as in Swift. A silently wrong number is worse than a stopped program.

**Wrap-around on purpose:** for hashes, checksums and random number generators, use `Int.wrappingAdd`, `Int.wrappingSub` and `Int.wrappingMul`.

```zsharp
let main () =
  let big = 9223372036854775807
  println $"{Int.wrappingAdd big 1} {Int.wrappingMul (u8 200) (u8 2)}"
  println $"{big - 1}"
  println $"{big + 1}"
  0
```

```text
-9223372036854775808 144
9223372036854775806
panic: integer overflow
```

**A whole function:** `[<Wrapping>]` makes a function's integer `+`, `-` and `*` wrap around, including in the lambdas inside it. Floats and strings are unaffected, and negation and division keep their checks.

```zsharp
[<Wrapping>]
let fnv1a (s: string) =
  let mutable h = u32 2166136261
  for i in 0 .. String.length s - 1 do
    h <- (h ^^^ u32 (String.byte s i)) * u32 16777619
  h

let main () =
  println $"{fnv1a "hello"} {fnv1a "world"}"
  0
```

```text
1335831723 933488787
```
