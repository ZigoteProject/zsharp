// Text functions (0024): padding to a width in characters, trimming one side, lines
let main () =
  println $"[{String.padLeft 5 "ab"}] [{String.padRight 4 "é"}] [{String.padLeftWith 6 '0' "42"}] [{String.padLeft 1 "long"}]"
  println $"[{String.trimStart "  x "}] [{String.trimEnd " x  "}] [{String.trimStart ""}]"
  println $"{String.splitLines "a\r\nb\n\nc\n"} {String.splitLines ""} {String.splitLines "no newline"}"
  0
