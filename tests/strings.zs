// Text functions (0024): padding to a width in characters, trimming one side, lines; searching
// (an empty sub, from past the end, a match in the last bytes, a sub longer than the text, a
// first byte that's there without the rest) and integers' text at their ends
let main () =
  println $"[{String.padLeft 5 "ab"}] [{String.padRight 4 "é"}] [{String.padLeftWith 6 '0' "42"}] [{String.padLeft 1 "long"}]"
  println $"[{String.trimStart "  x "}] [{String.trimEnd " x  "}] [{String.trimStart ""}]"
  println $"{String.splitLines "a\r\nb\n\nc\n"} {String.splitLines ""} {String.splitLines "no newline"}"
  let s = "abcabd"
  let at (sub: string) (from: int) = String.indexOfFrom s sub from
  println $"{at "" 0} {at "" 6} {at "" 7} {at "abd" 0} {at "d" 5} {at "d" 6} {at "abdx" 0} {at "abx" 0} {at "a" -3} {at "c" 3}"
  println $"{String.split ", " "a, b,, c, "} {String.replace s "ab" "-"} {String.lastIndexOf "ab" s} {String.contains "ca" s}"
  println $"{Int.wrappingAdd 9223372036854775807 1} {9223372036854775807} {0} {-7} {Int.wrappingSub (u64 0) (u64 1)} {i32 -2147483648}"
  0
