# Z# — design v1

An ML-family language with F# syntax and ergonomics. It compiles ahead of time to
native code through LLVM. It has no VM, no tracing GC, and direct C interop.

**Pitch:** F# syntax, OCaml semantics, Zig-style output: one native binary that
links straight against C.

Phased plan and status: [ROADMAP.md](ROADMAP.md).

## 1. Goals / non-goals

| Goals | Non-goals (v1) |
|---|---|
| F# light syntax (indentation, `let`, `\|>`, `match`) | .NET interop / CLR |
| Hindley–Milner inference, monomorphized generics | Higher-kinded types, functors |
| Algebraic data types + exhaustive pattern matching | OOP classes, inheritance |
| Native codegen via LLVM, C-competitive performance | Tracing GC, JIT |
| Call C / be called from C, C struct layout | Effect handlers (designed in §6.1, built in v3) |
| Deterministic memory (RC), memory-safe by default | Macros, general compile-time evaluation (`derive` is the one exception, §3.1) |
| Computation expressions; `Task` as a library | Built-in `async`/`await` keywords |
| Data parallelism and SIMD without data races | Green threads, a GIL |

"Simple" means the language fits in about 20 pages and a feature that needs a
runtime is out. The exception is a small C runtime (reference counting, task
scheduler, thread pool) that is linked only when the program uses it.

## 2. Language tour

```fsharp
module Geometry

type Point = { x: f64; y: f64 }          // record: value type, C-compatible layout

type Shape =                             // union: tagged
  | Circle of center: Point * radius: f64
  | Rect   of Point * Point

let area shape =                         // inferred: Shape -> f64
  match shape with
  | Circle (_, r) -> 3.14159 * r * r
  | Rect (a, b)   -> abs ((b.x - a.x) * (b.y - a.y))

let total shapes = shapes |> List.map area |> List.sum

type Tree<'a> =
  | Leaf
  | Node of Tree<'a> * 'a * Tree<'a>

let rec insert x t =
  match t with
  | Leaf -> Node (Leaf, x, Leaf)
  | Node (l, v, r) when x < v -> Node (insert x l, v, r)   // reuses the node in place if unique
  | Node (l, v, r)            -> Node (l, v, insert x r)

let sumTo n =                            // imperative code is fine; mutation stays local
  let mutable acc = 0
  for i in 1 .. n do
    acc <- acc + i
  acc
```

### Core features
- **Bindings:** `let`, `let mutable` with `<-`, `let rec`, plus shadowing. A `let mutable` can't be captured by a closure (an F# rule that §5 relies on).
- **Types:**
  - Integers: `int` (= i64), `i8..i64`, `u8..u64`, `usize`.
  - Floats: `f32`, `f64`.
  - Others: `bool`, `char` (u32 scalar), `string` (UTF-8, RC), `unit`.
  - SIMD vectors: `f32x4`, `i32x8`, … (§8).
- **Data:**
  - Tuples and records (`{ p with x = 1.0 }`) and unions.
  - Library types: `option<'a>`, `result<'a,'e>`, `list<'a>`, `array<'a>`, `ref<'a>`.
- **Functions:**
  - Curried by default, with closures (`fun x -> ...`), `|>`, `>>` and partial application.
  - Known call sites get uncurried, so currying costs nothing at runtime.
  - Self tail calls become loops, guaranteed.
- **Loops:** `for i in a .. b do`, `for x in xs do`, `while c do`.
- **Pattern matching:**
  - Supports nesting, guards, `as`, and or-patterns that bind variables.
  - A non-exhaustive match is an **error** that names a missing case. A case that can never match is also an error.
- **Errors:** `result` with a postfix `?` that propagates the error, or a `result { }` builder (§4).
- **Panics:** a bounds error, divide by zero, failed `assert` or explicit `panic` prints a message and backtrace, then **aborts**.
  - Panics can't be caught and there is no unwinding. That means no landing pads and no unwinding through C frames.
  - Recoverable errors use `result`; typed exceptions arrive with effects (§6.1).
