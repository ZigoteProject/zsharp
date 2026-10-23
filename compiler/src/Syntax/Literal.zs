/// Literals' values from their text: integers in any radix, floats, strings with their escapes,
/// characters, and an interpolated string's pieces (as the F# compiler's lexer reads them).

// a byte of a string as a number, -1 past the end
let private at (s: string) (i: int) : int =
  if i >= 0 && i < String.length s then int (String.byte s i) else -1

// a digit's value in radix 16 (letters either case), -1 for none
let private digitOf (c: int) : int =
  if c >= 48 && c <= 57 then c - 48
  else if c >= 97 && c <= 102 then c - 87
  else if c >= 65 && c <= 70 then c - 55
  else -1

/// An integer literal's value (`42`, `1_000`, `0xFF`, `0b1010`, `0o17`); radix literals take up
/// to 64 bits, so 0xFFFF_FFFF_FFFF_FFFF is -1. Error when it doesn't fit.
let intValue (text: string) : result<i64, string> =
  let n = String.length text
  let radix =
    if n > 2 && at text 0 = 48 then
      (match at text 1 with | 120 | 88 -> 16 | 98 | 66 -> 2 | 111 | 79 -> 8 | _ -> 10)
    else
      10
  if radix = 10 then
    match (Int.parse (String.replace text "_" "") : option<i64>) with
    | Some v -> Ok v
    | None -> Error "integer literal too large"
  else
    // digits past the first nonzero one, so the bits they need are known
    let mutable value: i64 = 0
    let mutable significant = 0
    let mutable lead = 0
    for i in 2 .. n - 1 do
      let d = digitOf (at text i)
      if d >= 0 then
        if significant = 0 && d > 0 then
          lead <- d
        if significant > 0 || d > 0 then
          significant <- significant + 1
        value <- Int.wrappingAdd (Int.wrappingMul value (i64 radix)) (i64 d)
    let bits = if radix = 16 then 4 else if radix = 8 then 3 else 1
    let leadBits = if lead >= 8 then 4 else if lead >= 4 then 3 else if lead >= 2 then 2 else 1
    let needs =
      if significant = 0 then 0 else (significant - 1) * bits + (if radix = 2 then 1 else leadBits)
    if needs > 64 then Error "integer literal too large (more than 64 bits)" else Ok value

/// A float literal's value.
let floatValue (text: string) : f64 =
  match (Float.parse (String.replace text "_" "") : option<f64>) with
  | Some v -> v
  | None -> 0.0

/// The escape after a backslash at s[i]: its code point and the index after it (\n \r \t \0 \\
/// \" \' and \u{hex}), or an error.
let escape (s: string) (i: int) : result<int * int, string> =
  match at s i with
  | 110 -> Ok(10, i + 1)
  | 114 -> Ok(13, i + 1)
  | 116 -> Ok(9, i + 1)
  | 48 -> Ok(0, i + 1)
  | 92 -> Ok(92, i + 1)
  | 34 -> Ok(34, i + 1)
  | 39 -> Ok(39, i + 1)
  | 117 when at s (i + 1) = 123 ->
    let mutable close = i + 2
    while close < String.length s && at s close <> 125 do
      close <- close + 1
    if close >= String.length s then
      Error "unterminated \\u{…} escape"
    else
      let hex = String.sub s (i + 2) (close - i - 2)
      match (Int.parseRadix 16 hex : option<int>) with
      | Some v when hex <> "" && v <= 0x10FFFF && not (v >= 0xD800 && v <= 0xDFFF) ->
        Ok(v, close + 1)
      | _ -> Error $"\\u{{{hex}}} is not a Unicode scalar value"
  | c -> Error $"unknown escape '\\{String.sub s i (if c >= 0 then 1 else 0)}'"

