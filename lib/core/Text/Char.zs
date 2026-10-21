/// Functions on characters: `char`, a Unicode scalar value such as `'a'` or `'é'`. The tests
/// know ASCII; other letters aren't classified.
module Text.Char

/// Whether `c` is an ASCII digit, '0' to '9'.
let isDigit (c: char) = c >= '0' && c <= '9'

/// Whether `c` is an ASCII lower-case letter.
let isLower (c: char) = c >= 'a' && c <= 'z'

/// Whether `c` is an ASCII upper-case letter.
let isUpper (c: char) = c >= 'A' && c <= 'Z'

/// Whether `c` is an ASCII letter.
let isLetter (c: char) = Char.isLower c || Char.isUpper c

/// Whether `c` is an ASCII letter or digit.
let isLetterOrDigit (c: char) = Char.isLetter c || Char.isDigit c

/// Whether `c` is a space, tab, line feed or carriage return.
let isWhitespace (c: char) = c = ' ' || c = '\t' || c = '\n' || c = '\r'

/// `c` in upper case (ASCII letters; others unchanged).
let toUpper (c: char) = if Char.isLower c then char (int c - 32) else c

/// `c` in lower case (ASCII letters; others unchanged).
let toLower (c: char) = if Char.isUpper c then char (int c + 32) else c

/// The value of an ASCII digit: `Some 7` for '7', `None` for anything else.
let digitValue (c: char) = if Char.isDigit c then Some (int c - int '0') else None
