# ZLayout

A Z# package for inspecting concrete type layout and estimating memory/cache costs. It is one of the Z# repository's packages, tested by its suite, and needs the compiler it ships with (the first release after 0.7.1): the `Inspect` derive reads `sizeof<'self>`, `alignof<'self>` and each field's `f.offset`, so every number in a report is the compiler's own.

## What it does

- Reports actual type size and alignment for the current compilation target.
- For records, reports each field's offset, size, and alignment, plus internal and trailing padding.
- Calculates a compact candidate field order and predicted size using descending alignment/size. It does not rewrite source code.
- Models shallow representation separately from heap allocations.
- Estimates array and string requested sizes, list-cell sizes and counts, and Z#'s 8-byte pool size classes up to 256 bytes.
- Calculates nominal cache-line density and array cache-line counts.
- Provides signed and unsigned integer range samplers to suggest the narrowest fixed-width integer that covers the observed samples.

The `Inspect` derive expands at compile time for each marked type. As with Z#'s other derives, it adds ordinary generated code rather than runtime reflection metadata. The inspector itself is a diagnostic tool: it builds a report value and should not be placed in a production hot path.

## Use in an application

Add the package:

```toml
[dependencies]
zlayout = { path = "…/packages/zlayout" }
```

Annotate the record and inspect a representative value:

```zs
open Zlayout

[<Derive(Inspect)>]
type Entity =
  { active: bool
    kind: u8
    position: Vec3
    age: f32
    name: string }

let report = Inspect.inspect "Entity" entity
printReport 64 true report
```

The second argument to `printReport` controls whether a field-reordering suggestion may be presented. Pass `false` for FFI records, persistent binary layouts, or any type whose field order is externally observable.

A `[<CLayout>]` record derives it in the same list, `[<CLayout; Derive(Inspect)>]`. A `[<Bits>]` record is one integer whose fields are bits, with no offsets in bytes, so deriving `Inspect` for one is a compile error.

Run the tests, and build the demo, with the Z# compiler:

```sh
zs test

cd examples/demo
zs run
zs build --release
```

## Important size semantics

### Inline and shallow size

`representationBytes value` and `sizeof<T>` report the representation stored inline. For a record this includes the bytes occupied by its fields, including handles for heap-backed fields. It does **not** recursively count the strings, arrays, lists, or other objects referenced by those handles.

For heap-backed types such as `array<T>` or `string`, `sizeof<T>` reports the handle representation, not the allocation behind it. `Heap.estimateArray` and `Heap.estimateString` model the separately allocated object as:

- one machine-word object header;
- one machine-word length;
- the direct payload bytes (for a string, its UTF-8 bytes and a terminating NUL).

The empty array and string literals are static objects: `estimateArray [||]` reports no allocation, and `estimateString` describes a string built at run time.

`requestedBytes` is the total over `allocations` objects. For objects up to 256 bytes, `poolClassBytes` is the 8-byte class each one is rounded to. Above that size the runtime uses the general allocator; allocator-specific metadata is not guessed.

A list cons cell is one header word, the inline head and one tail handle, laid out as a struct. On a 64-bit target, `list<int>` therefore has 24 requested bytes per cons cell (and so does `list<u8>`, after padding). Each cell is its own allocation: `estimateListCells 20 0` reports 20 allocations, 480 requested bytes and pool class 24. An empty list has no cons-cell allocation; `estimateListCells 0` reports zero allocations and no pool class.

`Buffer` may retain more capacity than its logical length after growth. `bufferPayloadLowerBound` intentionally reports only live element payload, not an invented capacity or allocator size.

### Unions

For a union, `sizeof<T>` and `alignof<T>` describe the complete type representation, but `Shape.of` on one value only exposes its active case. The first version reports the overall size/alignment and active case; it does not pretend that the active case is a complete map of every variant's layout.

### Field reordering

The candidate order is based on field size/alignment and the record's measured overall alignment; the tests check the predicted size against `sizeof` of a record declared in that order. It is useful for identifying possible padding reduction in ordinary records. It is not a promise that changing source declaration order will improve CPU time. Do not reorder C-layout/bit-layout/serialized/ABI-visible records, and benchmark before keeping a change.

## Practical CPU optimization guidance

- Narrow integer fields only when domain constraints prove the narrower range is valid. Runtime samples are evidence, not a correctness proof. On modern CPUs, a narrower scalar operation is not automatically faster; the main benefit is often lower memory traffic and more values per cache line.
- If a hot loop reads only a few fields from a large record array, test a structure-of-arrays layout. If it usually consumes a whole entity, array-of-structures may be better.
- Keep cold strings, large optional payloads, and rarely used metadata away from the hot path when profiling shows they cause extra cache traffic.
- Prefer arrays for dense sequential traversal and indexed access. A linked list adds a pointer-chasing step per element; Z# does fuse many pure list pipelines, so do not replace a list pipeline that is already allocation-free without measuring.
- Arrays are copy-on-write. Use `Buffer<T>` when shared mutation is genuinely needed, but account for capacity growth.
- Use Z#'s small unions and `option` rather than manually encoding tags. Pointer-shaped options can use the existing pointer niche without allocating a `Some` object.
- Consider `[<Bits>]` for dense flags or small enum fields when bit extraction is acceptable in the hot path.
- Use `[<NoAlloc>]` for bounded allocation-free paths where the language's allocation checker can enforce the requirement.

## Benchmarking workflow

1. Run the analyzer on the target you ship, not only the developer host: `sizeof`, `alignof`, and `offsetof` are target-specific.
2. Build optimized code with `zs build --release`.
3. Benchmark representative inputs using `zs bench` or a stable benchmark harness.
4. On Linux, correlate changes with hardware counters such as cycles, instructions, cache references, and cache misses (`perf stat` / `perf record`).
5. Change one representation at a time and compare both runtime and memory use.

## Scope and limitations

This is a per-type source-level analyzer, not a whole-program compiler plugin or sampling profiler. You opt types in with `[<Derive(Inspect)>]`. It cannot infer the runtime hotness of each field, transitive object graphs for arbitrary custom types, actual array capacity, or the general allocator's metadata. Use a CPU profiler and realistic benchmarks for those questions.

Z# is pre-1.0 and its library/compiler APIs can change; the package changes with the compiler it is tested against.
