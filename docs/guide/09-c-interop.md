# 9. C interop

**Linking with C is direct:** a Z# program calls C functions with no wrapper code, and C code can call Z#. Records marked `[<CLayout>]` have the C struct layout and pass by value under the platform's calling convention: x86-64 System V, or AAPCS64 on aarch64.

## Calling C: extern

`extern` declares a C function with C-compatible types.

| Z# | C |
|---|---|
| `i8` `i16` `i32` (`c_int`) `int` (`i64`) | `int8_t` … `int64_t`, `int`, `long` |
| `u8` … `u64`, `usize` | unsigned types, `size_t` |
| `f32` `f64` | `float` `double` |
| `bool` | `bool` |
| `cstr` | `const char *` (a string literal, or a Z# string, passed as its bytes) |
| `cptr` | any other pointer, opaque |
| a `[<CLayout>]` record | a struct, by value |
| `unit` | `void` |
| `callback<A -> R>` | a function pointer plus a `void *` user-data argument |

```zsharp
extern printf : cstr -> ... -> c_int
extern abs : c_int -> c_int
extern strlen : cstr -> usize

let main () =
  printf "%s has %d letters; abs -5 = %d\n" "hello" (strlen "hello") (abs (i32 -5)) |> ignore
  0
```

```text
hello has 5 letters; abs -5 = 5
```

## import c

**Importing a header:** `import c "header.h"` reads a C header with clang and declares everything it can.

| From the header | Becomes |
|---|---|
| functions | externs |
| structs | `[<CLayout>]` records, named or `typedef`'d unnamed alike |
| enum values and `#define` numbers and strings | constants |
| struct literal macros (`#define RED (Color){ 230, 41, 55, 255 }`) | record constants |

**What's left out:** unions, arrays, function pointers and `static inline` functions. Using one gives an error that says why: `C function 'apply' wasn't imported: parameter 1: it uses a function pointer`.

**Linking:** `[<Link "raylib">]` links a library (`-lraylib`). `[<Link "shapes.c">]` compiles and links a C file next to the program.

```fsharp
[<Link "raylib">]
import c "raylib.h"

let main () =
  InitWindow (i32 800) (i32 450) "Z# + raylib"
  SetTargetFPS (i32 60)
  while not (WindowShouldClose ()) do
    BeginDrawing ()
    ClearBackground RAYWHITE
    DrawText "Hello from Z#" (i32 300) (i32 200) (i32 20) DARKGRAY
    EndDrawing ()
  CloseWindow ()
  0
```

The repository's `examples/raylib` is a complete demo, a ball you push around with the arrow keys.

**Finding headers:**
- **Where:** the header is found next to the importing file, then on the system include path.
- **Saved imports:** each successful import is saved in the project's `.zs-cache/cimport/`, with a copy of the header. An editor whose language server can't run clang still gets the C names, with types and the header's comments on hover.

## Structs by value

```fsharp
[<CLayout>]
type Vec2 = { x: f32; y: f32 }

extern vec_length : Vec2 -> f32     // float vec_length(Vec2 v);
```

**How structs are passed:** the compiler applies the target's rules for passing and returning structs, so a Z# record and a C struct of the same layout interoperate in both directions.
- **Registers:** small structs go in registers.
- **HFAs on aarch64:** structs of up to four floats or doubles go in float registers.
- **Large structs:** these go by memory.

`tests/cimport/abi.zs` checks every shape on both x86-64 and aarch64.

## Callbacks

A `callback<A -> R>` parameter takes any Z# function, including a closure. C receives a function pointer and a `void *` user-data pointer that carries the closure:

```fsharp
// C: void each(long n, void (*f)(void *user, long i), void *user);
extern each : int -> callback<int -> unit> -> unit

let sumSquares n =
  let total = ref 0
  each n (fun i -> total.Value <- total.Value + i * i)
  total.Value
```

## Calling Z# from C

`[<Export "name">]` makes a function callable from C under that name. `zs build --lib` builds a static library (`.a`) and a header (`.h`) declaring the exported functions and the `[<CLayout>]` types they use.

```fsharp
[<CLayout>]
type Vec2 = { x: f64; y: f64 }

[<Export "geo_add">]
let add (a: Vec2) (b: Vec2) : Vec2 = { x = a.x + b.x; y = a.y + b.y }
```

```sh
zs build geo.zs --lib -o libgeo.a      # also writes libgeo.h
cc main.c libgeo.a -lm -o main
```

**Rules:**
- An exported function can't be generic.
- Its parameters and result must be C types.
- C passes strings in as `cstr`, and `String.ofCStr` copies one into a Z# string.

## Cross-compiling

`zs build --target <triple>` builds for another machine. For example, `aarch64-linux-musl` gives a static binary for 64-bit ARM Linux.
- **How:** clang compiles the program for the target, and Zig's `zig cc` compiles the runtime and links against Zig's bundled C library, so no sysroot is needed.
- **Testing:** `./test.sh --target aarch64-linux-musl` runs the whole test suite cross-compiled, under qemu.

```sh
zs build app.zs --target aarch64-linux-musl -o app-arm64
qemu-aarch64 ./app-arm64     # or copy it to the machine
```
