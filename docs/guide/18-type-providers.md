# 18. Type providers

A type provider reads a data source when the program is compiled and declares the types and
functions for it, so code against a JSON document, a CSV file, a database schema or a
microcontroller's SVD file is checked against the source's shape. `import c "header.h"`
([C interop](09-c-interop.md)) does this for C headers; a provider does it for data.

```fsharp
module Weather = import json "weather.json"

let report (text: string) : result<string, string> =
  result {
    let! w = Weather.parse text      // a Weather.Root, with the sample's fields and types
    return $"{w.city}: {w.temp}"
  }
```

The path is relative to the file that imports. `Weather` is a module like any other:
`Weather.Root` is a record, `Weather.parse` a function, `open Weather` works, and hover,
completion and go-to-definition in the editor see them. A key removed from `weather.json` makes
`w.humidity` a compile error naming the field. Nothing runs at run time that you didn't write:
the provided module is ordinary Z#.

## Two spellings

`module Name = import …` puts the declarations in a module. The bare form opens them where the
import is, as `import c` does:

```fsharp
import csv ("stocks.csv", separator = ";")

let total (text: string) =
  match parse text with                 // Row, parse and print, from the file's header and rows
  | Ok rows -> List.sum (List.map (fun (r: Row) -> r.volume) rows)
  | Error _ -> 0
```

A bare import's names come before the prelude's, so its `print` is the one in scope; name the
module when that gets in the way. Options follow the string in parentheses, as constants:
`import csv ("stocks.csv", separator = ";", hasHeaders = false)`.

## What each provider gives

**`json`**, from a sample document (`--root=Name` names the top record, `--types=temp:f64`
overrides a field's type by its path):

| In the sample | In Z# |
|---|---|
| an object | a record named after its key (`"readings": [{…}]` gives `Reading`); two keys with the same fields share one record; the document's is `Root` |
| an array | `list<T>`, `T` unified over the elements; an empty array is `list<Json>` |
| a number | `int` when every occurrence is integral, else `f64` |
| a string, a bool | `string`, `bool` |
| `null`, or a key some of an array's objects lack | `option<T>`, with `None` as its default |
| one key with values of different shapes | `Json`, the value as it is |
| a key that isn't a name (`first-name`) | a ``` ``first-name`` ``` field, so the `Json` derive reads the key |

The records carry `[<Derive(Json)>]`, and `parse` and `print` go through the derive, so a
provided record and one written by hand are the same thing underneath. `zs provide json
weather.json` prints the module; this is what it wrote for the sample in
[examples/providers](../../examples/providers/), and a program using it as it is:

```zsharp
/// From "readings": {"at":"2026-10-22T08:00:00Z","value":20.1,"note":"calm"}
[<Derive(Json)>]
type Reading = { at: string; value: f64; note: option<string> = None }

/// From "station": {"id":7,"name":"Blindern"}
[<Derive(Json)>]
type Station = { id: int; name: string }

/// From "weather.json": {"city":"Oslo","temp":21.5,"humidity":64,"readings":[{"at":"2026-10-22T08:00:00Z","value":20.1,"note…
[<Derive(Json)>]
type Root = { city: string; temp: f64; humidity: int; readings: list<Reading>; wind: option<Json> = None; station: Station; backup: Station; tags: list<Json>; mixed: list<Json>; ``first-name``: string }

/// Parses a document of Root's shape.
let parse (text: string) : result<Root, string> = Result.bind fromJson (Json.parse text)

/// Prints a Root as a document.
let print (value: Root) : string = Json.print (toJson value)

let main () =
  match parse "{\"city\": \"Bergen\", \"temp\": 12, \"humidity\": 90, \"readings\": [], \"wind\": null, \"station\": {\"id\": 1, \"name\": \"Florida\"}, \"backup\": {\"id\": 2, \"name\": \"Nesttun\"}, \"tags\": [], \"mixed\": [], \"first-name\": \"Ida\"}" with
  | Ok w -> println $"{w.city} {w.temp} {w.station.name} by {w.``first-name``}"
  | Error e -> println e
  match parse "{\"city\": \"Bergen\", \"temp\": \"mild\"}" with
  | Ok _ -> println "unexpected"
  | Error e -> println e
  0
```

```text
Bergen 12 Florida by Ida
at temp: expected a number, got "mild"
```

**`csv`**, from the header and the rows (`separator`, default `,`; `hasHeaders`, default
`true`, `false` naming the columns `col1`, `col2`, …; `types = "volume:f64"`): a `Row` record
whose columns are `int`, `f64`, `bool` or else `string`, an option where a cell is empty
somewhere, and `parse` and `print` that read and write quoted cells (a separator, a doubled
quote or a line break inside quotes). Reading the file is the program's, with `File.readAllText`,
so the module needs Core only and works on a microcontroller.

**`sql`**, from a schema's `CREATE TABLE`s (SQLite's dialect, and the common Postgres types): a
record per table, `INTEGER` as `int`, `REAL` and `NUMERIC` as `f64`, `TEXT` as `string`, `BLOB`
as `array<u8>`, `BOOLEAN` as `bool`, a column an option unless `NOT NULL` or in the primary
key, and a module of the record's name with `table` and `columns`:

```fsharp
module Db = import sql "schema.sql"

let insert (u: Db.Users) =
  let columns = String.join ", " Db.Users.columns
  $"insert into {Db.Users.table} ({columns}) values (…)"
```

With `queries = "queries.sql"`, a file of named queries in sqlc's style gives a module per query,
typed against the schema: its text with `?` where each parameter goes, the parameters' names,
a `Params` record typed from the columns the parameters are compared with (or inserted into), and
a `Row` record for what it selects (`SELECT *` is the table's columns; a join's columns by their
table or alias; an expression needs `AS name` and is an `int` for `COUNT`, `SUM`, `TOTAL` or
`LENGTH`, else a `string`). A column or table the schema doesn't have is an error naming the
query.

```sql
-- name: GetUser :one
SELECT id, name, email FROM users WHERE id = :id;
-- name: OrdersFor :many
SELECT o.id, o.total, u.name AS buyer FROM orders o JOIN users u ON u.id = o.user_id WHERE o.user_id = :user;
```

```fsharp
module Db = import sql ("schema.sql", queries = "queries.sql")

let lookup (id: int) =
  let p: Db.GetUser.Params = { id = id }
  (Db.GetUser.sql, Db.GetUser.parameters)      // "SELECT id, name, email FROM users WHERE id = ?", [ "id" ]
```

A driver package runs the text with the parameters and builds the `Row`; the provider gives it
what to type against, and nothing runs at compile time but the reading of the two files.

