# Z# — design draft v0

An ML-family language with F# syntax and ergonomics, compiled ahead of time to
native code through LLVM, with no runtime VM, no tracing GC, and direct C interop.

**Pitch:** F# syntax, OCaml semantics, Zig-style output: one native binary that
links straight against C.

## 1. Goals / non-goals

| Goals | Non-goals (v1) |
|---|---|
| F# light syntax (indentation, `let`, `\|>`, `match`) | .NET interop / CLR |
| Hindley–Milner inference, monomorphized generics | Higher-kinded types, functors |
| Algebraic data types + exhaustive pattern matching | OOP classes, inheritance |
| Native codegen via LLVM, C-competitive perf | Tracing GC, JIT |
| Call C / be called from C, C struct layout | Async / effect system |
| Deterministic memory (RC, no pauses) | Computation expressions, macros, comptime |

"Simple" here means you can explain the language in about 20 pages. Any feature
that needs a runtime gets cut.

## 2. Language tour

```fsharp
module Geometry

type Point = { x: f64; y: f64 }          // record: value type, C-compatible layout

type Shape =                             // union: tagged, auto-boxed if recursive
  | Circle of center: Point * radius: f64
  | Rect   of Point * Point

let area shape =                         // inferred: Shape -> f64
  match shape with
  | Circle (_, r) -> 3.14159 * r * r
  | Rect (a, b)   -> abs ((b.x - a.x) * (b.y - a.y))

let total shapes = shapes |> List.map area |> List.sum

type Tree<'a> =                          // recursive -> heap nodes, refcounted
  | Leaf
  | Node of Tree<'a> * 'a * Tree<'a>

let rec insert x t =
  match t with
  | Leaf -> Node (Leaf, x, Leaf)
  | Node (l, v, r) when x < v -> Node (insert x l, v, r)   // reuses node in place if unique
  | Node (l, v, r)            -> Node (l, v, insert x r)
```

### Core features
- **Bindings:** `let` (immutable), `let mutable` with `<-`, `let rec`, plus shadowing.
- **Types:** `int` (= i64), `i8..i64`, `u8..u64`, `f32`, `f64`, `bool`, `char` (u32 scalar), `string` (UTF-8, RC), `unit`.
- **Data:** tuples, records (with `{ p with x = 1.0 }`), unions, `option<'a>`, `result<'a,'e>`, `array<'a>`, `list<'a>`.
- **Functions:** curried by default, closures, `|>`, `>>`, partial application. The compiler uncurries known call sites, so curried code costs nothing at runtime.
- **Pattern matching:** nested, guards, `as`, or-patterns, plus an exhaustiveness and redundancy checker. Non-exhaustive matches are an error, not a warning.
- **Errors:** `result` with a postfix `?` that propagates (Rust-style). This stands in for F#'s `result { }` builder. `panic` is for bugs only.
- **Strings:** `$"x = {p.x}"` interpolation.
- **Modules:** one file is one module, with `open`, `private`, and nested `module`.

### Traits (replacing interfaces and SRTP)
```fsharp
trait Show<'a> =
  abstract show : 'a -> string

impl Show<Point> =
  let show p = $"({p.x}, {p.y})"

let print<'a when 'a : Show> (x: 'a) = Console.println (show x)
```
Traits are resolved statically and monomorphized, so there are no vtables
unless you ask for `dyn Show`. Operators (`+`, `<`, `=`) are traits (`Num`,
`Ord`, `Eq`) with built-in impls for primitives. `Eq`, `Ord`, `Hash` and `Show`
can be derived with `[<Derive(Eq, Show)>]`.

## 3. Memory model: Perceus reference counting

This is the most important decision. It is how Koka and Lean 4 get functional
code to run at native speed:

- **Value types:** primitives, tuples, records, and non-recursive unions live inline (stack or registers) and are copied.
- **Heap types:** recursive unions, closures, `string`, `array`, and `list` are refcounted.
- **The compiler inserts and elides RC ops** using ownership and borrow inference. Most `inc`/`dec` pairs disappear.
- **Reuse:** when a pattern match consumes a unique cell and builds one of the same size, it updates the cell in place. As a result, `insert`, `List.map`, and `arr.[i] <- x` on uniquely owned data do not allocate. This is "functional but in place."
- **Cycles:** immutable data can't form cycles. Only `ref`/mutable fields can, and that is documented as the user's job (use `weak`), the same as Swift.
- **Escape hatch:** an `Arena` for bulk allocation in hot paths (Zig flavor), plus raw `ptr<'a>` in `unsafe`.

