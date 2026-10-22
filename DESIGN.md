# Z# — design

An ML-family language with F# syntax and ergonomics, compiled ahead of time to native code
through LLVM. It has no VM and no tracing GC. Memory is managed by compiler-inserted reference
counting, and it links directly with C.

**Pitch:** F# syntax, OCaml semantics, Zig-style output: one native binary that links straight
against C, from desktop CPUs down to microcontrollers.

**Reading this document:** it describes the language as designed. Anything not built yet is
marked **(planned)**, with the phase or track that builds it. Status and order:
[ROADMAP.md](ROADMAP.md).
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

**"Simple":** a feature has to replace code people would otherwise write by hand, and a
feature that needs a runtime is out. The exception is a small C runtime (allocation, panics,
strings, later the task scheduler and thread pool), linked statically.

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
  - **SIMD vectors** `f32x4`, `i32x8`, `u8x32`, … (§8).
- **Data:** tuples, records (`{ p with x = 1.0 }`), unions; library types `option`, `result`, `list`, `array`, `Buffer`, `ref`, `Map`, `Set`, `HashMap`.
- **Functions:**
  - Curried, with closures (`fun x -> …`), `|>`, `>>` and partial application.
  - **Blocks inside brackets:** inside a bracket, a line ending in `->` (or `then`, `else`, `do`) and deeper lines after it open a block, as at the top level. So `xs |> List.map (fun x ->` can be followed by a multi-line body, and `Parser (fun cs ->` by a `match`. The block ends at the bracket's closer or at a line left of it.
  - **Custom operators:** `let (>>=) r f = …` defines one, and `(op)` is the function (`(+)` too). Precedence comes from the first character after any dots, as in F#: `|>`, `>>`, the comparisons and operators starting with `< > = | & $ !` share one level above `&&`; `@ ^` group like `::`, `+ -` like `+`, `* / %` like `*`, and `**` is right-associative. Operators starting with `!` (but not `!=`) or `~` are prefix: `!r` binds tighter than application.
  - Known calls pass all arguments at once, and so does a closure applied to as many arguments as it takes, so currying costs nothing at run time.
  - Tail calls: a call to itself becomes a loop, and other tail calls with the same signature use LLVM `musttail`. Recursion in tail position runs in constant stack.
- **Loops:** `for i in a .. b do`, `for i in a .. step .. b do`, `for pattern in xs do` (lists and arrays), `while c do`.
- **Pattern matching:**
  - Supports nesting, literals (numbers, characters, strings, bools), tuples, records (`{ x = 0; y = y }`, fields left out match anything), union cases (positional or by field name), lists, guards, `as` and or-patterns that bind variables.
  - Patterns work in `match`, `let`, function parameters (`let norm { x = x; y = y } = …`), lambdas and `for` loops.
  - A match that misses a case is an **error** naming an example of the missing value (`missing case: { kind = C }`). So is a case that can never match.
- **Errors:** `result` with a postfix `?` that returns the error early (`let x = parse s?`, or `parse s?` as a statement). `result { }` does the same for a block, with `let!` (§4).
- **Panics:** for bugs, not errors a caller handles. These all panic: an out-of-bounds index, division by zero, integer overflow, a failed `assert`, an explicit `panic`.
  - A panic prints a message (and a backtrace where the C library supports it), then stops the program at once: no unwinding, no cleanup, exit status 134, no core dump. `ZS_ABORT=1` makes it a real `abort()` for a debugger.
  - Panics can't be caught. So there are no landing pads, and nothing unwinds through C frames.
  - In a C program that uses a Z# library, a panic ends the host process too. `zs_set_panic_hook` lets the host log, flush or save its state first (§11).
- **Strings:** `$"x = {p.x}"` interpolation, where any expression with `Show` can go in a hole. `+` joins strings. A string can span lines (its line breaks are part of it), and `"""…"""` is raw: quotes and backslashes stay as written.
- **Modules:** one file is one module, with `open`, qualified names and `private`. `module Name` on the first line renames it.
  - **Namespaces:** `namespace X` on the first line makes the file's types and modules `X.Name`, as in F#. The library uses it to put `type Map` and `module Map` side by side in `Collections`.
  - **Fields, traits and derives belong to their module,** like types. A record literal, a record pattern, or `.f` on a value whose type isn't known yet, looks among the records in scope: the current module and the ones it's in, then opened modules, global names and the auto-opened namespaces, the nearest first. A trait's methods are called by name where its module is in scope, and by `Module.method` elsewhere.
  - **Nested modules:** `module Inner =` and an indented block. Names inside are `Outer.Inner.x`; the block sees the names of its enclosing modules, `private` reaches the modules nested inside, and an `open` lasts until the block ends.
- **Type inference:** Hindley–Milner, so annotations are optional. `(e: T)` in an expression gives a literal or a record literal its type.
  - **Dot resolution is type-directed, as in F#:** `x.M` needs `x`'s type known where it's read. Otherwise the error says to annotate `x`.
  - **Lambda arguments are typed last:** a lambda without parameter types is typed after the call's other arguments, with the parameter types the call expects. So `names |> List.map (fun s -> s.Length)` works, and so does `List.map (fun s -> s.Length) names`, which F# rejects. A lambda with annotated parameters keeps its place, so its types still reach the arguments after it.
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
  - There is no inheritance and no overloading (one member per name), which keeps inference predictable (§2.1).
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
  - **Without an expected type:** the fields must identify the record, among the records in scope (see Modules in §2.1). When two of those share all the given fields, the nearest scope wins, then the later declaration, as in F#.
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
  - **`dyn Trait`:** for heterogeneous collections and plugin APIs, a value of any type implementing the trait. It's a heap object holding the value and a pointer to a table of its type's impl (built when the value is made, at its type), so a call is one indirect call. A value becomes a `dyn` where one is expected (a declared type, a parameter, a result), with no conversion written. A trait can be `dyn` when each of its methods takes the value first and doesn't mention its type elsewhere: `Show` can, `Ord` can't.
