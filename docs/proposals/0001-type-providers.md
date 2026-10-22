# Proposal 0001: type providers

| | |
|---|---|
| **Status** | Draft |
| **Decided at** | the third design review ([ROADMAP](../../ROADMAP.md#third-design-review)) |
| **Builds** | track P ([ROADMAP](../../ROADMAP.md#type-providers-p)), after phase 11 |
| **Rests on** | decisions 20 (no compile-time code), 27 (source packages), 34 (new syntax needs a design discussion) and 39 ("Simple") in [DESIGN §13](../../DESIGN.md#13-decisions) |
| **Replaces** | track P's sketch, and DESIGN §3.1's "a later generalization of `import c`" |

- [ ] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

A type provider reads a data source when the program is compiled and declares the types and
functions for it, so code against a JSON document, a CSV file, a database schema or a
microcontroller's SVD file is checked against the source's shape:

```fsharp
module Weather = import json "weather.json"

let report (text: string) =
  result {
    let! w = Weather.parse text            // a Weather.Root, with the sample's fields and types
    return $"{w.city}: {w.temp}"
  }
```

`import c "header.h"` already does this for C headers: clang reads the header and the compiler
declares what it finds. This proposal makes `c` one provider among several. A provider is a
program, `zs`'s own or one on PATH, that turns its arguments into Z# source; the compiler
checks that source as a module of its own and caches it with the inputs it came from. No code
runs inside the compiler, nothing is added to the runtime, and the binary carries no metadata:
a provided module is ordinary Z#, which `zs provide` prints, and which a project can keep in
place of the import. In the editor the types are the same ones: the language server runs the
providers and checks their modules, so completion, hover and errors follow the source as it's
edited, with no build run.

## Motivation

**A JSON API.** The records for a three-field response are written by hand with
`[<Derive(Json)>]` in a minute. The records for a forty-field response with nested objects are
an afternoon, and when the API adds a field or makes one optional, nothing says so until a
parse fails at run time. With the provider, the sample document is the source of truth: the
records come from it, and a changed sample makes the code that no longer fits a compile error
that names the field.

**A CSV file.** A tool over `stocks.csv` reads the header once and the rows as typed values:

```fsharp
module Stocks = import csv "stocks.csv"

let highest (text: string) =
  Stocks.parse text |> Result.map (List.maxBy (fun (r: Stocks.Row) -> r.close))   // close: f64
```

**A microcontroller's registers.** `examples/mcu/nucleo-f401.zs` holds eleven register
addresses typed from the reference manual, and masks such as `u32 0xCF0` and
`bit 13 ||| bit 3 ||| bit 2`. A wrong constant is a wrong store, found with a logic analyzer.
The vendor's SVD file describes every peripheral, register, field, reset value and access
right, and Rust's svd2rust shows that generating the access code from it works. With the
provider, the same firmware reads as the manual does, and a write to a read-only register, or
a field the register doesn't have, doesn't compile:

```fsharp
import svd ("STM32F401.svd", only = "GPIOA,RCC,USART2")

let init () =
  Rcc.Ahb1enr.modify (fun r -> { r with gpioaen = true })
  Gpioa.Moder.modify (fun r -> { r with moder5 = Output; moder2 = Alternate; moder3 = Alternate })
  Usart2.Brr.write { div_mantissa = u16 8; div_fraction = u8 11 }      // 115200 baud at 16 MHz
  Usart2.Cr1.write { ue = true; te = true; re = true }
```

**A database schema.** A record per table from the `CREATE TABLE`s in `schema.sql`, with
`option` where a column is nullable, so a row's fields have the schema's types.

**Why a language feature, and not a generator run by hand.** quicktype, svd2rust and sqlc
generate such code, and the output is committed. What the import line adds: the compiler knows
the input and re-runs the provider when it changes, so the code can't go stale; there is
nothing to commit or keep in sync; the editor shows the types without a build step; and a
provider written for Z# writes idiomatic Z# (records with defaults, unions, `result`), where a
general generator writes to the lowest common denominator. Ejecting stays one command away
(`zs provide`), so a project that would rather own the code can.

**What F# has, and what carries over.** F#'s type providers (F# 3.0, 2012; FSharp.Data's
`JsonProvider` and `CsvProvider`, SQLProvider) are compiler plugins: .NET assemblies the
compiler loads, which produce types on demand, usually *erased* (an `obj` or a `JsonValue`
underneath, with the type only at compile time). Z# can't copy the mechanism: there is no
plugin host once the compiler is written in Z# (phase 11), erased types need a runtime
representation Z# has no equivalent of, and decision 20 rules out code running inside the
compiler. What carries over is the experience: name a source, get its types, see them in the
editor, and find out at compile time when the source changed.

## Detailed design

### Syntax

```
declaration  +=  import-decl
              |  'module' ident '=' import-decl        // the provided declarations, as a module
import-decl  :=  'import' ident import-args
import-args  :=  string
              |  '(' string { ',' ident '=' constant } ')'
constant     :=  string | number | 'true' | 'false'
```

- **`import c "raylib.h"`** is the existing form, which the parser today accepts with `c` only. `c` becomes one provider name; the attribute `[<Link>]` keeps applying to it.
- **A module from an import:** `module Weather = import json "weather.json"` puts the provided declarations in `Weather`. Today `module X =` takes an indented block; this is the one other thing it can take.
- **Bare:** `import svd "STM32F401.svd"` puts them in the enclosing module, as `import c` does. Inside a `module Hw =` block, they're `Hw.Gpioa`.
- **Arguments** are constants: the string first (what to read, a path relative to the importing file, as a header's is), then options as named arguments in a member call's syntax (decision 14). The options are the provider's own: the compiler passes them on, and the provider rejects what it doesn't know.
- **Where:** among a file's declarations, or a nested module's. Not in expressions, functions or types.
- **Under decision 34:** `import c`'s form is Z#'s own (after Zig's `@cImport`), not F#'s, so the extension needs this discussion. F#'s own form, `type Weather = JsonProvider<"weather.json">`, is in *Alternatives*.

### Meaning

- **A provided module is a module.** `module Weather = import json "weather.json"` is `Weather.zs` with the provider's output as its text: `Weather.Root` is a type, `Weather.parse` a function, `open Weather` works, `private` hides what the provider wants hidden, and `///` comments show on hover.
- **Its scope is a file's:** the prelude, the library's namespaces, and what it opens itself. It doesn't see the importing module, so its result depends on the provider's output alone (which the cache needs), and an error in it can't come from the importer. Nested modules written with `module Inner =` see their enclosing modules; a provided one is a file that happens to be named here.
- **The bare form** is a hidden module and an `open` of it at the import. So the usual scope rules decide names: the module's own declarations come first, then what's opened, nearest first (DESIGN §2.1), and a provided record is found by its fields where the import is in scope.
- **Positions** point into the provided module's file in the cache (below), so errors, hover, definition and debug lines have somewhere to go.

### A provider

A provider is a program that turns its arguments into Z# source. The whole protocol:

| | |
|---|---|
| **Arguments** | the string, then each option as `--name=value`; the working directory is the importing file's, so relative paths resolve as the import wrote them |
| **Standard output** | the declarations of one module. The first lines name what was read, one `// input: <path>` per file (relative to the working directory), and `// provided by <name> <version> from <string>` |
| **Standard error** | errors, one per line, `file:line:col: message` where there is a position |
| **Exit code** | non-zero fails the import, with standard error's lines as the errors |
| **`--version`** | prints the provider's version, part of the cache key |

- **Inputs are files.** A provider reads what's on disk, so a build is reproducible, needs no network, and the editor can tell whether an input changed. A provider whose shape comes from a service has a command that writes the file (`zs provide sql --dump postgres://… > schema.sql`, say), and the file is committed, as a lock file is.
- **Deterministic:** the same inputs and arguments give the same text, so the module cache and `tests/cache.sh`'s "a build from the cache is the same as one without it" hold.
- **Where providers come from:**
  1. **`zs`'s own:** `c`, `json`, `csv`, `svd` and `sql`. In a build they run in-process; `zs provide json weather.json` runs the same code and prints the source.
  2. **A program on PATH:** `zs-provider-<name>`, in any language. Nothing is loaded into the compiler: the provider is a process, as clang is for `import c`.
  3. **A dependency** *(later)*: a package with a `[provider]` section in `zs.toml`, built by `zs` before use, as Cargo builds a `build.rs`. The shape is in *Unresolved questions*; the first implementation has the two above.
- **Why text, and not a plugin API or an AST format:** the parser exists; the output is readable, diffable and ejectable; the protocol is a few lines and survives the compiler's rewrite in Z# (phase 11), where an API over the compiler's types wouldn't; and it's what the two precedents do: `import c` turns clang's `-ast-dump=json` into declarations, and C#'s source generators add C# source text to the compilation.

### What the compiler does

1. **Resolve the provider:** `zs`'s own, then `zs-provider-<name>` on PATH. Neither is an error naming both places.
2. **Look in the cache.** `.zs-cache/providers/<importing module>/<module name>.zs` holds the last output, with the provider's name and version, the arguments, and a hash of each `// input:` file. Unchanged: the cached text is the module's source. Changed, or absent: run the provider, save its output and the hashes. The provider can't run (an editor's sandbox, a machine without it) and a cached output exists: use it, as `import c` uses `.zs-cache/cimport/` without clang, with a diagnostic at the import when an input changed since (*In the editor*, below).
3. **Check it as a module,** named by `module X =`, or hidden and opened for the bare form. From here on it's ordinary: its checked result is cached per module (phase 9.5), it's monomorphized with the program, and the later passes don't know it was provided.
4. **`.zs-cache` is ignored by git** as it is today, so a clone runs the providers once. A project that doesn't want that ejects.

### In the editor

The types a provider gives are the type checker's, in the editor as in a build. `zs lsp` and
`zs mcp` check every module (DESIGN §9), a provided one among them, so hover shows
`temp: f64`, completion lists `city`, `temp` and `readings`, and `w.humidity` is an error as
it's typed, with no build run. What keeps that true while the code and its sources change:

- **The server runs providers.** An `import json "weather.json"` typed into a file runs the provider at once, in the server, as the server runs clang for `import c` today. `zs`'s own providers run in-process, so they work wherever the server does, Zed's Flatpak sandbox included, where clang can't run (the reason `CImport` has its cache). An external provider the sandbox can't run leaves the cached module standing, with the diagnostic at the import.
- **Inputs are watched.** The `// input:` lines say which files. Each time a file with an import is re-checked, its inputs' modification times are compared (a stat each), and a client that offers `workspace/didChangeWatchedFiles` reports changes made while nothing is being edited. A changed input re-runs the provider; a different output re-checks the provided module, then only the modules that use it (phase 9.5's rule for a changed interface). So a key added to `weather.json` is in completion after the edit, within track E's 100 ms re-check budget plus the provider's own time (milliseconds for `zs`'s own).
- **Unsaved edits** to an input open in the editor: `zs`'s own providers read the editor's buffer through the server's overlay of open files, so the types follow the sample as it's typed. An external provider reads the disk and sees the edit on save; a `--input-from` argument for the buffer is cheap to add when a provider wants it.
- **Nothing waits on a provider.** The server keeps the last provided module while a provider runs (an external one is a process, and a whole SVD takes a moment to check), and publishes the new types and diagnostics when it's done, as diagnostics are pushed anyway.
- **One cache** (phase 9.5): a provided module's checked result is in the server's memory and in `~/.cache/zs` between runs, keyed by its text, so reopening a project or restarting the server runs no provider and re-checks nothing while nothing changed.
- **Hover** on a provided name shows its declaration and the `///` comment the provider wrote, which says where it came from (`From "weather.json": "temp": 21.5`). **Definition** opens the module's file in the cache, read-only where the editor can, as Visual Studio opens a generated source; hover and definition work inside it too, since it's a module. **References** find a provided name's uses as any. **Rename** on one is refused with the reason: `temp is provided by json from weather.json; rename the key there`.
- **Inlay hints** show provided types on bindings as any other: `let w = Weather.parse text?` shows `w: Weather.Root`.
- **MCP:** `check`, `type_at` and `docs` see provided declarations with their provenance, so an agent fixing a type error after a sample changed sees which field the sample lost.

### Commands

- **`zs provide <name> <string> [--option=value]…`** prints the module. `zs provide json weather.json > Weather.zs` ejects it: the import line goes, and the module is the project's. `zs provide --list` names the providers found.
- **`zs doc`** documents a provided module as any; **`zs fmt`** leaves an import line as written.

### The providers

Each of `zs`'s own providers writes Core-only code, so a provided module works in a
microcontroller build (DESIGN §9's layers), and each names the original key, column or
register in a `///` comment on what it declares.

#### `json`: from a sample or a JSON Schema

```fsharp
module Weather = import json "weather.json"
```

```fsharp
// provided by json 0.1 from weather.json
// input: weather.json

/// From "weather.json": { "city": "Oslo", "temp": 21.5, "readings": […], "wind": null }
[<Derive(Json)>]
type Root = { city: string; temp: f64; readings: list<Reading>; wind: option<Wind> }

/// From "readings": { "at": "2026-10-22T08:00:00Z", "value": 20.1 }
[<Derive(Json)>]
type Reading = { at: string; value: f64 }

/// Parses a document of Root's shape.
let parse (text: string) : result<Root, string> = Json.parse text |> Result.bind fromJson

let print (r: Root) : string = Json.print (toJson r)
```

The provider writes types and lets the `Json` derive (DESIGN §3.1; track S item 5 puts
`Json`, `parse` and `print` in Core) do the parsing and printing, so the output is short, and
a hand-written record with `[<Derive(Json)>]` and a provided one are the same thing underneath.

| In the sample | In Z# |
|---|---|
| an object | a record, named after its key in PascalCase (`"readings": [{…}]` gives `Reading`), `Root` at the top; two keys with the same shape share a record |
| an array | `list<T>`, with `T` unified over the elements; an empty array is `list<Json>` |
| a number | `int` when every occurrence is integral, else `f64` |
| a string, a bool | `string`, `bool` |
| `null`, or a key missing from some of an array's objects | `option<T>` |
| one key with values of different shapes | `Json`, the value as it is |
| a key that isn't an identifier (`first-name`, `$ref`) | a ``` ``first-name`` ``` field, the key as its name, so the derive sees the key as `f.name` and no attribute is needed |

- **A JSON Schema** (a document whose top-level object has `$schema`) is read instead of inferred: `required` decides `option`, `enum` of strings becomes a union of cases without fields, `oneOf` a union with a case per branch, `additionalProperties` a `Map<string, T>`.
- **Options:** `root = "Weather"` names the top record; `types = "temp:f64,id:string"` overrides a field's type by its path.

#### `csv`: from the header and the rows

```fsharp
module Stocks = import csv ("stocks.csv", separator = ";")
```

```fsharp
/// From "stocks.csv": date;open;close;volume;note
type Row = { date: string; ``open``: f64; close: f64; volume: int; note: option<string> }

/// Parses rows of this shape, the header line included.
let parse (text: string) : result<list<Row>, string> = …

let print (rows: list<Row>) : string = …
```

- **Columns** are typed from every row: `int`, `f64`, `bool`, else `string`; an empty cell somewhere makes the column an `option`. A header name that isn't an identifier, or is a keyword, becomes a ``` ``double-backtick`` ``` field.
- **Reading a file is the program's:** `File.readAllText "stocks.csv" |> Result.bind Stocks.parse`, so the module stays Core-only.
- **Parsing** uses `Int.parse` and `Float.parse` (track S item 3).
- **Options:** `separator` (default `,`), `hasHeaders` (default `true`; `false` names the columns `col1`…), `types = "volume:f64"`.

#### `svd`: a microcontroller's peripherals

```fsharp
import svd ("STM32F401.svd", only = "GPIOA,RCC,USART2")
```

```fsharp
module Gpioa =
  /// GPIO port mode register (MODER, offset 0x00, read-write, reset 0xA8000000)
  [<Bits>]
  type Moder = { moder0: Mode = Input; moder1: Mode = Input; …; moder15: Mode = Alternate }

  /// MODER's field values
  type Mode = | Input | Output | Alternate | Analog

  module Moder =
    let private address = usize 0x40020000
    let read () : Moder = Bits.ofU32 (Mmio.read32 address)
    let write (r: Moder) = Mmio.write32 address (Bits.toU32 r)
    let modify (f: Moder -> Moder) = write (f (read ()))

  /// GPIO port bit set/reset register (BSRR, offset 0x18, write-only)
  [<Bits>]
  type Bsrr = { bs0: bool = false; …; br15: bool = false }

  module Bsrr =
    let private address = usize 0x40020018
    let write (r: Bsrr) = Mmio.write32 address (Bits.toU32 r)
```

- **A module per peripheral,** named in PascalCase (`GPIOA` gives `Gpioa`); a register is a `[<Bits>]` record (track M item 9: the shifts and masks are the compiler's) and a module of the same name holding its address and access functions; a field is named in lower case.
- **Access** follows the SVD: `read-only` gives `read`, `write-only` gives `write`, `read-write` all three; `writeOnce` and `read-writeOnce` are read-write. A read of a write-only register doesn't exist, so it doesn't compile.
- **Reset values are field defaults** (DESIGN §2.3), so a literal names only the fields it sets: `Usart2.Cr1.write { ue = true; te = true; re = true }`.
- **Field types:** a field with `enumeratedValues` is a union of cases without fields, so `moder5 = Output` reads as the manual; a 1-bit field without them is a `bool`, a wider one a `u8`, `u16` or `u32` by width, with `[<Width n>]` when the field has fewer bits than its type (`[<Width 12>] div_mantissa: u16`, [0013](0013-bit-fields.md)); a value too wide for the field panics, as an overflow does.
- **`derivedFrom` peripherals** (GPIOB from GPIOA) get their own copy of the types, so a `Gpioa.Moder` can't be written to GPIOB. **`dim` arrays** of registers become numbered names (`Cr1`, `Cr2`).
- **`Bits.ofU32` and `toU32`** stand for the conversions `[<Bits>]` brings, whose spelling track M decides.
- **Options:** `only = "GPIOA,RCC"` picks peripherals (an SVD describes a hundred and more, below); the default is all of them.
- **Cost:** a register function is one volatile access at an immediate address once inlined: track P's exit test is that `nucleo-f401.zs`, rewritten on the SVD, compiles to the same accesses as the `Mmio` version.

#### `sql`: records from a schema

```fsharp
module Db = import sql "schema.sql"       // CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, email TEXT);
```

```fsharp
/// From "schema.sql": users
type Users = { id: int; name: string; email: option<string> }

module Users =
  let table = "users"
  let columns = [ "id"; "name"; "email" ]
```

- **Types:** `INTEGER` is `int`, `REAL` `f64`, `TEXT` `string`, `BLOB` `array<u8>`, `BOOLEAN` `bool`; a column is `option` unless `NOT NULL` or a primary key. SQLite's dialect first, where the first-party `zsharp/sqlite` package is (track K); the common subset of Postgres's types too.
- **Rows:** with `rows = "sqlite"`, a `fromRow` per table for that package's rows, built from the column names.
- **Queries** typed from a file of named queries, as sqlc does, are the valuable half and need a SQL parser that types a query against the schema: *Unresolved questions*.

### Order of implementation

1. **`zs provide json` and `csv`,** with no language change: a command that writes a module, useful by hand before the syntax exists. Needs track S's `Json` in Core (item 5) and number parsing (item 3).
2. **The `import` form,** the cache, the hidden module of the bare form, and the editor whole: the server runs providers, watches inputs and re-checks (*In the editor*). Not a later step: track P's exit test is completion and hover in Zed with no build run.
3. **`svd`,** after track M's `[<Bits>]` records (item 9).
4. **`sql`,** records first.
5. **Providers on PATH;** providers from packages after track K's versions.

Each step keeps `./test.sh` green, with a test per provider in `tests/providers/`, and
`import c` unchanged throughout.

## Drawbacks

- **One more program a build may need.** An external provider must be installed where the project builds, as clang must be for `import c`; `.zs-cache` isn't committed, so CI runs providers too. The cache spares editors, and ejecting spares everyone.
- **Generated code is a layer to look through.** A type error "in `Weather.Root`" sends the programmer to a file they didn't write. Hover's comments, the cached file and `zs provide` make it readable, which is more than F#'s erased types give, but it's still indirection.
- **Inference from a sample guesses.** A field that's `null` in the sample becomes an `option`; an integral number becomes an `int` though the API sends floats. A schema, or the `types` option, settles it, and the guess is visible on hover.
- **Names are mangled from the source's** (`GPIOA` to `Gpioa`, `MODER5` to `moder5`), a convention to learn, with the original in the `///` comment.
- **Large sources make large modules.** A whole SVD is tens of thousands of lines; the first build pays for checking it once, the cache after. `only` keeps it to what the program uses.
- **More surface** for the third design review's "Simple" check: a parser form, a cache, a command and a protocol. The providers themselves sit outside the language.

## Alternatives

- **F#'s model and syntax.** `type Weather = JsonProvider<"weather.json">`, with providers as compiler plugins and types erased or generated on demand. The plugin host and erased types aren't available to Z# (see *Motivation*), and the syntax makes a string a type argument, a second exception after `fixed`'s numbers (decision 53), for something that is a module in Z#: types and functions side by side, as `import c` already gives. Not chosen; the look is familiar, and could be sugar for the module form if the discussion wants it.
- **Macros or `comptime`,** as Rust's proc macros and Zig's `@cImport` and `@embedFile`: decisions 20 and 26 rule out code running at compile time. The provider is a process, and the language stays as it is.
- **A generator run by hand, its output committed** (quicktype, svd2rust, sqlc). This is the same mechanism without the import line, and `zs provide` keeps it available. What the import adds is in *Motivation*: staleness tracked by the compiler, nothing to commit, and the editor without a build step.
- **A provider API over the compiler's types,** as F#'s `ProvidedTypes` or Roslyn's syntax factories. Ties every provider to the compiler's internals across the rewrite in Z#; text doesn't.
- **Providers that see the program,** as C#'s source generators see the compilation. None of the four providers needs it, and a provided module that read the importer would depend on it, losing the per-module cache and allowing cycles.
- **Lazy or erased types for huge sources,** as F#'s FreeBase and World Bank providers. They need a runtime representation; `only` and the module cache take the size instead.
- **Extending `derive` to read files.** A derive walks a type's shape at compile time; reading a file there would put IO in the type checker and make a derive's result depend on the machine.
- **Doing nothing.** Records by hand, with `[<Derive(Json)>]`; register addresses by hand, with `Mmio`. It works, as the examples show, and the mistakes in it are the ones the providers exist to make impossible.

## Compatibility

- **Not a breaking change.** `import c "header.h"` keeps its meaning. `import json …` fails to parse today (`expected 'c' after 'import'`), and `module X = import …` too, so no existing program changes.
- **An older compiler** meeting this source stops at the import line with that message, which names the form it knows.
- **Compiled binaries:** none to consider. Packages are source (decision 27), and a provided module leaves nothing in a binary.
- **The library:** unchanged by the mechanism. The providers' output uses Core's `Json` (track S item 5), `Int.parse` and `Float.parse` (item 3) and `[<Bits>]` (track M item 9), so each provider arrives after what it writes against.
- **Dependencies that use providers:** the sample or schema sits in the dependency's folder, and the provider runs on it as on the project's own; the cache is the project's.
- **Microcontrollers:** `zs`'s own providers write Core-only code, so a provided module builds for Cortex-M; `svd` exists for it.

## Pragmatics

### Diagnostics

Every error names the problem, points at it, and says what to write, as Z#'s do:

| Situation | Error |
|---|---|
| no such provider | `no provider 'jsn': zs has c, json, csv, svd and sql, and no zs-provider-jsn is on PATH` |
| the input is missing | `json: weather.json not found next to main.zs` |
| the provider failed | its standard error, one error each at the import: `json: weather.json:12:5: expected ',' or '}'` |
| an unknown option | `csv: unknown option 'seperator' (separator, hasHeaders, types)` |
| an argument that isn't a constant | `import takes constants: a string, a number, true or false` |
| the program no longer fits the source | the ordinary type error, with the provenance: `Root has no field 'humidity' (Root is provided by json from weather.json)` |
| an error in the provided module itself (a provider's bug, or one written for an older compiler) | `.zs-cache/providers/main/Weather.zs:14:3: …`, then `in module Weather, provided by json from weather.json`; the file is there to read |
| an input changed and the provider can't run here (an editor) | at the import, `weather.json changed; the types shown are from the last build`. A warning once phase 12 has them, an error until then |

- **Recovery:** an import whose provider fails leaves the file checked otherwise; uses of the provided names are errors as for a missing module.
- **Two bare imports** declaring the same name follow the scope rules for two `open`s: the later wins, as in F#.

### Tooling

The editor is part of the design, not a follow-up (*In the editor*). What to expect:

- **Auto-complete:** a provided module's names and a provided record's fields, as any module's, as soon as the import is typed.
- **Tooltips:** the checker's type, and the provider's `///` comment with the provenance.
- **Navigation:** definition into the provided module's file, references across the program; rename refused with where to rename instead.
- **Diagnostics while typing:** a use that no longer fits the source is an error as it's typed, and a changed source re-checks only the provided module and its users.
- **Inlay hints:** provided types on bindings, as any.
- **Error recovery:** an incomplete import (`import json`) is a parse error at the line, and the rest of the file parses; a failed provider leaves the file checked otherwise.
- **Debugging:** the provided module's lines are in its cached file, so gdb steps through `Weather.parse` as through any module.
- **Colorization and the grammar:** `import` and `module` are keywords already; the tree-sitter grammar gains the `module X = import` form and the argument list (pinned for Zed as grammar changes are).
- **Commands:** `zs provide`, and `zs doc` over provided modules; `zs fmt` leaves the import as written. The MCP tools see provided declarations with their provenance.

### Performance

- **Existing code:** none. The parser's `import` branch changes; nothing else does for a program without providers.
- **Running a provider:** only on a cache miss (a first build, a changed input, changed arguments, a new provider version). `zs`'s own run in-process: a JSON sample of 100 KB is milliseconds. An external one is a process, as clang is for `import c`, once per change.
- **Checking:** a provided module is checked once per change of its text and cached per module (phase 9.5), then loaded with the rest of the cache in milliseconds.
- **In the editor:** a keystroke in a file with imports costs a stat per input; a change to a sample costs the provider's run (milliseconds for `zs`'s own) and a re-check of the provided module and its users, within track E's 100 ms budget. Nothing else is re-checked, and the server never blocks on a provider.
- **Generated code:** ordinary code, monomorphized and optimized with the program; the `Json` derive expands per field, as for hand-written records, and a register function inlines to one volatile access. Nothing at run time, no metadata in the binary.
- **Reproducibility:** the output is deterministic and the cache key includes the provider's version, so a build from the cache equals one without it (`tests/cache.sh`).

### Scaling

Estimates for the dimensions that grow, with the upper bounds the compiler should take without
leaving linear time:

| Dimension | Hand-written, typical | Upper bound to accept |
|---|---|---|
| imports per program | 1–5 | 100 |
| JSON: fields per record, records per import, nesting depth | 20, 10, 4 | 500, 1,000, 30 |
| JSON: sample size | 10 KB | 100 MB (read once; the output follows the shape, not the size) |
| CSV: columns; rows read to type them | 10; 1,000 | 1,000; every row, linear in the file |
| SVD: peripherals, registers, fields | 3 (with `only`), 30, 300 | 150, 2,000, 20,000 (an STM32F4's SVD is 1–3 MB of XML) |
| provided module, lines | 100–1,000 | 50,000 (a whole SVD: about two lines per field and six per register) |
| SQL: tables, columns | 10, 50 | 500, 5,000 |

A whole SVD is the case to test: checking 50,000 lines once, from the cache after, and one
module's cache entry of that size loading without reading it all when nothing changed.

### Culture-aware formatting and parsing

- **Invariant throughout.** Providers and the parsers they write read numbers with `.` as the decimal point and no grouping, as `Float.parse` and `Show` do, and dates as strings (until Std has a time type, track S item 6). JSON is invariant by its grammar. A CSV written with `1,5` keeps a `string` column, and the program parses it; a `decimal` option is one line to add when a file needs it.
- **Names** are converted to PascalCase and lower case for ASCII letters only; a key or header with other characters keeps them in a ``` ``double-backtick`` ``` name.

## Unresolved questions

1. **The spelling:** `module Weather = import json "weather.json"` (this proposal), `import json "weather.json" as Weather`, or F#'s `type Weather = Json<"weather.json">` as sugar for the module. Decision 34's discussion decides.
2. **`import c` on the protocol.** `zs provide c raylib.h` would print a header's declarations as Z#, an ejectable binding, and `import c` would stop being a special case in `Driver`. Worth doing when phase 11's libclang work touches `CImport` anyway; not before.
3. **Providers from packages:** a `[provider]` section in `zs.toml` naming a main file; whether `zs build` builds and runs it as Cargo does a `build.rs`, and how its version enters the cache key.
4. **JSON numbers:** `int` when every value in the sample is integral (this proposal) against `f64` always, as FSharp.Data chose `decimal`-or-`float`. The `types` option covers either default.
5. **Typed SQL queries:** a `queries = "queries.sql"` file of named queries, each a function typed against the schema (sqlc's model), needs a SQL parser per dialect. Whether it's the `sql` provider's second half or a package's own provider.
6. **The stale-cache diagnostic's severity** in editors before phase 12 brings warnings.
7. **An external provider's authors:** the protocol gives them no way to ask the compiler anything (the target, the compiler's version, the options' types for hover). Add arguments when a provider needs one; none of the four does.

## History

- **2026-10-22:** drafted. Track P's sketch (ROADMAP, commit 6d15ae5) and DESIGN §3.1's "a later generalization of `import c`" are what it replaces.
- **Next:** the third design review approves it in principle or declines it, with a row in DESIGN §13 either way.
