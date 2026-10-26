# 17. Z# for F# programmers

Z# reads as F# does: indentation, `let`, pipelines, records and unions, `match`, options and
results, computation expressions, units of measure. What carries over isn't listed here; what
doesn't is, roughly in the order you'll meet it. The rest of the guide has each topic in full.

```zsharp
type Shape =
  | Circle of r: f64
  | Rect of w: f64 * h: f64

/// What an F# interface would be: a trait, and an impl per type.
trait Area<'a> =
  abstract area : 'a -> f64

impl Area<Shape> =
  let area s =
    match s with
    | Circle r -> 3.14159 * r * r
    | Rect(w, h) -> w * h

/// No exceptions: a result, and ? to pass an Error on.
let number (what: string) (s: string) : result<f64, string> =
  match String.parseInt s with
  | Some n -> Ok(float n)
  | None -> Error $"{what} isn't a number: {s}"

let parse (line: string) : result<Shape, string> =
  match String.split " " line with
  | [ "circle"; r ] ->
    let radius = number "a radius" r?
    Ok(Circle radius)
  | [ "rect"; w; h ] ->
    let width = number "a width" w?
    let height = number "a height" h?
    Ok(Rect(width, height))
  | _ -> Error $"not a shape: {line}"

let rec total (lines: list<string>) : result<f64, string> =
  match lines with
  | [] -> Ok 0.0
  | line :: rest ->
    let shape = parse line?
    let others = total rest?
    Ok(area shape + others)

/// A closure can't capture a let mutable; it can capture a ref.
let counter () =
  let count = ref 0
  fun () ->
    count.Value <- count.Value + 1
    count.Value

let main () =
  for lines in [ [ "circle 1"; "rect 2 3" ]; [ "rect 2 x" ] ] do
    match total lines with
    | Ok a -> println $"area {a:F2}"
    | Error e -> println $"error: {e}"
  let next = counter ()
  next () |> ignore
  println $"{Rect(2.0, 3.0)} {next ()}"
  0
```

```text
area 9.14
error: a height isn't a number: x
Rect (2, 3) 2
```

## Numbers and text

| F# | Z# |
|---|---|
| `int` is 32 bits | `int` is the machine word: 64 bits on a 64-bit target, 32 on a Cortex-M; `i32`, `i64`, `u8`… are fixed |
| arithmetic wraps silently | overflow panics; `[<Wrapping>]` on a function, or `Int.wrappingAdd`, for wrapping |
| `printfn "%d %s" n s`, `sprintf` | `println $"{n} {s}"`; `{x:F2}` and `{n:X8}` for formats |
| `string` is UTF-16 | `string` is UTF-8 bytes: `String.length` counts bytes, `char` is a Unicode scalar, `for c in s` decodes |
| `x.ToString()`, `%A` | `$"{x}"` through `Show`, which records, unions, lists and tuples have without a line of code |

## Data

- **No `null`:** a value that may be missing is an `option`.
- **Arrays are values:** `let b = a` and a change to `b` leave `a` alone (the copy happens only if both are still used, copy-on-write). `Buffer<'a>` is the mutable array every name shares, as a .NET array is.
- **No classes, inheritance or interfaces:** records and unions hold data, modules hold functions, and a type can have members (`member p.Norm = …`). One member per name: no overloading.
- **Equality, ordering, hashing and printing** are derived for records and unions when they're first needed, as F#'s structural equality is, and an `impl` replaces one.

## Functions

- **A closure can't capture a `let mutable`:** F# turns one into a hidden ref cell, Z# makes it an error, so make the `ref` yourself (`r.Value <- x`).
- **Four function types,** each for where the function goes:

| Type | Is | Needed for |
|---|---|---|
| `'a -> 'b` | a function or a closure | everything in one thread |
| `share<'a -> 'b>` | a function another thread may run: what it captures must be `Share` (immutable, or `Atomic`, `Mutex`, `Channel`), checked where it's made | `Parallel.both`, `Array.Parallel.map`, `Task.spawn` |
| `callback<'a -> 'b>` | a Z# function or closure that C calls back, from the thread that passed it | C's callbacks with a `void *` user data |
| `fnptr<'a -> 'b>` | a C function pointer: no captures, called in `unsafe` | C's tables of functions |

## Traits instead of SRTP and interfaces

- **`trait` and `impl`:** `trait Area<'a> = abstract area : 'a -> f64`, then `impl Area<Shape> = …` per type, as type classes are. Generic code that calls `area` works for every type with an impl; the constraint is inferred (`'a : Area`), so there's no `inline` and no `^a` member constraint.
- **`dyn Area`** holds values of different types together, where F# would cast to an interface.
- **Operators are traits:** `impl Add<Vec>` gives `+` and `List.sum`; `impl Num` the rest.
- **An impl lives with its trait or its type** (the orphan rule): a program can't write the library's `Show` for the library's `Map`; wrap the type in a one-case union of its own.

## Errors

- **No exceptions:** no `raise`, `try … with` or `failwith`. An expected failure is a `result`, passed on with `?` (or `result { }`'s `let!`); a bug (an index out of range, an overflow, `panic "…"`) stops the program.
- **`?` returns from the function it's in,** and a `for` loop's body is a function of its own: recurse or fold where a loop would stop at the first error.
- **Typed exceptions inside a module:** `Throw.throw e` performs the `Throw<E>` effect, which the function's type shows, and `Throw.catch` turns it back into a `result` ([chapter 16](16-effects.md)).

## Async, tasks and threads

| F# | Z# |
|---|---|
| `async { }` | `task { }`: cold, as `async` is; `let!`, `do!`, `return!` and `use` as in F# |
| `Async.RunSynchronously` | `Task.run`, from `main` |
| `Async.Parallel` | `Task.all`, `Task.both`; `Task.race` and `Task.timeout` cancel the loser |
| `Async.Sleep` | `Task.sleep`, on a microcontroller too |
| `Array.Parallel.map` | the same, with a `share<F>` the compiler checks: a function that captures a `ref` doesn't compile |

## Memory

- **No garbage collector:** reference counting, inserted and optimized by the compiler (Perceus), so memory is freed at the last use, and a `use` value is disposed at the end of its scope.
- **Cycles leak:** a cycle through a `ref` or a `Buffer` is never freed; the compiler warns about a type that can make one, and `weak<'a>` breaks it ([chapter 12](12-memory.md)).

## Projects and tools

| F# | Z# |
|---|---|
| `.fsproj`, `paket.dependencies` | `zs.toml`, with path and git dependencies (`version = "1.2"`) |
| files in compilation order | a file is a module named by its path, found from its uses; an import cycle is an error |
| `[<DllImport>]` | `import c "header.h"`: the header's functions, structs and constants, typed |
| Expecto | the same model in the library: `test`, `testList`, `[<Tests>]`, run by `zs test` |
| `dotnet fsi` | `zs run file.zs` |