// the UTF-8 bytes of a code point, appended
let private push (b: Buffer<u8>) (cp: int) =
  if cp < 0x80 then
    Buffer.push (u8 cp) b
  else if cp < 0x800 then
    Buffer.push (u8 (0xC0 ||| (cp >>> 6))) b
    Buffer.push (u8 (0x80 ||| (cp &&& 0x3F))) b
  else if cp < 0x10000 then
    Buffer.push (u8 (0xE0 ||| (cp >>> 12))) b
    Buffer.push (u8 (0x80 ||| ((cp >>> 6) &&& 0x3F))) b
    Buffer.push (u8 (0x80 ||| (cp &&& 0x3F))) b
  else
    Buffer.push (u8 (0xF0 ||| (cp >>> 18))) b
    Buffer.push (u8 (0x80 ||| ((cp >>> 12) &&& 0x3F))) b
    Buffer.push (u8 (0x80 ||| ((cp >>> 6) &&& 0x3F))) b
    Buffer.push (u8 (0x80 ||| (cp &&& 0x3F))) b

// the code point of the UTF-8 character at s[i], and the index after it
let private decode (s: string) (i: int) : int * int =
  let b0 = at s i
  if b0 < 0x80 then (b0, i + 1)
  else if b0 < 0xE0 then (((b0 &&& 0x1F) <<< 6) ||| (at s (i + 1) &&& 0x3F), i + 2)
  else if b0 < 0xF0 then
    (((b0 &&& 0x0F) <<< 12) ||| ((at s (i + 1) &&& 0x3F) <<< 6) ||| (at s (i + 2) &&& 0x3F), i + 3)
  else
    (((b0 &&& 0x07) <<< 18) ||| ((at s (i + 1) &&& 0x3F) <<< 12) ||| ((at s (i + 2) &&& 0x3F) <<< 6) ||| (at s (i + 3) &&& 0x3F), i + 4)

/// A string literal's value from its text (its quotes included): escapes read, a triple-quoted
/// one as written.
let stringValue (text: string) : result<string, string> =
  let n = String.length text
  if n >= 6 && String.startsWith "\"\"\"" text then
    Ok(String.sub text 3 (n - 6))
  else
    let b = Buffer.empty
    let mutable i = 1
    let mutable error = ""
    let stop = if n >= 2 && at text (n - 1) = 34 then n - 1 else n
    while i < stop && error = "" do
      if at text i = 92 then
        match escape text (i + 1) with
        | Ok(cp, next) ->
          push b cp
          i <- next
        | Error e -> error <- e
      else
        Buffer.push (String.byte text i) b
        i <- i + 1
    if error <> "" then Error error else Ok(String.ofBytes b)

/// A character literal's code point ('a', '\n', '\u{e9}', 'é').
let charValue (text: string) : result<int, string> =
  if at text 1 = 92 then
    match escape text 2 with
    | Ok(cp, _) -> Ok cp
    | Error e -> Error e
  else
    Ok(fst (decode text 1))

/// An interpolated string's pieces from its text ($"…"): each a literal's text (escapes read,
/// `{{` and `}}` single) or a hole's (its text, and its offset in the literal's text).
type Piece =
  | Text of string
  | Hole of string * int

let pieces (text: string) : result<list<Piece>, string> =
  let n = String.length text
  let stop = if n >= 3 && at text (n - 1) = 34 then n - 1 else n
  let out = Buffer.empty
  let b = Buffer.empty
  let mutable i = 2
  let mutable error = ""
  while i < stop && error = "" do
    let c = at text i
    if c = 92 then
      match escape text (i + 1) with
      | Ok(cp, next) ->
        push b cp
        i <- next
      | Error e -> error <- e
    else if c = 123 && at text (i + 1) = 123 then
      Buffer.push (u8 123) b
      i <- i + 2
    else if c = 125 && at text (i + 1) = 125 then
      Buffer.push (u8 125) b
      i <- i + 2
    else if c = 123 then
      Buffer.push (Text(String.ofBytes b)) out
      Buffer.clear b
      let from = i + 1
      let mutable depth = 0
      i <- i + 1
      // the hole may itself contain braces: {f { x = 1 }}
      while i < stop && (at text i <> 125 || depth > 0) do
        if at text i = 123 then depth <- depth + 1 else if at text i = 125 then depth <- depth - 1
        i <- i + 1
      Buffer.push (Hole(String.sub text from (i - from), from)) out
      i <- i + 1
    else
      Buffer.push (String.byte text i) b
      i <- i + 1
  Buffer.push (Text(String.ofBytes b)) out
  if error <> "" then Error error else Ok(Array.toList (Buffer.toArray out))
