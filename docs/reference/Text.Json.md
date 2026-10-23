# Text.Json

JSON (RFC 8259): one `Json` type for any document, `Json.parse`, `Json.print` and
`Json.pretty`, accessors that say where a document didn't fit, and the `ToJson` and `FromJson`
traits, which `[<Derive(Json)>]` writes for a record or a union. Every target has it.

## Traits

### `ToJson`

```zsharp
trait ToJson<'a>
```

A value as a JSON document. `[<Derive(ToJson)>]` (or `Json`, both ways) writes it for a record
or a union.

#### `ToJson.toJson`

```zsharp
abstract toJson : 'a -> Json
```

The value as a document.

### `FromJson`

```zsharp
trait FromJson<'a>
```

A value from a JSON document. `[<Derive(FromJson)>]` (or `Json`) writes it for a record or a
union.

#### `FromJson.fromJson`

```zsharp
abstract fromJson : Json -> result<'a, string>
```

The value the document holds, or what didn't fit and where:
`at users[3].email: expected a string, got 42`.

## Types

### `Json`

```zsharp
type Json
```

A JSON document. A number with no `.` or exponent that fits 64 bits is a `JInt` (an id
survives), any other a `JNumber`; an object keeps its keys in document order, duplicates too.

#### `JNull`

```zsharp
| JNull
```

`null`.

#### `JBool`

```zsharp
| JBool of bool
```

`true` or `false`.

#### `JInt`

```zsharp
| JInt of i64
```

An integral number that fits an `i64`.

#### `JNumber`

```zsharp
| JNumber of f64
```

Any other number.

#### `JString`

```zsharp
| JString of string
```

A string, its escapes decoded.

#### `JArray`

```zsharp
| JArray of list<Json>
```

An array.

#### `JObject`

```zsharp
| JObject of list<string * Json>
```

An object: its keys and values in document order.

## Derives and impls

### `impl Show<Json>`

```zsharp
impl Show<Json>
```

A document prints as `Json.print` writes it, so `string j` and `$"{j}"` are its text.

### `impl ToJson<Json>`

```zsharp
impl ToJson<Json>
```

A document as itself, so a field of type `Json` keeps what it holds.

### `impl FromJson<Json>`

```zsharp
impl FromJson<Json>
```

A document as itself.

### `impl ToJson<string>`

```zsharp
impl ToJson<string>
```

A string as a JSON string.

### `impl FromJson<string>`

```zsharp
impl FromJson<string>
```

A JSON string's text.

### `impl ToJson<char>`

```zsharp
impl ToJson<char>
```

A character as a string of one character.

### `impl FromJson<char>`

```zsharp
impl FromJson<char>
```

A string of one character.

### `impl ToJson<bool>`

```zsharp
impl ToJson<bool>
```

`true` or `false`.

### `impl FromJson<bool>`

```zsharp
impl FromJson<bool>
```

`true` or `false`.

### `impl ToJson<f64>`

```zsharp
impl ToJson<f64>
```

A number.

### `impl FromJson<f64>`

```zsharp
impl FromJson<f64>
```

Either kind of number.

### `impl ToJson<f32>`

```zsharp
impl ToJson<f32>
```

A number, widened to an `f64`.

### `impl FromJson<f32>`

```zsharp
impl FromJson<f32>
```

Either kind of number, narrowed to an `f32`.

### `impl ToJson<int>`

```zsharp
impl ToJson<int>
```

An integer.

### `impl FromJson<int>`

```zsharp
impl FromJson<int>
```

An integer that fits an `int` (32 bits on a microcontroller, 64 on a host).

### `impl ToJson<i64>`

```zsharp
impl ToJson<i64>
```

An integer.

### `impl FromJson<i64>`

```zsharp
impl FromJson<i64>
```

An integer that fits an `i64`.

### `impl ToJson<i32>`

```zsharp
impl ToJson<i32>
```

An integer.

### `impl FromJson<i32>`

```zsharp
impl FromJson<i32>
```

An integer that fits an `i32`.

### `impl ToJson<i16>`

```zsharp
impl ToJson<i16>
```

An integer.

### `impl FromJson<i16>`

```zsharp
impl FromJson<i16>
```

An integer that fits an `i16`.

### `impl ToJson<i8>`

```zsharp
impl ToJson<i8>
```

An integer.

### `impl FromJson<i8>`

```zsharp
impl FromJson<i8>
```

An integer that fits an `i8`.

### `impl ToJson<u64>`

```zsharp
impl ToJson<u64>
```

An integer; above `i64`'s range, a `JNumber`.

### `impl FromJson<u64>`

```zsharp
impl FromJson<u64>
```

An integer that fits a `u64`.

### `impl ToJson<u32>`

```zsharp
impl ToJson<u32>
```

An integer.

### `impl FromJson<u32>`

```zsharp
impl FromJson<u32>
```

An integer that fits a `u32`.

### `impl ToJson<u16>`

```zsharp
impl ToJson<u16>
```

