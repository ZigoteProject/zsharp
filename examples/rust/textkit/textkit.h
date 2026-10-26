// textkit: Rust's regex and sha2 crates behind a C ABI (src/lib.rs, the same declarations), read
// by Z#'s import c. Strings are NUL-terminated UTF-8; a char * this library returns is given back
// with tk_string_free.
#pragma once
#include <stdbool.h>
#include <stddef.h>

// a compiled regular expression (opaque)
typedef struct TkRegex TkRegex;

// a pattern compiled: the handle, or NULL with why in error (always a string, empty when valid)
typedef struct {
    TkRegex *regex;
    char *error;
} TkCompiled;

// where a match is: byte offsets into the text, when one was found
typedef struct {
    bool found;
    size_t start;
    size_t stop;
} TkMatch;

// the pattern compiled (the regex crate's syntax), or why it isn't valid
TkCompiled tk_regex_compile(const char *pattern);

// gives back a compiled pattern
void tk_regex_free(TkRegex *re);

// the first match in the text at or after byte `from`
TkMatch tk_regex_find(const TkRegex *re, const char *text, size_t from);

// the text with every match replaced by `by`, where $1 names a group
char *tk_regex_replace(const TkRegex *re, const char *text, const char *by);

// SHA-256 of the text's bytes, in lower-case hex
char *tk_sha256_hex(const char *text);

// gives back a string this library made
void tk_string_free(char *s);