- **Sequences:** `[1; 2; 3]` is an immutable cons list (pattern `x :: rest`), as in F#, and `[| 1; 2 |]` is an array. Perceus reuse makes `List.map` and `filter` work in place when the list is unique.
- **Strings:** UTF-8. `s.Length` is the byte length, `for c in s` iterates over `char` scalars, and slicing by byte range is checked to fall on character boundaries.
- **Strings:** `$"x = {p.x}"` interpolation.
- **Modules:** one file is one module, with `open`, `private`, and nested `module`.

### 2.1 F# features kept

```fsharp
[<Measure>] type m
[<Measure>] type s

type Vec = { x: f64<m>; y: f64<m> }
  with
    member v.Length = sqrt (v.x * v.x + v.y * v.y)       // f64<m>
    static member Zero = { x = 0.0<m>; y = 0.0<m> }

let speed (d: f64<m>) (t: f64<s>) = d / t               // f64<m/s>

let (|Even|Odd|) n = if n % 2 = 0 then Even else Odd    // total active pattern
let (|Int|_|) (s: string) = Int.tryParse s              // partial active pattern

let describe n =
  match n with
  | Even -> "even"
  | Odd  -> "odd"                                       // exhaustive: {Even, Odd} is complete

let same = { x = 1.0<m>; y = 2.0<m> } = { x = 1.0<m>; y = 2.0<m> }   // true, structural
```

- **Members** (`member`, `static member`) on records and unions:
  - Calls use dot syntax: `v.Length`, `Vec.Zero`, `s.Split ','`.
  - There is no inheritance and no overloading (one member per name). That keeps inference predictable.
  - **Dot resolution is type-directed, as in F#:** `x.M` requires `x`'s type to be known by that point, reading left to right. Otherwise the error is "annotate x". Pipelines (`xs |> List.map (fun p -> p.x)`) work because `|>` checks its left side first.
- **Automatic structural equality and comparison:**
  - `=`, `<>`, `compare` and `hash` work on every record, union and tuple whose fields support them, as in F#.
  - Functions, `ref` and `ptr` don't support them, so a type containing them gets a compile error at the use site.
  - Opt out with `[<NoEquality>]`/`[<NoComparison>]`; customise with `impl Eq<T>`.