The result is deterministic destruction, no GC pauses, a runtime that is just
`malloc`/`free` plus about 200 lines of C, and it's trivially embeddable in C programs.

## 4. C interop

```fsharp
// declare
extern puts   : cstr -> c_int
extern malloc : usize -> ptr<u8>
extern printf : cstr -> ... -> c_int             // variadic

// C-layout struct (records already are; this pins it and forbids reordering)
[<CLayout>]
type Vec2 = { x: f32; y: f32 }

// export to C: no currying, C calling convention, stable symbol
[<Export "zs_area">]
let area (s: Shape) : f64 = ...

// v2: import a header directly (libclang), like Zig's @cImport
import c "raylib.h"
```

- **FFI types:** `c_int`, `c_long`, `usize`, `cstr`, `ptr<'a>`, `fnptr<...>`.
- **Moving data across the boundary:** C-layout values pass by value. RC objects cross as opaque handles, using explicit `Rc.retain`/`Rc.release`.
- **Raw pointers:** `Ptr.read`, `Ptr.write`, and pointer arithmetic need an `unsafe` expression.
- **Linking:** `zs build` emits a `.o`/`.a`/`.so` plus a generated `.h` for every `[<Export>]` function. Use `--link -lfoo` to pull libraries in.

## 5. Compiler architecture

```
 .zs ─► Lexer (offside rule) ─► Parser ─► AST
        ─► Resolve (names, modules)
        ─► Typecheck (HM + trait constraints, exhaustiveness)
        ─► Core IR (typed, ANF)
        ─► Monomorphize ─► Match compile (decision trees)
        ─► Closure convert + uncurry
        ─► Perceus (RC insertion, borrow inference, reuse)
        ─► LLVM IR ─► clang/llc -O2 ─► native object ─► link
```

- **Bootstrap language: F#.** Unions and `match` are ideal for compilers, `dotnet` is already installed here, and you'd be dogfooding the ergonomics Z# copies. Self-hosting is optional and late.
- **Backend: emit textual LLVM IR (`.ll`) and run `clang` on it** (already installed). This needs no LLVM bindings or build setup, and it's trivial to debug because you just read the `.ll`. Switching to the LLVM C API is a mechanical change, worth making only if compile speed becomes a problem. `zig cc` works as a drop-in for cross-compiling.
- **Runtime:** `rt.c`, containing RC helpers, panic, and string/array primitives, compiled once and linked statically.
- **Debug info:** emit DWARF from day one (`!DILocation`) so gdb and lldb work on source lines.
- **CLI:** `zs build`, `zs run`, `zs test`. Plain `zs build main.zs` follows imports, so there's no project file in v1.

## 6. Roadmap

Each phase ends with a native binary that runs.

| Phase | Scope | Exit test |
|---|---|---|
| 0 | `int`, `let`, functions, `if`, `extern`, LLVM IR emit + clang | `fib 30` prints via C `printf` |
| 1 | HM inference, tuples, records, unions, `match` + exhaustiveness | Expression evaluator in Z# |
| 2 | Closures, generics (mono), `string`/`list`/`array`, Perceus RC | Red-black tree with no leaks under valgrind |
| 3 | Traits, modules, `?`, stdlib core, `[<Export>]` + `.h` gen | C program calls a Z# library |
| 4 | `import c` via libclang, DWARF polish, `zs test` | Raylib demo window |
| 5 | (optional) Self-host the compiler in Z# | — |

## 7. Open decisions (defaults chosen)

1. **`int` width:** 64-bit (F# uses 32). It's cheap on modern CPUs and avoids overflow surprises.
2. **Integer overflow:** wraps in release builds and traps in debug builds (Zig's approach).
3. **Syntax:** indentation only, no `begin/end` or verbose-syntax mode.
4. **Memory:** Perceus RC rather than a GC. Revisit only if cyclic mutable graphs turn out to dominate real code.
