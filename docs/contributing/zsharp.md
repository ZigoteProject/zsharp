# Z# for contributors

Enough of the language to read and write the repository's code. It assumes F# or another ML.
[The guide](../guide/README.md) teaches the language in full,
[chapter 17](../guide/17-from-fsharp.md) lists every difference from F#, and
[the specification](../spec/README.md) is the definition. When this page and those disagree,
they're right.

## The shape of a program

```fsharp
/// A doc comment: `zs doc` and the editor's hover show it.
type Shape =
  | Circle of radius: float
  | Rect of width: float * height: float

let area shape =
  match shape with
  | Circle r -> 3.14159 * r * r
  | Rect (w, h) -> w * h

let main () =
  println $"{area (Circle 1.0):F2}"
  0
```

- **A file is a module,** named by its path (`lib/core/Text/Hex.zs` is `Text.Hex`). Modules are
  found from their uses, not listed in order; an import cycle is an error.
- **`main` returns the exit code.**
- **Indentation is two spaces,** and significant (the offside rule), as in F#.
- **Output is `print` and `println`** with interpolated strings: `$"{n} {x:F2} {m:X8}"`. There
  is no `printfn`.

## What isn't F#

These are the mistakes someone fluent in F# makes first.

| You'd write | In Z# |
|---|---|
| `int` as 32 bits | `int` is the machine word: 64 bits on a host, 32 on a Cortex-M. `i32`, `u8`, `i64`… are fixed |
| arithmetic that wraps | overflow panics in every build. Wrapping is asked for: `Int.wrappingAdd`, or `[<Wrapping>]` on a function |
| `raise`, `try … with` | there are no exceptions. An expected failure is a `result`, passed on with `?`; a bug is a panic, which ends the process |
| `null` | there is none: `option` |
| a closure capturing a `let mutable` | an error. Capture a `ref` (`r.Value <- x`) |
| an interface, a class, inheritance | a `trait` and an `impl` per type; `dyn Trait` to hold different types together |
| `inline` and `^a` constraints | constraints are inferred from the traits used (`'a : Area`) |
| an overloaded member | one member per name |
| `async { }` | `task { }`, run with `Task.run` |
| `string` as UTF-16 | UTF-8 bytes: `String.length` counts bytes, a `char` is a Unicode scalar |
| mutating an array through an alias | arrays are values (copy-on-write). `Buffer<'a>` is the shared mutable one |
| an impl of a library trait for a library type | the orphan rule forbids it: wrap the type in a one-case union of your own |

## Memory

No garbage collector. The compiler inserts reference counts (Perceus) and removes most; a value
is freed at its last use, and a `use` value is disposed at the end of its scope.

- **Cycles leak.** A cycle through a `ref` or a `Buffer` is never freed. The compiler warns about
  a type that can form one; `weak<'a>` breaks it. `ZS_LEAKCHECK=1` reports leaks at exit, and the
  suite runs with it.
- **Allocation is visible.** `[<NoAlloc>]` on a function is checked at compile time; interrupt
  handlers have it implicitly.

## Effects

A function's type says what it performs: `list<Shape> -> float / Log`. An effect is declared
with its operations, performed by calling one, and handled up the stack:

```fsharp
effect Log =
  abstract note : string -> unit

let total shapes =
  Log.note $"{List.length shapes} shapes"
  shapes |> List.sumBy area

let main () =
  let t =
    handle total [ Circle 1.0 ] with
    | Log.note msg, k ->
      println $"log: {msg}"
      k ()            // resume `total` where it performed
  0
```

The compiler uses this throughout: a pass reports diagnostics through the `Report` effect and
goes on, and the boundary of a job collects them (`src/Diag/Report.zs`). `Throw<E>` is a typed
exception, turned back into a `result` by `Throw.catch`.

## Threads

What crosses threads must be `Share`: immutable, or made for threads (`Atomic`, `Mutex`,
`Channel`). A function another thread runs has the type `share<'a -> 'b>`, checked where it's
made. Safe code has no data races; a change that lets one through is a soundness bug.

## C and `unsafe`

- `extern` declares a C function; `import c "header.h"` reads a header's functions, structs and
  constants.
- `ptr<'a>`, `fnptr<F>`, `Ptr.read` and `write`, spans over C memory and the runtime's hooks under
  `Native` are compile errors outside an `unsafe` expression. `[<Unsafe>]` on a function makes it
  callable only from `unsafe`.
- Everything outside `unsafe` and `extern` has no undefined behavior
  ([DESIGN §5.3](../../DESIGN.md#53-what-code-without-unsafe-guarantees)). Keep `unsafe` blocks
  small, inside the library, behind a safe function that checks what it's given.

## The library's layers

- **Prelude** (`lib/prelude.zs`): names every program has unqualified: `option`, `result`,
  `print`, the operator traits.
- **Core** (`lib/core/`): needs no operating system, so every target has it. Nothing here may use
  Std.
- **Std** (`lib/std/`): files, processes, sockets, threads. On a microcontroller, using it is a
  compile error.

The namespaces (`Collections`, `Text`, `IO`, …) are open everywhere: `List.map` is
`Collections.List.map`. [The reference](../reference/README.md) has every module.

## Checking what you wrote

```sh
./dev bin/zs check file.zs       # type-check only: fast
./dev bin/zs run file.zs         # build and run
./dev bin/zs fmt file.zs         # format in place
```

`zs mcp` exposes `check`, `type_at`, `definition`, `build` and `run` to an agent; `zs lsp` is the
editor's server. When unsure whether something is valid Z#, check it with the compiler rather
than reasoning from F#.
