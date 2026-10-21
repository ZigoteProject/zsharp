# Z# — design

An ML-family language with F# syntax and ergonomics, compiled ahead of time to native code
through LLVM. It has no VM and no tracing GC. Memory is managed by compiler-inserted reference
counting, and it links directly with C.

**Pitch:** F# syntax, OCaml semantics, Zig-style output: one native binary that links straight
against C, from desktop CPUs down to microcontrollers.

**Reading this document:** it describes the language as designed. Anything not built yet is
marked **(planned)**, with the phase that builds it. Status and order: [ROADMAP.md](ROADMAP.md).
To learn the language: [the guide](docs/guide/README.md).

## 1. Goals and non-goals

| Goals | Non-goals (v1) |
|---|---|
| F# light syntax (indentation, `let`, `\|>`, `match`) | .NET interop, the CLR |
| Hindley–Milner inference, monomorphized generics | Higher-kinded types, functors |
| Algebraic data types, exhaustive pattern matching | OOP classes, inheritance |
| Native code via LLVM, as fast as C on the same algorithm | Tracing GC, JIT |
| Calling C and being called from C, C struct layout | Macros, general compile-time evaluation (`derive` is the one exception, §3.1) |
| Deterministic memory (reference counting), memory-safe by default | Built-in `async`/`await` keywords |
| Computation expressions; `Task` as a library | Green threads, a GIL |
| Data parallelism and SIMD without data races | |
| Runs on Linux, macOS, Windows and bare-metal microcontrollers | |

**"Simple":** the language fits in about 20 pages, and a feature that needs a runtime is out.
The exception is a small C runtime (allocation, panics, strings, later the task scheduler and
thread pool), linked statically.

**Who it's for first:** native libraries used from C, CLI tools, and microcontroller firmware.
Games over C libraries come next.

## 2. Language tour

```fsharp
module Geometry

type Point = { x: f64; y: f64 }          // record: a value, C-compatible layout with [<CLayout>]

type Shape =                             // union
  | Circle of center: Point * radius: f64
  | Rect   of Point * Point

let area shape =                         // inferred: Shape -> f64
  match shape with
  | Circle (_, r) -> 3.14159 * r * r
  | Rect (a, b)   -> Math.abs ((b.x - a.x) * (b.y - a.y))

let total shapes = shapes |> List.sumBy area

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

### 2.1 Core features

- **Bindings:** `let`, `let mutable` with `<-`, `let rec`, and shadowing.
  - A `let mutable` can't be captured by a closure (an F# rule that §5 relies on); `ref` cells can.
  - **Top-level values:**
    - **Constants:** built from literals, operators, conditionals, constructors, records, tuples, conversions and other constants. They're inlined at each use, and an unannotated number constant takes the type each use needs, like a literal. Their names resolve where they're defined.
    - **Other values:** these are computed once at startup, before `main`, in module order then declaration order, and freed at exit.
    - **Order:** declarations are in order, so nothing can read a value before it's initialized.
    - **Libraries:** a library (`--lib`) has no startup, so it can only have constants.
- **Numbers:**
  - `int` and `usize` are the machine word: 64 bits on 64-bit targets, 32 on a Cortex-M. This is as in Swift and Go, and keeps loop and index code native on 32-bit chips.
  - `i8 i16 i32 i64` and `u8 u16 u32 u64` have fixed sizes. `f32` and `f64` are IEEE floats.
  - Literals: `42`, `0xFF`, `0b1010`, `0o17`, `1_000_000`, `3.14`, `1e-3`. A literal takes the type the context needs, and conversions are explicit (`float n`, `u8 x`).
  - Bitwise operators use F#'s spelling, `&&& ||| ^^^ <<< >>> ~~~`, and bind tighter than comparison (`x &&& mask = 0`).
- **Other types:** `bool`, `string` (UTF-8 bytes, reference-counted, immutable), `unit`.
  - **`char`:** a Unicode scalar value (32 bits), written `'a'`, `'\n'` or `'\u{1F600}'`. It has equality, ordering, hashing and printing, and `match` on character literals, but no arithmetic. `int c` and `char n` convert.
  - **Strings and characters:** `for c in s` decodes a string's UTF-8 character by character; `String.length` stays the byte length. The `Char` functions classify ASCII.
  - **SIMD vectors** `f32x4`, `i32x8`, … are **(planned, phase 8)**.
- **Data:** tuples, records (`{ p with x = 1.0 }`), unions; library types `option`, `result`, `list`, `array`, `Buffer`, `ref`, `Map`, `Set`, `HashMap`.
- **Functions:**
  - Curried, with closures (`fun x -> …`), `|>`, `>>` and partial application.
  - Known calls pass all arguments at once, so currying costs nothing at run time.
  - Tail calls: a call to itself becomes a loop, and other tail calls with the same signature use LLVM `musttail`. Recursion in tail position runs in constant stack.
- **Loops:** `for i in a .. b do`, `for i in a .. step .. b do`, `for pattern in xs do` (lists and arrays), `while c do`.
- **Pattern matching:**
  - Supports nesting, literals, tuples, records (`{ x = 0; y = y }`, fields left out match anything), union cases (positional or by field name), lists, guards, `as` and or-patterns that bind variables.
  - Patterns work in `match`, `let`, function parameters (`let norm { x = x; y = y } = …`), lambdas and `for` loops.
  - A match that misses a case is an **error** naming an example of the missing value (`missing case: { kind = C }`). So is a case that can never match.
- **Errors:** `result` with a postfix `?` that returns the error early (`let x = parse s?`, or `parse s?` as a statement). A `result { }` builder is **(planned, phase 6)**.
- **Panics:** for bugs, not errors a caller handles. These all panic: an out-of-bounds index, division by zero, integer overflow, a failed `assert`, an explicit `panic`.
  - A panic prints a message (and a backtrace where the C library supports it), then stops the program at once: no unwinding, no cleanup, exit status 134, no core dump. `ZS_ABORT=1` makes it a real `abort()` for a debugger.
  - Panics can't be caught. So there are no landing pads, and nothing unwinds through C frames.
- **Strings:** `$"x = {p.x}"` interpolation, where any expression with `Show` can go in a hole. `+` joins strings.
- **Modules:** one file is one module, with `open`, qualified names and `private`. `module Name` on the first line renames it.
  - **Namespaces:** `namespace X` on the first line makes the file's types and modules `X.Name`, as in F#. The library uses it to put `type Map` and `module Map` side by side in `Collections`.
  - **Nested modules:** `module Inner =` and an indented block. Names inside are `Outer.Inner.x`; the block sees the names of its enclosing modules, `private` reaches the modules nested inside, and an `open` lasts until the block ends.
- **Type annotations in expressions:** `(e: T)`, which also gives a literal or a record literal its type.
- **Mutual recursion:** `let rec f … and g …`, at the top level or locally. A top-level group is generalized jointly, so generic members share their type variables.

### 2.2 F# features kept

```fsharp
[<Measure>] type m
[<Measure>] type s

