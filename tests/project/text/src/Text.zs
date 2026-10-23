// A library used as a path dependency: word splitting and counting.

/// Whether the byte is a space, tab, newline or carriage return.
let isSpace (b: u8) = b = u8 32 || b = u8 9 || b = u8 10 || b = u8 13

/// The number of whitespace-separated words.
let wordCount (s: string) =
  let mutable words = 0
  let mutable inWord = false
  for i in 0 .. String.length s - 1 do
    if isSpace (String.byte s i) then inWord <- false
    else
      if not inWord then words <- words + 1
      inWord <- true
  words

/// The number of newline bytes, as `wc -l` counts.
let lineCount (s: string) =
  let mutable n = 0
  for i in 0 .. String.length s - 1 do
    if String.byte s i = u8 10 then n <- n + 1
  n

[<Tests>]
let tests =
  Testing.testList "text" [
    Testing.test "counts words" (fun () ->
      assert (wordCount "  two words\n" = 2)
      assert (wordCount "" = 0))
    Testing.test "counts lines" (fun () ->
      assert (lineCount "a\nb\n" = 2)
      assert (lineCount "no newline" = 0))
  ]
