/// JSON (RFC 8259): one `Json` type for any document, `Json.parse`, `Json.print` and
/// `Json.pretty`, accessors that say where a document didn't fit, and the `ToJson` and `FromJson`
/// traits, which `[<Derive(Json)>]` writes for a record or a union. Every target has it.
namespace Text

/// A JSON document. A number with no `.` or exponent that fits 64 bits is a `JInt` (an id
/// survives), any other a `JNumber`; an object keeps its keys in document order, duplicates too.
type Json =
  /// `null`.
  | JNull
  /// `true` or `false`.
  | JBool of bool
  /// An integral number that fits an `i64`.
  | JInt of i64
  /// Any other number.
  | JNumber of f64
  /// A string, its escapes decoded.
  | JString of string
  /// An array.
  | JArray of list<Json>
  /// An object: its keys and values in document order.
  | JObject of list<string * Json>

/// A value as a JSON document. `[<Derive(ToJson)>]` (or `Json`, both ways) writes it for a record
/// or a union.
trait ToJson<'a> =
  /// The value as a document.
  abstract toJson : 'a -> Json

/// A value from a JSON document. `[<Derive(FromJson)>]` (or `Json`) writes it for a record or a
/// union.
trait FromJson<'a> =
  /// The value the document holds, or what didn't fit and where:
  /// `at users[3].email: expected a string, got 42`.
  abstract fromJson : Json -> result<'a, string>