type Vec =
  { x: f64<m>; y: f64<m> }
  member v.Dot(o: Vec) = v.x * o.x + v.y * o.y          // f64<m^2>
  static member Zero = { x = 0.0<m>; y = 0.0<m> }

let speed (d: f64<m>) (t: f64<s>) = d / t               // f64<m/s>

let (|Even|Odd|) n = if n % 2 = 0 then Even else Odd    // total active pattern
let (|Int|_|) (s: string) = String.parseInt s           // partial active pattern

let same () = { x = 1.0<m>; y = 2.0<m> } = { x = 1.0<m>; y = 2.0<m> }   // true, structural
```

- **Members** (`member`, `static member`, `type T with …` extensions) on records, unions and built-in types.
  - Calls use dot syntax: `v.Dot(w)`, `Vec.Zero`, `s.Split(", ")`.
  - There is no inheritance and no overloading (one member per name), which keeps inference predictable.
  - **Dot resolution is type-directed, as in F#:** `x.M` needs `x`'s type known by that point, reading left to right. Otherwise the error says to annotate `x`. Pipelines (`xs |> List.map (fun p -> p.x)`) work because `|>` checks its left side first.
- **Automatic structural equality, ordering, hashing and printing:**
  - `=`, `<>`, `compare`, `hash` and `string x` work on every record, union and tuple whose fields support them, as in F#.
  - Functions don't support them, so a type containing a function gets a compile error where equality is used.
  - Opt out with `[<NoEquality>]`/`[<NoComparison>]`; customise with `impl Eq<T>`, etc.
- **Units of measure:** checked at compile time, erased afterwards, so they cost nothing.
  - Exponents unify as an abelian group (Kennedy's algorithm), so `m/s * s` simplifies to `m`.
- **Active patterns:**
  - **Total** ones (`(|A|B|)`) define a closed set of cases and count toward exhaustiveness like constructors.
  - **Partial** ones (`(|P|_|)`, returning `option`) never count toward coverage, like a guarded case.
  - Parameterised ones (`(|DivBy|_|) 3`) are supported.

### 2.3 Default fields, named and optional arguments

There are two mechanisms. Curried `let` functions get neither, so their types stay plain.

**Default values for record fields.** A literal may leave out a field that has a default:

```fsharp
type Config =
  { host: string = "localhost"
    port: int = 8080
    timeout: int = port / 100          // may use earlier fields
    tls: option<TlsConfig> = None }    // option fields need an explicit default

connect { port = 9000 }                // the "options record" idiom replaces named arguments on functions
```

**Named, optional and default arguments on members** (tupled, as in F#):

```fsharp
type Http =
  static member Get(url: string, ?timeout: int = 30, ?headers: list<string * string>) = …

Http.Get("https://x", timeout = 5)     // inside Get: timeout is int, headers is option<_>
```

**Named fields on union cases:** construction and patterns can use the field names (`Circle(radius = 2.0)`, `| Rect(h = h) -> h`). Union fields have no defaults.

**Rules:**
- **When defaults run:** a default is any expression, evaluated at the use site each time, after the explicit values. It may use earlier fields or parameters. Defaults expand at the call site, so there's no callee-side `option` check. Values are immutable, so Python's shared-mutable-default trap can't happen.
- **Optional parameters without a default:** these are `option<_>` in the body, and an omitted argument is `None`.
- **Named arguments:** in a member call, `name = value` is a named argument when `name` is one of the member's parameters; elsewhere `x = 1` is equality. Positional arguments come first, and each parameter may be given at most once.
- **Record literals:**
  - **Picking the type:** a literal's record type comes from the type expected where it's written. That works through `if`/`match` branches, `let` tails, tuple, list and array elements, and function, constructor and C call arguments.
  - **Without an expected type:** the fields must identify the record. When two records share all the given fields, the later-declared one wins, as in F#.
  - **Missing fields:** a field without a default must always be given.
- **`derive` (§3.1):** `fromJson` uses a field's default when the key is missing.
- **C export:** exported functions have all parameters required, since C has no defaults.

## 3. Traits

Traits replace interfaces and F#'s SRTP.

```fsharp
trait Describe<'a> =
  abstract describe : 'a -> string

