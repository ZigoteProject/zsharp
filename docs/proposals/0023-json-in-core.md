# Proposal 0023: JSON in Core

| | |
|---|---|
| **Status** | Approved in principle |
| **Decided at** | track S's plan ([ROADMAP](../../ROADMAP.md#library-s)): item 5, before phase 11 |
| **Builds** | track S: library, item 5; [0001](0001-type-providers.md)'s `json` provider and phase 11's LSP and MCP ([ROADMAP](../../ROADMAP.md#phase-11-self-hosting)) build on it |
| **Rests on** | decisions 20 (derive), 28 (UTF-8 strings), 37 (what goes in Core) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §3.1](../../DESIGN.md#31-derive) |
| **Related** | [0001 type providers](0001-type-providers.md) (the `json` provider writes `[<Derive(Json)>]` records), [0024 library API](0024-library-api.md), [0020 self-hosting](0020-self-hosting.md) (the compiler's LSP and MCP use it), [0009 tests as values](0009-tests-as-values.md) (`Show`-based diffs) |
| **Replaces** | DESIGN §3.1's `Json<'a>` and `JsonValue` example, and `tests/json.zs`'s own type |

- [x] Approved in principle
- [ ] Discussion
- [x] Implementation (steps 1–3; tuples' impls and the Cortex-M0+ build of every Core module wait)

## Summary

Core gains `Text.Json`: one `Json` union for any document, `Json.parse`, `Json.print` and
`Json.pretty`, accessors that return a `result` with the path to the problem, and two traits,
`ToJson<'a>` and `FromJson<'a>`, with derives for records and unions. The derive is the one
DESIGN §3.1 shows, split in two so a type can have one direction:

```fsharp
[<Derive(Json)>]                                     // ToJson and FromJson
type User = { name: string; age: int; email: option<string> = None; ``first-name``: string }

[<Derive(FromJson)>]                                 // read only
type Reply = { users: list<User>; next: option<string> = None }

let emails (text: string) : result<list<string>, string> =
  result {
    let! doc = Json.parse text                       // Error "3:14: expected ',' or '}'"
    let! reply = fromJson doc                        // Error "at users[3].email: expected a string, got 42"
    return reply.users |> List.choose (fun u -> u.email)
  }

Console.println (Json.print (toJson { name = "ada"; age = 36; ``first-name`` = "Ada" }))
// {"name":"ada","age":36,"email":null,"first-name":"Ada"}
```

Every target gets it, since Core needs no OS; nothing is added to the runtime.

## Motivation

- **Three users wait for it.** The `json` provider ([0001](0001-type-providers.md)) writes records with `[<Derive(Json)>]` and a `parse` that is `Json.parse text |> Result.bind fromJson`. The self-hosted compiler ([0020](0020-self-hosting.md)) speaks JSON-RPC in `zs lsp` and `zs mcp`, which the F# compiler does with `System.Text.Json.Nodes` today (`src/Lsp.fs:9`, `src/Mcp.fs:8`, main tree). The packages of track K (HTTP, databases) exchange documents, and the roadmap's "what goes where" puts a type packages must agree on in one place: for JSON that place is Core, so every target and the providers have it.
- **What there is today.** `tests/json.zs` (the facts sheet §13) has a `JsonValue`, a single `Json` trait, four helpers, a derive and a 10-line printer, and no parser at all. Every program would write the same 130 lines, each with its own name for the type, and two packages couldn't pass a document between them.
- **What F# programmers reach for.** `System.Text.Json`, FSharp.Data's `JsonValue`, Thoth.Json: a value type, a parser, a printer, and decoders that say where a document went wrong. This proposal is that, with the decoders written by the derive.

## Detailed design

### The type

```fsharp
namespace Text

type Json =
  | JNull
  | JBool of bool
  | JInt of i64                      // an integral literal that fits 64 bits
  | JNumber of f64                   // any other number
  | JString of string
  | JArray of list<Json>
  | JObject of list<string * Json>   // keys in document order, duplicates kept
```

- **Where:** `lib/core/Text/Json.zs`, as `Map.zs` holds a type and its module under `namespace Collections`. The type is `Json`, the module beside it is `Json`, and both are reachable unqualified because namespaces open everywhere at the lowest precedence (decision 37): `Json.parse`, `JObject`, `fromJson`. The reference gains a `Text.Json` page next to `Text.String` ([reference](../reference/README.md)).
- **`JInt`, and why not `f64` only:** a document's ids (database bigints, snowflake ids) exceed 2^53 and lose digits as an `f64`. `i64` is 64 bits on every target (decision 3: `int` is 32 on Cortex-M), so an id survives a round trip through a microcontroller too. **Why not arbitrary precision:** Core has no big integer, no API sends one, and a literal with more than 19 digits is rare enough to take the one rule below.
- **Which literal is which:** a lexeme with no `.`, `e` or `E` that fits `i64` is `JInt`; any other is `JNumber`, including an integral literal too large for `i64`. `-0` is `JInt 0`.
- **Objects are lists of pairs** in document order, duplicate keys kept (RFC 8259 leaves them to the implementation; `Json.field` finds the first). A wide object becomes a map with `Map.ofList (Json.object j)?`.
- **Derived traits:** `Eq`, `Ord` and `Hash` are structural (decision 10), so `JInt 2 <> JNumber 2.0`. `Show` is an explicit impl: `string j` and `$"{j}"` print the document compactly (`Json.print`), so 0009's assert diffs show `{"age":36}` and not `JObject [("age", JInt 36)]`. `Json` is not a `Format` impl: `{j:F2}` is 0024's unknown-specifier error.
- **Units of measure are erased** (decision 11): `toJson (3.0<m>)` is `JNumber 3.0`, and `fromJson` gives an `f64<m>` where one is expected.

### Parsing

- **`Json.parse : string -> result<Json, string>`** reads one RFC 8259 document with whitespace around it: no comments, trailing commas, single quotes, `NaN`, `Infinity`, leading `+` or leading zeros. The grammar is the format's; the error says what was expected.
- **Errors** are `line:column: message`, 1-based, the column in bytes: `3:14: expected ',' or '}' after a value`.
- **A depth limit, not a stack overflow.** Nesting past 1,000 levels is an error at the bracket that crosses it. `Json.parseWith { depth = 10000 } text` raises it, with `type Json.Options = { depth: int = 1000 }` in DESIGN §2.3's style. The F# compiler parses clang's AST dump 10,000 levels deep (`src/CImport.fs:213`, main tree); phase 11's libclang item replaces that dump, so the default serves the LSP, the cache and documents in the wild.
- **UTF-8** (decision 28): the input is a Z# string, so it's bytes. Malformed bytes inside a string literal are an error at their position (`1:9: invalid UTF-8`), as is a control character below U+0020 unescaped. The escapes are JSON's eight plus `\uXXXX`; a surrogate pair becomes one scalar, a lone surrogate an error. The result holds the scalars, never the escapes.
- **Numbers** are read invariantly: `.` is the point, `e` the exponent. A `JInt` is accumulated with an overflow check; a `JNumber` goes through the runtime's `strtod` (`zs_str_to_float`, `runtime/rt.c:737`, main tree), as `String.parseFloat` does today, and through `Float.parse` once track S item 3 lands.
- **Shape:** recursive descent over the bytes, one pass, one allocation per node, plus one per string. A string without escapes is one copy of its bytes; one with escapes is built from its decoded characters.

### Printing

- **`Json.print : Json -> string`** is compact, with no spaces: `{"a":1,"b":[true,null]}`. `JInt` prints as the integer. `JNumber` prints as `Show` prints an `f64` (`zs_str_of_f64`, `runtime/rt.c:568`, main tree: the shortest of 15 to 17 significant digits that reads back as the same value, so `0.1` is `0.1`, `2.0` is `2`, `1e21` is `1e+21`). A `JNumber` that isn't finite prints as `null`, JavaScript's rule, since JSON has no spelling for it. Strings escape `"`, `\` and controls below U+0020 (`\n`, `\t`, `\r`, `\b`, `\f`, else `\u00XX`) and write every other scalar as UTF-8, not as `\u` escapes; `/` is not escaped.
- **`Json.pretty : Json -> string`** indents two spaces, writes `"key": value`, one element per line, `[]` and `{}` inline, and no newline at the end. The roadmap's pretty-printer example is `File.readAllText path |> Result.bind Json.parse |> Result.map Json.pretty`.
- **A round trip changes one thing:** `JNumber 2.0` prints as `2` and reads back as `JInt 2`. The accessors and the impls accept both, so programs don't notice; `Eq` on `Json` does, which is the trap to document.

### Accessors

```fsharp
Json.field  : string -> Json -> result<Json, string>    // an object's key
Json.at     : int -> Json -> result<Json, string>       // an array's element
Json.string : Json -> result<string, string>
Json.number : Json -> result<f64, string>               // JNumber, or a JInt converted
Json.int    : Json -> result<i64, string>               // JInt, or a JNumber that is integral and fits
Json.bool   : Json -> result<bool, string>
Json.array  : Json -> result<list<Json>, string>
Json.object : Json -> result<list<string * Json>, string>
Json.within : string -> result<'a, string> -> result<'a, string>   // prefixes the path
```

- **An error names what it got:** `expected a string, got 42` (the value printed compactly, cut at 40 bytes), `missing key email`, `index 3 is past the end (2 elements)`.
- **A path is added from the outside.** `Json.within "email" r` turns `expected a string, got 42` into `at email: expected a string, got 42`, and `Json.within "users[3]"` of that into `at users[3].email: …`. The derives call it at every field and element, so a decoded record names the exact place; hand-written code calls it where it wants the same. The format is one rule: `at <path>: <problem>`, the path in `a.b[3].c` form, no prefix at the root.
- **Typed access is the idiom,** not dynamic access: a record with `[<Derive(FromJson)>]` for the part of a document a program reads, as the summary does; `Json.field` and `Json.at` are for the ten-line script and for the impls themselves.

### Two traits and three derives

```fsharp
trait ToJson<'a> =
  abstract toJson : 'a -> Json

trait FromJson<'a> =
  abstract fromJson : Json -> result<'a, string>

derive ToJson = …                     // the record and union rules below
derive FromJson = …
derive Json = ToJson, FromJson        // a group: applying it applies both
```

- **Why two traits:** a response type is only read, a log record only written, and a type whose reading validates (an email, a range) writes its `impl FromJson` by hand while keeping the derived `ToJson`. With one trait both directions had to be derived or both written.
- **`[<Derive(Json)>]` keeps its spelling** (DESIGN §3.1, 0001) and means both. The attribute already takes several names (`Typer.fs:3622-3625`, main tree, loops over them), so `[<Derive(ToJson, FromJson)>]` works without a change; the group line makes `Json` a name for the pair. `derive` is Z#'s own syntax (decision 20), so the group form is an extension of it under decision 34; the alternative is in *Unresolved questions*.
- **Records write every field by name** in declaration order; `None` writes as `null`. Reading finds each key by name and accepts, for an absent key: the field's default when it has one (DESIGN §2.3's promise: `fromJson` uses a field's default), else `null` (so an `option` field reads `None`), else the error `missing key age`. A key the record doesn't have is ignored, so a document can grow without breaking its readers.
- **Keys that aren't identifiers** are double-backtick fields: ``` ``first-name`` ``` is the key `first-name`, since the lexer takes any text between the backticks as the name (`Syntax.fs:531-540`, main tree) and the derive sees it as `f.name`. 0001's provider writes keys this way. **No field attributes yet** (DESIGN §3.1): a renamed, skipped or flattened field is a hand-written impl until attributes are designed.
- **Unions** write `{"case": "Circle", "fields": [2.5]}`, DESIGN §3.1's form, with the fields positional, and a case without fields as its name alone: `"Dot"`. Reading accepts `"Dot"`, `{"case": "Dot"}` and `{"case": "Dot", "fields": []}`; a wrong count is `case Rect takes 2 fields, got 3`; a name the type lacks is `unknown case Triangle`. Fields stay positional because union fields may be unnamed (`Node of Tree<'a> * 'a * Tree<'a>`), and one shape for every case is what another language's reader matches on.
- **One Shape fact is new:** `f.default : option<'t>`, `Some` of the field's default expression where the field has one, resolved when the derive is expanded (`Derive.fs:215-227`, main tree, builds fields in declaration order, so a default may read the earlier fields as a literal's can). Everything else the derives use exists.

```fsharp
derive FromJson =
  let fromJson (j: Json) : result<'self, string> =
    match Shape.kind with
    | RecordKind ->
      Json.object j
      |> Result.bind (fun kvs ->
        Shape.build (fun f ->
          match List.tryFind (fun (k, _) -> k = f.name) kvs, f.default with
          | Some (_, v), _ -> fromJson v |> Json.within f.name
          | None, Some d -> Ok d
          | None, None -> fromJson JNull |> Result.mapError (fun _ -> $"missing key {f.name}")))
    | UnionKind ->
      let header =
        match j with
        | JString name -> Ok (name, [])
        | _ ->
          result {
            let! name = Json.field "case" j |> Result.bind Json.string |> Json.within "case"
            let! args = match Json.field "fields" j with Ok a -> Json.array a | Error _ -> Ok []
            return (name, args) }
      header
      |> Result.bind (fun (name, args) ->
        match Shape.buildCase name (fun f -> Json.at f.index args |> Result.bind fromJson |> Json.within $"fields[{f.index}]") with
        | Some built -> built
        | None -> Error $"unknown case {name}")
```

- **Impls in Core:** every integer width (reading a `JInt` or an integral `JNumber` that fits, else `expected an integer within int's 32 bits, got 3000000000`; a `u64` above `i64`'s range writes as a `JNumber`), `f32` and `f64` (reading either number case; an `f32` widens, so `0.3f` prints as its `f64`), `string`, `char` (a one-character string), `bool`, `list<'a>` and `array<'a>` (arrays, elements within `[i]`), `option<'a>` (`None` is `null`), `Map<string, 'v>` and `HashMap<string, 'v>` (objects, in the map's iteration order), tuples as arrays of their length (built in, as the structural `Eq` for tuples is: the facts sheet §4), and `Json` itself (the identity, so a field of type `Json` keeps a value as it is, which 0001's provider uses for keys of mixed shape).
- **Errors at compile time** keep DESIGN §3.1's form: `Derive(ToJson) on Callback: field run: int -> int does not implement ToJson`.

### Order of implementation

1. **The type, `print`, `pretty`, `Show`, the accessors and `within`:** Z# only, no compiler change. Tests under `tests/json/` with `.out` files, discovered as the facts sheet §14 says.
2. **`Json.parse`** with positions and the depth limit; a test that prints every error of a file of bad documents, and a round trip over `tests/json/`'s documents.
3. **The traits, the Core impls and the derives:** `f.default` in `Derive.fs`, the derive group, `tests/json.zs` rewritten over the Core type, DESIGN §3.1's example updated to the pair, `Text.Json.md` from `zs doc`.
4. **The Cortex-M0+ build** of the module (track S: every Core module builds for it), under `tests/mcu/`.
5. **Then its users:** 0001's `zs provide json` (its step 1), and the compiler's own LSP and MCP in phase 11 (0020), whose protocol records are `[<Derive(Json)>]`.

## Drawbacks

- **Two number cases.** A `match` on a `Json` handles `JInt` and `JNumber` both, and `Eq` tells `2` from `2.0` after a round trip. The accessors and impls hide it; pattern matches don't.
- **A tree, not a stream.** A 100 MB document is a 100 MB tree and several times that in nodes. The LSP's messages and the cache are kilobytes; a program over a multi-gigabyte log waits for a streaming reader.
- **Objects as lists.** A key lookup is linear in the object; a record with 40 fields over an object with 40 keys is 1,600 comparisons, which is nothing, and a 100,000-key object wants `Map.ofList`, which is one line.
- **Fixed encodings.** Without field attributes, a key that doesn't match a field's name, or a union in another encoding, is an impl by hand. Backtick fields cover the keys; the union encodings wait.
- **Core grows** by one module, about 400 lines (an estimate) that every target carries in source. A program that never mentions it pays nothing at run time: the derives expand only where applied, and nothing is in the binary that the program doesn't reach.

## Alternatives

- **A package.** The roadmap's reason against: the type is one packages must agree on, the provider and the compiler need it, and Core can't reach a package. A package can still bring a streaming reader or a schema validator on top of the Core type.
- **FSharp.Data's `JsonValue`,** with `Number of decimal` and `Float of float`. Z# has no `decimal`; `JInt` and `JNumber` cover what `decimal` is there for (ids and money's integers) without a type Core doesn't have.
- **`f64` only,** JavaScript's rule and `tests/json.zs`'s today. Ids above 2^53 lose digits silently, the failure a type is there to prevent.
- **A number as its text** (`JNumber of string`). Lossless and lazy, but every consumer parses, `1.0` and `1` are unequal as text, and the derives would parse per field. The open question below keeps it.
- **serde-style streaming visitors.** A `Serialize` over a `Serializer` trait needs a trait abstracted over another trait, which Z#'s single-parameter traits (the facts sheet §4) don't express, and the tree is what the LSP, the cache and the provider want.
- **A `?` dynamic operator** (`doc?users?[3]?email`), as F#'s on `JsonValue`. `?` is `result`'s operator in Z# (decision 19), and a derived record gives typed access with the same paths in its errors.
- **One `Json` trait** with both methods, as today. A type couldn't have one direction, and a validating reader would have to hand-write the writer too.
- **Field attributes now** (`[<Key "first-name">]`). DESIGN §3.1 has none, backtick names cover the keys, and attribute syntax on fields deserves its own design rather than one for JSON.

## Compatibility

- **Not a breaking change.** Nothing in `lib/` names `Json` (the facts sheet §13). A program with its own `Json` or `JsonValue` keeps it: a file's own declarations come before the namespaces, which open at the lowest precedence (DESIGN §2.1, decision 37).
- **An older compiler** fails on `Json.parse` with an unknown name, and on `[<Derive(Json)>]` with no derive of that name; a program that carries its own copy of the type builds on both.
- **Compiled binaries:** none to consider. Packages are source (decision 27), and the type is ordinary Z#.
- **The library:** `tests/json.zs` is rewritten over the Core type: its `JsonValue`, trait, helpers, derive and `render` go, the round trips and the missing-key case stay, and its `.out` changes (compact printing, `"Dot"` for the case without fields). DESIGN §3.1's example becomes the `ToJson`/`FromJson` pair, and the guide's pointer to the test (`../guide/06-traits.md`) points at Core's derive, which is now the fuller example. 0001's provider output is unchanged: it was written against this design.
- **Microcontrollers:** Core, no OS, so a firmware parses a configuration from a serial line with the same code. `i64` on Cortex-M0+ is software arithmetic, paid only in `JInt`. The parser allocates per node, so it's not for `[<NoAlloc>]` code ([0012](0012-interrupts-noalloc-intrinsics.md)).

## Pragmatics

### Diagnostics

Compile-time errors from the checker, run-time ones as the `Error` text, each naming the problem, pointing at it and saying what to write:

| Situation | Error |
|---|---|
| a field's type has no impl | `Derive(ToJson) on Callback: field run: int -> int does not implement ToJson` |
| a derive and a hand-written impl | `impl ToJson<User> is declared twice: Derive(ToJson) at main.zs:3 and impl at main.zs:40; keep one` |
| `{j:F2}` | `Json has no format specifiers: F2 applies to numbers; write {Json.pretty j}` (0024's unknown-specifier error) |
| a parse error | `3:14: expected ',' or '}' after a value` |
| the text ends early | `1:1: expected a value, got end of input` |
| text after the document | `5:3: unexpected text after the document` |
| a lax literal | `1:3: numbers can't have leading zeros`; `2:1: comments aren't JSON` |
| a bad escape or byte | `2:7: unknown escape '\x'`; `1:9: invalid UTF-8` |
| too deep | `1:1001: nesting deeper than 1000 levels; raise it with Json.parseWith { depth = … }` |
| a wrong type in a document | `at users[3].email: expected a string, got 42` |
| a missing key, no default, not an option | `at users[3]: missing key email` |
| an index past the end | `at users: index 3 is past the end (2 elements)` |
| an unknown or malformed case | `at shape: unknown case Triangle`; `at shape: case Rect takes 2 fields, got 3` |
| an integer out of range | `at age: expected an integer within int's 32 bits, got 3000000000` |

### Tooling

- **`zs lsp`:** hover on `Json.parse` shows `Json.parse : string -> result<Json, string>` and its `///` doc, as hover does for any library name (the facts sheet §1); completion after `Json.` lists the module; definition jumps into `lib/core/Text/Json.zs` as it jumps into `List.zs` today. A derive's field error appears at the type as it's typed, with no build run, since derives expand in the checker. No new capability is needed.
- **`zs mcp`:** `docs` answers `Json.parse`; `check` reports the derive's errors.
- **`zs doc`** generates `Text.Json.md`; **`zs fmt`** has nothing new to lay out.
- **The tree-sitter grammar** gains the `derive Json = ToJson, FromJson` line's name list, if the group spelling is adopted (pinned for Zed as grammar changes are); nothing else is new syntax.
- **The compiler itself** (phase 11) reads its LSP frames with `Json.parse` and writes replies from `[<Derive(ToJson)>]` records, so the protocol's types are checked, which `JsonNode` today doesn't give.

### Performance

- **`parse`** is linear in the bytes: one pass, one allocation per node and per string, the number parsing of `strtod`. Estimates: an LSP `didChange` carrying a 100 KB file is under a millisecond, dominated by the string copy; a 100 MB document takes seconds and three to five times its size in memory (a boxed union of a few words per node, decision 8, and a cons cell per element). Enough for the LSP, the cache and the provider; a streaming reader comes when a program needs one.
- **`print` and `pretty`** append in one pass. The string reuse that makes `s <- s + x` linear (track S's `StringBuilder` note) is what they rely on, measured when the module lands.
- **The derives** cost nothing at run time beyond the code they expand to (DESIGN §3.1): a record's `fromJson` does one list lookup per field.
- **Nothing in the runtime changes:** the float printer and `strtod` exist; `rt.c` gains no function.

### Scaling

| Dimension | Typical | Upper bound |
|---|---|---|
| document size | 1 KB to 1 MB (an LSP message, a config) | 100 MB (a large AST dump is tens of MB) |
| nesting depth | under 10 | 1,000 by default; `parseWith` raises it (clang's dump needs 10,000) |
| keys per object | 5 to 50 | 100,000 (linear lookups; `Map.ofList` for more) |
| elements per array | 10 to 10,000 | 10,000,000 (memory three to five times the text) |
| string length | 100 bytes | the document |
| record fields under a derive | 5 to 40 | 500 (0001's bound; expansion is linear in the fields) |
| union cases | 2 to 20 | 200 |

### Culture-aware formatting and parsing

- **Invariant by the grammar:** `.` is the point, no grouping, `e` the exponent. The runtime never calls `setlocale` (`rt.c` has no such call), so `snprintf` and `strtod` stay in the C locale, and `Json.print`'s numbers read back anywhere. A program that shows a number to a user formats it itself (0024).
- **Text** is UTF-8 in and out, and keys compare byte for byte: no normalization, so a precomposed and a decomposed `é` are two keys, as they are in every JSON library.
- **Dates and durations** are strings. ISO 8601 impls for `DateTime` and `Duration` come with those types (0024).

## Unresolved questions

1. **The namespace:** `Text.Json` (this proposal), where `String` and `Char` live, against a top-level `Json` beside `Option` and `Result`, or a `Data` namespace that would hold later formats. Either name resolves the same way in code; the reference page moves.
2. **`JInt` and `JNumber`** (this proposal) against the number as its text, lossless for every literal. The first consumer that needs a 20-digit literal intact decides; none is known.
3. **Union encodings without attributes:** adjacently tagged with positional `fields` (this proposal), against named fields as object keys when every field of a case is named (`{"case": "Rect", "w": 2, "h": 3}`), or externally tagged (`{"Rect": [2, 3]}`, serde's default). The first form has one shape for every case; the others wait for field attributes.
4. **Comments and trailing commas:** refused (this proposal), RFC 8259 only; the alternative is a `lax` option for configuration files. Z#'s own manifest is TOML, so nothing in the repository needs it.
5. **The group's spelling:** `derive Json = ToJson, FromJson` (this proposal) against a rule in the checker that reads `Derive(Json)` as the pair, which needs no syntax but puts a library name in the compiler.
6. **Non-finite numbers:** `null` on printing (this proposal, JavaScript's rule) against a panic, which would make `Json.print` partial.

## History

- **2026-10-22:** drafted from track S item 5 (ROADMAP), DESIGN §3.1's derive example and `tests/json.zs`; a new decision row, numbered by the coordinator, records it.