An integer.

### `impl FromJson<u16>`

```zsharp
impl FromJson<u16>
```

An integer that fits a `u16`.

### `impl ToJson<u8>`

```zsharp
impl ToJson<u8>
```

An integer.

### `impl FromJson<u8>`

```zsharp
impl FromJson<u8>
```

An integer that fits a `u8`.

### `impl ToJson<option<'a>>`

```zsharp
impl ToJson<option<'a>>
```

`None` as `null`, `Some x` as `x`.

### `impl FromJson<option<'a>>`

```zsharp
impl FromJson<option<'a>>
```

`null` as `None`, anything else as `Some`.

### `impl ToJson<list<'a>>`

```zsharp
impl ToJson<list<'a>>
```

An array of the elements.

### `impl FromJson<list<'a>>`

```zsharp
impl FromJson<list<'a>>
```

An array's elements, each one's error at its index.

### `impl ToJson<array<'a>>`

```zsharp
impl ToJson<array<'a>>
```

An array of the elements.

### `impl FromJson<array<'a>>`

```zsharp
impl FromJson<array<'a>>
```

An array's elements.

### `impl ToJson<Map<'k, 'v>>`

```zsharp
impl ToJson<Map<'k, 'v>>
```

An object of the entries, in key order: a string key as itself, another as its JSON text
(`{"1": "a"}` for `Map.ofList [ (1, "a") ]`).

### `impl FromJson<Map<'k, 'v>>`

```zsharp
impl FromJson<Map<'k, 'v>>
```

An object's entries, each value's error at its key; a key that isn't the map's key type as a
string is read as the document its text is.

### `impl ToJson<HashMap<'k, 'v>>`

```zsharp
impl ToJson<HashMap<'k, 'v>>
```

An object of the entries, in no particular order; keys as `Map`'s are.

### `impl FromJson<HashMap<'k, 'v>>`

```zsharp
impl FromJson<HashMap<'k, 'v>>
```

An object's entries, each value's error at its key; keys as `Map`'s are.

### `derive ToJson`

```zsharp
derive ToJson
```

`toJson` for a record (an object of its fields, by name, in declaration order; `None` as
`null`) or a union (`{"case": "Circle", "fields": [2.5]}`, a case without fields as its name).

### `derive FromJson`

```zsharp
derive FromJson
```

`fromJson` for a record (each field by its key; an absent key takes the field's default, or
`null` for an `option`, else `missing key age`; other keys are ignored) or a union (`"Dot"`,
`{"case": "Dot"}` or `{"case": "Rect", "fields": [2, 3.5]}`), each error at its place.

### `derive Json`

```zsharp
derive Json
```

`ToJson` and `FromJson`, both ways: `[<Derive(Json)>]`.

## Functions

### `Json.print`

```zsharp
Json.print : Json -> string
```

The document as text with no spaces: `{"a":1,"b":[true,null]}`. A `JNumber` prints as
`string` prints an `f64`, so `JNumber 2.0` is `2`, which reads back as `JInt 2`.

### `Json.pretty`

```zsharp
Json.pretty : Json -> string
```

The document indented by two spaces, `"key": value`, an element per line, `[]` and `{}`
inline, with no newline at the end.

### `Json.parseWith`

```zsharp
Json.parseWith : Json.Options -> string -> result<Json, string>
```

The document in `text`, with nesting limited as `options` says.

### `Json.parse`

```zsharp
Json.parse : string -> result<Json, string>
```

The document in `text` (RFC 8259: one value, with whitespace around it), or the first
problem as `line:column: message`, the column in bytes: `3:14: expected ',' or '}' after a
value`. Arrays and objects nest at most 1,000 levels deep (`parseWith` sets another limit).

### `Json.field`

```zsharp
Json.field : string -> Json -> result<Json, string>
```

The value of an object's first `key`.

### `Json.at`

```zsharp
Json.at : int -> Json -> result<Json, string>
```

An array's element at `index` (from 0).

### `Json.string`

```zsharp
Json.string : Json -> result<string, string>
```

A string's text.

### `Json.number`

```zsharp
Json.number : Json -> result<f64, string>
```

A number, a `JInt` converted.

### `Json.int`

```zsharp
Json.int : Json -> result<i64, string>
```

An integer: a `JInt`, or a `JNumber` that is integral and fits an `i64`.

### `Json.bool`

```zsharp
Json.bool : Json -> result<bool, string>
```

A boolean.

### `Json.array`

```zsharp
Json.array : Json -> result<list<Json>, string>
```

An array's elements.

### `Json.object`

```zsharp
Json.object : Json -> result<list<string * Json>, string>
```

An object's keys and values, in document order.

### `Json.within`

```zsharp
Json.within : string -> result<'a, string> -> result<'a, string>
```

`r`, its error said to be at `path` in the document: `Json.within "email"` makes
`at email: expected a string, got 42`, and `Json.within "users[3]"` of that
`at users[3].email: …`. The derives call it at every field and element.

