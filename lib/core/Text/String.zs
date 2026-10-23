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

/// The integer written in `s` (optional sign, decimal digits), or `None`: `Int.parse` at `int`.
let parseInt (s: string) : option<int> = Int.parse s

/// The floating-point number written in `s`, or `None`: `Float.parse` at `f64`.
let parseFloat (s: string) : option<f64> = Float.parse s

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

/// `s` with `c` before it, to `width` characters (`String.charCount`); never cut.
let padLeftWith (width: int) (c: char) (s: string) =
  let n = String.charCount s
  if n >= width then s else String.repeat (width - n) (string c) + s

/// `s` with `c` after it, to `width` characters; never cut.
let padRightWith (width: int) (c: char) (s: string) =
  let n = String.charCount s
  if n >= width then s else s + String.repeat (width - n) (string c)

/// `s` with spaces before it, to `width` characters: `String.padLeft 5 "ab"` is `"   ab"`.
let padLeft (width: int) (s: string) = String.padLeftWith width ' ' s

/// `s` with spaces after it, to `width` characters.
let padRight (width: int) (s: string) = String.padRightWith width ' ' s

// a space, tab or line break
let private isSpace (b: u8) = b = u8 32 || b = u8 9 || b = u8 10 || b = u8 13

/// `s` without its leading spaces, tabs and line breaks.
let trimStart (s: string) =
  let n = String.length s
  let mutable i = 0
  while i < n && isSpace (String.byte s i) do
    i <- i + 1
  String.sub s i (n - i)

/// `s` without its trailing spaces, tabs and line breaks.
let trimEnd (s: string) =
  let mutable n = String.length s
  while n > 0 && isSpace (String.byte s (n - 1)) do
    n <- n - 1
  String.sub s 0 n

/// The lines of `s`, split at `\n` and `\r\n`, with no empty last line: as `File.readAllLines`
/// splits a file.
let splitLines (s: string) =
  let lines =
    String.split "\n" s
    |> List.map (fun l -> if String.endsWith "\r" l then String.sub l 0 (String.length l - 1) else l)
  match List.rev lines with
  | "" :: rest -> List.rev rest
  | _ -> lines

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

/// A string's characters (code points), decoding its UTF-8; its bytes are `String.bytes s`.
impl Iter<string, char> =
  let forEach (s: string) f =
    let mutable pos = 0
    let mutable ok = true
    while ok && pos < String.length s do
      let (c, next) = decodeAt s pos
      pos <- next
      ok <- f c
    ok
