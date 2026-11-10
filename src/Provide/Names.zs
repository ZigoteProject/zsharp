/// The names a provider writes (proposal 0001): a key or a column as a field, in double backticks
/// when it isn't a plain name, so the derives read the key as the field's name; a key as a
/// record's name, in PascalCase and singular for a list's elements. And how what a provider
/// takes from its input goes into the module: a string literal escaped, a comment on one line,
/// so a sample's text is data there and never code.

let private hex = "0123456789abcdef"

/// A string as a Z# literal that reads back as it: `\`, `"` and the control characters escaped
/// (`\n`, `\r`, `\t`, else `\u{…}`), so no text ends it early.
let literal (s: string) : string =
  let out = Buffer.empty
  Buffer.push "\"" out
  let n = String.length s
  // the first byte not copied yet
  let from = ref 0
  let flush (upTo: int) =
    if upTo > from.Value then
      Buffer.push (String.sub s from.Value (upTo - from.Value)) out
  for i in 0 .. n - 1 do
    let b = int (String.byte s i)
    if b < 32 || b = 127 || b = 34 || b = 92 then
      flush i
      let e =
        match b with
        | 34 -> "\\\""
        | 92 -> "\\\\"
        | 10 -> "\\n"
        | 13 -> "\\r"
        | 9 -> "\\t"
        | _ -> "\\u{" + String.sub hex (b / 16) 1 + String.sub hex (b % 16) 1 + "}"
      Buffer.push e out
      from.Value <- i + 1
  flush n
  Buffer.push "\"" out
  String.concat (Array.toList (Buffer.toArray out))

/// Text for a comment: each control character (a line break among them) a space, so it stays on
/// its line.
let oneLine (s: string) : string =
  let out = Buffer.empty
  for i in 0 .. String.length s - 1 do
    let b = String.byte s i
    Buffer.push (if b < u8 32 || b = u8 127 then u8 32 else b) out
  String.ofBytes (Buffer.toArray out)

let private keywords : Set<string> =
  Set.ofList [ "let"; "rec"; "if"; "then"; "else"; "extern"; "true"; "false"; "not"; "match"; "with"; "when"; "type"; "of"; "as"; "fun"; "function"; "for"; "in"; "do"; "while"; "mutable"; "member"; "static"; "trait"; "impl"; "abstract"; "derive"; "open"; "module"; "namespace"; "private"; "and"; "unsafe"; "effect"
               // contextual: a statement or a handler starts with them
               "use"; "return"; "yield"; "handle" ]

/// Library names a provided record must not take: a program would reach the record instead.
let private reserved : Set<string> =
  Set.ofList [ "Json"; "Option"; "Result"; "List"; "Array"; "Map"; "Set"; "String"; "Int"; "Float"; "Char"; "Bytes"; "Math"; "Row" ]

let private isLetter (b: u8) = (b >= u8 65 && b <= u8 90) || (b >= u8 97 && b <= u8 122) || b >= u8 128
let private isDigit (b: u8) = b >= u8 48 && b <= u8 57

/// Whether `s` is written as it is: letters, digits and `_`, not starting with a digit, and not a
/// keyword (the lexer's rule).
let isIdent (s: string) : bool =
  let n = String.length s
  if n = 0 then false
  else
    let first = String.byte s 0
    let mutable ok = isLetter first || first = u8 95
    let mutable i = 1
    while i < n do
      let b = String.byte s i
      if not (isLetter b || isDigit b || b = u8 95) then ok <- false
      i <- i + 1
    ok && not (Set.contains s keywords)

/// Whether a key can be a field's name, itself or in double backticks: not empty, and with no
/// control character, no two backticks running and no backtick at its end, which would end the
/// backticks early or the line (the lexer reads no escape inside them).
let nameable (key: string) : bool =
  let n = String.length key
  let mutable ok = n > 0 && String.byte key (n - 1) <> u8 96
  let mutable i = 0
  while ok && i < n do
    let b = String.byte key i
    if b < u8 32 || b = u8 127 || (b = u8 96 && i + 1 < n && String.byte key (i + 1) = u8 96) then ok <- false
    i <- i + 1
  ok

/// A key as a field name: itself when it's a plain name, else in double backticks. A key that
/// isn't nameable has its control characters and backticks written as _, so what's written is a
/// name whatever the key holds; the providers refuse such a key first (`unnamed`).
let fieldName (key: string) : string =
  if isIdent key then key
  else if nameable key then "``" + key + "``"
  else
    let out = Buffer.empty
    for i in 0 .. String.length key - 1 do
      let b = String.byte key i
      Buffer.push (if b < u8 32 || b = u8 127 || b = u8 96 then u8 95 else b) out
    "``_" + String.ofBytes (Buffer.toArray out) + "``"

/// The first of the keys that can't be a field's name, as the error that says so; None when
/// every one can.
let unnamed (keys: list<string>) : option<string> =
  match List.tryFind (fun (k: string) -> not (nameable k)) keys with
  | Some k -> Some(literal k + " can't be a field's name: in double backticks a name is not empty, and holds no control character (a line break), no two backticks running and none at its end")
  | None -> None

/// A key as a type name: its words (split at anything that isn't a letter or a digit) capitalized
/// and joined, `Item` when nothing is left or it would start with a digit, and a suffix when it
/// would be a library name.
let typeName (key: string) : string =
  let n = String.length key
  // the pieces, joined once (a long key is no quadratic copy)
  let pieces = Buffer.empty
  let mutable i = 0
  let mutable newWord = true
  while i < n do
    let b = String.byte key i
    if b >= u8 128 then
      // a byte of a character beyond ASCII, copied as it is
      Buffer.push (String.sub key i 1) pieces
      newWord <- false
    else if isLetter b || isDigit b then
      let c = String.sub key i 1
      Buffer.push (if newWord then String.toUpper c else c) pieces
      newWord <- false
    else
      newWord <- true
    i <- i + 1
  let out = String.concat (Array.toList (Buffer.toArray pieces))
  let named = if out = "" || isDigit (String.byte out 0) then "Item" + out else out
  if Set.contains named reserved then named + "Record" else named

/// A key naming a list's elements, singular: readings → reading, entries → entry, boxes → box.
let singular (key: string) : string =
  let n = String.length key
  let ends (suffix: string) = String.endsWith suffix key
  if n > 3 && ends "ies" then String.sub key 0 (n - 3) + "y"
  else if n > 3 && (ends "ses" || ends "xes" || ends "zes" || ends "ches" || ends "shes") then String.sub key 0 (n - 2)
  else if n > 1 && ends "s" && not (ends "ss") then String.sub key 0 (n - 1)
  else key

/// The first `limit` bytes of `s` on one line (`oneLine`), cut at a character's end with an
/// ellipsis after.
let clip (limit: int) (s0: string) : string =
  let s = oneLine s0
  let n = String.length s
  if n <= limit then s
  else
    let mutable cut = limit
    // not inside a character: a continuation byte is 10xxxxxx
    while cut > 0 && String.byte s cut >= u8 128 && String.byte s cut < u8 192 do
      cut <- cut - 1
    String.sub s 0 cut + "…"
