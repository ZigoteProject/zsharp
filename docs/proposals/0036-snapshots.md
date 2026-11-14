# Proposal 0036: snapshots: a value's memory as bytes

| | |
|---|---|
| **Status** | Draft; builds only if a measurement asks for it (see *Order of implementation*) |
| **Decided at** | not yet: a design review |
| **Builds** | after 0.7 |
| **Rests on** | [DESIGN §5.1](../../DESIGN.md) (representation) and §5.2 (arenas: objects counted as any others, their memory freed together); §3.1 (`Binary`); §7 (`Share`) |
| **Related** | [0007 incremental builds](0007-incremental-builds.md) and [0020 the compiler in Z#](0020-self-hosting.md) (the cache files, `Binary`'s today); [0035 contained jobs](0035-contained-jobs.md) (the same copy of a value's objects); [0010 properties and fuzzing](0010-properties-and-fuzzing.md) |
| **Changes** | DESIGN §3.1 and §5.2; a new `lib/core/Snapshot.zs` and its reference page; `runtime/rt.c`; a write and a check function per type in the compiler. No syntax |

- [ ] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

`Snapshot.toBytes` writes a value's objects as they are in memory, pointers as offsets.
`Snapshot.ofBytes` checks those bytes in one pass and makes them the value's memory: nothing is
decoded and no object is allocated. The result is an ordinary value.

```fsharp
[<Derive(Snapshot)>]
type Index = { words: array<string>; postings: array<list<int>> }

Snapshot.toBytes : 'a -> array<u8>                    // 'a is Snapshot
Snapshot.ofBytes : array<u8> -> result<'a, string>

let load path : result<Index, string> =
  let bytes = (File.readAllBytes path)?
  Snapshot.ofBytes bytes                              // bytes' memory is now the index's
```

It's a cache's format, not an interchange format: only a build with the same layout reads it.
`Binary` stays for everything else.

## Motivation

**Reading a large value back costs as much as building it.** `Binary.ofBytes` decodes varints,
allocates each object and numbers each string. The scenarios:

- **The compiler's cache** (0007, 0020): a warm `zs check`, and the language server's start on
  a large workspace, read every module's interface through `Binary`.
- **A program's table made ahead of time:** a dictionary, a search index, a parsed grammar.

**Without the feature:** `Binary`, or a table generated as source and compiled in (flash-like,
but fixed at build time).

**Where it comes from.** [Goose](https://aardappel.github.io/goose/) stores references as
offsets, so a structure is written as raw bytes and checked on load. GHC's compact regions do
the same with a fix-up of pointers, trusting the bytes. Z# can't keep offsets in memory (every
pointer read would add a base), but an arena already is a block whose objects are ordinary
values freed together, which is what a loaded snapshot needs to be.

## Detailed design

### What has a snapshot

`Snapshot` is a trait the compiler implements, as it does `Share`:

- **Always:** numbers, `bool`, `char`, `string`, tuples, `option`, `result`, lists and arrays
  of such.
- **When asked,** with `[<Derive(Snapshot)>]`: a record or union whose fields have one. Asked,
  because loading makes a value without running the type's module: a type that keeps an
  invariant (a private constructor) must choose to be made this way.
- **Never:** functions and `dyn` (code pointers), `ref`, `Buffer`, `weak`, `Mutex`, `Channel`,
  `Atomic`, C pointers.
- **Not yet:** `Map`, `Set` and `HashMap`, whose order or hashes a loader would have to check
  (question 2).

### The bytes

A header, then the objects exactly as §5.1 lays them out, children before parents, the root
last:

- **Header:** a magic number, the format's version, the word's size and byte order, a
  fingerprint of the type's layout (the compiler computes it from the same description the
  check function is made from, so the two can't disagree), the length, the number of objects.
- **Objects:** each with its header, its count zero, each pointer the offset of its target.
  An object reached twice is written once. Static objects (count 0, §7.1) are copied in.
- **Deterministic:** the same value gives the same bytes on every run (rule 7 for the
  compiler's cache); the order is the walk's.

### Loading

`ofBytes` takes its array's memory if the array is unique, and copies it first if not. Then
one pass, by a function per type, from the root:

1. **The header:** another type, compiler, word or order is `Error "a snapshot of another
   build"`. Not a panic: a cache rebuilds.
2. **Every object:** its header is the one its type has; each pointer is aligned, inside the
   bytes and **lower than the object holding it** (so no cycle, with no table of visits); a
   union's tag, a `bool`, a `char` and a string's bytes are what the type allows; lengths fit.
3. **In the same pass,** each offset becomes an address and each object's count becomes the
   number of pointers found to it.
4. The block is registered as an arena's, its live count the number of objects.

A failure anywhere is `Error` naming the offset, and the array is dropped as it came. After a
success the value is as any made in an arena: counted, reused in place when unique, its memory
freed when its last object dies. The pass is a loop over a worklist, not recursion: a list of
a million cells loads.

**The bytes aren't trusted.** `ofBytes` is safe code, so step 2 is complete by construction:
nothing in the value is read by the program that the pass didn't check against its type.

### Order of implementation

0. **Measure first.** `Binary.ofBytes`'s share of a warm `zs check` of `src/`, and of the
   language server's start. Under 5% of either, stop here and decline the proposal.
1. **Try the cheap answer:** arrays of numbers written whole in `Binary`, and whatever else the
   profile of step 0 shows. Measure again.
2. `Snapshot.toBytes` (the walk 0035's copy-out shares) and `ofBytes` for the *always* types;
   `tests/snapshot/` with a round trip per type, a value with sharing, and each kind of bad
   byte as an `Error`.
3. `zs fuzz` over `ofBytes` followed by `Show` and `Eq` of the result, under `--sanitize`.
4. The derive; then the compiler's cache, behind the build-to-the-same-bytes check.

## Drawbacks

- **A second way to write a value,** beside `Binary`.
- **The check is the safety of safe code.** A bug in it is memory unsafety from bytes; it has
  to be fuzzed and stay small.
- **Loading is one pass over everything,** not Goose's nothing: Z# reads absolute pointers.
- **Larger files** than `Binary`'s: words where it writes varints, a header per object.
- **One live object keeps the whole block,** as in any arena.
- **The cache's files change with every layout change,** by design; nothing else may be kept
  in this format.

## Alternatives

- **Views over the bytes** (`flat<'a>`; FlatBuffers, Cap'n Proto, rkyv, Goose's relative
  references): nothing to do on load, fields read lazily. But a view is a second
  representation of every type: field access and `match` on it are language changes, and a
  function written for `Index` doesn't take a `flat<Index>`.
- **Offsets as the heap's own pointers,** as Goose has: an addition at every pointer read, in
  every program.
- **Mapping the file at a fixed address,** no fix-up (Emacs's dumper): fights address-space
  randomization and needs an address reserved on every platform.
- **Trusting the bytes** in `unsafe`, as GHC does: a cache file is a file anyone can write.
- **Only a faster `Binary`** (step 1). If it's enough, that's the outcome.

## Compatibility

- **Additive:** a module and a trait. No source changes.
- **Across builds:** a snapshot from another compiler version, target or type is an `Error`,
  never a wrong value. Programs keep `Binary` or JSON for data that outlives a build.
- **Stage 0:** the compiler's cache can use it only once a release has it; the cache's version
  changes then, as at any change of its format.

## Pragmatics

- **Diagnostics:** `Derive(Snapshot) on Session: field socket: TcpStream has no snapshot`;
  `Snapshot.ofBytes`'s errors name what and where (`a pointer at 4,112 leaves the bytes`).
- **Tooling:** none new. `zs fuzz` gets a target in the suite.
- **Performance:** step 0's numbers, then the load of the same cache both ways, in
  `docs/reports`. The claim to test: loading at memory speed, several times `Binary`'s.
- **Scaling:**

  | | Typical | Stress |
  |---|---|---|
  | a snapshot | 100 KB (a module's interface) | 1 GB |
  | objects | 10⁴ | 10⁸ |
  | a list's length | 10³ | 10⁷ (no recursion in the pass) |

- **Culture-aware formatting:** none.

## Unresolved questions

1. **Is it needed?** Step 0 decides.
2. **`Map`, `Set`, `HashMap`:** a check function a type supplies (its order, in one pass), or
   written as arrays and rebuilt?
3. **A mapped file:** `File.map` doesn't exist. A private mapping would let the kernel page a
   large snapshot in, but the pass touches every page anyway.
4. **32-bit and 64-bit:** an `Error` across them (the draft), or a second, slower reader?
5. **The attribute:** `[<Derive(Snapshot)>]` reads as a library derive but the compiler writes
   it. Is that the spelling?
6. **Chips:** a snapshot in flash can't be written to, so it would need counts of 0 and fixed
   addresses, which 0014's constants already are.

## History

- 2026-11-14: drafted, from Goose's position-independent values, alongside 0035.
