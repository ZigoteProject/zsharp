# Proposal 0013: bit fields

| | |
|---|---|
| **Status** | Approved in principle (decision 59), after phase 11; before 0.1 if the flagship is a microcontroller |
| **Decided at** | the third design review ([ROADMAP](../../ROADMAP.md#third-design-review-)): the field-attribute position is part of decision 59 (question 7) |
| **Builds** | track M item 9 ([ROADMAP](../../ROADMAP.md#microcontrollers-m)), after phase 11; the `svd` provider in [0001](0001-type-providers.md) waits for it |
| **Rests on** | decisions 4 (overflow traps), 10 (structural equality, ordering, hashing and printing), 20 (derive, no macros or comptime) and 53 (no general type-level numbers) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §2.3](../../DESIGN.md#23-default-fields-named-and-optional-arguments) (field defaults), [§5.1](../../DESIGN.md#51-representation) (plain values, enums as bytes) and [§11](../../DESIGN.md#11-c-interop) |
| **Related** | [0001 type providers](0001-type-providers.md) (the `svd` provider writes these records), [0004 C layout](0004-c-layout.md) (C unions; C's bit-fields stay out of `import c`), [0014 placement](0014-placement.md) (`[<Align 32>]` shares the number argument), [0012 interrupts, NoAlloc and intrinsics](0012-interrupts-noalloc-intrinsics.md) (registers written from handlers) |

- [x] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

A `[<Bits>]` record is one unsigned integer whose fields are ranges of its bits. The record
is written, read, copied and printed as a record; it's stored, compared, hashed and passed to
C as the integer. The compiler generates the shifts and masks from the field types:

```fsharp
/// USART control register 1 (CR1, offset 0x0C, reset 0x0000)
[<Bits 32>]
type Cr1 =
  { sbk: bool = false                   // bit 0: send break
    rwu: bool = false                   // bit 1: receiver wakeup
    re: bool = false                    // bit 2: receiver enable
    te: bool = false                    // bit 3: transmitter enable
    idleie: bool = false                // bits 4 to 8: the interrupt enables
    rxneie: bool = false
    tcie: bool = false
    txeie: bool = false
    peie: bool = false
    ps: Parity = Even                   // bit 9
    pce: bool = false                   // bit 10: parity control enable
    wake: bool = false                  // bit 11
    m: WordLength = Bits8               // bit 12
    ue: bool = false                    // bit 13: USART enable
    [<Bit 15>] over8: bool = false }    // bit 14 is reserved

type Parity = | Even | Odd
type WordLength = | Bits8 | Bits9

module Cr1 =
  let private address = usize 0x4000440C
  let read () : Cr1 = Bits.ofU32 (Mmio.read32 address)
  let write (r: Cr1) = Mmio.write32 address (Bits.toU32 r)
  let modify (f: Cr1 -> Cr1) = write (f (read ()))

let enable () = Cr1.write { ue = true; te = true; re = true }      // one store of 0x200C
let noBreak () = Cr1.modify (fun r -> { r with sbk = false })     // a load, an and, a store
```

Reading a field extracts its bits, `{ r with f = v }` is a masked write, a literal is the OR
of its shifted fields with the defaults (DESIGN §2.3) giving the rest, so a register's reset
value is its defaults. A value too wide for its field panics as an overflow does (decision 4).
Two field attributes, `[<Width n>]` and `[<Bit n>]`, are the first in the language. `Bits.toU32`
and `Bits.ofU32` (and the other widths) convert at the record's width, and `Bits<'r>` is an
auto trait so generic code can take any such record. No new integer types (`u2`, `u5`), and
C's bit-fields stay out of `import c`.

## Motivation

**Registers.** `examples/mcu/nucleo-f401.zs` (lines 111–142 at commit d6eb26d) drives the
STM32F401's USART with `bit 13 ||| bit 3 ||| bit 2`, `modify gpioaModer (u32 0xCF0) (u32 0x4A0)`
and `Mmio.write32 usartBrr (u32 0x8B)`. Each constant was typed from the reference manual, and
nothing checks it: a wrong shift is a wrong store, found with a logic analyzer (0001's third
motivation). With the record above, `enable` says what the manual says, a field that doesn't
exist is a type error, and a value that doesn't fit its field is a panic, not a store into the
neighbouring field. The `svd` provider ([0001](0001-type-providers.md)) writes such records for
every register of a chip; this proposal is what it writes against.

**Headers and formats.** An IPv4 header starts with a 4-bit version and a 4-bit header length;
its third word is 3 flag bits and a 13-bit fragment offset; a CAN identifier is 11 or 29 bits
in a 32-bit word. Each is a `[<Bits>]` record parsed from a `span<u8>`
([0003](0003-spans-and-slices.md)) with `Bits.ofU16` or `Bits.ofU32`.

**Packed state.** A program that keeps eight booleans in a `u8` to fit a table in cache, or a
chess move in 16 bits, reads them as named `bool`s and enums, at the same size.

**What exists.** Masks over `u32` with the bitwise operators
([guide](../guide/11-microcontrollers.md)): they work, as the example shows, and every
constant in them is unchecked. Without the feature, the `svd` provider would write a getter and
a setter per field, with the shifts in generated text instead of in the compiler, and a
hand-written driver would keep its masks.

**Why a language feature.** Decision 39's test: it replaces code people write by hand, and
it needs no runtime. The compiler knows each field's width from its type (a `bool` is a bit,
an enum as many as its cases need), which no library over `u32` can know.

## Detailed design

### Syntax

```
type-decl    +=  '[<' 'Bits' [ number ] '>]' record-type-decl
field        :=  [ field-attrs ] ident ':' type [ '=' expr ]
field-attrs  :=  '[<' field-attr { ';' field-attr } '>]'
field-attr   :=  'Width' number | 'Bit' number
```

- **`[<Bits>]`** marks a record; **`[<Bits 32>]`** fixes its width to 8, 16, 32 or 64 bits. Attribute arguments today are strings or identifiers (`Syntax.fs:2354` on; line numbers in this proposal are approximate, from the main checkout on 2026-10-22); a number (`KInt`, `Syntax.fs:182`) becomes a third form, which [0014](0014-placement.md)'s `[<Align 32>]` uses too.
- **Field attributes** are new: a record field is an identifier, a type and an optional default (`typeBody`, `Syntax.fs:2199` on), and DESIGN §3.1 says "there are no field attributes yet". This proposal adds the position with two attributes only, `[<Width n>]` and `[<Bit n>]`, allowed on fields of a `[<Bits>]` record and nowhere else. They're the precedent: a later field attribute (a JSON key's name, say) uses the same position and parser, and each one needs its own proposal.
- **Combined:** `[<Bit 4; Width 12>] div_mantissa: u16` places and narrows one field. The order inside `[< >]` doesn't matter.
- **Other attributes** on the type combine as today: `[<Bits 32; Derive(Json)>]`.

### Meaning

- **The whole** is an unsigned integer: the width given, or the smallest of `u8`, `u16`, `u32` and `u64` that holds the highest occupied bit. That integer is the record's representation everywhere: in registers, on the stack, as a field of another record or a union case, in `array<Cr1>` and `Buffer<Cr1>` (a buffer of integers), and at the C boundary. A `[<Bits>]` record is a plain value (DESIGN §5.1) and `Share` by construction: it never allocates, so `[<NoAlloc>]` code ([0012](0012-interrupts-noalloc-intrinsics.md)) uses it freely.
- **A field's type** is `bool`, a union whose cases have no fields (an enum), or `u8`, `u16`, `u32` or `u64`. Nothing else: `int` and `usize` change width with the target, signed and floating-point fields are in *Unresolved questions*, and a heap value has no bits to pack. A `[<Bits>]` record isn't a field of another (its gaps would need a width of their own); nested groups are written as the fields they are.
- **A field's width** comes from its type: `bool` one bit; an enum the bits its cases need (two cases one bit, three or four two bits, five to eight three, and so on); an unsigned integer its size. `[<Width n>]` is required whenever the field has fewer bits than its type (`[<Width 12>] div_mantissa: u16`), and allowed to widen an enum's field (`[<Width 3>]` on a five-case enum); `n` runs from 1 to the type's size, and a `bool` takes none.
- **Placement:** fields fill from bit 0 upward in declaration order. `[<Bit n>]` puts a field at bit `n`, and the next unpositioned field follows it. Two fields never share a bit, and no field reaches past the width: both are compile errors. The bits no field covers are gaps.
- **Enum values** are the case's index in declaration order, as the byte of an enum is today (`Codegen.fs:26, 524`): `Alternate` in `| Input | Output | Alternate | Analog` is 2. A provider orders cases by the manual's values and names a hole `Reserved3`.
- **Reading** `r.f` shifts and masks: a `bool` is the bit, an integer the bits zero-extended, an enum the case with that index. A value with no case (a reserved value read from hardware, in a widened field) panics, as an index past an array's end does.
- **Writing** `{ r with f = v }` clears the field's bits and ORs `v` shifted into place. When `v` is wider than the field it panics (`integer overflow`, decision 4's trap, in every build); the check is dropped when the value is known to fit: a constant, a `bool`, an enum, an integer field as wide as its type. The other bits, gaps included, are kept, which is what a register's reserved bits need.
- **Construction** `{ ue = true; te = true; re = true }` is the OR of the shifted fields; fields left out take their defaults, which run as DESIGN §2.3 says (an expression, earlier fields visible); a field without a default must be given; gaps are zero. A literal of constants folds to one immediate.
- **Equality, ordering and hashing** are the integer's, gaps included: one compare, and `Bits.toU32 (Bits.ofU32 x) = x` holds. So a register read with a reserved bit set differs from the literal that names the same fields. **`Show`** prints the fields as a record does: `{ sbk = false; rwu = false; …; over8 = false }`, gaps unseen (decision 10's structural printing; the derive sees fields, not the integer).
- **`derive`** (DESIGN §3.1) sees a record with these fields, so `[<Derive(Json)>]` on one writes each field by name; a derive never sees the integer.
- **Narrowing conversions** are unchanged: `u8 300` truncates, as `conv` does today (`Codegen.fs:3739–3757`). The field check is at the write: `{ r with div_mantissa = u16 5000 }` panics, `u16 5000` alone doesn't.

### The `Bits` module and the `Bits<'r>` trait

- **`Bits<'r>`** is an auto trait, as `Share` is (DESIGN §3): it holds for every `[<Bits>]` record and nothing else, has no methods, and can't be implemented by hand (the attribute is the impl, a built-in case in `userImpl` next to `Share`'s, the facts sheet's `Typer.fs:642–668`). Generic code writes `when 'r : Bits`.
- **`Bits`** is a Core module of built-ins, as `Mmio` is (`lib/core/Mmio.zs` is a header; `Typer.fs:279–280`; the list at `Driver.fs:397`), with [0001](0001-type-providers.md)'s spellings:

| Function | Type | Meaning |
|---|---|---|
| `Bits.toU8`, `toU16`, `toU32`, `toU64` | `'r -> uN when 'r : Bits` | the integer, at the record's width only: another width is a compile error |
| `Bits.ofU8`, `ofU16`, `ofU32`, `ofU64` | `uN -> 'r when 'r : Bits` | the record whose integer this is, gaps kept; the record type comes from the expected type |
| `Bits.raw` | `'r -> u64 when 'r : Bits` | the integer zero-extended, for generic code |
| `Bits.ofRaw` | `u64 -> 'r when 'r : Bits` | the inverse; a bit above the record's width set panics (`integer overflow`) |

- **Widths in generic code:** `sizeof<'r>` ([0004](0004-c-layout.md)) is the integer's size, so `sizeof<'r> * 8` is the width; no `Bits.width` is needed. `Bits.toU32` on a type variable is an error pointing at `Bits.raw`, since the width isn't known there.
- **Registers:** `Mmio.read32 addr |> Bits.ofU32` is the read, `Mmio.write32 addr (Bits.toU32 r)` the write, and a `modify` is both around a function, as `Cr1` above and 0001's provided modules show. A 16-bit register wants `Mmio.read16` and `write16`, two built-ins next to `read8` and `read32`; the `svd` provider asks for them when it meets one, and they aren't part of this proposal.

```fsharp
/// Prints any bits record with its integer: a debugging aid for a provided register.
let dump (name: string) (r: 'r) when 'r : Bits = println $"{name} = {r} ({Bits.raw r})"

/// The first word of an IPv4 header, from a packet's bytes: version and header length in
/// the first byte (bits 8 to 15 of the word), the type of service in the second.
[<Bits 16>]
type IpHead = { tos: u8; [<Width 4>] ihl: u8; [<Width 4>] version: u8 }

let ipHead (p: span<u8>) : IpHead = Bits.ofU16 (u16 p.[0] <<< u16 8 ||| u16 p.[1])
```

### C

- **At the boundary** a `[<Bits>]` record is its integer: an `extern` or an `[<Export>]` taking a `Cr1` takes a `uint32_t`, `checkCArg` (`Typer.fs:3001`, run on every extern and export parameter) accepts it as it accepts `u32`, and the header `zs build --lib` writes declares it `typedef uint32_t Cr1;` with the fields in a comment.
- **In a `[<CLayout>]` record** it's a field of its integer type, so a DMA descriptor or a packet header with a flags word matches its C struct; `sizeof` and `offsetof` ([0004](0004-c-layout.md)) see the integer.
- **C's bit-fields** (`unsigned flags : 3`) stay out of `import c`, as DESIGN §11 and 0004's third question say: their order, straddling and storage unit are implementation-defined, so no `[<Bits>]` layout matches them on every compiler. A struct with bit-fields imports with those members as the integer they share, and a program reads it with a `[<Bits>]` record of its own, which is right on the compiler it was checked against and nowhere else; the guide says so.

### Order of implementation

1. **Parser:** a number as an attribute argument; field attributes on record fields (`RecordTy`'s field triple gains them, `Syntax.fs:86`); the tree-sitter grammar's `attributes` rule on fields (`editors/tree-sitter-zsharp/grammar.js:69–84`).
2. **Typer:** the layout (widths, offsets, the whole's width) and its errors, next to `[<CLayout>]`'s branch (`Typer.fs:3598`); the `Bits` auto trait; the `Bits.*` built-ins and their width checks.
3. **Codegen:** the record as its integer; reads, `with`, construction, the overflow and no-case checks; `Eq`, `Ord`, `Hash` as the integer and `Show` per field; the C boundary; debug info ([0011](0011-debug-info-profiles-traces.md)).
4. **Library and docs:** `lib/core/Bits.zs` with its reference page; the register section of the guide's microcontrollers chapter; `tests/mcu/bits.zs` and `.err` files for each diagnostic; `examples/mcu/nucleo-f401.zs`'s hardware section rewritten on records, with a `.same-ir` sidecar (`test.sh:40–46`) against the mask version: the exit test is identical IR.
5. **Then** 0001's `svd` provider, which writes these records.

## Drawbacks

- **Field attributes are a new position,** and once it exists requests follow (key renames for `Json`, column names for `csv`). The precedent is set on purpose and kept to two attributes; each later one is its own proposal.
- **A record literal has two costs.** An ordinary record is a struct; a `[<Bits>]` one is an integer, and `{ r with te = true }` is a masked write, which the literal doesn't show. The attribute on the type and hover's bit positions are the tell.
- **Reads can panic.** An enum field in a widened field panics on a value with no case, so a register read is a possible panic where a mask over `u32` wasn't. Full-width integer fields, `bool`s and enums that fill their width never do, and a provider can name every value.
- **Gaps are visible to `=` and invisible to `Show`:** a surprise once per programmer, documented at the type.
- **No C bit-fields,** so a C struct with them keeps its masks on the Z# side.
- **Surface** for the third design review's "Simple" check: one type attribute, two field attributes, a module of ten functions and an auto trait.

## Alternatives

- **Masks by hand,** what exists (`bit 13 ||| bit 3`, `modify reg mask bits`). Works, unchecked, and the `svd` provider would have to write hundreds of such lines per peripheral. Not chosen for the reason in *Motivation*: the mistakes it allows are the ones the feature exists to make impossible.
- **Narrow integer types** (`u5`, `u12`, as Zig's `u5` and `i7`). A type per width, with arithmetic and conversions at each, and still nothing says where in a register a field sits; the widths would be numbers in types, which decision 53 confines to `fixed`. Track M item 9 says "no new integer types" for this reason.
- **Rust's `bitflags!` and `modular-bitfield`:** macros that generate the accessors. Decision 20 rules out macros; the attribute gives the compiler the same shape with no code generation visible to the programmer, and `derive` keeps working over it.
- **C's bit-fields** (`unsigned te : 1` in a struct). Their layout is implementation-defined, which is why portable drivers avoid them; and a `[<CLayout>]` record with them couldn't be checked against C by `sizeof` alone.
- **A library over `u32`** (`Field.get r 3 1`, `Field.set r 3 1 v`): the trait's `Bits.raw` plus shifts give that today. No named fields, no enums, no defaults as reset values, no `Show` per field, and every width is a literal again.
- **Packing every record of `bool`s automatically,** with no attribute. Changes the representation of records people have, and takes the choice away where a struct is wanted.
- **`[<Bits>]` on unions,** a set of flags as a union of cases. A union holds one case at a time; a set of flags is a record of `bool`s, which is what this gives.

## Compatibility

- **Not a breaking change.** `[<Bits>]` is "unknown attribute 'Bits'" today (`Typer.fs:3630`), `[<Bits 32>]` doesn't parse, and a `[<` where a field name goes fails with the parser's identifier error (`Syntax.ident`, `Syntax.fs:771`), so no existing program changes meaning. `Bits` is a new Core module; a program's own `Bits` module shadows it, as any name shadows the library's.
- **An older compiler** meeting this source stops at the attribute with that message, or at the first field attribute with the identifier error.
- **Compiled binaries:** none to consider. Packages are source (decision 27), and a `[<Bits>]` record leaves no metadata in a binary.
- **The library:** `lib/core/Bits.zs` and its built-ins are added; `Mmio` is unchanged; nothing in `lib/` is rewritten. The `svd` provider's output (0001) uses what this adds and nothing more, so it arrives after it.
- **Microcontrollers:** the feature is Core-only and allocates nothing, so it builds for every target, with `--no-heap`, and inside interrupt handlers. The `bench/mcu` ratios aren't affected: a program without `[<Bits>]` compiles to the same IR as before.

## Pragmatics

### Diagnostics

Each error names the problem, points at the field or the call, and says what to write:

| Situation | Error |
|---|---|
| a field type that isn't `bool`, an enum or an unsigned integer | `field 'count' of [<Bits>] record Cr1 is int: bits fields are bool, an enum, u8, u16, u32 or u64` |
| the fields need more bits than the width | `Cr1's fields need 36 bits and [<Bits 32>] holds 32: the last field, 'over8', starts at bit 35` |
| a width that isn't 8, 16, 32 or 64 | `[<Bits 12>]: the width is 8, 16, 32 or 64; put the fields in [<Bits 16>] and leave the rest as a gap` |
| `[<Width n>]` out of range | `[<Width 12>] on 'div_mantissa': u8 has 8 bits; write u16, or Width 8 or less` |
| `[<Width>]` on a `bool` | `[<Width 1>] on 'te': a bool is one bit; remove the attribute` |
| `[<Width>]` smaller than an enum needs | `[<Width 1>] on 'moder5': Mode has four cases and needs 2 bits; write Width 2 or more, or remove the attribute` |
| two fields share a bit | `'over8' at bit 13 overlaps 'ue' (bit 13): fields of Cr1 can't share bits; move one with [<Bit n>]` |
| a field attribute elsewhere | `[<Width>] is for fields of a [<Bits>] record; Config isn't one` |
| a generic `[<Bits>]` record | `a [<Bits>] record can't be generic` |
| a conversion at the wrong width | `Bits.toU16 on Cr1, which is 32 bits: write Bits.toU32` |
| a conversion on a type variable | `Bits.toU32 needs a known record type; 'r is any bits record here, so use Bits.raw` |
| `Bits.ofU32` with no expected type | `Bits.ofU32: which record? annotate the binding, as in let r: Cr1 = Bits.ofU32 x` |
| `impl Bits<T>` by hand | `Bits is implemented by [<Bits>] on a record, not by impl` |
| a value too wide, at run time | `panic: integer overflow: 5000 doesn't fit the 12 bits of div_mantissa` |
| a reserved value read into an enum, at run time | `panic: bits 4 to 5 of Moder hold 3, which isn't a case of Mode` |

### Tooling

- **`zs lsp`:** the checker's types, with no build run. Hover on a field shows its type and its bits (`te: bool`, then `bit 3 of Cr1`; `div_mantissa: u16`, `bits 4 to 15 of Brr`); on the type, its integer and layout (`Cr1 = u32; 15 fields in bits 0 to 15, bit 14 a gap`). Completion after `r.` lists the fields as for any record; definition and references go to the field and its uses; the layout errors above appear while editing, at the field.
- **Inlay hints:** none new; a `let r = Cr1.read ()` shows `r: Cr1` as any binding.
- **The tree-sitter grammar** gains attributes on record fields and a number as an attribute argument; `zs fmt` keeps a field attribute on its field's line; `zs doc` prints each field's bits after its type.
- **Debugging:** DWARF describes the record as its integer with a `DW_TAG_member` per field carrying `DW_AT_bit_size` and `DW_AT_data_bit_offset`, the form C's bit-fields get, so gdb prints `{sbk = false, …, ue = true}`; the enum's cases are the `DW_TAG_enumeration_type` an enum has today (`diType'`, `Codegen.fs:1713`). [0011](0011-debug-info-profiles-traces.md) owns the details.
- **MCP:** `type_at` and `docs` show the same hover text.

### Performance

- **Existing code:** none; a program without `[<Bits>]` compiles as before.
- **A read:** a shift and an and; a `bool` adds a compare, an enum a range check unless its cases fill the width, then the byte is the tag.
- **A write** (`with`): an and, a shift, an or, and the overflow compare where the value isn't known to fit.
- **A literal of constants:** one immediate. `Cr1.write { ue = true; te = true; re = true }` is one volatile store of `0x200C`, the same instruction `Mmio.write32 usartCr1 (bit 13 ||| bit 3 ||| bit 2)` compiles to today; the exit test holds the whole of `nucleo-f401.zs`'s hardware section to that.
- **Memory:** none; no allocation, no header, no reference count; `array<Cr1>` is an array of `u32`.
- **Compile time:** per record, a pass over its fields; the `svd` provider's 2,000-register module (0001's table) adds a few thousand small layouts, linear in the fields.

### Scaling

| Dimension | Typical | Upper bound |
|---|---|---|
| fields per record | 1–16 | 64 (one per bit of a `u64`) |
| width of a record | 8–32 bits | 64 bits |
| cases in an enum field | 2–8 | 256 (an 8-bit field of named values) |
| `[<Bits>]` records per program | 1–30 | 2,000 (every register of a chip, 0001's SVD bound) |
| conversions per program | 10–100 | 20,000 (a `read` and a `write` per register) |

### Culture-aware formatting and parsing

None. `Show` prints `true`, `false`, case names and integers as it prints them everywhere, invariant; nothing here parses text.

## Unresolved questions

1. **Overlapping `[<Bit>]` offsets:** not allowed (this proposal: each bit belongs to one field, so `with` can't change two). The alternative, overlapping views of the same bits, is what a `[<CLayout>]` union ([0004](0004-c-layout.md)) gives, and a register with two interpretations is two records over one address.
2. **Signed fields:** not supported (this proposal). `[<Width 5>] offset: i8` sign-extended on read, with a two's-complement range check on write, is the alternative; add it when a register needs it (ADC offsets and some PWM dead-time fields are signed).
3. **`[<Bits>]` records as `[<CLayout>]` fields:** yes, as their integer (this proposal), since a flags word in a C struct is the common case. The alternative, refusing them, would send such structs back to masks.
4. **Enum values with holes:** the case's index, with a named case per hole (this proposal), against F#'s enum syntax `| Fast = 3`, which would be a second kind of union. The provider can write either.
5. **Equality over gap bits:** as the integer (this proposal: one compare, and the conversions round-trip), against field-wise equality with a mask, which `Show`'s output would match.
6. **A reserved value read into an enum:** a panic (this proposal) against requiring an enum field to have exactly `2^n` cases, which would make the panic impossible and every provided enum longer.
7. **The field-attribute position's decision row:** part of this proposal's row (this proposal), or a new decision row, numbered by the coordinator, since later field attributes (a `Json` key's name) rest on the position rather than on bit fields.

## History

- **2026-10-22:** drafted from ROADMAP track M item 9, 0001's `svd` section and 0004's bit-field question.