impl Describe<Point> =
  let describe p = $"({p.x}, {p.y})"

let report x = Console.println (describe x)    // inferred: 'a -> unit when 'a : Describe
```

- **Dispatch:** resolved statically and monomorphized, with no runtime cost.
  - A generic function's trait requirements are inferred, and so are an impl's requirements on its type arguments. For example, `impl Show<list<'a>>` needs `Show<'a>`.
  - **`dyn Trait`** (vtables for heterogeneous collections and plugin APIs) is **(planned, phase L or later; in v1)**.
- **Operators are traits:** `Add` (`+`, `zero`), `Num` (`- * / %`, negation), `Eq`, `Ord`. They have built-in impls for primitives, and user types implement them with `impl`.
- **Built-in derives:** `Eq`, `Ord`, `Hash` and `Show` come from prelude derives (§3.1), applied automatically the first time a type needs them. An `impl` overrides them.
- **Auto traits:** `Share` (§7) will be derived structurally by the compiler, and can't be implemented by hand **(planned, phase 7)**.

### 3.1 Derive

Rust gets serializers, CLI parsers and builders from proc macros, Zig from `comptime`, and F#
from reflection. Z# has none of these. It has **derive**: a library definition that implements
a trait for any record or union by walking its fields. The built-in `Eq`, `Ord`, `Hash` and
`Show` are written this way.

```fsharp
trait Json<'a> =
  abstract toJson   : 'a -> JsonValue
  abstract fromJson : JsonValue -> result<'a, string>

