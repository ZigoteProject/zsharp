/// The names a provider writes (proposal 0001): a key or a column as a field, in double backticks
/// when it isn't a plain name, so the derives read the key as the field's name; a key as a
/// record's name, in PascalCase and singular for a list's elements.

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

/// A key as a field name: itself when it's a plain name, else in double backticks.
let fieldName (key: string) : string = if isIdent key then key else "``" + key + "``"

/// A key as a type name: its words (split at anything that isn't a letter or a digit) capitalized
/// and joined, `Item` when nothing is left or it would start with a digit, and a suffix when it
/// would be a library name.
let typeName (key: string) : string =
  let n = String.length key
  let mutable out = ""
  let mutable i = 0
  let mutable newWord = true
  while i < n do
    let b = String.byte key i
    if b >= u8 128 then
      // a byte of a character beyond ASCII, copied as it is
      out <- out + String.sub key i 1
      newWord <- false
    else if isLetter b || isDigit b then
      let c = String.sub key i 1
      out <- out + (if newWord then String.toUpper c else c)
      newWord <- false
    else
      newWord <- true
    i <- i + 1
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

/// The first `limit` bytes of `s` on one line, cut at a character's end with an ellipsis after.
let clip (limit: int) (s: string) : string =
  let n = String.length s
  if n <= limit then s
  else
    let mutable cut = limit
    // not inside a character: a continuation byte is 10xxxxxx
    while cut > 0 && String.byte s cut >= u8 128 && String.byte s cut < u8 192 do
      cut <- cut - 1
    String.sub s 0 cut + "…"
