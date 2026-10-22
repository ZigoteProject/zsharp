# Proposal 0003: spans and slices

| | |
|---|---|
| **Status** | Approved in principle |
| **Decided at** | the phase 9.6 design review (decision 52) |
| **Builds** | phase 9.6 ([ROADMAP](../../ROADMAP.md#phase-96-ergonomics-spans-and-c-structs)) |
| **Rests on** | decisions 2 (Perceus), 7 (copy-on-write arrays, `Buffer`), 28 (strings are UTF-8 bytes), 43 (a value becomes a `dyn` where one is expected), 52 (spans) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §5.1](../../DESIGN.md#51-representation) |
| **Related** | [0004 C layout](0004-c-layout.md), [0005 ergonomics](0005-ergonomics.md), [0024 the library's API](0024-library-api.md) (`Bytes` over spans) |

- [x] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

`span<'a>` is a window into an array, a string or a `Buffer` without a copy: its owner, an
offset and a length, as a plain three-word value that holds a reference to the owner, so it
can't dangle and needs no lifetime annotations. `a.[1..3]`, `a.[..n]` and `a.[i..]` are
spans; a string's slice stays a string; `String.bytes s` is a string's bytes as a `span<u8>`.
An array or a `Buffer` becomes a span where one is expected with nothing written, so the
library's reading functions take spans and work on all three. A span is read-only; a
writable window into a `Buffer` is a `Buffer` sharing its storage. C receives a span as a
pointer and a length.

```fsharp
let header (bytes: span<u8>) = Array.sum bytes.[..3]      // no copy of the file's bytes

let main () =
  let data = File.readAllBytes "img.bin"?                 // array<u8>
  println $"{header data}"                                // the array becomes a span
  0
```

## Motivation

- **Parsers and IO copy today.** `Array.sub a i n` copies; a parser over a file's bytes either copies at each step or carries indices by hand, as `examples/mcu/nucleo-f401.zs`'s `hasAt line len start` does. A `span<u8>` and an index is the shape every parser wants.
- **Library functions take one type.** `Array.sum` takes an array, so a `Buffer` must be copied with `Buffer.toArray` to sum it. With spans, one `Array.sum` reads arrays, `Buffer`s and slices of either.
- **C APIs take pointer and length.** `write(fd, buf, len)` over part of a buffer needs a copy or `unsafe` arithmetic today.
- **Phase 11 needs it:** the compiler's lexer and the LSP's framing read bytes without copying.

## Detailed design

### The type

- **`span<'a>`:** owner (a reference to an `array<'a>`, a `Buffer<'a>` or, for `span<u8>`, a `string`), offset and length. Three words, in registers, never on the heap. It's a value: copying a span copies three words and dups the owner.
- **Read-only.** `s.[i]` reads; there is no `Span.set`. A writable window into a `Buffer` is a `Buffer` that shares its storage (`Buffer.slice b i n`, and `b.[i..j]` on a `Buffer`), so value semantics hold for arrays (a write can never reach an array through a span) and `Buffer`'s contract (a write is seen through every alias) holds for its windows. Decision 52's words "writable over a `Buffer`" mean this; see *Unresolved questions* for the alternative.
- **Owner reference:** a span dups its owner when made and drops it when it dies, so the owner outlives every span over it. Nothing else is needed for safety.
- **Copy-on-write:** a live span over an array makes the array's count at least 2, so a write to the array copies it, and the span keeps seeing the bytes it had. That's the value semantics decision 7 promises, at the cost of one copy only when a program writes to an array it has a span of.

### Slices

| Expression | On an array or a `Buffer` | On a string | On a span |
|---|---|---|---|
| `x.[i..j]` | a span (a `Buffer` window) of elements `i` to `j` inclusive, as F# | a string, copied | a span |
| `x.[..j]`, `x.[i..]` | likewise | likewise | likewise |
| out of range | panic, naming the range and the length | panic | panic |
| a string offset inside a character | | panic naming the byte offset | |

- **`String.bytes s`** is a `span<u8>` over the string's bytes, no copy; `String.ofBytes` copies a span into a string (validating UTF-8, as decision 28 says for malformed bytes).
- **A slice of a slice** adds offsets; the owner is the original.

### Conversions

- **Where a span is expected** (a parameter, a declared type, a result, through `if` and `match` branches and list elements, the rule decision 43 gives `dyn`), an array or a `Buffer` becomes a span over all of it with nothing written. A string doesn't: `String.bytes` is explicit, since a string's elements are characters, not bytes.
- **The other way** is explicit: `Array.ofSpan`, `Buffer.ofSpan` copy.

### Reference counting

- **A span is owned like any value** with a heap field: Perceus dups and drops the owner through it. A function that only reads its span parameter borrows it, so a loop over `s.[i]` does no count traffic (borrowed reads, DESIGN §5.2).
- **Borrowed fields** apply: `let s = a.[1..3]` where `a` dies after it moves `a`'s reference into the span, with no dup.
- **Fusion** reads spans as it reads arrays: a pipeline from a span is one loop over `owner.[offset + i]`.
- **Bounds checks:** loop versioning (DESIGN §9.1) proves a span's reads once before a loop, from its length.

### The library

- **Reading functions take spans:** `Array.sum`, `fold`, `iter`, `exists`, `contains`, `map`, `mapi`, `filter`, `rev`, `sort` (returning arrays), and `Buffer.toArray`; `Array.length` on a span is its length. `Array.sub` stays as the copying form.
- **New:** `Span.length`, `Span.isEmpty`, `Span.slice`, `Array.ofSpan`, `Buffer.ofSpan`, `Buffer.slice`, `String.bytes`, `String.ofBytes`.
- **Bytes:** `Bytes.readU32LE` and the rest ([0024](0024-library-api.md)) read a span at an offset.
- **SIMD:** `F32x8.load` takes a span and an index too, so kernels work on slices.

### C

- **Crossing:** a `span<'a>` parameter whose element is a C type crosses as a pointer and a length, two arguments in that order (`int (*)(const T *, size_t)`), the owner borrowed for the call. A span can't be returned from C or stored by it.
- **A span over C memory:** `Span.ofPtr p n` inside `unsafe`: its owner is a static object, so no count is kept and the memory's lifetime is the programmer's, which is what `unsafe` says.

### Order of implementation

1. The type, slices, conversions and the count rules; `String.bytes`.
2. The library's reading functions over spans; `Buffer.slice`; `Bytes`.
3. C crossing and `Span.ofPtr`.
4. SIMD loads over spans.

## Drawbacks

- **One more reference kind.** `ref`, `Buffer`, `weak`, `span` and `ptr` are five; the third design review's "how many kinds" item asks whether a programmer can tell them apart. Spans are the one that's a window, and the guide's table says when to reach for which.
- **A write to an array with a live span copies it,** which may surprise where a programmer expected one array. It's the value semantics arrays already have (`cow.zs`), seen through a span.
- **Spans over `Buffer`s see writes,** as the `Buffer` does; a span is only as stable as its owner.
- **Three words per span** against a pointer-and-length pair in Rust: the owner reference is the price of no lifetimes.

## Alternatives

- **Rust's slices** (`&[T]`): a pointer and a length checked by lifetimes. Z# has no lifetimes and won't; holding the owner costs one count operation per span and nothing else.
- **.NET's `Span<T>`:** stack-only, enforced by `ref struct` rules the compiler checks everywhere a span flows. Z#'s span can be stored in a record or a list, because it holds its owner; `Memory<T>` is the closer relative.
- **Swift's `ArraySlice`:** shares storage with copy-on-write, as this does; Swift keeps the original indices, which trips people up; Z# slices start at 0.
- **Copying** (`Array.sub`): what exists; linear in the slice at every step of a parser.
- **Two span types,** read-only and writable (`span` and `mspan`): one type and the `Buffer` window do the same with one name fewer; a flag at run time would panic on writes through a span of an array, which is worse.

## Compatibility

- **Not breaking:** `a.[i..j]` doesn't parse today, and `Array.sub` stays. Library functions that gain span parameters accept arrays as before through the conversion.
- **Type inference:** a lambda whose parameter flows into `Array.sum` is typed as a span where it was an array; a program that then indexes it still works. One that passes it on to a function wanting an `array<'a>` gets an error, and `Array.ofSpan` fixes it. This is the one place existing code could change meaning, and the exit tests run the whole suite to find it.
- **C exports** with span parameters are new signatures only.

## Pragmatics

### Diagnostics

| Situation | Error |
|---|---|
| writing through a span | `a span is read-only: slice the Buffer (b.[i..j]) for a window you can write to` |
| a span where an array is needed | `expected array<u8>, got span<u8>: Array.ofSpan copies it` |
| a slice past the end | at run time: `panic: slice 4..9 of an array of length 6` |
| a string slice inside a character | at run time: `panic: byte 3 is inside a character` |
| `Span.ofPtr` outside `unsafe` | `Span.ofPtr needs unsafe: the memory's lifetime isn't checked` |
| returning a span from C, or storing one | `a span can't come from C: it needs an owner` |

### Tooling

- **Hover** shows `span<u8>`; the inlay hint on `let s = a.[1..3]` shows it.
- **Debugging:** gdb shows a span as its owner, offset and length; a pretty-printer ([0011](0011-debug-info-profiles-traces.md)) shows the elements.
- **The grammar** gains the slice forms.

### Performance

- **Existing code:** none; arrays passed to reading functions are converted at no cost (three register moves).
- **Spans:** a slice is three words and one dup; reads are the owner's reads plus an add. Loop versioning keeps bounds checks out of loops over spans.
- **Copy-on-write:** a write to an array with a live span copies the array once.

### Scaling

Nothing grows with spans beyond the arrays they window.

### Culture-aware formatting and parsing

None. Byte offsets into strings are bytes, not characters, as `String.length` is.

## Unresolved questions

1. **Writable spans:** the `Buffer` window here, or one `span<'a>` with a writability flag in the type (`span<'a, write>`), which decision 52's wording could also mean. The window needs no new type and no run-time check.
2. **Slicing a `list`:** F# allows `xs.[1..3]` on lists (linear, copying). Not here; `List.take` and `skip` say the cost.
3. **`fixed<'a, N>` as a span** ([0004](0004-c-layout.md)): a `fixed` lives inline in a record, which is a plain value with no owner, so a span over it would dangle; reading one through a span needs a copy or `unsafe`. Left to 0004.

## History

- **2026-10-22:** drafted from DESIGN §5.1 and decision 52.