**`svd`**, from a microcontroller's SVD file (the vendor's description of its peripherals;
`only = "GPIOA,RCC"` keeps the module to the peripherals a program uses): a module per
peripheral, each register a [`[<Bits>]` record](11-microcontrollers.md) whose defaults are its
reset value, so a literal names only the fields it sets, and a module of the register's name
with its address and the access the file allows: `read-only` gives `read`, `write-only`
`write`, `read-write` both and `modify`. A write to a read-only register doesn't compile. A
field whose enumerated values are 0 to n-1 is a union of cases without fields, named after the
list (`Value` added when a register's record has the name), so `mode5 = Output` reads as the
manual; sparse values stay a number.

```fsharp
import svd ("stm32f401-part.svd", only = "GPIOA,GPIOC,RCC,USART2")

let init () =
  Rcc.Ahb1enr.modify (fun r -> { r with gpioaen = true; gpiocen = true })
  Gpioa.Moder.modify (fun r -> { r with moder5 = u8 1 })        // PA5 as an output
  Usart2.Cr1.write { ue = true; te = true; re = true }

let setLed (lit: bool) = Gpioa.Bsrr.write (if lit then { bs5 = true } else { br5 = true })
let buttonDown () = not (Gpioc.Idr.read ()).idr13
```

Each register function is one volatile access at an immediate address once inlined:
[examples/mcu/nucleo-f401-svd.zs](../../examples/mcu/nucleo-f401-svd.zs) is the Nucleo
firmware on the chip's SVD, and the test suite checks that it compiles to the same register
accesses as [the version with addresses by hand](../../examples/mcu/nucleo-f401.zs).

**`c`**, the one that was there first: `module Ray = import c "raylib.h"` is the header's
declarations as a module, each with its C signature and comment as its doc, read by libclang
as the bare `import c` reads them ([C interop](09-c-interop.md)); `zs provide c raylib.h`
prints that binding to keep. The bare form keeps its own path, with `[<Link>]` and the editor's
C hover; the library a named module needs is linked by the package's `[c]` section.

## Where the module is, and keeping it

A provided module is written to `.zs-cache/providers/<importing module>/<Name>.zs` and loaded
as a dependency of the file, so errors inside it, hover and definition point into that file (a
dependency's import is written to the project's `.zs-cache/pkgs/<name>-<hash>/providers/`, not
into the dependency).
`.zs-cache` is ignored by git, so a clone runs the providers once. To keep the module in the
project instead, print it and drop the import:

```bash
zs provide json weather.json > Weather.zs
```

`zs provide --list` names the providers. In the editor, the types follow the sample: the
language server runs the providers at each check, watches the files they read, and re-checks the
documents made from a file that changes, so a key added to `weather.json` is in completion after
the edit, and a renamed provided name is refused with where it comes from
(`temp is provided by json from weather.json; change it there`).

## A provider of your own

A provider is a program named `zs-provider-<name>` on PATH, in any language (on Windows an
executable, `zs-provider-<name>.exe`, not a script), or a package: a dependency whose `zs.toml`
has a `[provider]` section naming its program is the provider of its name, built by the compiler
into `.zs-cache/providers/bin` and run the same way. It's built again when a file it's built from
changes: its package's `zs.toml`, Z# and C files, those of the packages it depends on, the
library's and the runtime's (`ZS_LIB`, `ZS_RUNTIME`), or the compiler. It's built with the
project's checkouts of its dependencies (the build that needs it fetched them), so it fetches
nothing and writes nothing into its package:

```toml
[package]
name = "shout"
main = "Main.zs"

[provider]
main = "Main.zs"
```

The compiler runs it in the importing file's directory with the string and each option as
`--name=value`. Its standard output is the declarations of one module, starting with `//
provided by <name> <version> from <string>` and one `// input: <path>` per file it read
(relative to that directory); its standard error has errors, one per line, `file:line:col:
message` where there is a position; a non-zero exit fails the import with those lines. A
provider that hasn't finished after 60 seconds (`ZS_PROVIDER_TIMEOUT=<seconds>` changes that) is
stopped, and the import fails saying so. The
compiler caches the output with a hash of each input, so a machine without the provider (an
editor's sandbox) still gets the types from the last output, with a `stale-input` warning at the
import that says so. Nothing is loaded into the compiler: the provider is a process, as clang is
for `import c`.

The provider's program is built against the project's dependencies: its own git dependencies are
the checkouts the project's `zs.lock` pinned and hashed, never fetched or locked apart, so it runs
the code the lock names and builds with `--offline` too.

A package's provider is the project's own code, so the language server and the MCP server build
and run it only when started with `--trust` ([Trust](10-tools.md#trust)); without it, the import
gets the module from the last build, with the `stale-input` warning, or the error `provider shout
not run: the project is not trusted (start the language server with --trust)`. `zs build`, `zs
check`, `zs doc`, `zs test` and the other commands build and run it, as a build of the project
does (`cargo check` runs a package's build script the same way): checking a project, or
printing its reference, runs code of its own, so check one you don't trust in the language
server without `--trust`. Every command and server runs zs's own providers and a
`zs-provider-<name>` on PATH, which you installed.

A provider's file must be a regular file (or a link to one): a pipe or a device named by an
import (`/dev/stdin`, `/dev/zero`) is an error, not a read that never ends. What a provider takes
from its file and writes into the module is quoted: a key, a column or a register's name becomes
a field in double backticks (a key holding a line break, a control character or two backticks is
an error, as no name can hold it), a string literal has its `\`, `"` and control characters
escaped, and a comment its line breaks removed, so no sample can add code to the program.

Errors name the problem and what to write: `no provider 'jsn': zs has c, json, csv, sql and svd,
no zs-provider-jsn is on PATH, and no dependency named jsn has a [provider] section`, `csv:
unknown option 'seperator' (separator, hasHeaders, types)`, `json: weather.json not found next
to main.zs`, `csv: wide.csv: a row has 3 cells, the header 2`. The design is [proposal
0001](../proposals/0001-type-providers.md).
