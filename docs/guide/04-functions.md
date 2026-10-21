# 4. Functions

## First-class functions and closures

**Functions are values:**
- They can be passed, returned and stored.
- `fun x -> …` writes one inline.
- A function closes over the values it uses.

```zsharp
let twice f x = f (f x)

let adder n = fun x -> x + n

let main () =
  let add10 = adder 10
  println $"{twice add10 1} {twice (fun s -> s + "!") "hey"}"
  let fs = [ adder 1; adder 2; (fun x -> x * x) ]
  println $"{List.map (fun f -> f 5) fs}"
  0
```

```text
21 hey!!
[6; 7; 25]
```

## Partial application and pipelines

**Curried functions:** a function of several arguments is curried, so giving it fewer arguments gives a function of the rest. Pipelines build on this:
- `x |> f` is `f x`, so a chain of transformations reads left to right.
- `f >> g` composes two functions.

```zsharp
let add x y = x + y

let main () =
  let inc = add 1
  let total =
    [ 1; 2; 3; 4; 5 ]
    |> List.map (fun x -> x * x)
    |> List.filter (fun x -> x % 2 = 1)
    |> List.sum
  let shout = String.toUpper >> (fun s -> s + "!")
  println $"{inc 41} {total} {shout "hi"}"
  0
```

```text
42 35 HI!
```

## Custom operators

**Defining one:** `let (>>=) r f = …` defines an operator, a function with a symbolic name.
- **Using it:** it goes between its two arguments: `r >>= f`.
- **As a function:** `(>>=)` is the function itself, and so is `(+)` for a built-in operator.

**Precedence:** an operator binds like the built-in ones that start with the same character, as in F#. Leading dots don't count, so `.>>` binds like `>>`.

| Starts with | Binds like | Groups |
|---|---|---|
| `<` `>` `=` `\|` `&` `$` `!` | `\|>`, `>>` and `=` | from the left |
| `@` `^` | `::` | from the right |
| `+` `-` | `+` | from the left |
| `*` `/` `%` | `*` | from the left |
| `**` | | from the right |

So `x |> parse >>= check` is `(x |> parse) >>= check`, and `a =~ b && c` is `(a =~ b) && c`. A line that starts with an operator continues the one above, as a line starting with `|>` does. This is what railway-style error handling and parser combinators (`p <|> q`, `p .>>. q |>> f`) are written with.

```zsharp
let (>>=) r f = Result.bind f r
let (>=>) f g x = f x >>= g

let parse (s: string) =
  match String.parseInt s with
  | Some n -> Ok n
  | None -> Error $"not a number: {s}"

let positive n = if n > 0 then Ok n else Error $"not positive: {n}"
let even n = if n % 2 = 0 then Ok n else Error $"odd: {n}"

let check = parse >=> positive >=> even

let main () =
  println $"{check "42"} {check "-2"} {check "7"} {check "x"}"
  let next =
    "20"
    |> parse
    >>= fun n -> Ok (n + 1)
  println $"{next} {List.fold (+) 0 [ 1; 2; 3 ]}"
  0
```

```text
Ok 42 Error not positive: -2 Error odd: 7 Error not a number: x
Ok 21 6
```

## Recursion

**Recursive functions:**
- A function that calls itself is declared `let rec`.
- Calls in tail position compile to jumps, so a tail-recursive loop runs in constant stack space, however long it goes.
- Functions can also be defined inside other functions.

```zsharp
let rec sumTo acc n = if n = 0 then acc else sumTo (acc + n) (n - 1)

let collatz start =
  let rec steps n count =
    if n = 1 then count
    else if n % 2 = 0 then steps (n / 2) (count + 1)
    else steps (3 * n + 1) (count + 1)
  steps start 0

let main () =
  println $"{sumTo 0 10000000} {collatz 27}"
  0
```

```text
50000005000000 111
```

Functions that call each other are defined together with `let rec … and …`, at the top level or inside a function. Calls between them in tail position are tail calls too, so mutual recursion also runs in constant stack.

```zsharp
let rec isEven n = if n = 0 then true else isOdd (n - 1)
and isOdd n = if n = 0 then false else isEven (n - 1)

let main () =
  let rec ping n = if n = 0 then "ping" else pong (n - 1)
  and pong n = if n = 0 then "pong" else ping (n - 1)
  println $"{isEven 10} {isOdd 1000001} {ping 3}"
  0
```

```text
true true pong
```

## Generics

**Generic code:**
- Functions are generic without any extra syntax: `swap` below works on pairs of any types.
- Types take type parameters, `'a`, written in angle brackets.
- Generic code is compiled once per type it's used with, so it runs as fast as code written for one type.

```zsharp
let swap (a, b) = (b, a)

type Stack<'a> = { items: list<'a> }

let push x (s: Stack<'a>) = { items = x :: s.items }

let main () =
  println $"{swap (1, "one")} {swap (true, 2.5)}"
  let s = { items = [] } |> push 1 |> push 2
  println $"{s.items}"
  0
```

```text
(one, 1) (2.5, true)
[2; 1]
```

## Members

A type can have members, which are functions called with dot syntax.
- **Properties:** `member v.Length = …` takes no arguments.
- **Methods:** `member v.Add(o) = …` takes arguments in parentheses, separated by commas.
- **Static members:** called on the type.
- **Type extensions:** `type T with …` adds members to a type defined elsewhere.

```zsharp
type Vec =
  { x: f64; y: f64 }
  member v.Length = v.x * v.x + v.y * v.y
  member v.Add(o: Vec) = { x = v.x + o.x; y = v.y + o.y }
  static member Zero = { x = 0.0; y = 0.0 }

type string with
  member s.Shout = s.ToUpper() + "!"

let main () =
  let v = { x = 3.0; y = 4.0 }
  println $"{v.Length} {(v.Add(Vec.Zero)).x} {"hey".Shout}"
  0
```

```text
25 3 HEY!
```

## Named, optional and default arguments

**Member arguments:**
- **Named:** a member's arguments can be given by name.
- **Optional:** an argument declared `?name` may be left out. With `= default` it gets that value; without one it's an `option`.
- **Defaults:** a default can use the arguments before it.

These apply to members only. Ordinary curried functions keep positional arguments.

```zsharp
type Http =
  static member Get(url: string, ?timeout: int = 30, ?retries = timeout / 10, ?tag: string) =
    let t = Option.defaultValue "none" tag
    $"GET {url} timeout={timeout} retries={retries} tag={t}"

let main () =
  println (Http.Get("a.org"))
  println (Http.Get("b.org", 50, tag = "x"))
  println (Http.Get("c.org", retries = 7))
  0
```

```text
GET a.org timeout=30 retries=3 tag=none
GET b.org timeout=50 retries=5 tag=x
GET c.org timeout=30 retries=7 tag=none
```
