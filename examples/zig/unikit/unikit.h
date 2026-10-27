// unikit: zg's Unicode text processing behind a C ABI (src/unikit.zig, the same declarations),
// read by Z#'s import c. Strings are NUL-terminated UTF-8; a char * this library returns is given
// back with uk_free.
#pragma once
#include <stdbool.h>
#include <stddef.h>

// how many grapheme clusters, the characters a reader sees, the text has
size_t uk_graphemes(const char *text);

// how many columns the text takes on a terminal (an emoji or a CJK character takes two)
size_t uk_width(const char *text);

// the text in upper case, by Unicode's full mapping (ß is SS)
char *uk_upper(const char *text);

// the text in lower case, by Unicode's full mapping (a final Σ is ς)
char *uk_lower(const char *text);

// the text in Normalization Form C: é as one code point, not e and a combining accent
char *uk_nfc(const char *text);

// whether two texts are the same ignoring case, after canonical normalization (Straße is STRASSE)
bool uk_same_caseless(const char *a, const char *b);

// gives back a string this library made
void uk_free(char *s);