/// Parsing, printing and reading JSON documents.
module Json =
  /// How `parseWith` reads: arrays and objects nest at most `depth` levels.
  type Options = { depth: int = 1000 }

  // ---- printing

  // the text of a byte that a string literal escapes
  let private escape (b: int) =
    match b with
    | 34 -> "\\\""
    | 92 -> "\\\\"
    | 10 -> "\\n"
    | 13 -> "\\r"
    | 9 -> "\\t"
    | 8 -> "\\b"
    | 12 -> "\\f"
    | _ ->
      "\\u00" + String.sub "0123456789abcdef" (b / 16) 1 + String.sub "0123456789abcdef" (b % 16) 1

  // `s` as a string literal: `"`, `\` and controls escaped, everything else as its UTF-8
  let private quote (s: string) =
    let n = String.length s
    let mutable out = "\""
    let mutable from = 0 // the first byte not copied yet

    for i in 0 .. n - 1 do
      let b = int (String.byte s i)
      if b = 34 || b = 92 || b < 32 then
        out <- out + String.sub s from (i - from) + escape b
        from <- i + 1

    out + String.sub s from (n - from) + "\""

  let rec private compact (j: Json) : string =
    match j with
    | JNull -> "null"
    | JBool b -> if b then "true" else "false"
    | JInt n -> string n
    | JNumber x -> if x - x = 0.0 then string x else "null" // JSON has no spelling for NaN or infinity
    | JString s -> quote s
    | JArray xs -> "[" + String.join "," (List.map compact xs) + "]"
    | JObject kvs ->
      "{" + String.join "," (List.map (fun (k, v) -> quote k + ":" + compact v) kvs) + "}"

  /// The document as text with no spaces: `{"a":1,"b":[true,null]}`. A `JNumber` prints as
  /// `string` prints an `f64`, so `JNumber 2.0` is `2`, which reads back as `JInt 2`.
  let print (j: Json) = compact j

  let rec private indented (indent: string) (j: Json) : string =
    let inner = indent + "  "

    match j with
    | JArray [] -> "[]"
    | JObject [] -> "{}"
    | JArray xs ->
      "[\n" + String.join ",\n" (List.map (fun x -> inner + indented inner x) xs) + "\n" + indent + "]"
    | JObject kvs ->
      let field (k, v) = inner + quote k + ": " + indented inner v
      "{\n" + String.join ",\n" (List.map field kvs) + "\n" + indent + "}"
    | _ -> compact j

  /// The document indented by two spaces, `"key": value`, an element per line, `[]` and `{}`
  /// inline, with no newline at the end.
  let pretty (j: Json) = indented "" j

  // ---- parsing: each function reads from byte i and gives the value and the byte after it

  // `line:column` of byte i (1-based; the column in bytes), for an error
  let private position (s: string) (i: int) =
    let mutable line = 1
    let mutable col = 1

    for k in 0 .. min i (String.length s) - 1 do
      if String.byte s k = u8 10 then
        line <- line + 1
        col <- 1
      else
        col <- col + 1

    $"{line}:{col}"

  let private fail (s: string) (i: int) (msg: string) : result<'a, string> =
    Error (position s i + ": " + msg)

  // the byte at i, or -1 past the end
  let private byteAt (s: string) (i: int) =
    if i < String.length s then int (String.byte s i) else -1

  let rec private skip (s: string) (i: int) =
    let b = byteAt s i
    if b = 32 || b = 9 || b = 10 || b = 13 then skip s (i + 1) else i

  let private isDigit (b: int) = b >= 48 && b <= 57

  let rec private digits (s: string) (i: int) = if isDigit (byteAt s i) then digits s (i + 1) else i

  // a number: an optional '-', an integer part without leading zeros, an optional fraction and
  // exponent
  let private numberAt (s: string) (start: int) : result<Json * int, string> =
    let i = if byteAt s start = 45 then start + 1 else start

    if not (isDigit (byteAt s i)) then
      fail s i "expected a digit"
    else
      let afterInt = if byteAt s i = 48 then i + 1 else digits s i

      if byteAt s i = 48 && isDigit (byteAt s afterInt) then
        fail s afterInt "a number has no leading zeros"
      else
        let afterFrac =
          if byteAt s afterInt = 46 then
            (if isDigit (byteAt s (afterInt + 1)) then digits s (afterInt + 1) else -1)
          else
            afterInt

        if afterFrac < 0 then
          fail s (afterInt + 1) "expected a digit after '.'"
        else
          let afterExp =
            let b = byteAt s afterFrac
            if b = 101 || b = 69 then
              let e =
                if byteAt s (afterFrac + 1) = 43 || byteAt s (afterFrac + 1) = 45 then
                  afterFrac + 2
                else
                  afterFrac + 1
              if isDigit (byteAt s e) then digits s e else -1
            else afterFrac

          if afterExp < 0 then
            fail s afterFrac "expected a digit in the exponent"
          else
            let text = String.sub s start (afterExp - start)
            let intDigits = afterInt - i

            // an integral literal that fits 64 bits: 19 digits at most, compared as text at 19
            let limit = if i > start then "9223372036854775808" else "9223372036854775807"
            let fits =
              afterExp = afterInt && (intDigits < 19 || (intDigits = 19 && String.sub s i 19 <= limit))

            if fits then
              let mutable n = i64 0
              for k in i .. afterInt - 1 do
                n <- n * i64 10 - i64 (byteAt s k - 48) // negative, so i64's lowest fits too
              Ok (JInt (if i > start then n else -n), afterExp)
            else
              match String.parseFloat text with
              | Some x -> Ok (JNumber x, afterExp)
              | None -> fail s start "a number out of range"

  let private hexValue (b: int) =
    if isDigit b then b - 48
    else if b >= 97 && b <= 102 then b - 87
    else if b >= 65 && b <= 70 then b - 55
    else -1

  // the four hex digits of a \u escape at i, or -1
  let private hex4 (s: string) (i: int) =
    let mutable v = 0
    for k in i .. i + 3 do
      let h = hexValue (byteAt s k)
      v <- if v < 0 || h < 0 then -1 else v * 16 + h
    v

  // a string's text after its opening quote: one copy of each run without escapes, the escapes
  // decoded, UTF-8 checked
  let rec private text (s: string) (i: int) (acc: string) (from: int) : result<string * int, string> =
    let b = byteAt s i

    if b = 34 then
      Ok (acc + String.sub s from (i - from), i + 1)
    else if b < 0 then
      fail s i "a string that doesn't end"
    else if b < 32 then
      fail s i "a control character in a string (escape it: \\n, \\t, \\u0001)"
    else if b = 92 then
      let acc = acc + String.sub s from (i - from)
      let e = byteAt s (i + 1)
      let simple =
        match e with
        | 34 -> "\""
        | 92 -> "\\"
        | 47 -> "/"
        | 98 -> "\u{8}"
        | 102 -> "\u{c}"
        | 110 -> "\n"
        | 114 -> "\r"
        | 116 -> "\t"
        | _ -> ""

      if simple <> "" then
        text s (i + 2) (acc + simple) (i + 2)
      else if e = 117 then
        let u = hex4 s (i + 2)
        if u < 0 then
          fail s i "expected four hex digits after \\u"
        else if u >= 0xD800 && u <= 0xDBFF then
          // a surrogate pair is one character
          let lo = if byteAt s (i + 6) = 92 && byteAt s (i + 7) = 117 then hex4 s (i + 8) else -1
          if lo >= 0xDC00 && lo <= 0xDFFF then
            let c = 0x10000 + ((u - 0xD800) <<< 10) + (lo - 0xDC00)
            text s (i + 12) (acc + string (char c)) (i + 12)
          else
            fail s i "a lone surrogate (\\uD800 to \\uDBFF needs a \\uDC00 to \\uDFFF after it)"
        else if u >= 0xDC00 && u <= 0xDFFF then
          fail s i "a lone surrogate (\\uDC00 to \\uDFFF follows a \\uD800 to \\uDBFF)"
        else
          text s (i + 6) (acc + string (char u)) (i + 6)
      else
        fail s i "an unknown escape (the escapes are \\\" \\\\ \\/ \\b \\f \\n \\r \\t \\uXXXX)"
    else if b < 0x80 then
      text s (i + 1) acc from
    else
      // a UTF-8 sequence: well formed, shortest, not a surrogate
      let (c, next) = String.decodeAt s i
      let cp = int c
      let length = next - i
      let ok =
        (if length = 2 then cp >= 0x80
          else if length = 3 then cp >= 0x800 && (cp < 0xD800 || cp > 0xDFFF)
          else length = 4 && cp >= 0x10000 && cp <= 0x10FFFF)
      if ok then text s next acc from else fail s i "invalid UTF-8"

  let private literal (s: string) (i: int) (word: string) (value: Json) : result<Json * int, string> =
    let n = String.length word
    if i + n <= String.length s && String.sub s i n = word then
      Ok (value, i + n)
    else
      fail s i "expected a value"

  let rec private value (s: string) (i: int) (depth: int) (limit: int) : result<Json * int, string> =
    let i = skip s i

    match byteAt s i with
    | 123 -> objectAt s (i + 1) depth limit
    | 91 -> arrayAt s (i + 1) depth limit
    | 34 ->
      let (t, j) = (text s (i + 1) "" (i + 1))?
      Ok (JString t, j)
    | 116 -> literal s i "true" (JBool true)
    | 102 -> literal s i "false" (JBool false)
    | 110 -> literal s i "null" JNull
    | b when b = 45 || isDigit b -> numberAt s i
    | -1 -> fail s i "expected a value, found the end"
    | _ -> fail s i "expected a value"

  and private objectAt (s: string) (i: int) (depth: int) (limit: int) : result<Json * int, string> =
    if depth >= limit then
      fail s (i - 1) $"nesting deeper than {limit} levels"
    else
      let i = skip s i
      if byteAt s i = 125 then Ok (JObject [], i + 1) else members s i (depth + 1) limit []

  and private members (s: string) (i: int) (depth: int) (limit: int) (acc: list<string * Json>) : result<Json * int, string> =
    let i = skip s i

    if byteAt s i <> 34 then
      fail s i "expected a key (a string)"
    else
      let (key, j) = (text s (i + 1) "" (i + 1))?
      let j = skip s j

      if byteAt s j <> 58 then
        fail s j "expected ':' after a key"
      else
        let (v, k) = (value s (j + 1) depth limit)?
        let k = skip s k

        match byteAt s k with
        | 44 -> members s (k + 1) depth limit ((key, v) :: acc)
        | 125 -> Ok (JObject (List.rev ((key, v) :: acc)), k + 1)
        | _ -> fail s k "expected ',' or '}' after a value"

  and private arrayAt (s: string) (i: int) (depth: int) (limit: int) : result<Json * int, string> =
    if depth >= limit then
      fail s (i - 1) $"nesting deeper than {limit} levels"
    else
      let i = skip s i
      if byteAt s i = 93 then Ok (JArray [], i + 1) else elements s i (depth + 1) limit []

  and private elements (s: string) (i: int) (depth: int) (limit: int) (acc: list<Json>) : result<Json * int, string> =
    let (v, k) = (value s i depth limit)?
    let k = skip s k

    match byteAt s k with
    | 44 -> elements s (k + 1) depth limit (v :: acc)
    | 93 -> Ok (JArray (List.rev (v :: acc)), k + 1)
    | _ -> fail s k "expected ',' or ']' after a value"

  /// The document in `text`, with nesting limited as `options` says.
  let parseWith (options: Options) (text: string) : result<Json, string> =
    let (j, i) = (value text 0 0 options.depth)?
    let i = skip text i
    if i < String.length text then fail text i "expected the end after the document" else Ok j

  /// The document in `text` (RFC 8259: one value, with whitespace around it), or the first
  /// problem as `line:column: message`, the column in bytes: `3:14: expected ',' or '}' after a
  /// value`. Arrays and objects nest at most 1,000 levels deep (`parseWith` sets another limit).
  let parse (text: string) = parseWith { depth = 1000 } text

  // ---- reading

  // what a mismatch shows of a value: its text, cut at 40 bytes (at a character's start)
  let private got (j: Json) =
    let t = compact j
    if String.length t <= 40 then t
    else
      let mutable cut = 40
      while cut > 0 && int (String.byte t cut) &&& 0xC0 = 0x80 do
        cut <- cut - 1
      String.sub t 0 cut + "…"

  /// The value of an object's first `key`.
  let field (key: string) (j: Json) : result<Json, string> =
    match j with
    | JObject kvs ->
      match List.tryFind (fun (k, _) -> k = key) kvs with
      | Some (_, v) -> Ok v
      | None -> Error $"missing key {key}"
    | _ -> Error $"expected an object, got {got j}"

  let rec private nth (i: int) (xs: list<Json>) =
    match xs with
    | [] -> None
    | x :: rest -> if i = 0 then Some x else nth (i - 1) rest

  /// An array's element at `index` (from 0).
  let at (index: int) (j: Json) : result<Json, string> =
    match j with
    | JArray xs ->
      match (if index < 0 then None else nth index xs) with
      | Some x -> Ok x
      | None ->
        let n = List.length xs
        Error $"index {index} is past the end ({n} element{if n = 1 then "" else "s"})"
    | _ -> Error $"expected an array, got {got j}"

  /// A string's text.
  let string (j: Json) : result<string, string> =
    match j with
    | JString s -> Ok s
    | _ -> Error $"expected a string, got {got j}"

  /// A number, a `JInt` converted.
  let number (j: Json) : result<f64, string> =
    match j with
    | JNumber x -> Ok x
    | JInt n -> Ok (f64 n)
    | _ -> Error $"expected a number, got {got j}"

  /// An integer: a `JInt`, or a `JNumber` that is integral and fits an `i64`.
  let int (j: Json) : result<i64, string> =
    match j with
    | JInt n -> Ok n
    | JNumber x when x - x = 0.0 && f64 (i64 x) = x && x < 9.2e18 && x > -9.2e18 -> Ok (i64 x)
    | _ -> Error $"expected an integer, got {got j}"

  /// A boolean.
  let bool (j: Json) : result<bool, string> =
    match j with
    | JBool b -> Ok b
    | _ -> Error $"expected true or false, got {got j}"

  /// An array's elements.
  let array (j: Json) : result<list<Json>, string> =
    match j with
    | JArray xs -> Ok xs
    | _ -> Error $"expected an array, got {got j}"

  /// An object's keys and values, in document order.
  let object (j: Json) : result<list<string * Json>, string> =
    match j with
    | JObject kvs -> Ok kvs
    | _ -> Error $"expected an object, got {got j}"

  /// `r`, its error said to be at `path` in the document: `Json.within "email"` makes
  /// `at email: expected a string, got 42`, and `Json.within "users[3]"` of that
  /// `at users[3].email: …`. The derives call it at every field and element.
  let within (path: string) (r: result<'a, string>) : result<'a, string> =
    match r with
    | Ok v -> Ok v
    | Error e ->
      if String.startsWith "at " e then
        let rest = String.sub e 3 (String.length e - 3)
        Error ("at " + path + (if String.startsWith "[" rest then "" else ".") + rest)
      else
        Error ("at " + path + ": " + e)

/// A document prints as `Json.print` writes it, so `string j` and `$"{j}"` are its text.
impl Show<Json> =
  let show (j: Json) = Json.print j

// ---- the impls for Core's types

/// A document as itself, so a field of type `Json` keeps what it holds.
impl ToJson<Json> =
  let toJson (j: Json) = j

/// A document as itself.
impl FromJson<Json> =
  let fromJson (j: Json) : result<Json, string> = Ok j

/// A string as a JSON string.
impl ToJson<string> =
  let toJson (s: string) = JString s

/// A JSON string's text.
impl FromJson<string> =
  let fromJson (j: Json) = Json.string j

/// A character as a string of one character.
impl ToJson<char> =
  let toJson (c: char) = JString (string c)

/// A string of one character.
impl FromJson<char> =
  let fromJson (j: Json) : result<char, string> =
    match j with
    | JString s when String.length s > 0 && snd (String.decodeAt s 0) = String.length s ->
      Ok (fst (String.decodeAt s 0))
    | _ -> Error $"expected a string of one character, got {Json.print j}"

/// `true` or `false`.
impl ToJson<bool> =
  let toJson (b: bool) = JBool b

/// `true` or `false`.
impl FromJson<bool> =
  let fromJson (j: Json) = Json.bool j

/// A number.
impl ToJson<f64> =
  let toJson (x: f64) = JNumber x

/// Either kind of number.
impl FromJson<f64> =
  let fromJson (j: Json) = Json.number j

/// A number, widened to an `f64`.
impl ToJson<f32> =
  let toJson (x: f32) = JNumber (f64 x)

/// Either kind of number, narrowed to an `f32`.
impl FromJson<f32> =
  let fromJson (j: Json) = Json.number j |> Result.map f32

/// An integer.
impl ToJson<int> =
  let toJson (n: int) = JInt (i64 n)

/// An integer that fits an `int` (32 bits on a microcontroller, 64 on a host).
impl FromJson<int> =
  let fromJson (j: Json) : result<int, string> =
    match Json.int j with
    | Ok n when i64 (int n) = n -> Ok (int n)
    | Ok _ -> Error $"expected an integer that fits int, got {Json.print j}"
    | Error e -> Error e

/// An integer.
impl ToJson<i64> =
  let toJson (n: i64) = JInt n

/// An integer that fits an `i64`.
impl FromJson<i64> =
  let fromJson (j: Json) = Json.int j

/// An integer.
impl ToJson<i32> =
  let toJson (n: i32) = JInt (i64 n)

/// An integer that fits an `i32`.
impl FromJson<i32> =
  let fromJson (j: Json) : result<i32, string> =
    match Json.int j with
    | Ok n when i64 (i32 n) = n -> Ok (i32 n)
    | Ok _ -> Error $"expected an integer that fits i32, got {Json.print j}"
    | Error e -> Error e

/// An integer.
impl ToJson<i16> =
  let toJson (n: i16) = JInt (i64 n)

/// An integer that fits an `i16`.
impl FromJson<i16> =
  let fromJson (j: Json) : result<i16, string> =
    match Json.int j with
    | Ok n when i64 (i16 n) = n -> Ok (i16 n)
    | Ok _ -> Error $"expected an integer that fits i16, got {Json.print j}"
    | Error e -> Error e

/// An integer.
impl ToJson<i8> =
  let toJson (n: i8) = JInt (i64 n)

/// An integer that fits an `i8`.
impl FromJson<i8> =
  let fromJson (j: Json) : result<i8, string> =
    match Json.int j with
    | Ok n when i64 (i8 n) = n -> Ok (i8 n)
    | Ok _ -> Error $"expected an integer that fits i8, got {Json.print j}"
    | Error e -> Error e

/// An integer; above `i64`'s range, a `JNumber`.
impl ToJson<u64> =
  let toJson (n: u64) = if n > u64 9223372036854775807 then JNumber (f64 n) else JInt (i64 n)

/// An integer that fits a `u64`.
impl FromJson<u64> =
  let fromJson (j: Json) : result<u64, string> =
    match j with
    | JInt n when n >= i64 0 -> Ok (u64 n)
    | JNumber x when x >= 0.0 && x < 1.8446744073709552e19 && f64 (u64 x) = x -> Ok (u64 x)
    | _ -> Error $"expected an integer that fits u64, got {Json.print j}"

/// An integer.
impl ToJson<u32> =
  let toJson (n: u32) = JInt (i64 n)

/// An integer that fits a `u32`.
impl FromJson<u32> =
  let fromJson (j: Json) : result<u32, string> =
    match Json.int j with
    | Ok n when i64 (u32 n) = n -> Ok (u32 n)
    | Ok _ -> Error $"expected an integer that fits u32, got {Json.print j}"
    | Error e -> Error e

/// An integer.
impl ToJson<u16> =
  let toJson (n: u16) = JInt (i64 n)

/// An integer that fits a `u16`.
impl FromJson<u16> =
  let fromJson (j: Json) : result<u16, string> =
    match Json.int j with
    | Ok n when i64 (u16 n) = n -> Ok (u16 n)
    | Ok _ -> Error $"expected an integer that fits u16, got {Json.print j}"
    | Error e -> Error e

/// An integer.
impl ToJson<u8> =
  let toJson (n: u8) = JInt (i64 n)

/// An integer that fits a `u8`.
impl FromJson<u8> =
  let fromJson (j: Json) : result<u8, string> =
    match Json.int j with
    | Ok n when i64 (u8 n) = n -> Ok (u8 n)
    | Ok _ -> Error $"expected an integer that fits u8, got {Json.print j}"
    | Error e -> Error e

/// `None` as `null`, `Some x` as `x`.
impl ToJson<option<'a>> =
  let toJson (o: option<'a>) =
    match o with
    | Some x -> toJson x
    | None -> JNull

/// `null` as `None`, anything else as `Some`.
impl FromJson<option<'a>> =
  let fromJson (j: Json) : result<option<'a>, string> =
    match j with
    | JNull -> Ok None
    | _ -> Result.map Some (fromJson j)

/// An array of the elements.
impl ToJson<list<'a>> =
  let toJson (xs: list<'a>) = JArray (List.map toJson xs)

/// An array's elements, each one's error at its index.
impl FromJson<list<'a>> =
  let fromJson (j: Json) : result<list<'a>, string> =
    let rec go (i: int) (xs: list<Json>) (acc: list<'a>) =
      match xs with
      | [] -> Ok (List.rev acc)
      | x :: rest ->
        let v = (fromJson x |> Json.within $"[{i}]")?
        go (i + 1) rest (v :: acc)
    let xs = (Json.array j)?
    go 0 xs []

/// An array of the elements.
impl ToJson<array<'a>> =
  let toJson (xs: array<'a>) = JArray (Array.toList (Array.map toJson xs))

/// An array's elements.
impl FromJson<array<'a>> =
  let fromJson (j: Json) : result<array<'a>, string> = Result.map Array.ofList (fromJson j)

// an object's key for a map's key: a string as itself, another key as its document's text
let private keyText (k: Json) =
  match k with
  | JString s -> s
  | _ -> Json.print k

// a map's key from an object's key: as a string, else as the document the text is
let private keyOf (text: string) : result<'k, string> =
  match fromJson (JString text) with
  | Ok k -> Ok k
  | Error e ->
    match Json.parse text with
    | Ok j -> fromJson j
    | Error _ -> Error e

/// An object of the entries, in key order: a string key as itself, another as its JSON text
/// (`{"1": "a"}` for `Map.ofList [ (1, "a") ]`).
impl ToJson<Map<'k, 'v>> =
  let toJson (m: Map<'k, 'v>) = JObject (List.map (fun (k, v) -> (keyText (toJson k), toJson v)) (Map.toList m))

/// An object's entries, each value's error at its key; a key that isn't the map's key type as a
/// string is read as the document its text is.
impl FromJson<Map<'k, 'v>> =
  let fromJson (j: Json) : result<Map<'k, 'v>, string> =
    let rec go (kvs: list<string * Json>) (acc: Map<'k, 'v>) =
      match kvs with
      | [] -> Ok acc
      | (key, x) :: rest ->
        let k = (keyOf key |> Json.within key)?
        let v = (fromJson x |> Json.within key)?
        go rest (Map.add k v acc)
    let kvs = (Json.object j)?
    go kvs Map.empty

/// An object of the entries, in no particular order; keys as `Map`'s are.
impl ToJson<HashMap<'k, 'v>> =
  let toJson (m: HashMap<'k, 'v>) = JObject (List.map (fun (k, v) -> (keyText (toJson k), toJson v)) (HashMap.toList m))

/// An object's entries, each value's error at its key; keys as `Map`'s are.
impl FromJson<HashMap<'k, 'v>> =
  let fromJson (j: Json) : result<HashMap<'k, 'v>, string> =
    let rec go (kvs: list<string * Json>) (acc: HashMap<'k, 'v>) =
      match kvs with
      | [] -> Ok acc
      | (key, x) :: rest ->
        let k = (keyOf key |> Json.within key)?
        let v = (fromJson x |> Json.within key)?
        go rest (HashMap.add k v acc)
    let kvs = (Json.object j)?
    go kvs HashMap.empty

// ---- the derives

/// `toJson` for a record (an object of its fields, by name, in declaration order; `None` as
/// `null`) or a union (`{"case": "Circle", "fields": [2.5]}`, a case without fields as its name).
derive ToJson =
  let toJson (x: 'self) =
    match Shape.of x with
    | Record r ->
      let mutable fields = []
      for f in r.fields do
        fields <- (f.name, toJson f.value) :: fields
      JObject (List.rev fields)
    | Union c ->
      if c.count = 0 then
        JString c.name
      else
        let mutable args = []
        for f in c.fields do
          args <- toJson f.value :: args
        JObject [ ("case", JString c.name); ("fields", JArray (List.rev args)) ]

/// `fromJson` for a record (each field by its key; an absent key takes the field's default, or
/// `null` for an `option`, else `missing key age`; other keys are ignored) or a union (`"Dot"`,
/// `{"case": "Dot"}` or `{"case": "Rect", "fields": [2, 3.5]}`), each error at its place.
derive FromJson =
  let fromJson (j: Json) : result<'self, string> =
    match Shape.kind with
    | RecordKind ->
      let kvs = (Json.object j)?
      Shape.build (fun f ->
        match (List.tryFind (fun (k, _) -> k = f.name) kvs, f.default) with
        | (Some (_, v), _) -> fromJson v |> Json.within f.name
        | (None, Some d) -> Ok d
        | (None, None) -> fromJson JNull |> Result.mapError (fun _ -> $"missing key {f.name}"))
    | UnionKind ->
      let (name, args) =
        (match j with
          | JString name -> Ok (name, JArray [])
          | _ ->
            let name = (Json.field "case" j |> Result.bind Json.string |> Json.within "case")?
            let args = (match Json.field "fields" j with
              | Ok a -> Json.array a |> Result.map (fun _ -> a) |> Json.within "fields"
              | Error _ -> Ok (JArray []))?
            Ok (name, args))?
      match Shape.buildCase name (fun f ->
        Json.at f.index args |> Result.bind fromJson |> Json.within $"fields[{f.index}]") with
      | Some built -> built
      | None -> Error $"unknown case {name}"

/// `ToJson` and `FromJson`, both ways: `[<Derive(Json)>]`.
derive Json = ToJson, FromJson
