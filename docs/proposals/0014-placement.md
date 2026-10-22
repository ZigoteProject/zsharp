# Proposal 0014: placement: constants in flash, the heap, `[<Section>]` and `[<Align>]`

| | |
|---|---|
| **Status** | Approved in principle for constants in flash and the heap (track M items 3 and 7); Draft for `[<Section>]` and `[<Align>]` (item 12, after phase 11) |
| **Decided at** | track M's plan ([ROADMAP](../../ROADMAP.md#microcontrollers-m)) for items 3 and 7; the third design review ([ROADMAP](../../ROADMAP.md#third-design-review)) for item 12 |
| **Builds** | track M: items 3 and 7 next, item 12 after phase 11 |
| **Rests on** | decisions 2 (Perceus), 7 (arrays are values, `Buffer` is shared), 8 (static cells with count 0), 26 (`zig cc`) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §5.1](../../DESIGN.md#51-representation), [§5.2](../../DESIGN.md#52-perceus-reference-counting), [§10](../../DESIGN.md#10-targets) |
| **Related** | [0013 bit fields](0013-bit-fields.md) (register records as constants), [0012 interrupts, `[<NoAlloc>]` and intrinsics](0012-interrupts-noalloc-intrinsics.md) (`--no-heap`, a `Buffer` shared with a handler), [0016 async on bare metal](0016-async-bare-metal.md) (what fits the heap), [0004 C layout](0004-c-layout.md) (`sizeof`, `alignof`, `fixed`), [0018 packages](0018-packages.md) (the `[target.<name>]` table) |

- [x] Approved in principle (constants in flash, the heap)
- [ ] Discussion (`[<Section>]`, `[<Align>]`)
- [ ] Implementation

## Summary

Where a top-level value's memory is. Three things, from the roadmap's track M:

1. **Constants in flash (item 3).** A top-level value built from literals and the constructors of immutable types (an array or list literal, a record, a union case, a string) becomes a static object with count 0 in `.rodata`, as string literals and the cases without fields already are. It costs no startup code and no RAM, and copy-on-write keeps it correct: a static object is never unique, so a write copies it.
2. **The heap (item 7).** The embedded runtime reuses freed blocks over 256 bytes through a first-fit list, and a project sets the heap and stack sizes per target in `zs.toml`.
3. **Placement (item 12, after phase 11).** `[<Section ".noinit">]` on a top-level value puts its storage in a named section (memory that survives a reset, a DMA region a linker script names), and `[<Align 32>]` on a value or a type aligns it (DMA buffers, cache lines).

```fsharp
let crcTable = [| u32 0x00000000; u32 0x77073096; u32 0xEE0E612C (* … 253 more *) |]   // flash: no code, no RAM

[<Section ".noinit">]
let bootCount = ref 0                      // survives a reset: validate before trusting it

[<Section ".dma"; Align 32>]
let rxFrame = Buffer.create 1536 (u8 0)    // static storage in the DMA region, 32-byte aligned
```

```toml
[target.cortex-m0plus]
heap = "6K"
stack = "2K"
```

## Motivation

**A table in flash.** A table-driven CRC-32 holds 256 words. In C it's `static const uint32_t table[256]`: 1 KB of flash and nothing else. In Z# today the array literal isn't a constant (`Typer.isConstant` admits only the empty array literal, src/Typer.fs ~3200 in the main tree, with the comment "a list of elements allocates, so it's a value computed at startup"), so the table is a startup value: an init function in flash that allocates the array on the heap and stores 256 words, a global holding the pointer, and the heap space for the program's lifetime. On the `cortex-m0plus` with its 8 KB heap, the table is an eighth of it. [The report](../reports/microcontrollers.md) measured the shape of this: `crc32`'s 4 KB buffer costs 4,144 bytes of heap where C uses a static array. A lookup table, a font, a sine table, a list of commands, a record of calibration defaults: firmware is full of these, and today each costs RAM and startup time.

**A library without startup.** A `--lib` build has no startup to compute values in, so `let table = [| … |]` in a library is an error today ("top-level value 'table' is computed at startup, which a library doesn't have; make it a constant or a function", src/Driver.fs ~665 at HEAD). With this proposal it's a constant, and a C program linking the library sees `.rodata`, as it expects.

**A heap that runs out.** `rt-embedded.c`'s allocator keeps free lists per 8-byte class up to 256 bytes and never reuses a larger block (the note at ~line 128 at HEAD: "blocks over 256 bytes are never reused; a first-fit list if programs need it"). A program that makes a 1 KB array per frame and drops it takes fresh heap each frame, and the `cortex-m4`'s 64 KB heap is gone after about sixty frames (estimate) with `panic: out of memory`. Perceus reuse doesn't help: `Array.create` is a call, not a constructor that a match consumes. And the heap's size is the chip's default (64 KB or 8 KB, `Driver.mcus`, src/Driver.fs ~359 at HEAD), with no way to say that this program needs 2 KB of heap and 6 KB of stack, or the reverse.

**Memory with an address.** A DMA controller writes into a buffer the program gave it; the buffer must not move, must be aligned as the controller demands (32 bytes on a Cortex-M7 with a cache), and often must sit in a particular RAM that the linker script names. A boot counter or a crash log must survive a reset, so it can't be in `.data` (copied over at reset) or `.bss` (zeroed). C does all of this with `__attribute__((section(".noinit")))` and `_Alignas(32)`; Z# has `Buffer` for a shared mutable region, and no way to say where it is.

**Without the feature:** tables are computed at startup, cost RAM, and can't be in libraries; per-frame scratch arrays leak the heap; heap and stack sizes are edited in the compiler; DMA and no-init memory need a C file.

## Detailed design

### Constants: what becomes a static object

- **Today's rule** (DESIGN §2.1, phase L): a top-level `let` whose body is a constant is inlined at each use; any other top-level value is computed once at startup, in module order, and freed at exit. `Typer.isConstant` (src/Typer.fs ~3177 in the main tree) admits literals, negation, `not`, measure and type annotations, names of constants and of cases without fields (`[]` too), operators, `if` with both branches, tuples, records, the empty array literal, constructor calls other than `::`, and the number conversions, each over constants.
- **The rule extends** to non-empty array literals, list literals and `::`, over constants. With them it reads: *literals and the constructors of immutable types, applied to constants.*
- **Two kinds of constant.** A constant whose value is a plain value (DESIGN §5.1: numbers, `bool`, `char`, tuples, records and small unions of those) stays as it is: inlined at each use, no memory. A constant whose value is a heap object (a string, an array, a list, a boxed union case with fields, or a record or tuple holding one) becomes **one static object**: an LLVM `constant` global with the object's layout and count 0, in `.rodata`, and each use is its address. A record with an array field is inlined as a plain value whose field points at the static array.
- **Static means what it already means.** String literals (`@.str.N`, `{ i_W 0, i_W len, bytes }`, src/Codegen.fs ~848 in the main tree), `@zs.none` and the cases without fields (`nullary`, ~640) are static objects today, with count 0. `zs.dup` increments only a positive count, and `zs.release` frees only at 1 and decrements only above 1 (the IR prelude, src/Codegen.fs ~195–230, main tree), so a static object is never counted and never freed, in threaded builds too (a negative count marks a shared object; 0 is neither). Reference counting needs nothing new.
- **Copy-on-write stays correct.** The uniqueness check that `a.[i] <- x`, `Array.set` and Perceus reuse rely on is `count = 1` (`@"unique.array<T>"`, ~1138; reuse, ~2430). A static object's count is 0, so it's never unique: a write copies it, as a write to a shared array does; reuse never writes into it; and a program can't tell a static array from one it allocated, except through `Runtime.allocations`, which counts fewer.
- **Linkage:** one address per program, as for the cases without fields: `private` in a single-module build, `linkonce_odr hidden` (`shared`, src/Codegen.fs ~507) when a program is built as several modules, each defining the constants it uses and the linker merging them.
- **What stays a startup value:** anything computed (`Array.init 256 f`, `Map.ofList …`, a call of any function), anything mutable (`Buffer.create`, `ref`), and lambdas. Decision 20 rules out running code at compile time, so a table that needs computing is computed at startup, written out as a literal, or produced by a type provider ([0001](0001-type-providers.md)).
- **Hosted targets** get the same: fewer init functions and no startup allocations; `.rodata` is `.rodata` on Linux too.

```fsharp
let crcTable = [| u32 0x00000000; u32 0x77073096 (* … *) |]          // array<u32>: 1 KB of .rodata

let commands = [ "help"; "reset"; "status" ]                          // three static list cells and three static strings

type Mode = | Idle | Run of int
let presets = [| { name = "slow"; mode = Run 10 }; { name = "stop"; mode = Idle } |]   // plain records, static strings

let crc32 (data: span<u8>) =
  let mutable crc = u32 0xFFFFFFFF
  for b in data do
    crc <- crcTable.[int ((crc ^^^ u32 b) &&& u32 0xFF)] ^^^ (crc >>> u32 8)
  crc ^^^ u32 0xFFFFFFFF

let main () =
  let mutable t = crcTable
  t.[0] <- u32 1          // t is now a copy on the heap; crcTable is unchanged, in flash
  0
```

### The heap

- **Large blocks.** `zs_free` puts a block over 256 bytes on one list of large free blocks, keeping its size in the 8-byte header it already has (`runtime/rt-embedded.c` ~93–140 at HEAD). `zs_alloc` for a size over 256 bytes walks that list first-fit: a block that fits is split when the remainder holds a header and 8 bytes, and the remainder goes back on the list; when nothing fits, the block comes from the top, as today. A freed block whose end is the top of the heap lowers the top instead, so a program that allocates and frees one large array at a time never grows the heap. A freed block merges with the free block after it, found through its size (the header's lowest bit marks a free block; sizes are multiples of 8). Merging with the block before it needs a footer: *Unresolved questions*.
- **Small blocks** are untouched: the 33 class lists (`H.free_lists`), their fast path, and the `bench/mcu` ratios.
- **Out of memory** says what was asked and what there was: `panic: out of memory: 1032 bytes asked, 7912 of the 8192-byte heap in use (zs.toml [target.cortex-m0plus] heap)`, instead of today's bare `out of memory` (~line 115).
- **Sizes in `zs.toml`:**

```toml
[target.cortex-m4]
heap = "16K"       # bytes, or with a K or M suffix; the chip's default when absent (64K; 8K on cortex-m0plus)
stack = "4K"       # the board's default when absent (microbit 4K, mps2-an386 32K)
```

  `heap` becomes `-DZS_HEAP_SIZE=16384` on the runtime's compile, where the driver passes the chip's default today (src/Driver.fs ~1568 at HEAD, ~1822 in the main tree), and `stack` becomes `_stack_size = 4096;` at the head of the linker script the driver already writes (it splices `cortex-m.ld` into the board's, ~1553 at HEAD), with the board files' own assignments moved behind `DEFINED`. `[target.<name>]` is the manifest's per-target table, which [0018](0018-packages.md) lists and whose `[target.<name>.c]` subtable [0022](0022-targets-macos-windows.md) uses for C flags; `heap` and `stack` are its two keys here. A single-file build without a project keeps the defaults.
- **Too much:** `cortex-m.ld`'s `ASSERT` fails when data, bss, the heap and the stack don't fit the RAM; the driver turns the linker's line into its own, with the numbers (*Diagnostics*).
- **What to set:** the exit report's `#zs heap_peak=… heap_reserved=… stack=…` line (`report`, `rt-embedded.c` ~345) is the measurement; `heap` a little above `heap_reserved`, and `stack` above `stack`, is the setting.

### `[<Section>]` *(after phase 11)*

- **Form:** `[<Section ".noinit">] let v = e` on a top-level value, with `e` one of: `Buffer.create n x` with `n` and `x` constants; `ref x` with `x` a constant; a constant.
- **Meaning:** the value's object is a static object with count 0 (never freed, never unique) in the named section, instead of a heap object made at startup. For a `Buffer` or a `ref` it's a `global`, written through as any `Buffer` or `ref` is; for a constant it's the `constant` of the previous section, placed in that section instead of `.rodata`.
- **Filling:** a `Buffer` or `ref` in a section is filled at startup by its init function, as `Buffer.create` fills heap memory, **unless the section is `.noinit`**: then nothing is written, and the contents are whatever the memory held, the previous run's after a reset. A program validates them before trusting them (a magic word, a checksum), as a C program does. A constant in a section carries its contents in the image, and the linker script decides whether that's flash or a copy into RAM.
- **The linker script's part:** `cortex-m.ld` gains `.noinit (NOLOAD) : { . = ALIGN(4); *(.noinit*) } > RAM` after `.bss`, which `Reset_Handler` neither copies nor zeros (it copies `_sdata` to `_edata` from flash and zeros `_sbss` to `_ebss`, `rt-embedded.c` ~356–359), and the stack `ASSERT` counts it. Any other name (`.dma`, `.sram2`) is placed by the board's script in the region it means; without a line for it, the linker places the section as an orphan after `.bss`, in RAM, which is right for a buffer.
- **`.data` on a constant** is the one useful case of a constant in a section: `[<Section ".data">] let sine = [| … |]` is copied to RAM by the reset handler's loop, for a table read in a hot loop on a chip whose flash has wait states. RAM for speed, chosen per table.
- **Where it applies:** top-level values only; functions (code in RAM, `.ramfunc`) are in *Unresolved questions*. On hosted ELF targets the name is emitted as given; macOS and Windows ([0022](0022-targets-macos-windows.md)) name sections differently, so the name is dropped there, and the storage is static all the same, which keeps a firmware module building and testing on the host.
- **With `--no-heap` and `[<NoAlloc>]`** ([0012](0012-interrupts-noalloc-intrinsics.md)): a static object is not an allocation, so a program with no heap at all can have tables, a `.noinit` log and a DMA buffer; the allocation analysis gives such a site the verdict *static*. A `Buffer` in a section is the natural thing to share with an interrupt handler, since `Buffer` is `Share`.

### `[<Align>]` *(after phase 11)*

- **On a value:** `[<Align 32>] let frame = Buffer.create 1536 (u8 0)` aligns the static storage so (`align 32` on the global), with the element data starting at a multiple of it after the header. It applies to the values `[<Section>]` applies to, with or without a section.
- **On a type:** `[<Align 32>] type Frame = { … }` gives every value of the type that alignment wherever it sits: a stack slot, a field, an array or `Buffer` element (the stride rounds up, as C's `_Alignas` makes it), and a heap cell of a boxed union. `alignof<Frame>` and `sizeof` ([0004](0004-c-layout.md)) say so, and a `[<CLayout>]` record with it matches a struct declared with `_Alignas`.
- **The allocator:** a heap object of an aligned type comes from `zs_alloc_aligned(size, align)`: on the host `aligned_alloc`, as `zs_alloc_wide` does for 64-byte vectors (`runtime/rt.c` ~135 in the main tree), with the `SYSTEM` class in its header; in `rt-embedded.c` a free list per size class and alignment, carved from the top at the alignment (the gap before the block, up to `align − 8` bytes, is left), with the alignment recorded in the header's spare low bits so `zs_free` finds the list. Today's embedded `zs_alloc_wide` is `zs_alloc` (~401), since LLVM does a vector's lanes one at a time there; aligned types are the first thing on a chip that needs more than word alignment.
- **Values:** a power of two from 8 to 4096; 8 is what every object has.

### Order of implementation

1. **Constants in flash (item 3):** `isConstant` takes array and list literals and `::`; `Typer` tells the two kinds apart by the constant's type; `Codegen` emits a static object per heap constant, with `shared` linkage, and no init function or global for it. Tests: `tests/static.zs` prints a constant array, list and record, writes to copies of them, sums them in a loop, and runs under `ZS_LEAKCHECK=1`; `tests/cexport` gains a library with a constant table; for the chip, `llvm-size` of a build with a 1 KB table shows it in text, not in data or bss, and `heap_peak` doesn't move with the table's size (`bench/mcu/run.sh` prints both).
2. **The heap (item 7):** the large list, splitting, forward merging and the top block in `rt-embedded.c`; the out-of-memory message; `heap` and `stack` in `readManifest`, the `-D` and the script line; the RAM-overflow diagnostic. Tests: a QEMU program that allocates and drops a 1 KB array 1,000 times on the 8 KB heap; one with `heap = "2K"` whose `heap_reserved` stays under it; `bench/mcu` within its ratios, heap peaks included.
3. **`[<Section>]` and `[<Align>]` (item 12, after phase 11):** the attributes on values and types, `.noinit` in `cortex-m.ld`, the aligned lists and `zs_alloc_aligned`. Tests: a program that counts boots in a `.noinit` `ref` and resets the chip through the AIRCR register prints `boot 2` on its second start under QEMU; an aligned `Buffer`'s address is a multiple of 32; a `[<CLayout>]` record with `[<Align 16>]` matches C's `_Alignas(16)` struct through `import c`.

Each step keeps `./test.sh` green on the host and `bench/mcu/run.sh` within its ratios.

## Drawbacks

- **Flash reads cost more than RAM reads on real chips.** At high clocks a flash read takes wait states that the chip's accelerator hides only partly; QEMU doesn't model them, so `bench/mcu` won't show the difference. A table in a hot loop asks for RAM with `[<Section ".data">]` (item 12) or is copied at startup (`let fast = Array.copy table`); the default puts tables where C's `const` puts them.
- **Two rules to know:** what's a constant (static, no RAM) and what's computed at startup (RAM). The line is the expression's shape, the same line phase L drew for inlining, and hover says which side a value is on (*Tooling*).
- **Two attributes more** for the third design review's "Simple" check (decision 39). Each replaces a C file and a linker-script edit, and neither runs anything.
- **First fit fragments.** A long-running program with large blocks of varied sizes can fragment the list until a request fails while enough bytes are free in pieces. Forward merging and the top block bound it; a program past them is one for an arena (item 8) or a `Buffer` it keeps.
- **`.noinit` trusts the program.** Nothing checks that the contents are valid after a reset; a program that forgets the magic word reads garbage, as in C. The guide's example ([microcontrollers](../guide/11-microcontrollers.md)) validates.

## Alternatives

- **A `const` keyword** (Zig's `const` and `comptime`, Rust's `const` and `static`): the programmer says what's constant. The compiler knows already from the expression's shape (`isConstant`), and a keyword would add a second top-level `let` under decision 34 for information the checker has. Not chosen.
- **A `static` storage class** (C's `static const uint32_t table[256]`, `static uint8_t buf[512]`): placement by keyword. Z# values have no storage classes, and the one case that needs a word from the programmer, a `Buffer` in a named section, is what attributes are for, as `[<Export>]` and `[<CLayout>]` are. Not chosen.
- **The linker script alone,** which is how C does half of `.noinit`: the script places the section, but nothing in the language says that a value's storage is static and unfilled, and that half is the compiler's. Not chosen alone; the script keeps its half.
- **`.noinit` buffers allocated at startup** from a reserved region: the contents would survive, but the address would depend on allocation order, so a reset couldn't find them again. Not chosen.
- **Folding `Array.init` at compile time** (C++'s `constexpr`, Zig's `comptime`): decisions 20 and 26 rule out running code in the compiler. A computed table is computed at startup, written out, or provided ([0001](0001-type-providers.md)). Not chosen.
- **A better large-block allocator** (TLSF, a buddy system): constant time, and more code in a runtime of a few kilobytes, for lists that hold a handful of blocks in practice. First fit is some thirty lines (estimate); *Scaling* says when to revisit.
- **Heap and stack on the command line** (`--heap 16K`): a project setting belongs with its target in the manifest, next to [0018](0018-packages.md)'s target table, not in every build command. Not chosen; a flag can come when a script needs one.
- **Doing nothing:** tables in RAM, no tables in libraries, leaking large blocks, sizes in the compiler, DMA in C. It works for `bench/mcu`'s seven programs and not for firmware.

## Compatibility

- **Not a breaking change.** A constant array or list behaves as the value it was: the same contents, a copy on a write, the same equality. The differences are a lower `Runtime.allocations`, no init function, and that a library may hold one. Startup order is unchanged for the values that still have it.
- **An older compiler** computes the constants at startup as before; on `[<Section>]` or `[<Align>]` on a value it stops with `attributes are only supported on type declarations yet` (src/Typer.fs ~3631 in the main tree), on `[<Align>]` on a type with `unknown attribute 'Align'` (~3630), and on `[target.cortex-m4]` with `unknown section [target.cortex-m4]` (src/Driver.fs ~113).
- **Compiled binaries:** none to consider; packages are source (decision 27).
- **The library:** no source change. `HashMap.empty`'s buckets are the empty array literal, a constant already, and any table in Core moves to `.rodata` by itself.
- **Microcontrollers:** the point of the proposal; the `bench/mcu` ratios are the regression test. With `--no-heap` ([0012](0012-interrupts-noalloc-intrinsics.md)), static objects are what a program's data can be.
- **Hosted targets:** constants in `.rodata` and the same attributes; section names are emitted on ELF and dropped on macOS and Windows ([0022](0022-targets-macos-windows.md)).

## Pragmatics

### Diagnostics

| Situation | Error |
|---|---|
| `[<Section>]` on a value that isn't a constant, a `Buffer.create` or a `ref` of constants | `[<Section>] needs a constant, 'Buffer.create n x' or 'ref x' with constant arguments; 'Array.init 256 f' is computed at startup. Write the table as a literal, or fill a Buffer in main` |
| `[<Section>]` or `[<Align>]` on a function or a local | `[<Section>] applies to top-level values; 'tick' is a function` |
| a section name that isn't one | `section name " no init" isn't valid: letters, digits, '.', '_' and '$', no spaces` |
| `[<Align 24>]` | `[<Align>] takes a power of two from 8 to 4096; 24 isn't one` |
| `[<Align>]` on a type that can't carry it | `[<Align>] applies to records and unions; 'Handler' is a function type` |
| `heap` under a hosted target | `zs.toml: heap applies to bare-metal targets (cortex-m4, cortex-m0plus); a hosted target uses the system allocator` |
| a size that isn't one | `zs.toml: heap = "16 kilobytes" isn't a size; write bytes, or a K or M suffix: "16K"` |
| an unknown target | `zs.toml: unknown target [target.cortex-m3]; the targets are cortex-m4, cortex-m0plus, …` (the hosted names are [0022](0022-targets-macos-windows.md)'s) |
| the RAM doesn't hold it (the linker's `ASSERT`, reworded by the driver) | `cortex-m0plus: 16 KB of RAM doesn't hold 2112 bytes of data and bss, the 12 KB heap and the 4 KB stack: 2160 bytes over. Lower heap or stack in zs.toml's [target.cortex-m0plus]` |
| out of memory at run time | `panic: out of memory: 1032 bytes asked, 7912 of the 8192-byte heap in use (zs.toml [target.cortex-m0plus] heap)` |
| a write to a constant | no error: `t.[0] <- x` on a `let mutable t = table` copies, as a write to a shared array does |

### Tooling

- **`zs lsp`:** hover on a top-level value shows its type and, after it, `constant` for one inlined, `constant, static` for a static object, and `computed at startup` for the rest, from the checker's own decision (the hover text is `Typer`'s, so the editor needs no build). Completion and definition are unchanged. The attribute errors above are the checker's, so they show as they're typed; the `zs.toml` errors show when the server reads the manifest; the RAM-overflow error only on a build, since it's the linker's.
- **The tree-sitter grammar** gains nothing: attributes with string and number arguments parse already (`[<Target "avx2">]`, `[<Multiversion("a", "b")>]`).
- **`zs build --time`** on a microcontroller target adds a line with the image's memory: flash, data, bss, heap and stack against the RAM, from the ELF's section sizes, as `bench/mcu/run.sh` reads them with `llvm-size`.
- **`zs doc`** marks a constant as such on its page. **gdb** shows a static array as any array ([0011](0011-debug-info-profiles-traces.md)).

### Performance

- **Constants:** no init function, no global load at a use (the address is immediate), no heap object, no RAM; a read is a flash read. `crc32` with a 1 KB table: 1 KB of flash and 0 bytes of heap, against about 1 KB of heap plus headers and an init function today (estimate; the exit test measures).
- **Copy-on-write:** the check stays the one compare it is; a static object fails it and is copied once, into a heap array with count 1 that's unique from then on.
- **The heap:** the small-class fast path is untouched. A large allocation walks the large list (first fit, linear in the free blocks on it) only when the list isn't empty; the per-frame array case hits the top block and costs what today's bump does.
- **`.noinit`:** no fill, so a 4 KB log costs no startup cycles.
- **Aligned objects:** up to `align − 8` bytes of gap per block carved; their own lists keep them out of the ordinary classes.
- **Sizes:** `heap` and `stack` cost nothing at run time.

### Scaling

| Dimension | Typical | Upper bound |
|---|---|---|
| elements in one constant table | 256 | 1,000,000 (the IR initializer is written once, linear; a 4 MB table fits the mps2-an386's flash) |
| static objects per program | 10 | 10,000 (one global each, linear in the module's IR) |
| nesting of a constant (arrays of records of lists) | 2 | 100 |
| values with `[<Section>]` or `[<Align>]` | 1–5 | 100 |
| blocks on the large free list | 0–10 | 1,000 (first fit walks them; past that, an arena or a kept `Buffer`) |
| heap size | 8–64 KB | the chip's RAM (4 MB on the mps2-an386) |
| alignment | 32 | 4096 |

### Culture-aware formatting and parsing

- **Invariant throughout.** `heap` and `stack` are digits with an optional `K` or `M`, no grouping, no locale; the diagnostics and the exit report print plain digits, in every locale.

## Unresolved questions

1. **Merging backward.** This document merges a freed block with the free block after it and returns the top block; merging with the block before needs a footer in each free block. Chosen: forward only, until a program shows fragmentation; the alternative is boundary tags both ways from the start.
2. **`.noinit` on hosted targets.** Chosen: never filled, on any target (the loader's zero pages on Linux, so a host test sees zeros and the chip sees what was there). The alternative, filling on hosted targets, makes one program mean two things.
3. **`[<Section>]` on functions** (code in RAM, `.ramfunc`, or a boot section). Chosen: values only, since no example needs it yet; LLVM supports it, so adding functions is small when one does.
4. **`import c` and alignment.** Chosen: a struct clang reports as over-aligned (`_Alignas`, `__attribute__((aligned))`) imports with `[<Align n>]`; the alternative leaves it out, as bit-fields are left out ([0004](0004-c-layout.md)).
5. **The reach of the constant rule.** Chosen: literals, constructors, conversions and operators, as `isConstant` has, plus array and list literals. The alternative folds `Array.init` and `List.init` with literal bounds and pure bodies in the optimizer, a step toward compile-time evaluation that decision 20 declines.
6. **`stack` under a hosted target.** Chosen: an error, as `heap` is, since the OS sets the main thread's stack; the alternative passes it to the linker, which only Windows honours.
7. **Decision rows.** Constants in flash and the heap extend decisions 7 and 8 and need no row; `[<Section>]` and `[<Align>]` get a new decision row, numbered by the coordinator, when the third design review takes them.

## History

- **2026-10-22:** drafted from track M items 3, 7 and 12 (ROADMAP), DESIGN §5.1's static objects and `rt-embedded.c`'s heap.
