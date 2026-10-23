// A package with C code (0018 item 4): vowels.h is in its [c] include directory, and vowels.c
// is compiled and linked with the program.
import c "vowels.h"

/// The number of vowels in s, counted in C.
let vowels (s: string) = int (count_vowels s)

/// The square root of x, times pkg-config's scale.
let scaledRoot (x: f64) = scaled_root x
