// char: a Unicode scalar value. Literals, comparison, conversion, patterns, iteration over a
// string's UTF-8, and the Char/String functions.
let kind c =
  match c with
  | ' ' | '\t' -> "space"
  | '\n' -> "newline"
  | 'é' -> "e-acute"
  | c when Char.isDigit c -> "digit"
  | c when Char.isLetter c -> "letter"
  | _ -> "other"

let main () =
  let a = 'a'
  println $"{a} {int a} {char 66} {a < 'b'} {'z' = 'z'} {Char.toUpper a} {Char.toLower 'Q'}"
  println $"{'\u{e9}' = 'é'} {int '\u{1F600}'} {'\''} {'\\'} {kind '7'} {kind 'x'} {kind 'é'} {kind '!'}"
  let s = "naïve 🙂!"
  let mutable n = 0
  for c in s do
    n <- n + 1
  println $"bytes {String.length s} chars {String.charCount s} counted {n}"
  println $"{String.chars "héllo"} {String.ofChars [ 'o'; 'k' ]} {String.ofChar 'é'}"
  let digits = String.chars "a1b22c" |> List.choose Char.digitValue
  println $"{digits} {List.sum digits}"
  let shout = String.chars "Hi there" |> List.map Char.toUpper |> String.ofChars
  println $"{shout} {hash 'a' = hash 'a'} {compare 'a' 'b'} {List.sort [ 'c'; 'a'; 'b' ]}"
  println $"escapes: [\r] {String.length "\r"} {String.length "\u{e9}"} {String.length "\u{1F600}"}"
  0
