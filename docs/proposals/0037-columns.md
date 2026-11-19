# Proposal 0037: columns, an array of records stored field by field

| | |
|---|---|
| **Status** | Implemented in part (decision 88): steps 1 to 4, the value type, its columns, its writes and `ColumnBuffer` (`tests/columns.zs`, `tests/columns_write.zs`, `tests/err_columns.zs`, `tests/column_buffer.zs`, `bench/columns/`), with the differences under *As built*; the compiler's own tables (step 5) wait |
| **Decided at** | the user's request to build it (2026-11-16), without a design review: the unresolved questions below are still open |
| **Builds** | [track G](../../ROADMAP.md#language-g), in the steps under *Order of implementation*; step 5 (the compiler's own tables) waits for a stage 0 that has the type |
| **Rests on** | decisions 20 (derive, no macros or comptime: a derive can't declare a type), 39 (a feature replaces code people write by hand and needs no runtime) and 78 (the compiler's tables are arrays indexed by ids) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §5.1](../../DESIGN.md#51-representation) (arrays are values with copy-on-write, `Buffer`, spans), [§8](../../DESIGN.md#8-simd) (SIMD) and [§9.1](../../DESIGN.md#91-optimization-strategy) (monomorphization) |
| **Related** | [0003 spans and slices](0003-spans-and-slices.md) (a column is a span), [0004 C layout](0004-c-layout.md) (layout facts; decision 87, proposed, lets a derive report a record's padding), [0013 bit fields](0013-bit-fields.md) (the other way to make a table denser), [0026 performance you can see](0026-performance-you-can-see.md) |

- [x] Approved in principle (built at the user's request)
- [ ] Discussion
- [x] Implementation (steps 1 to 4; not tuples or single columns as rows, or `columns<'a>` written with a type variable)

## Summary

`columns<'r>` is an array of records stored as one run of memory per field (a structure of
arrays) and used as the array of records it stands for:

```fsharp
[<Derive(Columns)>]
type Particle = { x: f32; y: f32; z: f32; vx: f32; vy: f32; vz: f32; age: f32; id: i64 }

let step (dt: f32) (ps: columns<Particle>) : columns<Particle> =
  let mutable ps = ps
  for i in 0 .. Columns.length ps - 1 do
    ps.[i].x <- ps.[i].x + ps.[i].vx * dt     // two loads and a store, in two columns
    ps.[i].age <- ps.[i].age + dt
  ps

let oldest (ps: columns<Particle>) = Array.max ps.age     // ps.age : array<f32>, the column
let first (ps: columns<Particle>) : Particle = ps.[0]     // a row, built from every column
```

- `ps.[i]` is a row, a `Particle`. `ps.[i].age` reads one column and `ps.[i].age <- v` writes
  one.
- `ps.age` is the column, an `array<f32>`: every function that reads an array reads it
  (`Array.sum`, `Array.fold`, `F32x8.load`, a slice), with nothing new in the library.
- It is a value with copy-on-write, as `array<'a>` is, every column of one length.
  `ColumnBuffer<'r>` is its shared, growing counterpart, as `Buffer<'a>` is `array<'a>`'s.

Changing `array<Particle>` to `columns<Particle>` in a signature changes the layout and leaves
the loops as they are, so which layout is faster is measured, not argued.

## As built

Steps 1 to 4, on 2026-11-16. The text from *Motivation* on is the draft's, kept as the record of
what was proposed; where the two differ, this section and [DESIGN §5.1](../../DESIGN.md#51-representation)
say what the compiler does.

- **`[<Derive(Columns)>]` on the row type.** `columns<R>` exists for a record that derives it,
  not for any type. The columns' type has to be declared once, where its row is: declared the
  first time some module wrote `columns<R>`, it would belong to whichever module came first, which
  a checked module's cache and an impl's one home (decision 84) both rule out. So a library's
  record has columns when its library says so, as with any derive.
- **A record of arrays, not one object.** The derive declares a record with the row's fields,
  each an `array` (`Types.Ty.columnsOf`), and `columns<R>` is that record. A span's owner is an
  array (§5.1): one object holding every column couldn't hand out `c.f` without a new kind of
  owner, its own drops and copies, and a case in everything that walks the heap. As a record of
  arrays, nothing after the checker knows the type: reference counting, code generation, threads,
  contained jobs and the debugger see what they already handle. The cost is a header and a length
  per column, and a value of a pointer per column where the draft had one.
- **`c.f` is `array<'f>`,** which is more than the draft's span: it's the column itself, and a
  span where one is expected.
- **Library, not built-ins.** `Columns.Columnar<'c, 'r>` (`length`, `get`, `set`) and
  `Columns.Row<'r, 'c>` (`ofArray`) are traits in `lib/core/Columns.zs`, implemented by a derive
  written there with two new forms, `Shape.field f x` and `Shape.record (fun f -> …)`
  (DESIGN §3.1); `init`, `create`, `toArray` and `map` are functions over them. Generic code
  works by the constraints inferred, so `let last c = Columns.get c (Columns.length c - 1)` is
  any columns'.
- **What the checker does** (`Infer/Exprs`): `c.[i]` is a record literal of each column's
  element, `c.[i].f` and `c.[i].f <- v` are the column's `c.f.[i]`, and `c.[i] <- row` a write
  per column. A `let mutable` that holds columns is a `let mutable` per column, so an element's
  write is `CArraySet` on a variable, the path a `let mutable` array's takes: in place, nothing
  allocated (`tests/columns_write.zs` counts).
- **One length,** kept by refusing the three ways to break it: a record literal of a `columns`
  type, `{ c with f = … }`, and `c.f <- …`.
- **Not built:** a tuple or a single column as the row; `columns<'a>` written with a type
  variable (an error that says to leave the annotation out); `Columns.ofArray [||]`, whose row
  type nothing gives (annotate the array); a slice of rows.
- **The draft was wrong about equality:** an array has no `Eq`, so columns have none.
- **Measured** (`bench/columns/columns.zs` beside `by_hand.zs`, 4,000,000 rows of 56 bytes, ns per
  element, one run of each on the same machine):

  | Loop | `array<Particle>` | arrays by hand | `columns<Particle>` |
  |---|---|---|---|
  | sum of `age` | 1.46 | 0.93 | 0.92 |
  | sum of `age`, `[<FastMath>]` | 1.59 | 0.079 | 0.073 |
  | largest `age` | 1.49 | 0.62 | 0.62 |
  | `vx² + vy² + vz²` summed | 2.95 | 2.80 | 2.79 |
  | a step writing `x` and `age` | 3.00 | | 0.60 |

  Reading whole rows (`let p = c.[i]`) and using three fields is 2.80: an optimized build drops
  the loads it doesn't use.
- **A cost to know:** `ps <- step dt ps` passes columns the variable still holds, so the step's
  first write to each column copies it. A step's result given straight to the next step
  (a recursive loop, or a `let`) is held once and written in place.
- **`ColumnBuffer<'r>`** (step 4) is the same derive's, declared beside the columns: a record
  with the row's fields, each a `Buffer` (`Types.Ty.columnBufferOf`). `b.[i]`, `b.[i].f` and
  their writes take the columns' path in the checker, and their writes are a `Buffer`'s, through
  any binding, also where `b` is an element, a call's result or a ref's `Value` (held, as a read
  holds it). `b.f` is the column, a `Buffer` sharing the storage, not the draft's slice of it: a
  slice pushed to or held across a growth is a write that's lost, where the column is the column
  however the buffer grows. A column pushed to or truncated alone would mix rows, so `length`,
  `set`, `push`, `truncate` and a row's write (`b.[i] <- row`, its receiver held first, as `set`
  takes it) check that every column is one length as they begin, and panic if one isn't
  (`tests/column_buffer_lengths.zs`); `b.[i]`, `b.[i].f` and `b.[i].f <- v` reach their own
  columns only. A `Buffer` isn't `Share`, so a column doesn't
  cross threads: unresolved question 7 stays open (tasks on one loop may each write a column,
  taking turns, but none writes in parallel). Its functions are a trait,
  `ColumnBuffer.Buffered<'b, 'r>`, and functions over it. Each column grows on its own, as a
  `Buffer` does, not the draft's one object laid out for the capacity. `ColumnBuffer.empty ()`
  takes its type from where it's used, since a trait is dispatched by its first parameter; where
  nothing gives it, `zs check` says so at the call, as for any trait method only its result gives
  the type of (it was a build's error with no place, naming `int`).
- **Names, as a file's own come first:** `lib/core/Columns.zs` is in `Collections`, as `Buffer`
  is, so a program's own module `Columns` or `ColumnBuffer` is its own, and so is a type or an
  alias named `columns` or `ColumnBuffer` (`tests/columns_own_names.zs`,
  `tests/columns_own_modules.zs`). The derive's code calls the library's functions whatever the
  program names its own (a derive's `M.f` is the library's as the derive's module sees it). A
  private row's fields are private through its columns and its ColumnBuffer too.
- **Found on the way:** an element of an array in a `let mutable` record's field (`r.a.[i] <- v`)
  copied the array at every write. It's written in place now (`tests/record_array_write.zs`),
  which columns in a record's field need and every such record gets.

## Motivation

**One field of many.** A loop that reads one or two fields of each record pulls the whole
record through the cache. Measured with `zs 0.7.1 --release` on 4,000,000 records of 56 bytes
(`bench/columns/by_hand.zs`; an x86-64 laptop; ns per element, the median of three runs, each
the best of 15 rounds):

| Loop | `array<Particle>` | one `array<f32>` per field | |
|---|---|---|---|
| sum of `age` | 1.21 | 0.70 | 1.7× |
| sum of `age`, `[<FastMath>]` | 1.31 | 0.085 | 15× |
| largest `age` | 1.29 | 0.54 | 2.4× |
| `vx² + vy² + vz²` summed | 2.39 | 2.22 | 1.1× |

The second row is the one that matters: over a column the loop adds a vector of lanes an instruction,
and over records it's a load every 56 bytes, which doesn't vectorize whatever the attribute
says. The others are memory traffic alone (224 MB against 16 MB a column), and the last
shows the other side: a loop that uses three fields which already sit together gains little.
Runs differ by a tenth or so (a laptop's clock), the vectorized row between 15× and 19×.

**What programs write today.** A record of arrays, by hand. The compiler's syntax tree is one
(`src/Syntax/Tree.zs`, decision 78):

```fsharp
type Tree =
  { …
    /// Per node: its kind.
    kinds: array<Kind>
    /// Per node: where its children start in `children`, and how many it has.
    firsts: array<int>
    counts: array<int>
    /// Per node: the node it's a child of (-1 for the root).
    parents: array<int>
    starts: array<int>
    ends: array<int> }
```

and `bench/host/nbody.zs` passes seven: `energy (x: array<f64>) (y: array<f64>) … (m: array<f64>)`.
What that costs, each a thing nothing checks:

- **"Per node" is a comment.** Six arrays have six lengths. That they're equal is the
  programmer's to keep; one built short is an `index out of bounds` far from the mistake, or a
  wrong answer where the loop runs to the shorter one's length.
- **No row.** There is no `Node` to pass, print, compare or put in a test's `expect`; a function
  over one node takes the tree and an index.
- **Six of everything:** six objects and six lengths, six bounds checks where an index is one,
  six copies where one array is written while shared.
- **The layout is in every line.** `t.kinds.[n]` is written at each use (two dozen lines for
  `kinds` alone in the compiler). Trying the other layout rewrites them all, so it's rarely tried, and the
  measurement above is rarely made.

**Why a language feature.** Decision 39's test: it replaces code people write by hand, and it
needs no runtime. A library can't write it: a type whose fields are another type's, each wrapped
in an array, is a type made from a type, and Z# has no macros, no comptime and no higher-kinded
types (decision 20). A `derive` implements a trait; it can't declare the record of arrays
(DESIGN §3.1, *Not included*). The compiler already knows each field's size and where an index
goes.

## Detailed design

### The type

- **`columns<'r>`** is a built-in type, as `array<'a>` and `span<'a>` are. No new syntax.
- **`'r` is any type.** A record gives a column per field, in declaration order. A tuple gives
  one per component. Anything else (a number, a union, a string) is a single column, so
  `columns<f32>` is laid out as `array<f32>` is. Generic code over `columns<'a>` therefore needs
  no constraint: `Columns.map` is written once, and is monomorphized (§9.1) at each row type as
  any generic function is.
- **One level.** A field that is itself a record is one column of that record, its fields
  together: in `{ position: Vec3; velocity: Vec3; age: f32 }` there are three columns, and
  `ps.position` is a `span<Vec3>`. To split it further, write its fields in the row. (Nested
  splitting is an unresolved question.)
- **A `[<Bits>]` record** is a single column of its integer: its fields are bits, not bytes
  ([0013](0013-bit-fields.md)). A `[<CLayout>]` record gives a column per field like any other;
  the attribute is about the record as C sees it, and a column crosses to C as a pointer and a
  length (§11).
- **A field of a heap type** (`string`, a list, another array) is a column of pointers, counted
  as an array's elements are.

### Meaning

`c : columns<'r>`, `'r` a record with a field `f : 'f`:

| Form | Type | Meaning |
|---|---|---|
| `Columns.length c` | `int` | the number of rows |
| `c.[i]` | `'r` | row `i`, built from each column; one bounds check |
| `c.[i].f` | `'f` | one load from column `f`; the other columns aren't touched |
| `c.f` | `span<'f>` | column `f`: read-only, `Columns.length c` long, holding a reference to `c` |
| `c.[i] <- row` | `unit` | writes each column (`c` a `let mutable`) |
| `c.[i].f <- v`, `c.[i].f += v` | `unit` | writes one column |
| `for row in c do` | | each row in order (`Iter<columns<'r>, 'r>`, [0017](0017-iteration.md)) |

- **A value.** `columns<'r>` is a value with copy-on-write, exactly as an array (§5.1): a write
  through one name is never seen through another, it happens in place when `c` holds the only
  reference, and the object (every column) is copied first otherwise. `c.[i] <- row` and
  `c.[i].f <- v` are places as `a.[i]` and `a.[i].f` are today
  ([specification 5.8](../spec/05-expressions.md#58-blocks-and-bindings)); nothing in the rules for places changes but
  that the receiver may be a `columns`.
- **`c.[i].f` is one load in every build.** The checker sees the field access on the index and
  makes it a column read, so a debug build doesn't build the row to take one field of it. Where a
  row is bound first (`let p = c.[i]` then `p.age`), every column is loaded and the unused loads
  are dead code, which an optimized build removes and a debug build keeps.
- **`c.f` is a span** ([0003](0003-spans-and-slices.md)): owner, pointer, length. It keeps `c`
  alive, so it can't dangle; a write to `c` while a column is held copies `c`, as a write to an
  array does while a span of it is held. `columns<'r>` has no fields of its own, so `c.f` has
  one meaning; a name that isn't a field of `'r` is an error listing the fields.
- **Equality, ordering and hashing** are an array's of the same rows (decision 10), so
  `Columns.ofArray a = Columns.ofArray b` exactly when `a = b`. It has no `Show`, as an array has
  none; `Columns.toArray c |> Array.toList` prints the rows.
- **Threads.** A `columns<'r>` crosses to another thread when `array<'r>` does, by the same rule
  (§7.1), and is one shared object there.
- **`[<NoAlloc>]`.** Reading rows and columns allocates nothing. A write may copy, as an
  array's does, and is reported the same way.

### Representation

One heap object: the header word, a length word, then the columns in declaration order, each
starting at its element's alignment.

```
array<Particle>      | hdr | len | x y z vx vy vz age _ id | x y z vx vy vz age _ id | …
columns<Particle>    | hdr | len | x x x … | y y y … | … | age age age … | id id id … |
```

- **No padding per row.** `Particle` is 40 bytes with 4 of padding; its columns hold 36 a row,
  and at most one alignment's worth between columns for the whole object.
- **A column's start** is the payload's plus the lengths of the columns before it: a
  multiply-add per column, computed once outside a loop (it depends on the length alone, which
  a loop doesn't change).
- **`sizeof<columns<'r>>`** is a pointer's, as an array's is.
- **The empty one** is a static object and costs no allocation, as the empty array.
- **Alternative shape:** a pointer per column kept in the value (Odin's `#soa` slices). The
  value would be as many words as the row has fields, in every record that holds one and every
  call that passes one; one object with computed offsets (Zig's `MultiArrayList`) keeps it a
  pointer.

### The `Columns` module

Built-ins, as `Array`'s are, and no more than these in the first step:

| Function | Type |
|---|---|
| `Columns.length` | `columns<'r> -> int` |
| `Columns.init` | `int -> (int -> 'r) -> columns<'r>` |
| `Columns.create` | `int -> 'r -> columns<'r>` |
| `Columns.ofArray`, `Columns.toArray` | `span<'r> -> columns<'r>`, `columns<'r> -> array<'r>` |
| `Columns.set` | `columns<'r> -> int -> 'r -> columns<'r>` (a changed copy, as `Array.set`) |
| `Columns.map` | `('r -> 's) -> columns<'r> -> columns<'s>` |

Folds, sums and searches over one field are `Array`'s over the column (`Array.sum c.age`).
Those over whole rows (`Columns.fold`, `filter`, `sortBy`) are library code over `for row in c`
and are added as programs ask for them, not ahead.

### `ColumnBuffer<'r>`

The shared, growing form, for a table that is built up (an entity store, the compiler's nodes):

- `ColumnBuffer.empty`, `create`, `length`, `push`, `pop`, `truncate`, `clear`, `ofColumns`,
  `toColumns`, as `Buffer`'s; `b.[i]`, `b.[i].f`, `b.[i] <- row` and `b.[i].f <- v` as above,
  through any binding, as a `Buffer`'s elements are written.
- **Capacity:** the columns are laid out for the capacity, not the length, so a push writes one
  element at the end of each column and moves nothing; growing doubles the capacity and moves
  each column once.
- **`b.f`** is a `Buffer<'f>` over the column, sharing its storage until either grows past it,
  which is what a `Buffer`'s slice is today (§5.1).

### Order of implementation

1. **The value type, read:** `columns<'r>`, its layout in `Types/Repr` and code generation,
   `Columns.init`, `create`, `ofArray`, `toArray`, `length`, `c.[i]`, `c.[i].f`, `for row in c`,
   equality and hashing. *Exit:* `tests/columns.zs` (a record, a tuple, a single column, a
   generic function at two row types, the empty one, an index out of bounds), under the leak
   check and valgrind.
2. **Columns as spans:** `c.f`. *Exit:* `tests/columns_span.zs` (`Array.sum`, a slice,
   `F32x8.load`, a column passed to C); `bench/columns/` with the table above's loops over
   `columns<Particle>` beside the arrays by hand, the two within the benchmark's noise of each
   other, and the vectorized sum's IR holding a vector add.
3. **Writes:** `c.[i] <- row`, `c.[i].f <- v`, the assignment operators, `Columns.set`, `map`,
   copy-on-write. *Exit:* `tests/columns_write.zs` (a write while shared copies; a loop over a
   fresh one allocates once), `[<NoAlloc>]`'s report on a shared write.
4. **`ColumnBuffer<'r>`.** *Exit:* `tests/column_buffer.zs`; a property against a model of
   `Buffer<'r>` (`Prop.model`, [0010](0010-properties-and-fuzzing.md)).
5. **The compiler's tree** as `columns<Node>` once stage 0 has the type. *Exit:* the bootstrap
   gives the same bytes, and `bench/compile` is no slower.

Each step is usable without the next; the review may take 1 to 3 and leave 4 and 5.

## Drawbacks

- **A second array type,** and a third and fourth after `Buffer`: every question "which
  collection" gets longer, and the guide must answer it with a measurement, not a rule.
- **A row costs more.** `c.[i]` as a whole row is a load per column from places far apart;
  code that uses most of each record is slower over `columns` than over an array. The type
  makes that a one-word change to find out, and it's still a way to make a program slower.
- **Compiler surface:** a built-in type with its own layout touches the checker, `Types/Repr`,
  reference counting (a drop walks each column of a counted type), code generation, debug info
  and the editor. `fixed` and spans were this size.
- **`c.f` is a field access that isn't the row type's own field access.** A reader who knows
  records sees `ps.age` and must know `ps` is a `columns` to read it as a column.

## Alternatives

- **A record of arrays by hand,** as today. It works, as the compiler shows; *Motivation* lists
  what it leaves unchecked.
- **A `derive`.** `[<Derive(Columns)>]` would need to declare `ParticleColumns`; a derive
  implements a trait and declares nothing (decision 20). Letting derives declare types is
  macros by another name, a larger change than this type.
- **A type provider** writing the record of arrays and its functions from a record's
  declaration. Providers read data sources, not the program's types
  ([0001](0001-type-providers.md)); the result is generated text per type with none of
  `c.[i].f`, and the lengths are still six.
- **An attribute on the record:** `[<Columns>] type Particle` making every array of it columnar.
  The layout is a property of a container and a loop, not of the record: the same `Particle` is
  wanted both ways, in one program, to measure. And `array<'a>` in generic code would change
  layout with its argument.
- **An attribute or keyword on the array:** `array<Particle>` with `[<Columns>]` at the binding.
  A layout that isn't in the type can't be seen in a signature, and a function couldn't tell
  which it's given.
- **Higher-kinded data:** `type Particle<'f> = { x: 'f<f32>; … }` at `'f = array`. Z# has no
  higher-kinded types and this isn't the reason to add them.
- **The optimizer splits arrays of records itself.** It can't in general (a record's address
  escapes into a span, to C, to another module), it would be whole-program, and a layout that
  changes with an unrelated edit is the opposite of [0026](0026-performance-you-can-see.md).
- **Arrays of small blocks of columns** (AoSoA: 8 or 16 rows a block). Better for loops that
  use every field under SIMD; worse for the common case here, one field of many; and the block
  size is a type-level number (decision 53). Not this proposal.

## Compatibility

- **Not breaking** for programs that don't use the names. `columns` joins the built-in type
  names and `Columns` and `ColumnBuffer` the library's modules; a program with a type or a
  module of those names keeps its own (a file's own names come first), and the suite and the
  packages have none.
- **Older compilers** reject the type by name. The compiler's own use (step 5) waits for a
  stage 0 that has it.
- **The library:** nothing changes for arrays. `Json`, `Binary` and `Arbitrary` get impls for
  `columns<'a>` written as `array<'a>`'s are, reading and writing the same documents and bytes,
  so a program can change the layout without changing its files.
- **C:** a `columns` doesn't cross to C; a column does, as the span it is (a pointer and a
  length, §11).

## Pragmatics

### Diagnostics

```
Particle has no field 'ages': the columns of columns<Particle> are x, y, z, vx, vy, vz, age, id
a column is read-only: write an element with ps.[i].age <- v
ps.[1..3]: a columns has no slice of rows; slice a column (ps.age.[1..3])
columns<Particle> doesn't cross to C; pass a column (ps.x)
```

An index out of range is `panic: index out of bounds`, as an array's.

### Tooling

- **Editor:** hover shows `columns<Particle>` and, on `c.f`, `span<f32>`; completion after `c.`
  offers the row's fields. The allocation hints ([0026](0026-performance-you-can-see.md)) show
  one allocation for a `Columns.init`, and a copy at a shared write.
- **Debuggers:** a `columns` shows its length and each column as an array (0011's
  pretty-printers, when they're there; the raw object before).
- **`zs fmt`, `zs doc`:** nothing new: no syntax.

### Performance

- **Reads of one field** are a single array's: the measurements under *Motivation* are the
  target, and step 2's exit holds the compiler to them.
- **Bounds checks:** one per `c.[i]`, since there is one length, where the arrays by hand have
  one each.
- **Rows:** `c.[i]` whole costs a cache line per column on a cold table. Nothing hides that;
  the guide says when an array is the better choice (most fields of each record used, random
  access by index).
- **Memory:** no padding per row, one header instead of one per field's array.

### Scaling

- **Compile time:** a `columns<R>` is instantiated per row type, as an array's functions are
  per element type; the row's gather and scatter are a load or a store per field, generated
  once per type.
- **Wide rows:** a record of 100 fields is 100 columns and a 100-load `c.[i]`; nothing is
  quadratic.

### Culture-aware formatting and parsing

None: no text is read or written but `Show`'s, which is the rows'.

## Unresolved questions

1. **The names.** `columns<'r>` says what is stored; `soa<'r>` is the term of art and says
   nothing to someone who hasn't met it; `table<'r>` reads well and suggests a database.
   `ColumnBuffer` follows `Buffer`.
2. **Nested records:** split one level, as proposed, or all the way down, with `ps.position`
   then a view of three columns (a `columns<Vec3>` that doesn't own its storage, which the
   value type above isn't)?
3. **Unions as rows.** A union could be a column of tags and a column per case's fields (Zig
   does this for its syntax tree). Here it's a single column of the union as an array holds it.
4. **Slices of rows:** `c.[a..b]` would be a span of rows, a new type. A column's slice exists.
5. **Vector stores.** `F32x8.store` takes and returns an array. Writing a column a vector at a
   time needs `store` over a column place, or `{ c with age = lanes }` replacing a column
   whole; which, and whether steps 1 to 3 are worth having without it for write-heavy loops.
6. **Alignment:** each column at its element's alignment, or at 64 bytes, for aligned vector
   loads and so that two threads writing two columns don't share a line?
7. **Writing columns in parallel:** two tasks, a column each, is safe and can't be said with a
   value type; `ColumnBuffer`'s `b.f` as a `Buffer` says it, with `Buffer`'s rules.
8. **Is `ColumnBuffer` in the first release of this,** or does it wait for the compiler's use
   to show its shape?

## History

- **2026-11-16:** drafted. The numbers are `bench/columns/by_hand.zs` with `zs 0.7.1 --release`.
  It came from writing a layout inspector as a package (`zlayout`), whose README could only tell
  a reader to "test a structure-of-arrays layout", by hand.
- **2026-11-16:** steps 1 to 3 built, as *As built* says, after a prototype written by hand showed three things: the columns' record of the same field names took the row's record literals (so it isn't among the records a literal is looked up in), an array has no `Eq`, and a write to an array in a record's field copied the array.
- **2026-11-16:** step 4 built, `ColumnBuffer`, as *As built* says, with the exit property
  against a model (`tests/column_buffer.zs`).
- **2026-11-19:** a review of step 4 found 30 defects, each reproduced, and they're fixed, as
  *As built* says: a program's own `columns` or `ColumnBuffer` type sharing the derived one's drop
  function (a crash in safe code); every `Buffer` named `ColumnBuffer<<T>>`; a private row's
  fields reachable through its columns; a program's own module, type or alias of those names
  refused; writes through an element, a call or a ref refused with wrong advice; a column's length
  changed alone mixing rows; `ColumnBuffer.empty ()` with no type a build's error with no place;
  the reference missing the traits' methods; and the messages and tests around them.