- **Operators are traits:** `Add` (`+`, `zero`), `Num` (`- * / %`, negation), `Eq`, `Ord`. They have built-in impls for primitives, and user types implement them with `impl`.
- **Built-in derives:** `Eq`, `Ord`, `Hash` and `Show` come from prelude derives (§3.1), applied automatically the first time a type needs them. An `impl` overrides them.
- **Auto traits:** `Share` (§7) is derived structurally by the compiler, and can't be implemented by hand.

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
  - **Names:** trait methods named inside a derive mean the trait's, as the derive's own module sees them, even where a program defines a function of the same name.
- **Generics and recursion:** deriving for `Tree<'a>` adds `'a : Json` to the impl. Recursive types work because impls are monomorphized.
- **Cost:** none at run time. The expanded impl is ordinary code, and no type metadata is in the binary.
- **Not included:**
  - Derives can't add members, types or other declarations.
  - There are no field attributes yet, such as renaming a JSON key.
  - Declarations generated from a schema, as F# type providers do, would be a later generalization of `import c`.

## 4. Computation expressions

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

A builder is a **module**, not an object, so it resolves statically and inlines: `w { }` uses
`W.Builder` (`option { }` is `Option.Builder`, `result { }` `Result.Builder`). The parser rewrites
the forms into calls of its functions:

| Form | Rewrites to |
|---|---|
| the whole body | `B.delay (fun () -> body)`, so a cold computation (a task) runs it when it runs |
| `let! x = m in rest` | `B.bind m (fun x -> rest)` |
| `do! m` | `B.bind m (fun () -> …)` |
| `return e` / `return! m` | `B.ret e` / `m` |
| `use x = e` | `B.using e (fun x -> …)` |
| `for x in xs do` | `B.forEach xs (fun x -> …)` |
| `if c then m` (no else), or a body ending in a statement | `B.zero ()` on the missing branch |

**Checking a builder:** a form whose function the builder lacks is a compile error at that
form, naming it (`counter { } needs Counter.Builder.bind, for let! and do!`). DESIGN first had a
`Builder` trait check this, but a builder's functions are over a type constructor (`bind`
takes an `M<'a>` for any `'a`), which Z#'s traits, over one type, can't name; the check per
form says the same, where it matters.
- **`task { }`** is the one the compiler makes itself (phase 9): its body stays in direct style, its waits (`let!`, `do!`, `return!`) marked, and it becomes a state machine (§6), so a wait allocates no continuation.
- **Outside builders:** `use x = e` in plain code disposes `x` after the rest of its block.

## 5. Memory

### 5.1 Representation

- **Plain values:** these live in registers or on the stack and are copied.
  - **Which types:** numbers, `bool`, tuples, records, and **small unions**: unions that aren't recursive and have at most 4 fields over all their cases, none of them heap data.
  - **Small unions:** these are a tag plus fields, e.g. `option<int>`, `result<int, f64>`, enums, and state machines with number fields. They never allocate.
  - **Enums:** a union whose cases have no fields is one byte, so an array of them is a byte per element. Other small unions have a 32-bit tag, which costs no space next to their fields and no extension on a 32-bit chip.