- **Units of measure:** checked at compile time and erased at runtime, so they cost nothing.
  - Measure exponents are unified as an abelian group (Kennedy's algorithm), so `m/s * s` simplifies to `m`.
  - They apply to numeric types and to SIMD vector element types.
- **Active patterns:**
  - **Total** ones (`(|A|B|)`) define a closed set of cases and take part in exhaustiveness like constructors.
  - **Partial** ones (`(|P|_|)`, returning `option`) never count toward coverage, the same as a guarded case.
  - Parameterised ones (`(|DivBy|_|) 3`) are supported.

### 2.2 Default fields, named and optional arguments

There are two mechanisms. Curried `let` functions get neither, so their types stay plain.

**Default values for record fields.** A literal may omit any field that has a default:

```fsharp
type Config =
  { host: string = "localhost"
    port: int = 8080
    timeout: int = port / 100          // may refer to earlier fields
    tls: option<TlsConfig> = None }    // option fields need an explicit default

let connect (cfg: Config) = ...
connect { port = 9000 }                // the "options record" idiom replaces named arguments on functions
```

**Named, optional and default arguments on members** (tupled, as in F#):

```fsharp
type Http =
  static member Get(url: string, ?timeout: int = 30, ?headers: list<string * string>) = ...

Http.Get("https://x", timeout = 5)     // inside Get: timeout is int, headers is option<_>
```

**Named fields on union cases:** construction and patterns can use the field names from the declaration. Union fields have no defaults.

```fsharp
type Shape = Circle of radius: f64 | Rect of w: f64 * h: f64
let c = Circle(radius = 2.0)
match s with
| Rect(h = h) -> h                     // unnamed fields are wildcards
| Circle _ -> 0.0
```

**Rules:**
- **When defaults run:** a default is any expression. It is evaluated at the call or construction site each time, after the values given explicitly. It may refer to earlier fields or parameters.
  - Defaults expand at the call site, so they cost nothing at runtime: there is no callee-side `option` check, and no allocation.
  - Values are immutable, so Python's shared-mutable-default trap can't happen.
- **Optional parameters without a default:** an optional parameter with no default (`?headers`) is an `option<_>` in the body. An omitted argument is the static `None`.
- **Named arguments:** in a member call, `name = value` is a named argument when `name` is one of that member's parameters. Everywhere else, `x = 1` is still equality.
  - Positional arguments come first.
  - Each parameter may be given at most once.
- **Record literals:**
  - **Picking the type:** the literal's fields must identify one record type, using the expected type when it is known. When defaults make the fields ambiguous, an annotation is required, as in F#.
  - **Required fields:** a field without a default must always be given, and a missing one is an error naming that field.
  - **`option` fields:** these get a default only from an explicit `= None`.
- **`derive` (§3.1):** `fromJson` uses a field's default when the key is missing.
- **C export:** exported members have all parameters required. C has no defaults.
- **Library versioning:** a changed default reaches users when they recompile (the same as C#/Kotlin, and consistent with shipping Core IR).

## 3. Traits (replacing interfaces and SRTP)

```fsharp
trait Show<'a> =
  abstract show : 'a -> string

impl Show<Point> =
  let show p = $"({p.x}, {p.y})"

let print<'a when 'a : Show> (x: 'a) = Console.println (show x)
```

- **Dispatch:** resolved statically and monomorphized, with no vtables unless you write `dyn Show`.
- **Operators:** `+`, `<` and `=` are traits (`Num`, `Ord`, `Eq`) with built-in impls for primitives and SIMD vectors.
- **Built in:** `Eq`, `Ord` and `Hash` are provided structurally and automatically (§2.1). `Show` is automatic too, used for `%A`-style printing, and `impl` overrides any of them. All four are ordinary derives (§3.1) in the prelude, applied automatically.
- **Auto traits:** `Share` (§7) is derived structurally by the compiler, and users can't implement it by hand.

### 3.1 Derive

Rust gets serializers, CLI parsers and builders from proc macros, Zig gets them
from `comptime`, and F# gets them from reflection. Z# has none of these, so it
gets them from **derive**: a library definition that implements a trait for any
record or union by walking its fields. The compiler uses the same mechanism for
`Eq`, `Ord`, `Hash` and `Show`.

```fsharp
trait Json<'a> =
  abstract toJson   : 'a -> JsonValue
  abstract fromJson : JsonValue -> result<'a, string>

derive Json =                                   // implements Json<'self> for a record or union
  let toJson (x: 'self) =
    match Shape.of x with
    | Record r ->
        let mutable fields = []
        for f in r.fields do                    // unrolled: one copy of the body per field
          fields <- (f.name, toJson f.value) :: fields
        JsonValue.Object (List.rev fields)
    | Union c ->
        let mutable args = []
        for f in c.fields do
          args <- toJson f.value :: args
        JsonValue.Object [ ("case", JsonValue.String c.name); ("fields", JsonValue.Array (List.rev args)) ]

  let fromJson (j: JsonValue) : result<'self, string> =
    match Shape.kind<'self> with
    | RecordKind -> Shape.build<'self> (fun f -> Json.field f.name j |> Result.bind fromJson)
    | UnionKind  ->
        result {
          let! name = Json.field "case" j |> Result.bind Json.string
          let! args = Json.field "fields" j |> Result.bind Json.array
          let! built = Shape.buildCase<'self> name (fun f -> Json.at f.index args |> Result.bind fromJson)
                       |> Option.toResult $"unknown case {name}"
          return! built
        }

[<Derive(Json)>]
type User = { name: string; age: int; email: option<string> }

[<Derive(Json)>]
type Tree<'a> = Leaf | Node of Tree<'a> * 'a * Tree<'a>     // impl requires 'a : Json

let s = toJson { name = "ada"; age = 36; email = None }
```

- **What a derive sees:** `Shape.of x` is `Record r` or `Union c`. `r.fields` lists every field, and `c.name`/`c.fields` describe the active case. Each field has `name`, `index`, and a `value` of that field's own type. Unnamed union fields are named `item1`, `item2`, … as in F#.
- **Comparing two values:** `match Shape.pair a b with Same c -> … | Different (i, j) -> …` gives a derive both values at once.
  - **`Same`:** both have the same case (always, for records). Each field has `f.left` and `f.right`.
  - **`Different`:** carries the two case indexes.
  - **Case facts:** `c.index` and `c.count` give the case's position and its number of fields.
  - **Prelude:** the derives for `Eq`, `Ord`, `Hash` and `Show` are written with these.
- **Per-field expansion:** a `for f in ….fields do` loop is unrolled at compile time, and its body is typechecked once per field, at that field's type. So `toJson f.value` resolves `Json` separately for `string`, `int` and `option<string>`. This is Zig's `inline for` over `@typeInfo`, but it is the only construct that works this way. A lambda passed to `Shape.build<'self>` (records) or `Shape.buildCase<'self> name` (unions) expands the same way. It is called once per field and returns `result<field, 'e>`. `build` returns `result<'self, 'e>` and stops at the first error. `buildCase` returns `None` for an unknown case name. `Shape.kind<'self>` tells a derive whether it is building a record or a union.
- **Checking:** a derive body is checked for names and syntax where it is defined. It is fully typechecked at each `[<Derive>]` type. Errors name the derive, the type and the field: `Derive(Json) on User: field created: Time has no Json impl`. This is the tradeoff C++ templates and Zig comptime make, confined to derive bodies.
- **Generics and recursion:** deriving for `Tree<'a>` adds `'a : Json` to the impl, as Rust's `#[derive]` does. Recursive types work because impls are monomorphized.
- **Cost:** none at runtime. The expanded impl is ordinary code that is inlined and optimized like a hand-written one. No reflection or type metadata ends up in the binary.
- **Not included:**
  - Derives can't add members, types or other declarations, and they can't see function bodies.
  - There are no field attributes yet (for example, renaming a JSON key). Add `f.attr<'t>`, returning an `option` of a typed attribute value, when the first real library needs it.
  - Declarations generated from a schema (like F# type providers) are a separate, later feature that generalizes `import c` (§10).

## 4. Computation expressions

These are F#'s builder syntax, kept general so that async, `result`, `option`,
parsers and generators are all libraries rather than compiler features.

```fsharp
let loadUser id =
  task {
    let! row  = Db.query $"select * from users where id = {id}"
    let! avatar = Http.get row.avatarUrl
    use file = File.create $"{id}.png"      // closed on completion, error *or* cancellation
    do! file.write avatar
    return row.name
  }
```

A builder is a **module**, not an object, so it resolves statically and can be
inlined. The forms rewrite as follows:

| Form | Rewrites to |
|---|---|
| `let! x = m in rest` | `B.bind m (fun x -> rest)` |
| `do! m` | `B.bind m (fun () -> ...)` |
| `return e` / `return! m` | `B.ret e` / `m` |
| `use x = e` | `B.using e (fun x -> ...)` |
| `for x in xs do` | `B.forEach xs (fun x -> ...)` |
| `if c then m` (no else) | `B.zero` on the missing branch |

The compiler checks the builder's shape with a `Builder` trait, so a missing
`bind` is a type error at the use site.

## 5. Memory model and memory safety

### Perceus reference counting (Koka, Lean 4)
- **Value types:** primitives, tuples, records, SIMD vectors, and *small non-recursive* unions live inline (registers or stack) and are copied.
- **Heap types:** recursive unions, closures, `string`, `array`, `list` and `ref` are refcounted.
- **The compiler inserts and elides RC operations.** Borrow inference removes most `inc`/`dec` pairs.
- **Reuse:** when a match consumes a unique cell and builds one of the same size, it overwrites the cell. This makes code "functional but in place": `insert`, `List.map`, `arr.[i] <- x` and CPS continuations don't allocate when their input is unique.
- **Cycles:** immutable data can't form cycles. Only `ref` and mutable fields can, which is the user's job, the same as in Swift (use `weak`).
- **Escape hatches:** `Arena.with (fun a -> ...)` for bulk allocation, and `ptr<'a>` inside `unsafe`.

### What code without `unsafe` guarantees

| Guarantee | Mechanism |
|---|---|
| No use-after-free or double free | RC; values die when their last reference does |
| No null | `option<'a>`; `option<ref>` compiles to a nullable pointer (niche) |
| No uninitialised reads | Every binding has a value; arrays are created with `init` or `create` |
| No out-of-bounds access | Bounds-checked indexing, with checks hoisted or removed in loops (§9) |
| No data races | `let mutable` can't be captured, plus the `Share` trait (§7) |
| Deterministic cleanup | RC plus `use`; this also runs when a task is cancelled (§6) |
| Arithmetic | Integer overflow traps in debug and wraps in release. Divide by zero always traps. |

**Not guaranteed (and still memory-safe):** leaks through mutable `ref` cycles.

**Unsafe on purpose:** `unsafe` expressions, raw `ptr<'a>`, and every `extern` call.

## 6. Concurrency: `Task`

There is **one type, `Task<'a>`, and it is cold.** A task is a value that
describes work. Defining it does nothing, and running it twice runs the work
twice. `Task.start` gives a hot handle when you want the work to begin now. F#
needed both Async and Task only because of .NET compatibility, which Z# doesn't
have.

```fsharp
let both a b =
  task {
    let! (x, y) = Task.both (Http.get a) (Http.get b)   // concurrent
    return x.length + y.length
  }

let main () = Task.run (both "https://a" "https://b") |> printfn "%d"
```

- **Implementation:** a plain library on top of §4. Each `let!` becomes a continuation closure.
  - Continuations are almost always unique, so Perceus reuses them in place. A loop that waits repeatedly settles into steady memory use, not one allocation per await.
  - Bind chains use LLVM `musttail` (guaranteed tail calls on x86-64 and aarch64), so the stack doesn't grow.
  - Later, the compiler may lower `task { }` to stackless state machines, as F# 6 did with resumable code, with no change to the source (ROADMAP phase 9).
- **Structured concurrency:**
  - Child tasks can't outlive the scope that started them (`Task.both`, `Task.all`, `Task.race`, `Task.scope`).
  - Cancellation flows down implicitly.
  - Cancelling drops the continuation, so RC releases everything it captured and `use` resources close immediately.
- **Event loop:** about 300 lines of C over epoll/kqueue (io_uring later), linked only if `Task` is used. **v1 is single-threaded; v2 makes the scheduler multi-threaded** (ROADMAP phase 7).
- **Blocking C calls:** `Task.blocking (fun () -> sqlite3_step db)` moves the call to a helper thread so it doesn't stall the loop. In v1 this is the only use of threads.

### 6.1 Effect handlers (designed now, built in v3)

This is designed now so that v1 and v2 choices don't rule it out. With effect
handlers, a single feature can express generators, async, exceptions,
backtracking and dependency injection, with no function colouring.

```fsharp
effect Yield<'a> =
  abstract yield : 'a -> unit

let numbers () =                         // inferred: unit -> unit / Yield<int>
  for i in 1 .. 3 do Yield.yield i

let sum () =
  let mutable total = 0
  handle numbers () with
  | Yield.yield x, k -> total <- total + x; k ()   // k: the resumption, called at most once
  | return () -> total
```

- **Effect types:** Koka-style effect rows (`a -> b / E`), inferred and row-polymorphic. A function with no effects shows nothing extra in its type, so ordinary code stays unannotated.
- **One-shot resumptions only** (`k` is called at most once). This keeps RC sound, since there's no duplication of captured resources, and allows in-place reuse. Multi-shot continuations (backtracking) would be a later, opt-in effect kind.
- **Implementation:** generalized evidence passing with yield-bubbling (Xie & Leijen, ICFP 2021). This is what Koka uses, and Koka also uses Perceus.
  - It compiles to plain code with **no stack switching and no stack copying**.
  - Only functions whose effect row is non-empty pay any cost. Pure code is untouched.
- **C interop rule:** an `extern` is effect-free by definition. A closure passed to C as a callback must have an empty effect row, checked at compile time. So a continuation can never be captured across a C frame, which is the property that sinks stack-switching designs.
- **Relation to Task:** `Task` keeps its v1 API and `task { }` syntax. Later it may be reimplemented as an `Async` effect without breaking user code. Builders (§4) remain for monads that aren't effects (parsers, `result`).
- **Constraints that apply now (v1 and v2):**
  1. The runtime and FFI must not assume one contiguous native stack.
  2. `Task` stays opaque, so its representation can change.
  3. Core IR keeps the type information needed to add effect rows later.
  4. The keywords `effect` and `handle` are reserved.

## 7. Parallelism

**Concurrency** (`Task`, waiting on I/O) and **parallelism** (using all cores)
are separate APIs that share one runtime thread pool.

```fsharp
let rows = matrix |> Array.Parallel.map (fun row -> Array.sum row)
let (a, b) = Parallel.both (fun () -> fib 35) (fun () -> fib 36)
Parallel.for 0 n (fun i -> out.[i] <- f i)       // disjoint writes, see below
```

- **Thread pool:** work-stealing with Chase–Lev deques, sized to the core count, in the C runtime.
- **`Share` auto-trait (like Rust's `Send`, but with no lifetimes):** a value may cross threads only if it is immutable or explicitly synchronised. Immutable-by-default means nearly all data qualifies automatically.
  - **Share:** primitives, immutable records, tuples, unions, `string`, `list`, immutable `array`, and closures whose captured values are all `Share`.
  - **Not Share:** `ref`, mutable fields, and plain `array` mutated through `<-`. Wrap these in `Atomic<'a>`, `Mutex<'a>` or `Channel<'a>`.
  - **Indexed parallel writes:** `Parallel.for` and `Array.Parallel.init` write to one array by index. The library proves the writes are disjoint by construction, since each index belongs to exactly one task.
- **Reference counts across threads** (the Koka and Lean approach):
  - RC is non-atomic by default, so single-threaded code pays nothing.
  - When a value is sent to another thread, its object graph is marked *shared* once, and from then on only those objects use atomic RC.
- **Concurrency tools in the stdlib:** `Atomic`, `Mutex`, `Channel` (bounded, MPMC) and `Parallel.reduce`.
- **Verification:** ThreadSanitizer runs in CI over the parallel tests.

## 8. SIMD

There are three levels, from free to manual.

1. **Autovectorization (free):** the compiler emits IR that LLVM can vectorize:
   - Arrays of unboxed value types are stored contiguously.
   - Immutable arrays are marked `noalias` and `readonly`, a direct win from FP.
   - Bounds checks are hoisted out of loops.
   - Floats are strict IEEE by default. `[<FastMath>]` on a function allows reassociation, so reductions vectorize.
2. **Portable vector types** (like Zig's `@Vector` and C#'s `Vector128`):
   - Value types `f32x4`, `f32x8`, `f64x2`, `f64x4`, `i32x4`, `i32x8`, `i8x16`, `u8x32`, … map to LLVM `<N x T>`.
   - They support arithmetic and comparison operators through the `Num`/`Ord` traits, plus `load`, `store`, `splat`, `shuffle`, `select`, `sum`, `min` and `max`.
   - Any operation the target lacks is legalised by LLVM, so the code stays portable.

   ```fsharp
   let dot (a: array<f32>) (b: array<f32>) =
     let mutable acc = f32x8.zero
     for i in 0 .. 8 .. a.length - 8 do
       acc <- acc + f32x8.load a i * f32x8.load b i
     f32x8.sum acc + Array.dotTail a b (a.length / 8 * 8)
   ```
3. **Target intrinsics:** `Simd.X86` and `Simd.Arm` modules, which are thin `extern`s to LLVM intrinsics.
   - **Selecting the CPU:** `zs build --cpu=native|x86-64-v3|...`, or per function with `[<Target("avx2")>]`.
   - **Picking a variant at runtime:** `[<Multiversion("avx2", "sse4.2")>]` compiles several versions and chooses one when the program starts.

## 9. Compiler architecture and optimization

```
 .zs ─► Lexer (offside rule) ─► Parser ─► AST
        ─► Resolve (names, modules)
        ─► Typecheck (HM + traits, exhaustiveness)              [Typer.fs]
        ─► Core IR (typed)
        ─► Monomorphize ─► Core optimizer ─► Perceus (RC, borrow, reuse)
        ─► LLVM IR ─► LLVM -O2/-O3 (+ThinLTO) ─► native object ─► link
```

- **Bootstrap language:** F#. Self-hosting is optional and late.
- **Generics across libraries:** a compiled library ships its generic functions as serialized Core IR next to its object code, the way Rust ships `.rlib` files. Users monomorphize them at their own types. `[<Export>]` functions must be monomorphic.
- **Cross-compilation:** `zs build --target aarch64-linux-musl`, as in Zig.
  - LLVM emits the object for the target triple.
  - `zig cc` links it using Zig's bundled libc headers and libraries (glibc, musl, macOS, Windows/mingw).
  - It's found on `PATH` or vendored with the release, so no target sysroot needs to be installed.
- **Target platforms, in priority order:**
  1. Linux x86-64 and aarch64.
  2. macOS aarch64.
  3. Windows x86-64.
  4. WASM (WASI), which is later.
- **Backend:** textual LLVM IR passed to `clang`. Debugging is trivial because you just read the `.ll` file. Switch to the LLVM C API when compile time demands it (phase 9).
- **Runtime:** `rt.c` (RC helpers, panic, strings and arrays, scheduler, thread pool), compiled once and linked statically.
- **Debug info:** DWARF (`!DILocation`) so gdb and lldb step through source lines. This is not yet implemented and is planned for phase 4.

### Optimization strategy

LLVM is excellent at scalar loops and register allocation. It knows nothing
about closures, unions, or which values are unique. Z# does the
**functional-language optimizations** on Core IR and leaves the rest to LLVM.

| Layer | Optimization |
|---|---|
| Core IR | Inlining (especially small higher-order functions: `\|>`, `List.map (fun ...)`), uncurrying, closure elimination and lambda lifting |
| Core IR | case-of-known-constructor, case-of-case, let-floating, dead code elimination |
| Core IR | Self tail calls become loops. Other tail calls use `musttail`. |
| Core IR | Match compilation into decision trees, so no subterm is tested twice |
| Representation | Small non-recursive unions and tuples are unboxed (scalar replacement). Enums become `i8`. `option<ptr>` uses the null niche. Nullary constructors are pointer-tagged. |
| Perceus | Borrow inference, drop specialization, reuse analysis, fusing RC ops on the fast path |
| LLVM metadata | `noalias`/`readonly` on immutable data, `nonnull`, range metadata on tags, bounds-check hoisting |
| LLVM | `-O2` by default, `-O3 --cpu=native` for release, ThinLTO across modules and `rt.c`, later PGO (`zs build --pgo`) |
| Compile time | One LLVM module per Z# module, with incremental caching keyed on module interface hashes |

**Performance contract:** a benchmark suite tracked in CI (fib, binary-trees,
nbody, spectral-norm, a red-black tree, JSON parsing, mandelbrot). Each runs
against C (clang -O2), OCaml and F#. A regression of more than 5% fails the build.

## 10. C interop

```fsharp
extern puts   : cstr -> c_int
extern printf : cstr -> ... -> c_int             // variadic

[<CLayout>]                                      // pins C layout, forbids reordering
type Vec2 = { x: f32; y: f32 }

[<Export "zs_area">]                             // no currying, C calling convention, stable symbol
let area (s: Shape) : f64 = ...

import c "raylib.h"                              // libclang, like Zig's @cImport
```

- **FFI types:** `c_int`, `c_long`, `usize`, `cstr`, `ptr<'a>`, `fnptr<...>`.
- **Passing values across the boundary:**
  - `[<CLayout>]` records pass by value. The compiler does the C ABI lowering, since LLVM doesn't.
  - RC objects cross as opaque handles, using `Rc.retain`/`Rc.release`.
- **Callbacks:** a C `void (*cb)(void*)` paired with a `void* user` receives a Z# closure. The compiler generates the thunk and passes the closure through `user`.
- **Raw pointers:** `Ptr.read`, `Ptr.write` and pointer arithmetic require an `unsafe` expression.
- **Build output:** `zs build` emits a `.o`/`.a`/`.so` and a `.h` for every `[<Export>]` function.
- **Interaction with Task:** a blocking C call goes through `Task.blocking` (§6).

## 10.1 Editor tooling

- **Highlighting:** a tree-sitter grammar (`editors/tree-sitter-zsharp`). It drives highlighting, indentation and the outline in Zed, Neovim and Helix, and code views on GitHub.
- **Language server:** `zs lsp`. It reuses the compiler's lexer, parser and type checker, so hover types and diagnostics are exactly what the compiler reports.
- **AI agents:** `zs mcp` exposes the same queries, plus build and run, as MCP tools.
- **Formatting:** `zs fmt` applies one canonical, configuration-free style (Fantomas-like layout, 100 columns). It is built on a lossless syntax tree, so comments survive. It's the backend for LSP formatting and format-on-save.
- **Zed integration:** the Zed extension (`editors/zed`) bundles the grammar and starts both servers.
- **Compiler requirements:**
  - Source spans with columns.
  - Error recovery, so all errors are reported, not just the first.
  - A position-to-type/definition index.

  These also improve command-line error messages.

Plan: ROADMAP "Editor tooling track".

## 11. Decisions

| # | Decision | Chosen default | Status |
|---|---|---|---|
| 1 | `int` width | 64-bit | decided |
| 2 | Integer overflow | traps in debug, wraps in release; divide by zero always traps | decided |
| 3 | Syntax | indentation only | decided |
| 4 | Memory | Perceus RC, no GC | decided |
| 5 | Unreachable match case | error (F# warns) | decided |
| 6 | Async types | one cold `Task<'a>` + `Task.start` | decided |
| 7 | Async syntax | general computation expressions, builders as modules | decided |
| 8 | Threads | v1 single-threaded event loop; multi-threading in v2 | decided |
| 9 | Effect handlers | designed now (§6.1), built in v3; one-shot, evidence passing | decided |
| 10 | Float semantics | strict IEEE; `[<FastMath>]` opt-in per function | default |
| 11 | SIMD API | portable `f32x8`-style value types + target intrinsics | default |
| 12 | Zig traits adopted | built-in cross-compilation via `zig cc`. Not adopted: explicit allocators, no-hidden-allocation, comptime | decided |
| 13 | Members / dot methods | yes; type-directed, no inheritance or overloading | decided |
| 14 | Equality / comparison | automatic and structural, opt-out attributes | decided |
| 15 | Units of measure | yes, erased, Kennedy unification | decided |
| 16 | Active patterns | yes: total, partial, parameterised | decided |
| 17 | `[ ]` literal | F# immutable cons list; `[\| \|]` is an array | decided |
| 18 | Panics | abort with backtrace, never unwind, can't be caught | decided |
| 19 | Strings | UTF-8; `Length` is bytes; iteration over chars | default |
| 20 | Generics across libraries | ship Core IR, monomorphize at the user | default |
| 21 | Target order | Linux x64/arm64, macOS arm64, Windows x64, WASM | default |
| 22 | User code generation | `derive` over record and union shapes (§3.1); no macros, no comptime | default |
| 23 | Editor support | tree-sitter grammar + `zs lsp` + `zs mcp`, Zed extension first | decided |
| 24 | Named/optional/default args | default record fields + named/optional/default on members only; none on curried functions | decided |
| 25 | `option` record fields | default only with explicit `= None` | decided |
| 26 | Default expressions | any expression, evaluated at the call site, may use earlier fields/parameters | decided |
| 27 | Union case fields | named construction and patterns; no defaults | decided |
| 29 | `?` operator | `let p = e?` and statement `e?` for now; general positions arrive with `result { }` (Phase 6) | decided |
| 30 | Automatic Eq/Ord/Hash/Show | derived the first time a type needs them; a type whose fields can't support it simply doesn't get it | decided |
| 31 | Callbacks into C | `callback<A -> R>` = `R (*)(void* user, A)` + `void* user`; the closure is borrowed for the call | decided |
| 28 | Formatter | `zs fmt`, one canonical style, no configuration; lossless CST with comment trivia | decided |

"Default" means chosen by me and open to change until the phase that implements it begins.
