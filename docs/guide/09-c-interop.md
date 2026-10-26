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
| `ptr<T>` | `T *`, for T one of these C types ([Pointers and unsafe](#pointers-and-unsafe)) |
| `fnptr<A -> B -> R>` | `R (*)(A, B)`, a C function pointer (`fnptr<unit -> R>` takes nothing) |
| a `[<CLayout>]` record | a struct, by value |
| `unit` | `void` |
| `callback<A -> R>` | a function pointer plus a `void *` user-data argument |
| any other Z# object (a union, a list, a closure, a `dyn` value) | `zs_handle`, an opaque handle ([Handles](#handles)) |

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
| unions | `[<CLayout>]` unions ([C unions](#c-unions)), a member a case named through the union: `Data.u32` |
| a struct or union without a name in a struct's field (`union { … } body;`) | a type named after both: `Msg_body` |
| enum values and `#define` numbers and strings | constants |
| struct literal macros (`#define RED (Color){ 230, 41, 55, 255 }`) | record constants |
| function pointers (`double (*area)(double, double)`, typedef'd or not) | `fnptr` types |
| array fields (`uint8_t data[16]`, `int m[3][4]`) | `fixed<u8, 16>`, `fixed<fixed<i32, 4>, 3>` ([fixed-size arrays](05-collections.md#fixed-size-arrays)) |
| array parameters (`const int xs[4]`) | pointers to the first element, as in C |

**What's left out:** arrays without a length, structs with bit fields (where a compiler puts them is its own choice), members without a name (C11's anonymous unions), and `static inline` functions. Using one gives an error that says why: `C name 'Msg' wasn't imported: a field: it uses an array without a length`.

**Spans:** an `extern` taking a `span<'a>` of a C type gets two arguments, a pointer to the first element and the length (`int count(const uint8_t *p, size_t n)`); the span's owner stays alive for the call. A span can't come from C, which has no owner to give it; `unsafe` code makes one over C memory with `Span.ofPtr p n`, whose lifetime is the programmer's to keep.

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
- **Out of registers:** on x86-64, a struct whose parts don't all fit in the registers left goes on the stack whole, and the arguments after it still take the registers left, as C does.

`tests/cimport/abi.zs` checks every shape, unions included, on x86-64, aarch64, the Cortex-M chips and WebAssembly.

**Checking a layout:** `sizeof<T>`, `alignof<T>` and `offsetof<T> "field"` are `int` constants for the target the build is for, a `[<CLayout>]` type's as C lays it out. A top-level `assert` on constants is checked when compiling, so a record that drifts from its C struct stops the build instead of corrupting memory at a call:

```zsharp
[<CLayout>]
type Packet = { kind: u8; length: u32; data: fixed<u8, 6>; flags: u16 }

assert (sizeof<Packet> = 16 && offsetof<Packet> "length" = 4)

let main () =
  println $"{sizeof<Packet>} {alignof<Packet>} {offsetof<Packet> "flags"}"
  0
```

```text
16 4 14
```

When a field changes, the build stops at the `assert` with what it read: `assert fails when compiling: sizeof<Packet> = 16 is false (sizeof<Packet> is 20)`. An `assert` whose condition isn't a constant runs at startup instead, and `zs build --lib` puts a `_Static_assert` of each struct's size in the header it writes, so the C side checks the same fact.

## C unions

```zsharp
// C: union { uint32_t u32; uint64_t u64; void *ptr; }
[<CLayout>]
type Data =
  | U32 of u32
  | U64 of u64
  | Ptr of cptr

let main () =
  let d = U64(u64 4294967303)
  // the first four bytes, as C reads them
  println $"{unsafe d.U32} {unsafe d.U64} {sizeof<Data>}"
  0
```

```text
7 4294967303 8
```

**A `[<CLayout>]` union** is C's: it has no tag, and each case is a view of the same bytes, so its size is its largest case's and its alignment the strictest.
- **Building one:** by a case, which writes that case's field; the bytes after it are zero.
- **Reading one:** `v.Case` inside `unsafe`. The compiler can't know which case is there, so the code that knows is marked. Without a tag there's nothing to match on, compare, hash or print, so a C union can't be matched, and it has no `=`, ordering, hashing or `Show`.
- **Cases:** each has one field, of a type that crosses to C: a number, a pointer, a `[<CLayout>]` record or union, a `fixed` array.
- **Crossing to C:** by value, as C passes a struct of its size and class, and in a record's field, as C's are in structs. `zs build --lib` declares it in the header it writes.

**From a header:** a member of an imported union is a case named through it, as C names it through a value: `union epoll_data { int fd; … }` is built with `epoll_data.fd 3` and read with `unsafe ev.data.fd`. Two unions in a header can have members of the same name, as in C.

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

## Pointers and unsafe

**Raw pointers:** a `ptr<T>` points at C data: a number, a `bool`, a `[<CLayout>]` record or union, or another pointer.
- **Unsafe on purpose:** reading and writing through a pointer, pointer arithmetic, casts and freeing compile only inside `unsafe`, which is an expression or an indented block. The compiler can't check that the memory is there, so the code that trusts it is marked.
- **The functions:** `Ptr.read p`, `Ptr.write p x`, `Ptr.add p n` (n elements on), `Ptr.alloc n` and `Ptr.free p` (C's `calloc` and `free`), and `Ptr.cast`. `Ptr.null ()`, `Ptr.isNull p` and `Ptr.toCPtr p` (to pass to a `cptr` parameter) are safe.

```zsharp
let main () =
  let n = 4
  let p: ptr<i32> = unsafe Ptr.alloc n

  unsafe
    for i in 0 .. n - 1 do
      Ptr.write (Ptr.add p i) (i32 (i * i))

    let mutable total = 0

    for i in 0 .. n - 1 do
      total <- total + int (Ptr.read (Ptr.add p i))

    println $"total {total}"
    Ptr.free p

  0
```

```text
total 14
```

**C function pointers:** a `fnptr<A -> R>` is called like a function, inside `unsafe`, with C's calling convention. A C library's table of functions comes across from `import c` with its fields as `fnptr`s:

```fsharp
// C: typedef struct { double (*area)(double w, double h); void (*hello)(void); } ShapeOps;
//    ShapeOps shape_ops(void);
[<Link "ops.c">]
import c "ops.h"

let main () =
  let ops = shape_ops ()
  unsafe
    println $"area {ops.area 2.0 3.5}"
    ops.hello ()
  0
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

**Shared libraries:** an output ending in `.so` is a shared library instead. The archive's code is position-independent too, so a C shared library can include it whole:

```sh
zs build geo.zs --lib -o libgeo.so                     # a C program links libgeo.so
cc -shared host.c -Wl,--whole-archive libgeo.a -Wl,--no-whole-archive -lm -o libhost.so
```

**Rules:**
- An exported function can't be generic.
- Its parameters and result must be C types, or Z# objects as handles (below).
- C passes strings in as `cstr`, and `String.ofCStr` copies one into a Z# string.

### Handles

**A Z# object in C:** an exported function can take and return Z# objects other than strings: a union such as a tree, a list, a closure, a `dyn` value. C holds each as a `zs_handle`, declared in the header with two functions:
- **`zs_release(h)`** gives up a reference; the object goes with the last one. A handle a function returns is the caller's, to release when done.
- **`zs_retain(h)`** adds one, to keep a handle after passing it on.
- **Passing one back:** a handle passed to a Z# function is only lent for the call, so C still releases it later. The same holds for an `extern` that takes a Z# object: C borrows the handle for the call, and retains it to keep it.

```fsharp
type Tree =
  | Leaf
  | Node of Tree * int * Tree

[<Export "tree_insert">]
let add (t: Tree) (x: int) : Tree = insert x t      // zs_handle tree_insert(zs_handle p0, intptr_t p1);

[<Export "tree_adder">]
let adder (t: Tree) : int -> int = fun x -> x + total t
```

```c
zs_handle t = tree_empty();
zs_handle bigger = tree_insert(t, 5);
zs_release(t);       // the old tree, if nothing else holds it
…
zs_release(bigger);
```

`tests/chandle` builds a tree and keeps a closure from C, and valgrind checks that everything is freed.

**Panics:** a panic in the library ends the whole program, C side included. So report the errors a caller can handle as a result the C side can check, and keep panics for bugs. The header declares a hook that runs before the program stops, to log or save state:

```c
static void on_panic(const char *message) {
    fprintf(log, "geo: %s\n", message);   // when it returns, the program stops
}

int main(void) {
    zs_set_panic_hook(on_panic);
    …
}
```

## Cross-compiling

`zs build --target <triple>` builds for another machine. For example, `aarch64-linux-musl` gives a static binary for 64-bit ARM Linux.
- **How:** clang compiles the program for the target, and Zig's `zig cc` compiles the runtime and links against Zig's bundled C library, so no sysroot is needed.
- **Testing:** `./test.sh --target aarch64-linux-musl` runs the whole test suite cross-compiled, under qemu.

```sh
zs build app.zs --target aarch64-linux-musl -o app-arm64
qemu-aarch64 ./app-arm64     # or copy it to the machine
```

Everything in this chapter works on every target: Linux, macOS and Windows on x86-64 and arm64 with
their own conventions, a microcontroller with AAPCS, and WebAssembly. A Z# library on a chip is an
archive a C firmware links ([C on a chip](11-microcontrollers.md#c-on-a-chip)).