- **Heap objects:** strings, arrays, `Buffer`, `ref`, closures, lists, and the other unions.
  - **Header:** each object starts with one word: a 32-bit reference count, and on a 64-bit target beside it the case tag of a union cell (when the union has more than one case with fields) and where the object came from (the pool's size class, §5.2). On a 32-bit chip the count is the word, and a union cell with a tag has a word for it after. Strings and arrays add a word-sized length, closures their code and a pointer to what describes them (§9.1). A list cell is the header, the head and the tail.
  - **The count's range:** past 2³¹ references, a count turns negative and stays so: the object is never freed, as Koka's sticky counts. (Koka's header also has the number of fields to scan, for a generic drop; Z#'s drops are generated per type.)
  - **Cases without fields** (`[]`, `Leaf`, `None`) are static cells, told apart from the others by their address, so a match tests a pointer and loads nothing.
  - **The `option` niche:** a union of `option`'s shape (one case without fields, one with a single field) whose field is a pointer, such as `option<string>` or `option<list<int>>`, is that pointer, or one static object for `None`. `Some s` allocates nothing.
  - **Static objects:** string literals, constant constructors and the cases without fields are static objects, with count 0, never freed.
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
| **Borrowed fields** | The fields a match takes from a value that stays alive past it are borrowed from that value, not dup'd; the value lives until their last use |
| **Re-matching** | In `match x with C (a, b) -> if c then f a else x`, the branch where `x` dies matches it again, so that branch takes the cell apart and can reuse it although the other returns `x` |
| **Moves out of mutables** | `x <- f x`, and `let r = f … x …` when `x` is reassigned before its next read, give `f` `x`'s own reference. So a unique value stays unique, and copy-on-write and reuse happen in place |
| **Copy-on-write in loops** | An array a loop writes, and doesn't otherwise share, is made unique once before the loop; the writes inside skip the check |

**Cycles:** immutable data can't form cycles, because a value can only point to values built
before it. Mutable cells can: a `ref` or `Buffer` holding a value that points back to it
(directly, or through a closure that captures it).
- **What happens:** RC never frees such a cycle. It leaks silently, and it stays memory-safe. There is no cycle collector, which would need a GC's tracing.
- **Avoiding them:** back-pointers (a child's parent, a list of observers) are `weak<'a>` references, which don't keep their object alive: `Weak.get w` is `Some x` while it lives. Otherwise, breaking a cycle is the program's job, as in Swift.
  - **How:** the weak references to an object share a cell { count, object }, found from the object through a table. An object dying empties its cell: when it's freed, and when Perceus reuses its cell for another object, which the reuse reports.
  - **Who pays:** only a program with weak references (or arenas) allocates and frees through the runtime's checked functions; the others' code is what it was.
- **Finding them:** `ZS_LEAKCHECK=1` reports the objects still allocated at exit, so a test suite run with it (as `./test.sh` runs the compiler's) catches a cycle the tests make.

**Escape hatches:** `Arena.with (fun () -> …)` for bulk allocation that's freed at once, and raw
`ptr<'a>` inside `unsafe` expressions (§11).
- **The pool:** in a program without threads, objects up to 256 bytes come from the runtime's pool: a free list per 8-byte size class, carved from 64 KB chunks, with each object's class in its header (§5.1). Freeing one puts it on its list, and the next object of that size takes it, so allocating and freeing tiny objects calls no system allocator, and ThinLTO inlines both into the program (`binarytrees` takes 0.26× C's time, which calls `malloc` and `free` for each node, and 23% less memory: a node is 24 bytes, where `malloc` gives C's 32). Larger objects, programs with threads, and sanitizer and valgrind builds (`ZS_NO_POOL`) use `malloc`. The pool keeps its chunks until the program ends.
- **Arenas:** what the function allocates comes from the arena's 64 KB blocks, bumped through, one malloc each. An object dying frees nothing, and the blocks go together when the arena's last object has: when the function returns, or later if something it made lives on. So an arena can't be misused into a dangling pointer, and needs no escape analysis or annotations. Objects in an arena are counted as any others; only their memory is the arena's.

### 5.3 What code without `unsafe` guarantees

| Guarantee | Mechanism |
|---|---|
| No use-after-free or double free | Reference counting; a value dies with its last reference |
| No null | `option<'a>` |
| No uninitialised reads | Every binding has a value; arrays are created filled |
| No out-of-bounds access | Indexing is bounds-checked; in loops the checks are proved once before the loop where possible (§9) |
| No data races | `let mutable` can't be captured; what crosses threads is `Share` (§7): immutable, or made for threads |
| Deterministic cleanup | RC, plus `use`, which also runs when a task is cancelled |
| No silent overflow | Integer overflow traps in every build, as in Swift. Wrapping is explicit: `Int.wrappingAdd`, `Int.wrappingSub`, `Int.wrappingMul`, or `[<Wrapping>]` on a function, whose integer `+ - *` wrap. Division by zero traps |

**Not guaranteed (and still memory-safe):** leaks through cycles of `ref` cells or `Buffer`s (§5.2).

**Unsafe on purpose:** `extern` calls, `Mmio.*` register accesses, and `unsafe` expressions
with raw pointers (§11).

## 6. Concurrency: `Task`

> **Decision gate (before phase 6), decided: CPS.** A time-boxed spike compiled one built-in
> `Async` effect by evidence passing with yield bubbling, against CPS, by hand
> ([the report](docs/reports/effects-spike.md)). At run time the effect is better: an await that
> completes at once allocates nothing (CPS: 5 allocations), and one that suspends 2 (CPS: 7). But
> knowing which calls may yield takes effect rows on every function type, polymorphic through
> generic code such as `List.iter`, which is phase 10's work; without them, every closure call
> would pay, or `await` outside a task would compile. So the CPS design below stands, phase 9's
> state machines take the allocations away, and phase 10 may move `Task` onto an `Async`
> effect. The `Task` API in this section is what users see either way.

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

- **Implementation:** a library (`lib/std/Threading/Task.zs`) and a compiled form for `task { }`. A task is its result when it has one at once (`Task.ret`), else its work, given its cancellation and a continuation.
  - **`task { }` is a state machine** (phase 9): its work is an LLVM coroutine, whose frame is allocated once, when the work starts, behind a closure header (the face). A wait on a task whose result is ready goes on at once. Otherwise it passes the face as that task's continuation, with the face's code set for the result's type (it stores the result and resumes the coroutine), and suspends. So a wait allocates nothing: a task waiting 200,000 times allocates what one waiting 10 times does (`tests/task/awaits.zs`).
  - **Cancellation:** a task cancelled while it waits is let go by what it waits on, which drops its continuation, the face; a wait that finds its task cancelled already suspends for good. Either way the face's last reference going destroys the coroutine at that wait, dropping what the task held there (reference counting records it at each wait), and the cancellation disposes its `use` values.
  - A loop that waits repeatedly settles into steady memory. The echo server holds 10,000 connections in 21 MB, flat for the hour of a soak test (`bench/echo/soak.sh`: 32.6 million round trips, none failed).
  - **The stack:** a continuation called inside another (an await that completes at once) is counted, and the 64th goes through the event loop instead, so a run of them doesn't grow the stack.
- **Structured concurrency:**
  - Child tasks can't outlive the scope that started them: `Task.both`, `all`, `race` and `timeout` wait for theirs, and `Task.scope` for those `Task.start` started in it (a `Promise` gives each one's result).
  - Cancellation flows down: a task's cancellation has its children's under it, and a race cancels its loser.
  - Cancelling a task drops what it waits on (its continuation, so RC releases what that captured) and disposes what it bound with `use`, newest first.
- **Event loop:** C in `runtime/rt.c` over epoll (kqueue comes with macOS, track T; io_uring later): callbacks waiting for descriptors, timers in a heap, and a queue of ready callbacks, all Z# closures the loop owns. Each thread has its own loop, and `Task.spawn` runs a task on another thread's (§7).
- **Blocking C calls:** `Task.blocking (fun () -> sqlite3_step db)` moves the call to a helper thread, which signals the loop through a pipe when it's done. The function is a `share<…>` (§7): what it captures can be shared between threads, and is marked shared before it goes.

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

## 7. Parallelism

**Concurrency** (`Task`, waiting on I/O) and **parallelism** (using all cores) are separate APIs.
Each is in the C runtime: a thread pool for parallel work, and an event loop per thread for
tasks.

```fsharp
let rows = matrix |> Array.Parallel.map (fun row -> Array.sum row)
let (a, b) = Parallel.both (fun () -> fib 35) (fun () -> fib 36)
let squares = Array.Parallel.init n (fun i -> i * i)
```

- **Thread pool:** work stealing with Chase–Lev deques (Lê et al.'s C11 version), a thread per core (`ZS_WORKERS` sets the number). Fork-join: `Parallel.*` halves its range until a part is about 1/32 of a thread's share, forking one half; a join runs the job itself if no one stole it, and other jobs while it waits.
- **What crosses: the `Share` trait,** like Rust's `Send` but with no lifetimes. A value may cross threads only if it's immutable or made for threads. Immutable-by-default means nearly all data qualifies.
  - **Share:** numbers, `bool`, `char`, `string`, and records, unions, tuples, lists and arrays (they're values) whose parts are Share; `share<F>` functions; `Atomic`, `Mutex` and `Channel`.
  - **Not Share:** `ref`, `Buffer`, `weak`, `dyn` values, C pointers, and plain functions.
  - **`share<F>`:** a function another thread may run, as Swift's `@Sendable`. A function type doesn't say what a closure captures, so a function that crosses threads has this type: `Parallel.both : share<unit -> 'a> -> share<unit -> 'b> -> 'a * 'b`. A lambda, a local function or a top-level function where one is expected is checked there: what it captures must be Share, looking through the local functions it captures. A `share<F>` is called, and passed where an `F` is expected, as any function.
  - **Top-level values:** a top-level `ref` isn't captured but reached. After monomorphization, when every trait call has its impl, the compiler follows each `share<F>`'s calls; reaching a top-level value that isn't Share is an error. The top-level values that are Share are marked shared at startup in a program with threads.
- **Disjoint results instead of disjoint writes:** `Array.Parallel.init` builds each part of the array on the thread that computes it, and joins the parts; nothing writes into one array from several threads. A job's result goes back to the thread that joins it without being marked: it belongs to that thread alone.
- **Reference counts across threads** (as in Koka and Lean): RC is non-atomic by default. When a value is sent to another thread, its object graph is marked *shared* once, and only those objects use atomic RC from then on (§7.1).
- **Library:** `Parallel.both`, `for` and `reduce`; `Array.Parallel.init` and `map`; `Atomic` (lock-free, for numbers, `bool` and `char`); `Mutex` (a futex lock, `Mutex.update` under it); `Channel` (bounded, any number of senders and receivers).
- **Tasks on every core:** each thread has its own event loop. `Task.spawn` hands a `share<unit -> Task<'a>>` to one of a set of loop threads (a thread per core), where the task runs to the end; its result comes back through the spawning loop's inbox (a pipe the loop's epoll watches). `Task.blocking`'s helper thread uses the same inbox. A task never moves between threads: what it holds can be thread-local.
- **Testing:** `--sanitize=thread` builds with ThreadSanitizer, which `./test.sh` runs over the parallel and spawning tests. The deques use release/acquire and sequentially consistent operations rather than fences, which ThreadSanitizer doesn't model.

### 7.1 How a value crosses threads

Written down before the optimizer was tuned (phase 5), so that phase 7 didn't undo its work.

- **The count's sign is the mark,** as in Lean 4. A count above 0 is a thread-local object, 0 is a static one (never freed), and below 0 is shared: changed only with atomic operations, and freed by whichever thread drops the last reference.
- **The fast path is the same as without threads:** `dup` tests `count > 0`, and a drop tests `count = 1`, then `count > 1`. A static or shared object takes the other branch, where a program with threads has the atomic operations (and a program without them skips the count). So a program that never starts a thread runs the code it always did.
- **Where values cross:** the `share<F>` functions given to `Parallel.*`, `Task.spawn` and `Task.blocking`, `Channel.send`, and what goes into a `Mutex`.
- **Marking:** at a crossing, compiled code walks the value's object graph (a function per type) and makes each thread-local count negative. It stops at objects already shared or static, so it visits each object once: sending the same value again costs one test. A closure's description has the function that marks what it captured.
- **Dropping a cell's fields:** Perceus's specialized drop takes the fields it keeps out of a cell that dies. With threads, a cell that isn't unique may be another thread's too: its kept fields are dup'd before its reference goes, since after it the other thread may free it.
- **What can't cross:** `ref`, `Buffer` and closures that capture them (the `Share` trait), so a shared graph is immutable. Mutation across threads goes through `Atomic`, `Mutex` or `Channel`.
- **Uniqueness:** a shared object's count is never 1, so reuse and copy-on-write copy it instead of writing in place. Thread-local data, which is most data, keeps every optimization in §5.2. Shared data pays for atomic counts and copies.
- **Not chosen:**
  - **Atomic counts everywhere,** as in Swift: every count pays for the rare shared value.
  - **Copying at the crossing,** as in Erlang, or allowing only unique values to cross: a parallel map over one large shared tree, the common case, needs sharing.

## 8. SIMD

There are three levels, from free to manual.

1. **Autovectorization:** the compiler emits IR that LLVM can vectorize.
   - Arrays of plain values are contiguous.
   - Element access uses `inbounds nuw` addressing, and lengths carry range metadata.
   - Bounds checks move out of loops (§9): a `for` loop with a constant step checks the reads at its index, plus or minus values it doesn't change, once before it runs.
   - Floats are strict IEEE by default. `[<FastMath>]` on a function makes its float `+ - * /` LLVM's `fast` ones (the type checker marks them, as `[<Wrapping>]` does integers'), so reductions vectorize.
2. **Portable vector types** (like Zig's `@Vector`, C#'s `Vector128`):
   - Every number type at 128, 256 and 512 bits (`f32x4`, `f32x8`, `f64x2`, `i32x8`, `u8x32`, …) is a built-in type, LLVM's `<n x T>`, and lane-wise comparisons give masks (`mask4`, LLVM's `<4 x i1>`).
   - **Operators** through `Add`, `Num` and `Eq` (`=` on whole vectors). Integer vectors wrap on overflow, as SIMD instructions do; integer division checks every lane. Bitwise operators and shifts on integer vectors.
   - **Functions** in a module per type (`F32x8.load`): `splat`, `init`, `load`, `store`, `get`, `set`, `sum`, `min`, `max`, `reduceMin`, `reduceMax`, `abs`, the comparisons, `select`, `shuffle` (constant indices), conversions between vectors with as many lanes (floats saturate into integers), and `sqrt`, `floor`, `ceil`, `round`, `mulAdd` for floats. Each is an LLVM instruction or intrinsic, which LLVM splits or scalarizes where a target lacks it.
   - **Memory:** `load` and `store` take an array of the element type and an index; `store` gives the array back, in place when unique, as `Array.set` does. A program with 32- or 64-byte vectors allocates its objects 64-byte aligned (`zs_alloc_wide`), so a vector field or element is as aligned as LLVM expects.