derive Json =                                   // implements Json<'self> for a record or union
  let toJson (x: 'self) =
    match Shape.of x with
    | Record r ->
      let mutable fields = []
      for f in r.fields do                      // unrolled: one copy of the body per field
        fields <- (f.name, toJson f.value) :: fields
      JObject (List.rev fields)
    | Union c ->
      let mutable args = []
      for f in c.fields do
        args <- toJson f.value :: args
      JObject [ ("case", JString c.name); ("fields", JArray (List.rev args)) ]

  let fromJson (j: JsonValue) : result<'self, string> =
    match Shape.kind with
    | RecordKind -> Shape.build (fun f -> Json.field f.name j |> Result.bind fromJson)
    | UnionKind ->
      let name = (Json.field "case" j |> Result.bind Json.string)?
      let args = (Json.field "fields" j |> Result.bind Json.array)?
      match Shape.buildCase name (fun f -> Json.at f.index args |> Result.bind fromJson) with
      | Some built -> built
      | None -> Error $"unknown case {name}"

[<Derive(Json)>]
type User = { name: string; age: int; email: option<string> }
```

The full example is `tests/json.zs`.

- **What a derive sees:**
  - `Shape.of x` is `Record r` or `Union c`. `r.fields` lists every field, and `c.name`/`c.fields` describe the active case.
  - Each field has `name`, `index` and a `value` of the field's own type.
  - `c.index` and `c.count` give the case's position and its number of fields.
- **Two values at once:** `match Shape.pair a b with Same c -> … | Different (i, j) -> …`. With `Same`, each field has `f.left` and `f.right`; `Different` carries the two case indexes.
- **Building values:** `Shape.kind` tells a derive whether it builds a record or a union.
  - `Shape.build (fun f -> …)` makes a record from per-field results, stopping at the first `Error`.
  - `Shape.buildCase name (fun f -> …)` makes the named union case, or `None` for an unknown name.
- **Per-field expansion:** a `for f in ….fields` loop is unrolled at compile time, and each copy is type-checked at that field's type. So `toJson f.value` resolves `Json` separately for each field. This is Zig's `inline for` over `@typeInfo`, and it's the only construct that works this way.
- **Checking:**
  - **Where the derive is defined:** the body is checked for names and syntax.
  - **At each derived type:** it's fully type-checked. Errors name the derive, the type and the field: `Derive(Json) on Callback: field run: … does not implement Json`.
  - **Names:** trait methods named inside a derive always mean the trait's, even where a program defines a function of the same name.
- **Generics and recursion:** deriving for `Tree<'a>` adds `'a : Json` to the impl. Recursive types work because impls are monomorphized.
- **Cost:** none at run time. The expanded impl is ordinary code, and no type metadata is in the binary.
- **Not included:**
  - Derives can't add members, types or other declarations.
  - There are no field attributes yet, such as renaming a JSON key.
  - Declarations generated from a schema, as F# type providers do, would be a later generalization of `import c`.

## 4. Computation expressions (planned, phase 6)

These are F#'s builder syntax, kept general so that async, `result`, `option`, parsers and
generators are libraries, not compiler features.

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

A builder is a **module**, not an object, so it resolves statically and inlines.

| Form | Rewrites to |
|---|---|
| `let! x = m in rest` | `B.bind m (fun x -> rest)` |
| `do! m` | `B.bind m (fun () -> …)` |
| `return e` / `return! m` | `B.ret e` / `m` |
| `use x = e` | `B.using e (fun x -> …)` |
| `for x in xs do` | `B.forEach xs (fun x -> …)` |
| `if c then m` (no else) | `B.zero` on the missing branch |

The compiler checks a builder's shape with a `Builder` trait, so a missing `bind` is a type
error at the use site.

## 5. Memory

### 5.1 Representation

- **Plain values:** these live in registers or on the stack and are copied.
  - **Which types:** numbers, `bool`, tuples, records, and **small unions**: unions that aren't recursive and have at most 4 fields over all their cases, none of them heap data.
  - **Small unions:** these are a tag plus fields, e.g. `option<int>`, `result<int, f64>`, enums, and state machines with number fields. They never allocate.
- **Heap objects:** strings, arrays, `Buffer`, `ref`, closures, lists, and the other unions.
  - **Header:** each object starts with a word-sized reference count, and arrays and strings add a word-sized length. That's 8 bytes of header on a Cortex-M, 16 on 64-bit targets.
  - **Static objects:** string literals and constant constructors are static objects, with count 0, never freed.
- **Arrays are values with copy-on-write**, as in Swift and Lean. A write through one name is never visible through another.
  - `a.[i] <- x` needs `let mutable a`. It writes in place when `a` holds the only reference, and copies the array first otherwise.
  - `Array.set a i x` returns the changed array.
  - **`Buffer<'a>`:** a fixed-size *shared* mutable array, for when a write must be seen through every alias (a ring buffer handed to C, a shared scratch buffer).
  - This is a deliberate difference from F#, whose arrays are shared mutable references.

### 5.2 Perceus reference counting

Reference counting follows Perceus (Koka, Lean 4): precise ownership, so a value is freed at
its last use.

| Technique | What it does |
|---|---|
| **Ownership** | Every owned variable is consumed exactly once on each path: moved into its last use, dup'd before earlier ones, dropped as soon as it's dead |
| **Drop specialization** | A matched cell that dies has only its unused fields dropped |
| **Reuse** | A match that consumes a unique cell and builds one of the same layout writes into that cell. `List.map` over a unique list, `insert` into a unique tree, and a state machine's step don't allocate |
| **Borrowing** | A function that only reads, applies or passes on a parameter borrows it: the caller keeps ownership and the callee does no RC. Inferred by fixpoint for directly called functions |
| **Borrowed reads** | `a.[i]` and lengths don't dup or drop the array |
| **Moves out of mutables** | `x <- f x`, and `let r = f … x …` when `x` is reassigned before its next read, give `f` `x`'s own reference. So a unique value stays unique, and copy-on-write and reuse happen in place |
| **Copy-on-write in loops** | An array a loop writes, and doesn't otherwise share, is made unique once before the loop; the writes inside skip the check |

**Cycles:** immutable data can't form cycles. Only `ref` cells can, and breaking them is the
user's job, as in Swift. **`weak` references** (planned, in v1) will help.

**Escape hatches (planned, in v1):** `Arena.with (fun a -> …)` for bulk allocation that's freed
at once, and raw `ptr<'a>` inside `unsafe` expressions.

### 5.3 What code without `unsafe` guarantees

| Guarantee | Mechanism |
|---|---|
| No use-after-free or double free | Reference counting; a value dies with its last reference |
| No null | `option<'a>` |
| No uninitialised reads | Every binding has a value; arrays are created filled |
| No out-of-bounds access | Indexing is bounds-checked; in loops the checks are proved once before the loop where possible (§9) |
| No data races | `let mutable` can't be captured; the `Share` trait (planned, §7) |
| Deterministic cleanup | RC, plus `use` (planned, phase 6), which also runs when a task is cancelled |
| No silent overflow | Integer overflow traps in every build, as in Swift. Wrapping is explicit: `Int.wrappingAdd`, `Int.wrappingSub`, `Int.wrappingMul` (and `[<Wrapping>]` on a function, planned). Division by zero traps |

**Not guaranteed (and still memory-safe):** leaks through `ref` cycles.

**Unsafe on purpose:** `extern` calls, `Mmio.*` register accesses, and (planned) `unsafe`
expressions with raw pointers.

## 6. Concurrency: `Task` (planned, phase 6)

> **Decision gate (before phase 6).** Async could otherwise be built three times: CPS `Task`
> in phase 6, state machines in phase 9, effects in phase 10. So a time-boxed spike comes first:
> one built-in `Async` effect with one-shot resumptions, compiled by evidence passing (§6.1).
> - **If it type-checks and meets the phase 5 performance bar:** `Task` is a library over
>   effects from the start, and most of phase 9's `Task` work goes away.
> - **If not:** the CPS design below stands.
>
> Either way, the `Task` API in this section is what users see.

There is **one type, `Task<'a>`, and it is cold.** A task is a value that describes work.
Defining it does nothing, and running it twice runs the work twice. `Task.start` gives a hot
handle when the work should begin now. F# needed both Async and Task only because of .NET
compatibility, which Z# doesn't have.

```fsharp
let both a b =
  task {
    let! (x, y) = Task.both (Http.get a) (Http.get b)   // concurrent
    return String.length x + String.length y
  }

let main () =
  println $"{Task.run (both "https://a" "https://b")}"
  0
```

- **Implementation:** a library on top of §4. Each `let!` becomes a continuation closure.
  - Continuations are almost always unique, so Perceus reuses them in place. A loop that waits repeatedly settles into steady memory, not one allocation per await.
  - Bind chains use `musttail`, so the stack doesn't grow.
  - Later, `task { }` may be lowered to stackless state machines with no change to the source (phase 9).
- **Structured concurrency:**
  - Child tasks can't outlive the scope that started them (`Task.both`, `all`, `race`, `scope`).
  - Cancellation flows down implicitly.
  - Cancelling drops the continuation, so RC releases what it captured and `use` resources close.
- **Event loop:** about 300 lines of C over epoll/kqueue (io_uring later), linked only if `Task` is used. v1 is single-threaded, and v2 makes the scheduler multi-threaded (phase 7).
- **Blocking C calls:** `Task.blocking (fun () -> sqlite3_step db)` moves the call to a helper thread. In v1 that's the only use of threads.

### 6.1 Effect handlers (planned, phase 10, v3)

These are designed now, so v1 and v2 choices don't rule them out. With effect handlers, one
feature expresses generators, async, exceptions, backtracking and dependency injection, with no
function colouring.

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

- **Effect types:** Koka-style effect rows (`a -> b / E`), inferred and row-polymorphic. A function with no effects shows nothing extra in its type.
- **One-shot resumptions only:** `k` runs at most once. That keeps RC sound and allows reuse. Multi-shot continuations would be a later, opt-in kind.
- **Implementation:** generalized evidence passing with yield-bubbling (Xie & Leijen, ICFP 2021), as in Koka, which also uses Perceus. It compiles to plain code with no stack switching or copying, and only functions with effects pay any cost.
- **C interop rule:** an `extern` is effect-free. A closure passed to C must have an empty effect row, checked at compile time, so no continuation is captured across a C frame.
- **Relation to Task:** `Task` keeps its API and `task { }` syntax, and may later be reimplemented over an `Async` effect. Builders stay for monads that aren't effects (parsers, `result`).
- **Constraints that hold until then:**
  1. The runtime and FFI don't assume one contiguous native stack.
  2. `Task` stays opaque.
  3. Core IR keeps the type information effect rows will need.
  4. `effect` and `handle` are reserved words.

## 7. Parallelism (planned, phase 7)

**Concurrency** (`Task`, waiting on I/O) and **parallelism** (using all cores) are separate APIs
over one runtime thread pool.

```fsharp
let rows = matrix |> Array.Parallel.map (fun row -> Array.sum row)
let (a, b) = Parallel.both (fun () -> fib 35) (fun () -> fib 36)
Parallel.for 0 n (fun i -> out.[i] <- f i)       // disjoint writes into a unique array
```

- **Thread pool:** work-stealing with Chase–Lev deques, sized to the core count, in the C runtime.
- **`Share` auto-trait:** like Rust's `Send`, but with no lifetimes. A value may cross threads only if it's immutable or explicitly synchronised. Immutable-by-default means nearly all data qualifies.
  - **Share:** primitives, records, tuples, unions, `string`, `list`, arrays (they're values) whose elements are `Share`, and closures that capture only `Share` values.
  - **Not Share:** `ref` and `Buffer<'a>`. Use `Atomic<'a>`, `Mutex<'a>` or `Channel<'a>` instead.
  - **Disjoint writes:** `Parallel.for` and `Array.Parallel.init` write to one uniquely owned array by index. Each index belongs to one task, so the writes are disjoint by construction.
- **Reference counts across threads** (as in Koka and Lean): RC is non-atomic by default. When a value is sent to another thread, its object graph is marked *shared* once, and only those objects use atomic RC from then on.
- **Library:** `Atomic`, `Mutex`, `Channel` (bounded, MPMC), `Parallel.reduce`.
- **Testing:** ThreadSanitizer runs over the parallel tests.

## 8. SIMD (planned, phase 8)

There are three levels, from free to manual.

1. **Autovectorization:** the compiler emits IR that LLVM can vectorize.
   - Arrays of plain values are contiguous.
   - Element access uses `inbounds nuw` addressing, and lengths carry range metadata.
   - Bounds checks move out of loops (§9).
   - Floats are strict IEEE by default. `[<FastMath>]` on a function allows reassociation, so reductions vectorize.
2. **Portable vector types** (like Zig's `@Vector`, C#'s `Vector128`):
   - The types `f32x4`, `f32x8`, `f64x2`, `i32x8`, `u8x32`, … map to LLVM `<N x T>`.
   - They come with operators through `Num`/`Ord`, plus `load`, `store`, `splat`, `shuffle`, `select` and reductions.
   - LLVM handles operations a target lacks.
3. **Target intrinsics:** `Simd.X86` and `Simd.Arm`, thin externs to LLVM intrinsics.
   - **Choosing the CPU:** `--cpu=native|x86-64-v3|…`, or per function with `[<Target("avx2")>]`.
   - **Choosing at startup:** `[<Multiversion("avx2", "sse4.2")>]` builds several versions and picks one when the program starts.

## 9. Compiler

```
 .zs ─► Lexer (offside rule) ─► Parser ─► AST ─► import c (clang)        Syntax, CImport
     ─► Type check: HM + kinds + traits + units, exhaustiveness ─► Core   Typer, Match, Derive
     ─► Monomorphize (trait dispatch, units erased) ─► list fusion        Mono
     ─► Closure conversion, lambda lifting                                Lift
     ─► Perceus: ownership, borrowing, moves, reuse, drop specialization  Rc
     ─► LLVM IR (textual) ─► clang -O2/-Os ─► object ─► link              Codegen, Driver
```

- **Implementation language:** F# (.NET 10). Self-hosting is optional and late (phase 11).
- **Backend:** textual LLVM IR passed to clang, so reading the `.ll` file is the debugger. A switch to the LLVM C API comes when compile time demands it (phase 9).
- **Runtimes:** `runtime/rt.c` on an OS, and `runtime/rt-embedded.c` on bare metal (§10). Each is one C file, linked statically.
- **Generics across libraries:** libraries are **source**, as in Go and Zig.
  - **How they're used:** a dependency's modules are type-checked with the program and monomorphized at the program's types.
  - **Speed:** comes from caching each module's checked Core, keyed by its content hash **(planned, phase 5)**.
  - **No IR format:** there's no binary format to version. Closed-source code ships as an `[<Export>]` C library.
- **The library** (`lib/`) is Z#, in three layers:
  - **Prelude** (`lib/prelude.zs`): the global names: the operator traits and their derives, `option`, `result`, `id`, `fst`, `min`, ….
  - **Core** (`lib/core`): what needs no operating system, so every target has it: collections, text, options, results, `Math`, `Mmio`.
  - **Std** (`lib/std`): what needs one: `Console`, `Environment`, `IO` and `Diagnostics`. A microcontroller build doesn't load it, and a name from it is a compile error that says why.
  - **Namespaces, as in .NET:** `Collections` (`List`, `Array`, `Buffer`, `Map`, `Set`, `HashMap`), `Text` (`String`, `Char`), `IO` (`File`, `Directory`, `Path`) and `Diagnostics` (`Process`, `Stopwatch`). They are open in every module at the lowest precedence, so `List.map` is `Collections.List.map` unless a program defines its own, and full names work too.
  - **Names:** modules have .NET's names (`Directory`, `Environment`, `Stopwatch`) and functions F#'s style (`File.readAllText`, `Directory.list`, `Environment.getVariable`).
  - **Built-in functions:** what the runtime provides is built into the compiler under its full name (`Text.String.length`, `IO.File.exists`). The operating-system calls the library wraps are under `Native`, which programs don't use.

### 9.1 Optimization strategy

LLVM is excellent at scalar loops and register allocation. It knows nothing about closures,
unions or which values are unique, so Z# does the functional-language optimizations itself,
and gives LLVM the facts it can't prove.

| Layer | Optimization | Status |
|---|---|---|
| Representation | Small non-recursive unions as plain values; word-sized headers | done |
| Mono | List fusion: `List.init` chains into `sum`/`sumBy`/`fold`/`length` with pure lambdas become one loop | done (more sources and consumers planned) |
| Perceus | Ownership, drop specialization, reuse, borrowing, moves out of mutables, borrowed reads | done |
| Codegen | Copy-on-write checks hoisted out of loops; loop versioning that proves bounds once for innermost call-free loops | done |
| Codegen | Overflow checks via `llvm.*.with.overflow`, which LLVM drops when ranges prove them safe | done |
| Codegen | `print` of an interpolation prints the pieces, without building the string | done |
| LLVM facts | `!range` on lengths, `inbounds nuw` element access, `noalias` allocator with `allockind`, `inlinehint` on higher-order functions, `optsize` at `-Os` | done |
| Core | Inlining of small higher-order functions, case-of-known-constructor, case-of-case, decision trees for matches | planned (phase 5) |
| Representation | `i8` enums, null niche for `option<ref>`, tagged nullary constructors | planned (phase 5) |
| Linking | ThinLTO with the runtime, PGO | planned (phase 9). On microcontrollers, linking the runtime as bitcode was measured and made code bigger and slower |

**Performance contract:**
- **Microcontrollers:** the suite in `bench/mcu` compares each program with its C version (same clang, same chip, under QEMU) [(results)](docs/reports/microcontrollers.md).
- **Host (planned, phase 5):** a host suite (fib, binary-trees, nbody, spectral-norm, the red-black tree, JSON) against C, OCaml and F#. A regression of more than 5% fails the build.

## 10. Targets

| Tier | Targets | How |
|---|---|---|
| 1 | Linux x86-64 and aarch64 | native, or `--target aarch64-linux-musl` (static) |
| 2 | Bare-metal ARM Cortex-M: `cortex-m4` (M4F), `cortex-m0plus` | `--target cortex-m4`; tested under QEMU |
| 3 | macOS aarch64, Windows x86-64 | through `zig cc` (planned) |
| 4 | WASM (WASI) | later |

**Cross-compiling:** `zs build --target <triple>`. clang compiles the program for the target,
and `zig cc` builds the runtime and links with Zig's bundled C library, so no sysroot is
needed. C structs by value follow the target's convention: x86-64 System V, or AAPCS64.

**Bare metal (`cortex-m4`, `cortex-m0plus`):**
- **Runtime:** `rt-embedded.c`, with no OS and no libc. It contains:
  - a vector table and a reset handler, which sets up RAM, enables the FPU and starts SysTick;
  - a static heap with size-class free lists (64 KB or 8 KB);
  - semihosting output and exit;
  - a peak heap and stack report at exit.
- **What's missing:** OS functions (`File`, `Process`, `Env`) aren't provided, so a program that uses one fails to link, naming the function.
- **Hardware:** `Mmio.read32/write32/read8/write8` are volatile register accesses, and `Runtime.ticks ()` counts cycles.
- **Planned:** interrupt handlers (`[<Interrupt "SysTick">]`), RISC-V (ESP32-C3) and more boards (linker scripts in `runtime/boards`). Top-level constants for register addresses come in phase L.

## 11. C interop

```fsharp
extern puts   : cstr -> c_int
extern printf : cstr -> ... -> c_int             // variadic

[<CLayout>]                                      // C layout, no reordering
type Vec2 = { x: f32; y: f32 }

[<Export "vec_add">]                             // C calling convention, a stable symbol
let add (a: Vec2) (b: Vec2) : Vec2 = { x = a.x + b.x; y = a.y + b.y }

[<Link "raylib">]                                // -lraylib; or a .c/.o/.a file next to this one
import c "raylib.h"                              // like Zig's @cImport
```

- **FFI types:**
  - **Scalars:** numbers, `bool`, `unit` (void).
  - **Pointers:** `cstr` (`const char *`; a Z# string passes as its bytes) and `cptr` (any other pointer, opaque).
  - **Structs:** `[<CLayout>]` records, passed by value.
  - **Callbacks:** `callback<A -> R>`, a function pointer plus `void *` user data.
  - **Planned (in v1):** typed raw pointers `ptr<'a>` with `Ptr.read`/`write` and pointer arithmetic inside `unsafe`, and C function pointers callable from Z#.
- **`import c`:** clang reads the header, with `-ast-dump=json` for declarations and `-E -dD` for macros. Only what that header itself declares is imported.
  - **What comes across:**
    - functions, which become externs;
    - structs, named or `typedef`'d, which become `[<CLayout>]` records;
    - enum values, which become constants, as do `#define` numbers, strings and struct literals such as `CLITERAL(Color){ … }`.
  - **Types:** `char*` becomes `cstr`, other pointers `cptr`, and enum types `i32`. `long` follows the word; `long long` is `i64`.
  - **What's left out:** unions, arrays, function pointers, `static inline` functions and opaque structs by value. Using one gives an error that says why.
  - **Caching and editors:**
    - The header is found next to the importing file, then on the system path.
    - The result is cached in memory, and saved with a copy of the header in `.zs-cache/cimport/`, so editors without clang or the header still get it.
    - In the editor, hover shows the C declaration and the header's comment.
- **Exporting:** `[<Export "name">]` functions must be monomorphic, with C types only. `zs build --lib` produces a static library (`.a`) and a header (`.h`).
  - **Planned:** shared libraries (`.so`), and RC objects crossing as opaque handles (`Rc.retain`/`Rc.release`).
- **Callbacks:** a C `void (*cb)(void *user, …)` paired with `void *user` receives a Z# closure; the compiler generates the thunk. The closure is borrowed for the call, so a callback can't be stored by C.
- **With `Task` (planned):** a blocking C call goes through `Task.blocking` (§6).

## 12. Tooling

All of it lives in the one `zs` binary and reuses the compiler's lexer, parser and type
checker, so tools can't drift from the compiler.

- **Projects:** `zs.toml` at the root, with `[package]` (`name`, `version`, `main`) and `[dependencies]`.
  - **Path dependencies:** `text = { path = "../text" }`.
  - **Git dependencies:** `json = { git = "https://…", rev = "v1.2" }`, where `rev` is a tag, branch or commit.
    - They're checked out into `.zs-cache/deps/`, and `zs.lock` pins each commit; commit `zs.lock` with the project.
    - `zs fetch` checks them out and `zs update` moves them to the newest commit of their `rev`. The language server never fetches.
  - **Modules:** found next to the importing file, then in each dependency, transitively.
  - **Commands:** `zs new`, `zs build` (to `build/<name>`), `zs run`, `zs test`.
- **Tests:** `[<Test>]` marks a `unit -> unit` function. `zs test` runs each test in its own process, so a failure or panic fails only that test. A failed `assert` names its file and line.
- **Debugging:** `zs build -g` builds at `-O0` with DWARF.
  - gdb breaks on Z# functions and lines, steps, and shows backtraces.
  - Number and bool locals and arguments are visible. Strings, records and unions are **(planned)**.
- **Documentation:** `///` comments above a declaration document it.
  - **Where they show:** hover, completion, the MCP `docs` tool, and `zs doc <file>`, which writes Markdown.
  - **The library:** fully documented, with one reference page per module in `docs/reference` (built-in functions included), which `./test.sh` keeps current.
- **Formatting:** `zs fmt` has one canonical style and no options. Today it's token-based: it re-indents, spaces operators and keeps comments, and the result must lex to the same tokens. Reflowing long lines to 100 columns needs a lossless syntax tree **(planned)**.
- **Editors:**
  - **Grammar:** a tree-sitter grammar (`editors/tree-sitter-zsharp`), for highlighting, indentation and outlines.
  - **`zs lsp`:** diagnostics, hover with types and docs, definition, references, completion, inlay hints, symbols and formatting. Signature help, rename and code actions are **(planned)**.
  - **`zs mcp`:** for AI agents. Tools: `check`, `type_at`, `docs`, `build`, `run`, `emit_llvm`, `format`.
  - **Zed:** a Zed extension (`editors/zed`) packages all three.
- **Diagnostics:** each error gives `file:line:col` and the source line with a caret, and one run reports every error.

## 13. Decisions

| # | Decision | Chosen | Status |
|---|---|---|---|
| 1 | Syntax | F# light syntax, indentation only | decided |
| 2 | Memory | Perceus RC, no GC; borrowing, reuse, moves | decided |
| 3 | `int` width | the machine word (64-bit; 32 on Cortex-M); `i64` always 64-bit | decided (changed for microcontrollers: 64-bit `int` cost 1.5–2× in array loops there) |
| 4 | Integer overflow | traps in every build; explicit wrapping operations, `[<Wrapping>]` planned; division by zero traps | decided |
| 5 | Panics | message (+ backtrace), exit 134, no unwinding, no core dump, can't be caught | decided |
| 6 | Unreachable match case | an error (F# warns) | decided |
| 7 | Array semantics | copy-on-write values; `Buffer<'a>` for shared mutation | decided |
| 8 | Union representation | plain values when non-recursive with ≤ 4 non-heap fields; boxed otherwise | decided |
| 9 | Members / dot methods | yes; type-directed, no inheritance, no overloading | decided |
| 10 | Equality, ordering, hashing, printing | automatic and structural (prelude derives), opt-out attributes | decided |
| 11 | Units of measure | yes, erased, Kennedy unification | decided |
| 12 | Active patterns | total, partial, parameterised | decided |
| 13 | `[ ]` literal | F# immutable cons list; `[\| \|]` is an array | decided |
| 14 | Named/optional/default arguments | default record fields; named/optional/default on members only; none on curried functions | decided |
| 15 | `option` record fields | a default only with an explicit `= None` | decided |
| 16 | Default expressions | any expression, evaluated at the use site, may use earlier fields/parameters | decided |
| 17 | Union case fields | named construction and patterns; no defaults | decided |
| 18 | Record literal type | from the expected type, through branches and elements; else the fields, latest declaration wins | decided |
| 19 | `?` operator | `let p = e?` and statement `e?`; general positions with `result { }` (phase 6) | decided |
| 20 | Code generation by users | `derive` over record and union shapes; no macros, no comptime | decided |
| 21 | Async | one cold `Task<'a>` + `Task.start`; general computation expressions; an effects spike decides CPS vs effects before phase 6 | decided |
| 22 | Threads | v1 single-threaded event loop; multi-threading in v2 | decided |
| 23 | Effect handlers | designed now (§6.1), built in v3; one-shot, evidence passing | decided |
| 24 | Float semantics | strict IEEE; `[<FastMath>]` opt-in per function | default |
| 25 | SIMD API | portable `f32x8`-style value types + target intrinsics | default |
| 26 | From Zig | cross-compilation through `zig cc`. Not adopted: explicit allocators, no-hidden-allocation, comptime | decided |
| 27 | Libraries | source packages (path, git + `zs.lock`), checked Core cached per module; no binary IR format | decided |
| 28 | Strings and `char` | UTF-8 strings, `Length` is bytes; `char` is a Unicode scalar; `for c in s` decodes UTF-8 (malformed bytes become U+FFFD) | decided |
| 29 | Target order | Linux x64/arm64; bare-metal Cortex-M; macOS arm64, Windows x64; WASM | decided |
| 30 | Who it's for first | native libraries used from C, CLI tools, microcontroller firmware; games over C libraries next | decided |
| 31 | Callbacks into C | `callback<A -> R>` = `R (*)(void *user, A)` + `void *user`; borrowed for the call | decided |
| 32 | Editor support | tree-sitter grammar + `zs lsp` + `zs mcp`, Zed extension first | decided |
| 33 | Formatter | `zs fmt`, one style, no configuration; lossless syntax tree for reflow (planned) | decided |
| 34 | Surface syntax | the freeze is lifted. Missing F# syntax comes first (phase L); new non-F# syntax needs a design discussion | decided |
| 35 | Kept in v1 though not yet needed | `ptr<'a>` + `unsafe`, `Arena`, `dyn Trait`, `weak` references | decided |
| 36 | Optimizations that change evaluation order | only for pure code (list fusion requires pure lambdas; printing pieces evaluates them all first) | decided |
| 37 | Library organization | prelude (global names) / Core (no OS: every target) / Std (needs an OS); .NET-style namespaces open everywhere at the lowest precedence; .NET module names, F# function names | decided |

"Default" means chosen by me and open to change until the phase that implements it begins.
