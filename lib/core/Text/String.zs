/// Functions on strings: immutable UTF-8 text. Lengths and indexes count bytes; `for c in s`
/// and `String.chars` give the characters.
module Text.String

/// Whether the string has no bytes.
let isEmpty (s: string) = String.length s = 0

/// Whether `sub` occurs in `s`.
let contains (sub: string) (s: string) = String.indexOfFrom s sub 0 >= 0

/// The byte index of the first `sub` in `s`, or `None`.
let indexOf (sub: string) (s: string) =
  let i = String.indexOfFrom s sub 0
  if i < 0 then None else Some i

/// The byte index of the last `sub` in `s`, or `None`.
let lastIndexOf (sub: string) (s: string) =
  let rec go found from =
    let i = String.indexOfFrom s sub from
    if i < 0 then found else go (Some i) (i + 1)
  go None 0

/// Whether `s` begins with `p`.
let startsWith (p: string) (s: string) =
  String.length p <= String.length s && String.sub s 0 (String.length p) = p

/// Whether `s` ends with `p`.
let endsWith (p: string) (s: string) =
  String.length p <= String.length s && String.sub s (String.length s - String.length p) (String.length p) = p

/// The pieces of `s` between occurrences of `sep`: `String.split ", " "a, b" = ["a"; "b"]`.
let split (sep: string) (s: string) =
  let rec go acc start =
    let i = String.indexOfFrom s sep start
    if i < 0 then List.rev (String.sub s start (String.length s - start) :: acc)
    else go (String.sub s start (i - start) :: acc) (i + String.length sep)
  if String.length sep = 0 then [ s ] else go [] 0

/// The strings with `sep` between them.
let join (sep: string) (xs: list<string>) =
  match xs with
  | [] -> ""
  | x :: rest -> List.fold (fun acc s -> acc + sep + s) x rest

/// The strings joined with nothing between them.
let concat (xs: list<string>) = String.join "" xs

/// `s` repeated `n` times.
let repeat n (s: string) =
  let mutable r = ""
  for _ in 1 .. n do
    r <- r + s
  r

/// The integer written in `s` (optional sign, decimal digits), or `None`.
let parseInt (s: string) : option<int> =
  let n = String.length s
  if n = 0 then None
  else
    let first = String.byte s 0
    let neg = first = u8 45
    let start = if neg || first = u8 43 then 1 else 0
    if start = n then None
    else
      let mutable acc = 0
      let mutable ok = true
      for i in start .. n - 1 do
        let b = int (String.byte s i)
        if b < 48 || b > 57 then ok <- false else acc <- acc * 10 + (b - 48)
      if ok then Some (if neg then -acc else acc) else None

/// The floating-point number written in `s`, or `None`.
let parseFloat (s: string) : option<f64> = if String.isFloat s then Some (String.toFloat s) else None

/// The character that starts at byte `i` of `s`, and the byte index after it (UTF-8 decoding;
/// a malformed sequence gives U+FFFD and moves one byte). `for c in s` uses it.
let decodeAt (s: string) (i: int) : char * int =
  let b0 = int (String.byte s i)
  if b0 < 0x80 then (char b0, i + 1)
  else
    let n = String.length s
    let cont k = if i + k < n then int (String.byte s (i + k)) else 0
    let ok k = cont k &&& 0xC0 = 0x80
    if b0 &&& 0xE0 = 0xC0 && ok 1 then
      (char (((b0 &&& 0x1F) <<< 6) ||| (cont 1 &&& 0x3F)), i + 2)
    else if b0 &&& 0xF0 = 0xE0 && ok 1 && ok 2 then
      (char (((b0 &&& 0x0F) <<< 12) ||| ((cont 1 &&& 0x3F) <<< 6) ||| (cont 2 &&& 0x3F)), i + 3)
    else if b0 &&& 0xF8 = 0xF0 && ok 1 && ok 2 && ok 3 then
      (char (((b0 &&& 0x07) <<< 18) ||| ((cont 1 &&& 0x3F) <<< 12) ||| ((cont 2 &&& 0x3F) <<< 6) ||| (cont 3 &&& 0x3F)), i + 4)
    else (char 0xFFFD, i + 1)

/// The characters of `s`, in order (decoded from UTF-8).
let chars (s: string) =
  let mutable acc = []
  let mutable i = 0
  while i < String.length s do
    let (c, next) = String.decodeAt s i
    acc <- c :: acc
    i <- next
  List.rev acc

/// The number of characters in `s`. `String.length` counts bytes.
let charCount (s: string) =
  let mutable count = 0
  let mutable i = 0
  while i < String.length s do
    let (_, next) = String.decodeAt s i
    count <- count + 1
    i <- next
  count

/// A string of one character (its UTF-8 encoding).
let ofChar (c: char) = string c

/// A string of the characters, in order.
let ofChars (cs: list<char>) = String.concat (List.map String.ofChar cs)

type string with
  /// The length in bytes (UTF-8).
  member s.Length = String.length s
  /// Whether `sub` occurs in the string.
  member s.Contains(sub: string) = String.contains sub s
  /// Whether the string begins with `p`.
  member s.StartsWith(p: string) = String.startsWith p s
  /// Whether the string ends with `p`.
  member s.EndsWith(p: string) = String.endsWith p s
  /// The byte index of the first `sub`, or `None`.
  member s.IndexOf(sub: string) = String.indexOf sub s
  /// The pieces between occurrences of `sep`.
  member s.Split(sep: string) = String.split sep s
  /// The `len` bytes starting at byte `start`. Panics if out of range.
  member s.Substring(start: int, len: int) = String.sub s start len
  /// The string without leading and trailing spaces, tabs and line breaks.
  member s.Trim() = String.trim s
  /// The string with ASCII letters in upper case.
  member s.ToUpper() = String.toUpper s
  /// The string with ASCII letters in lower case.
  member s.ToLower() = String.toLower s
  /// The string with every `old` replaced by `by`.
  member s.Replace(old: string, by: string) = String.replace s old by