3. **Target intrinsics:** `Simd.X86` and `Simd.Arm`, thin wrappers over LLVM's intrinsics (`rsqrt8`, `shuffleBytes16`, `tableLookup16`, …), each for its architecture. One that needs a feature beyond the target's baseline (SSE2, NEON) is a compile error unless `--cpu` or the function's attributes provide it.
   - **Choosing the CPU:** `--cpu=native|x86-64-v3|…` for the whole program (clang's `-march`, or `-mcpu` off x86), or per function with `[<Target "avx2,fma">]` (LLVM's `target-features`; such a function isn't inlined into others).
   - **Choosing at startup:** `[<Multiversion("avx2,fma", "sse4.2")>]` compiles a version for each and one for the baseline; the function's own name is a dispatcher that asks the runtime (`zs_cpu_supports`: cpuid on x86-64, the auxiliary vector on aarch64 Linux) the first time and calls the first version the CPU has.
- **Performance:** `bench/simd` (a dot product, an n-body step over 1,024 bodies, a 3×3 blur) runs within 10% of C with AVX or NEON intrinsics, from one source on x86-64 and on aarch64.

## 9. Compiler

```
 .zs ─► Lexer (offside rule) ─► Parser ─► AST ─► import c (clang)        Syntax, CImport
     ─► Type check: HM + kinds + traits + units, exhaustiveness ─► Core   Typer, Match, Derive
        (the library's and other modules' checked state from the cache)   Snapshot, Driver
     ─► Monomorphize (trait dispatch, units erased) ─► fusion             Mono
     ─► Uncurrying, inlining of small functions                           Inline
     ─► Known constructors, case of case, lambdas applied in place        Simplify
     ─► Decision trees for matches, with join points                      Decide
     ─► Closure conversion, lambda lifting                                Lift
     ─► Perceus: ownership, borrowing, moves, reuse, drop specialization  Rc
     ─► LLVM IR (textual), a module per source file                       Codegen
     ─► clang -O2/-Os per module, in parallel, cached ─► ThinLTO link     Driver
```

- **Implementation language:** F# (.NET 10). Self-hosting is optional and late (phase 11).
- **Reading the optimizer:** `ZS_DUMP_CORE=name` prints the Core of the functions whose name contains `name`, after reference counting. `ZS_NO_DECIDE=1` compiles matches clause by clause, for comparison. `ZS_NO_CACHE=1` checks everything again instead of using the cache.
- **Backend:** textual LLVM IR passed to clang, so reading the `.ll` file is the debugger (`--emit-llvm` writes the whole program as one module). A switch to the LLVM C API was to come when compile time demanded it, and phase 9 measured that it doesn't: parsing the text is 2.6% of clang's time on a program's 8 MB of IR, and the module cache skips the IR of unchanged modules.
  - **Linking:** a host build compiles the modules and the runtime to bitcode and optimizes them together at the link (ThinLTO, lld, with its cache), so the runtime's allocation functions inline into the program. `--profile-generate` and `--profile-use <file>` add PGO; a module's IR names it after its source file, so a profile finds its internal functions in the next build. On microcontrollers the runtime stays a separate object: as bitcode it changed nothing at `-Os` and cost 1.4–3.1 KB of flash at `-O2` ([the report](docs/reports/microcontrollers.md)).
  - **A module per source file:** a host build of a program of several files makes one LLVM module per file, with a copy of each library function and generic instance it uses, so LLVM inlines within a module as it would in one big one; what needs one address in the program (top-level values, the static cells of cases without fields) is defined in each and merged by the linker. A single-file program, and `--emit-llvm`, `-g`, `--lib`, `--sanitize`, cross and microcontroller builds, are one module.
  - **Compiled once:** the modules and the runtime compile in parallel, and each object is kept in `~/.cache/zs/objects` under a hash of its IR. Every pass names what it makes per function, so a file whose functions didn't change gives byte-identical IR, and a rebuild compiles only the modules whose code changed.
  - **The module cache** (phase 9): each module's object is also kept in `~/.cache/zs/modules` under a key of what its code is made from: the compiler and its settings, the program's types, the module's functions after lambda lifting (a structural hash) with their borrowed parameters, and the signatures of what it calls in other modules. A module whose key is there skips reference counting, LLVM IR and clang. The passes before, and the analysis of borrowed parameters, run over the whole program, since a module's code depends on them.
  - **Every core:** the passes that work per function (simplification, decision trees, lifting, reference counting) and code generation per module run in parallel.
- **Runtimes:** `runtime/rt.c` on an OS, and `runtime/rt-embedded.c` on bare metal (§10). Each is one C file, linked statically.
- **Generics across libraries:** libraries are **source**, as in Go and Zig.
  - **How they're used:** a dependency's modules are type-checked with the program and monomorphized at the program's types.
  - **Speed:** a build caches the type checker's state after the library, and after the main file's other modules, in the user's cache directory (`~/.cache/zs/checked`), keyed by a hash of the compiler and of those modules' sources. A build whose library and other modules haven't changed starts from there and checks only the main file; one whose main file's modules changed starts from the library. Editors and `zs doc` check everything, since they need every hover.
  - **No IR format:** there's no binary format to version. Closed-source code ships as an `[<Export>]` C library.
- **The library** (`lib/`) is Z#, in three layers:
  - **Prelude** (`lib/prelude.zs`): the global names: the operator traits and their derives, `option`, `result`, `id`, `fst`, `min`, ….
  - **Core** (`lib/core`): what needs no operating system, so every target has it: collections, text, options, results, `Math`, `Mmio`.
  - **Std** (`lib/std`): what needs one: `Console`, `Environment`, `IO`, `Diagnostics`, `Threading` and `Net`. A microcontroller build doesn't load it, and a name from it is a compile error that says why.
  - **Namespaces, as in .NET:** `Collections` (`List`, `Array`, `Buffer`, `Map`, `Set`, `HashMap`), `Text` (`String`, `Char`), `IO` (`File`, `Directory`, `Path`), `Diagnostics` (`Process`, `Stopwatch`), `Threading` (`Task`) and `Net` (`Tcp`). They are open in every module at the lowest precedence, so `List.map` is `Collections.List.map` unless a program defines its own, and full names work too.
  - **Names:** modules have .NET's names (`Directory`, `Environment`, `Stopwatch`) and functions F#'s style (`File.readAllText`, `Directory.list`, `Environment.getVariable`).
  - **Built-in functions:** what the runtime provides is built into the compiler under its full name (`Text.String.length`, `IO.File.exists`). The operating-system calls the library wraps are under `Native`, which programs don't use.

### 9.1 Optimization strategy

LLVM is excellent at scalar loops and register allocation. It knows nothing about closures,
unions or which values are unique, so Z# does the functional-language optimizations itself,
and gives LLVM the facts it can't prove.

| Layer | Optimization | Status |
|---|---|---|
| Representation | Small non-recursive unions as plain values; enums as bytes | done |
| Representation | Cases without fields are static cells, matched by address; a union cell has a tag only when several cases have fields; `option<string>` and other unions of `option`'s shape over a pointer are the pointer (no cell for `Some`) | done |
| Mono | Fusion: a pipeline of `map`s and `filter`s from `List.init`, a list, `Array.init` or an array into `sum`/`sumBy`/`fold`/`length`/`iter` is one loop; one of several stages that builds a list or an array builds only that. Pure lambdas only (decision 36) | done |
| Core | Uncurrying: a function whose body is a lambda takes its parameters (`let f x = fun y -> …` has two); a closure applied to several arguments calls code taking them all when it takes that many, through the closure's static description (drop function, arity, full entry), instead of building a closure per argument | done |
| Perceus | Ownership, drop specialization, reuse, borrowing, moves out of mutables, borrowed reads and fields, re-matching | done |
| Codegen | Copy-on-write checks hoisted out of loops; loop versioning that proves bounds once for innermost call-free loops | done |
| Codegen | Overflow checks via `llvm.*.with.overflow`, which LLVM drops when ranges prove them safe | done |
| Codegen | `print` of an interpolation prints the pieces, without building the string | done |
| LLVM facts | `!range` on lengths, `inbounds nuw` element access, `noalias` allocator with `allockind`, `inlinehint` on higher-order functions, `optsize` at `-Os` | done |
| Core | Inlining of small functions. Decision trees for matches: no value is tested twice, and a part reached on several paths is a join point (a block with phis) that reuse tokens pass through | done |
| Core | Known constructors: a match on a value whose case is known (built there, bound by `let`, or taken by an enclosing case) takes its case at compile time, testing inside its fields directly. Case of case: a match on a match or an `if` moves into its branches, with join points for bodies several reach. A lambda bound by `let` and only called is applied in place. So an inlined `Option.map` or `Result.bind` and the match on its result build no `option` or `result` | done |
| Representation | A one-word object header: a 32-bit count, a union cell's tag and the pool's size class (64-bit targets). The pool: free lists of 8-byte size classes, inlined into the program | done (phase 9) |
| Linking | ThinLTO with the runtime, PGO | done (phase 9) on the host. On microcontrollers the runtime stays separate: as bitcode it changes nothing at `-Os` and costs flash at `-O2` |

**Performance contract:**
- **Microcontrollers:** the suite in `bench/mcu` compares each program with its C version (same clang, same chip, under QEMU) [(results)](docs/reports/microcontrollers.md).
- **Host:** the suite in `bench/host` (fib, binary-trees, nbody, spectral-norm, the red-black tree) compares each program with C (also built with `-ftrapv`, whose overflow traps match Z#'s), Rust, Swift, Zig, OCaml and F# on .NET [(results)](docs/reports/host.md). A regression of more than 5% in instructions fails the build.
- **Compile time:** `bench/compile/run.sh` builds a generated program of modules from nothing, then after a one-function change in the main file and in a module.

## 10. Targets

| Tier | Targets | How |
|---|---|---|
| 1 | Linux x86-64 and aarch64 | native, or `--target aarch64-linux-musl` (static) |
| 2 | Bare-metal ARM Cortex-M: `cortex-m4` (M4F), `cortex-m0plus` | `--target cortex-m4`; tested under QEMU |
| 3 | macOS aarch64, Windows x86-64 | through `zig cc` (planned, targets track) |
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
- **What's missing:** Std, the part of the library that needs an operating system (`Console`, `Environment`, `IO`, `Diagnostics`, `Threading`, `Net`). A microcontroller build doesn't load it, and using it is a compile error that says why (§9).
- **Hardware:** `Mmio.read32/write32/read8/write8` are volatile register accesses, and `Runtime.ticks ()` counts cycles.
- **Registers as constants:** a top-level constant such as `let uart = usize 0x40004000` is inlined, so a register access compiles to a store to an immediate address.
- **Planned (microcontroller track):** interrupt handlers (`[<Interrupt "SysTick">]`), constant arrays in flash, RISC-V (ESP32-C3) and more boards (linker scripts in `runtime/boards`).
- **No allocation (planned, microcontroller track):** `[<NoAlloc>]` on a function is a compile error if it, or anything it calls, may allocate or free heap memory. Firmware needs to know where the heap is touched, and Z# allocates implicitly (strings, closures, boxed unions).
  - **The error** names the call chain down to the allocation.
  - **What's checked:** Z#'s own IR, after borrow inference, unboxing and list fusion, so the result doesn't depend on `-O`, and a fused pipeline or a small union passes. Freeing counts too, since dropping a reference can free a chain of objects.
  - **Externs** count as not allocating: C is outside the check.
  - **Interrupt handlers** are `NoAlloc` implicitly, since the allocator isn't reentrant.
  - **`--no-heap`:** the whole program is checked, and the image has no heap.

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
  - **Structs:** `[<CLayout>]` records, passed by value. On x86-64, a struct whose parts don't all fit in the argument registers left goes on the stack whole, as C passes it.
  - **Callbacks:** `callback<A -> R>`, a function pointer plus `void *` user data.
  - **Raw pointers:** `ptr<'a>` to C data, with `Ptr.read`, `write`, `add`, `alloc`, `free` and `cast` inside `unsafe` expressions (an expression or an indented block), outside of which they're compile errors.
  - **C function pointers:** `fnptr<A -> B -> R>` is `R (*)(A, B)`, called like a function inside `unsafe`, with C's conventions.
  - **Z# objects:** any other reference-counted value (a union's cell, a list, a closure, a `dyn` value) crosses as an opaque `zs_handle` with its own count, `zs_retain` and `zs_release` in the generated header. A handle a function returns is the caller's; one passed in is lent for the call.
- **`import c`:** clang reads the header, with `-ast-dump=json` for declarations and `-E -dD` for macros. Only what that header itself declares is imported.
  - **What comes across:**
    - functions, which become externs;
    - structs, named or `typedef`'d, which become `[<CLayout>]` records;
    - enum values, which become constants, as do `#define` numbers, strings and struct literals such as `CLITERAL(Color){ … }`.
  - **Types:** `char*` becomes `cstr`, other pointers `cptr`, and enum types `i32`. `long` follows the word; `long long` is `i64`.
  - **Function pointers** (struct fields such as `double (*area)(double, double)`, typedef'd or not) become `fnptr` types.
  - **What's left out:** unions, arrays, `static inline` functions and opaque structs by value. Using one gives an error that says why.
  - **Caching and editors:**
    - The header is found next to the importing file, then on the system path.
    - The result is cached in memory, and saved with a copy of the header in `.zs-cache/cimport/`, so editors without clang or the header still get it.
    - In the editor, hover shows the C declaration and the header's comment.
- **Exporting:** `[<Export "name">]` functions must be monomorphic, with C types only. `zs build --lib` produces a static library (`.a`) and a header (`.h`).
  - **Shared libraries:** an output ending in `.so` is one. The archive's code is position-independent too, so a C shared library can link it whole (`--whole-archive`).
- **Panics in a C host:** a library reports the errors its caller can handle as `result`. A panic is a bug in the library, and it ends the host process, as Rust's `panic = "abort"` does.
  - **The hook:** `zs_set_panic_hook(void (*hook)(const char *message))`, declared in every generated header, runs after the message is printed. It can log, flush or save the host's state, or end the process its own way (`exit`). If it returns, the process stops as before.
  - **No calls back:** the hook must not call into the library, whose state is undefined after a panic.
  - **A host that must survive a library's bugs** runs it in a separate process.
- **Callbacks:** a C `void (*cb)(void *user, …)` paired with `void *user` receives a Z# closure; the compiler generates the thunk. The closure is borrowed for the call, so a callback can't be stored by C.
- **With `Task`:** a blocking C call goes through `Task.blocking` (§6).

## 12. Tooling

All of it lives in the one `zs` binary and reuses the compiler's lexer, parser and type
checker, so tools can't drift from the compiler.

- **Projects:** `zs.toml` at the root, with `[package]` (`name`, `version`, `main`) and `[dependencies]`.
  - **Path dependencies:** `text = { path = "../text" }`.
  - **Git dependencies:** `json = { git = "https://…", rev = "v1.2" }`, where `rev` is a tag, branch or commit.
    - They're checked out into `.zs-cache/deps/`, and `zs.lock` pins each commit; commit `zs.lock` with the project.
    - `zs fetch` checks them out and `zs update` moves them to the newest commit of their `rev`. The language server never fetches.
  - **Modules:** found next to the importing file, then in each dependency, transitively.
  - **Commands:** `zs new`, `zs build` (to `build/<name>`), `zs run`, `zs check`, `zs test`. Builds take `-g`, `-Os`, `--target`, `--lib`, `--emit-llvm`, `--sanitize` and `--time`.
- **Tests:** `[<Test>]` marks a `unit -> unit` function. `zs test` runs each test in its own process, so a failure or panic fails only that test. A failed `assert` names its file and line.
- **Debugging:** `zs build -g` builds at `-O0` with DWARF.
  - gdb breaks on Z# functions and lines, steps, and shows backtraces.
  - Locals and arguments are visible when they are numbers, bools, chars, strings (shown as their text), or tuples, records and plain unions of those (a union as its case and fields).
- **Documentation:** `///` comments above a declaration document it.
  - **Where they show:** hover, completion, the MCP `docs` tool, and `zs doc <file>`, which writes Markdown.
  - **The library:** fully documented, with one reference page per module in `docs/reference` (built-in functions included), which `./test.sh` keeps current.
- **Formatting:** `zs fmt` has one canonical style and no options. Today it's token-based: it re-indents, spaces operators and keeps comments, and the result must lex to the same tokens. Reflowing long lines to 100 columns needs a lossless syntax tree **(planned, editor track)**.
- **Editors:**
  - **Grammar:** a tree-sitter grammar (`editors/tree-sitter-zsharp`), for highlighting, indentation and outlines.
  - **`zs lsp`:** diagnostics, hover with types and docs, definition, references, completion, inlay hints, symbols and formatting. Signature help, rename and code actions are **(planned, editor track)**.
  - **`zs mcp`:** for AI agents. Tools: `check`, `type_at`, `docs`, `build`, `run`, `emit_llvm`, `format`.
  - **Zed:** a Zed extension (`editors/zed`) packages all three.
- **Diagnostics:** each error gives `file:line:col` and the source line with a caret, and one run reports every error.

## 13. Decisions

| # | Decision | Chosen | Status |
|---|---|---|---|
| 1 | Syntax | F# light syntax, indentation only | decided |
| 2 | Memory | Perceus RC, no GC; borrowing, reuse, moves | decided |
| 3 | `int` width | the machine word (64-bit; 32 on Cortex-M); `i64` always 64-bit | decided (changed for microcontrollers: 64-bit `int` cost 1.5–2× in array loops there) |
| 4 | Integer overflow | traps in every build; explicit wrapping operations and `[<Wrapping>]` functions; division by zero traps | decided |
| 5 | Panics | message (+ backtrace), exit 134, no unwinding, no core dump, can't be caught; a C host can set a hook that runs first (`zs_set_panic_hook`) | decided |
| 6 | Unreachable match case | an error (F# warns) | decided |
| 7 | Array semantics | copy-on-write values; `Buffer<'a>` for shared mutation | decided |
| 8 | Union representation | plain values when non-recursive with ≤ 4 non-heap fields (enums a byte); boxed otherwise, with a tag only when several cases have fields, cases without fields as static cells, and `option`'s shape over a pointer as the pointer itself | decided |
| 9 | Members / dot methods | yes; type-directed, no inheritance, no overloading | decided |
| 10 | Equality, ordering, hashing, printing | automatic and structural (prelude derives), opt-out attributes | decided |
| 11 | Units of measure | yes, erased, Kennedy unification | decided |
| 12 | Active patterns | total, partial, parameterised | decided |
| 13 | `[ ]` literal | F# immutable cons list; `[\| \|]` is an array | decided |
| 14 | Named/optional/default arguments | default record fields; named/optional/default on members only; none on curried functions | decided |
| 15 | `option` record fields | a default only with an explicit `= None` | decided |
| 16 | Default expressions | any expression, evaluated at the use site, may use earlier fields/parameters | decided |
| 17 | Union case fields | named construction and patterns; no defaults | decided |
| 18 | Record literal type | from the expected type, through branches and elements; else the fields, among the records in scope: the nearest scope, then the latest declaration | decided |
| 19 | `?` operator | `let p = e?` and statement `e?`; for a block, `result { }` with `let!` | decided |
| 20 | Code generation by users | `derive` over record and union shapes; no macros, no comptime | decided |
| 21 | Async | one cold `Task<'a>` + `Task.start`; general computation expressions; CPS, which the effects spike before phase 6 chose (§6) | done |
| 22 | Threads | v1 single-threaded event loop; in v2 a work-stealing pool and a loop per thread, with non-atomic RC and a negative count marking the objects that crossed threads (§7.1) | decided |
| 23 | Effect handlers | designed now (§6.1), built in v3; one-shot, evidence passing | decided |
| 24 | Float semantics | strict IEEE; `[<FastMath>]` opt-in per function | default |
| 25 | SIMD API | portable `f32x8`-style value types + target intrinsics (§8) | decided |
| 26 | From Zig | cross-compilation through `zig cc`; a checked opt-in instead of no-hidden-allocation (`[<NoAlloc>]`, #42). Not adopted: explicit allocators, comptime | decided |
| 27 | Libraries | source packages (path, git + `zs.lock`), checked Core cached per module; no binary IR format | decided |
| 28 | Strings and `char` | UTF-8 strings, `Length` is bytes; `char` is a Unicode scalar; `for c in s` decodes UTF-8 (malformed bytes become U+FFFD) | decided |
| 29 | Target order | Linux x64/arm64; bare-metal Cortex-M; macOS arm64, Windows x64 (a targets track, build-only until a machine runs the tests); WASM | decided |
| 30 | Who it's for first | native libraries used from C, CLI tools, microcontroller firmware; games over C libraries next | decided |
| 31 | Callbacks into C | `callback<A -> R>` = `R (*)(void *user, A)` + `void *user`; borrowed for the call | decided |
| 32 | Editor support | tree-sitter grammar + `zs lsp` + `zs mcp`, Zed extension first | decided |
| 33 | Formatter | `zs fmt`, one style, no configuration; lossless syntax tree for reflow (planned) | decided |
| 34 | Surface syntax | the freeze is lifted. Missing F# syntax comes first (phase L); new non-F# syntax needs a design discussion | decided |
| 35 | Kept in v1 though not yet needed | `ptr<'a>` + `unsafe`, `Arena`, `dyn Trait`, `weak` references, built in phase V before CEs and `Task` | done |
| 36 | Optimizations that change evaluation order | only for pure code (fusion requires pure lambdas, and stages that can't panic when the consumer's function has effects; printing pieces evaluates them all first) | decided |
| 37 | Library organization | prelude (global names) / Core (no OS: every target) / Std (needs an OS); .NET-style namespaces open everywhere at the lowest precedence; .NET module names, F# function names | decided |
| 38 | Operator precedence | F#'s: custom operators by their first character; `\|>` and `>>` at the comparison level, above `&&` and `\|\|` (they used to be the loosest) | decided |
| 39 | "Simple" | a feature replaces code people would write by hand and needs no runtime; no page budget | decided |
| 40 | Reference cycles | not collected; `weak` references for back-pointers, `ZS_LEAKCHECK=1` to find leaks | decided |
| 41 | Lambda arguments | typed after the call's other arguments when a parameter has no annotation, with the parameter types the call expects; `x \|> fun p -> body` is `let p = x` | decided |
| 42 | Code that must not touch the heap | `[<NoAlloc>]` functions and `--no-heap` programs, checked at compile time on Z#'s IR after its optimizations; freeing counts; externs trusted; interrupt handlers implicitly `NoAlloc` (§10) | default |
| 43 | `dyn Trait` | the value boxed with its type's impl table; made where a `dyn` is expected, with no conversion written; for traits whose methods take the value first and don't mention its type elsewhere (§3) | decided |
| 44 | Arenas | `Arena.with (fun () -> …)`: what the function allocates comes from the arena's blocks, freed together when the arena's last object goes. An object that lives on keeps its blocks, so arenas are memory-safe without escape analysis (§5.2) | decided |
| 45 | Z# objects in C | an opaque `zs_handle` with its own count (`zs_retain`, `zs_release`); a returned handle is the caller's, a passed one is lent for the call (§11) | decided |
| 46 | Computation expressions' builders | a module `W.Builder` for `w { }`; the body goes to `delay`; a missing function is an error at the form that needs it, not a trait (§4). `task { }` is the compiler's own, a state machine (phase 9, §6) | decided |
| 47 | Functions that cross threads | `share<F>`, checked where a function becomes one (its captures Share, through captured local functions), and after monomorphization for the top-level values it reaches; not a closure type per lambda (as in Rust) nor an effect on every function type (§7) | decided |
| 48 | A thread's tasks | a loop per thread; `Task.spawn` runs a task on a loop thread to the end, and its result comes back; tasks don't move between threads, so what a task holds needn't be Share (§7) | decided |
| 49 | SIMD functions | a built-in module per vector type (`F32x8.load`), not generic functions over vectors: HM can't relate a vector type to its element type without type families (§8) | decided |
| 50 | SIMD integer overflow | vectors wrap, as their instructions do; scalars stay checked (§8) | decided |

"Default" means chosen by me and open to change until the phase that implements it begins.
