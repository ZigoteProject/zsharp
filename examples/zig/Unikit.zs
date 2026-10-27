/// zg, a Zig package for Unicode text (the unikit/ package, a static library), in Z#'s terms:
/// strings in, Zig's copied into Z# strings and given back.
module Unikit

import c "unikit/unikit.h"

// a string Zig made: copied into a Z# string, and Zig's given back
let private taken (s: cstr) : string =
  let text = String.ofCStr s
  uk_free s
  text

/// How many grapheme clusters, the characters a reader sees, the text has.
let graphemes (text: string) : int = int (uk_graphemes text)

/// How many columns the text takes on a terminal (an emoji or a CJK character takes two).
let width (text: string) : int = int (uk_width text)

/// The text in upper case, by Unicode's full mapping (ß is SS).
let upper (text: string) : string = taken (uk_upper text)

/// The text in lower case, by Unicode's full mapping (a final Σ is ς).
let lower (text: string) : string = taken (uk_lower text)

/// The text in Normalization Form C: é as one code point, not e and a combining accent.
let nfc (text: string) : string = taken (uk_nfc text)

/// Whether two texts are the same ignoring case, after canonical normalization.
let sameCaseless (a: string) (b: string) : bool = uk_same_caseless a b
