# 3. Data

## Tuples

A tuple groups a fixed number of values, possibly of different types. `let (a, b) = …`
takes one apart.

```zsharp
let divmod a b = (a / b, a % b)

let main () =
  let (q, r) = divmod 17 5
  let pair = ("x", 2.5)
  println $"{q} {r} {fst pair} {snd pair} {pair}"
  0
```

```text
3 2 x 2.5 (x, 2.5)
```

## Records

A record has named fields.
- **Creating:** write the fields in braces. The record type is found from the field names, among the records in scope ([Programs](08-programs.md#modules)); when two record types share their field names, the expected type decides.
- **Immutable:** a record's fields can't be assigned. `{ r with field = … }` makes a copy with some fields changed.

```zsharp
type Point = { x: int; y: int }

type Config =
  { host: string = "localhost"
    port: int = 8080
    timeout: int = port / 100 }

let main () =
  let p = { x = 1; y = 2 }
  let q = { p with y = 10 }
  println $"{p} {q} {p.x + q.y} {p = { x = 1; y = 2 }}"
  let c = { port = 9000 }
  println $"{c.host}:{c.port} timeout {c.timeout}"
  0
```

```text
{ x = 1; y = 2 } { x = 1; y = 10 } 11 true
localhost:9000 timeout 90
```

**Defaults:**
- A field can have a default (`= …`), and a literal may then leave it out.
- A default can use the fields before it, as `timeout` uses `port`.
- A field whose type is an option needs an explicit `= None` to be optional.

## Unions

A union, or discriminated union, is a value that is one of several cases, each with its own data. Cases may name their fields.

```zsharp
type Shape =
  | Circle of radius: f64
  | Rect of w: f64 * h: f64
  | Dot

let area s =
  match s with
  | Circle r -> 3.14159 * r * r
  | Rect (w, h) -> w * h
  | Dot -> 0.0

let main () =
  let shapes = [ Circle 1.0; Rect (2.0, 3.0); Rect(h = 1.0, w = 4.0); Dot ]
  for s in shapes do
    println $"{s}: {area s}"
  0
```

```text
Circle 1: 3.14159
Rect (2, 3): 6
Rect (4, 1): 4
Dot: 0
```

Unions can be generic and recursive:

```zsharp
type Tree<'a> =
  | Leaf
  | Node of Tree<'a> * 'a * Tree<'a>

let rec insert x t =
  match t with
  | Leaf -> Node (Leaf, x, Leaf)
  | Node (l, v, r) -> if x < v then Node (insert x l, v, r) else Node (l, v, insert x r)

let rec toList t =
  match t with
  | Leaf -> []
  | Node (l, v, r) -> toList l @ [ v ] @ toList r

let main () =
  let t = List.fold (fun t x -> insert x t) Leaf [ 5; 2; 8; 1 ]
  println $"{toList t}"
  0
```

```text
[1; 2; 5; 8]
```

## Option and result

There is no null. A value that may be missing is an `option`, `Some x` or `None`, and the
compiler makes you handle both. A computation that can fail returns a `result`, `Ok value` or
`Error err` ([Errors](07-errors.md)).

```zsharp
let find key pairs =
  match List.tryFind (fun (k, _) -> k = key) pairs with
  | Some (_, v) -> Some v
  | None -> None

let main () =
  let ages = [ ("ada", 36); ("alan", 41) ]
  println $"{find "ada" ages} {find "bob" ages}"
  println $"{find "bob" ages |> Option.defaultValue 0} {Option.map (fun a -> a + 1) (find "alan" ages)}"
  0
```

```text
Some 36 None
0 Some 42
```

## Pattern matching

`match` tries each case in order and takes the first that matches.

**What a pattern can be:**
- a literal (a number, character, string or bool), or `_` for anything;
- a variable, which binds the value;
- a tuple, a record (`{ x = 0; y = y }`, where the fields left out match anything), a union case, or a list (`[]`, `x :: rest`, `[ a; b ]`);
- an or-pattern (`|`);
- `as name`, which binds the whole value too.

`when` adds a condition to a case.

**`function`:** `function | p -> … | q -> …` is a lambda that matches its argument, for `fun x -> match x with …`: `List.map (function Some n -> n | None -> 0) opts`.

**Checks:** the compiler rejects a `match` that misses a case, naming an example of the missing value, and a case that can never be reached.

```zsharp
let describe xs =
  match xs with
  | [] -> "empty"
  | [ x ] -> $"just {x}"
  | x :: y :: _ when x = y -> "starts with a pair"
  | x :: rest -> $"{x} and {List.length rest} more"

let classify n =
  match n with
  | 0 -> "zero"
  | 1 | 2 | 3 -> "small"
  | n when n < 0 -> "negative"
  | _ -> "big"

let command (words: list<string>) =
  match words with
  | [ "open"; file ] -> $"opening {file}"
  | [ "quit" ] | [ "exit" ] -> "bye"
  | _ -> "unknown"

let main () =
  println $"{describe []} | {describe [ 7 ]} | {describe [ 4; 4; 1 ]} | {describe [ 1; 2; 3 ]}"
  println $"{classify 0} {classify 2} {classify -5} {classify 99}"
  println $"{command [ "open"; "a.txt" ]} {command [ "exit" ]}"
  match (1, "one") with
  | (n, name) as both when n > 0 -> println $"{name} {both}"
  | _ -> println "other"
  0
```

```text
empty | just 7 | starts with a pair | 1 and 2 more
zero small negative big
opening a.txt bye
one (1, one)
```

Record patterns also work wherever a pattern can go: in `let`, in function parameters and in `for` loops.

```zsharp
type Point = { x: int; y: int }

let quadrant p =
  match p with
  | { x = 0; y = 0 } -> "origin"
  | { x = 0 } -> "on the y axis"
  | { x = x; y = y } when x > 0 && y > 0 -> "first"
  | _ -> "elsewhere"

let norm { x = x; y = y } = x * x + y * y

let main () =
  let { x = a; y = b } = { x = 3; y = 4 }
  println $"{quadrant { x = 0; y = 2 }} {quadrant { x = a; y = b }} {norm { x = a; y = b }}"
  0
```

```text
on the y axis first 25
```

## Active patterns

An active pattern is a function you can match with.
- **Total:** `(|Even|Odd|)` splits every value into cases.
- **Partial:** `(|Positive|_|)` matches or doesn't, by returning an option.
- **Parameterized:** `(|DivBy|_|) d` takes arguments before the value.

```zsharp
let (|Even|Odd|) n = if n % 2 = 0 then Even else Odd

let (|DivBy|_|) d n = if n % d = 0 then Some (n / d) else None

let fizz n =
  match n with
  | DivBy 15 _ -> "FizzBuzz"
  | DivBy 3 _ -> "Fizz"
  | DivBy 5 _ -> "Buzz"
  | Even -> "even"
  | Odd -> "odd"

let main () =
  for i in 1 .. 15 do
    print $"{fizz i} "
  println ""
  0
```

```text
odd even Fizz even Buzz Fizz odd even Fizz Buzz odd Fizz odd even FizzBuzz 
```
