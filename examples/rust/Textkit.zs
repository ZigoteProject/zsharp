/// Rust's regex and sha2 crates (the textkit/ crate, a static library) in Z#'s terms: a Regex
/// that `use` gives back, matches as offsets, and strings copied in, Rust's given back.
module Textkit

import c "textkit/textkit.h"

/// A compiled pattern: Rust's `Regex` behind its pointer, given back to Rust by `use`.
type Regex = { raw: cptr }

impl Dispose<Regex> =
  let dispose (r: Regex) = tk_regex_free r.raw

// a string Rust made: copied into a Z# string, and Rust's given back
let private taken (s: cstr) : string =
  let text = String.ofCStr s
  tk_string_free s
  text

module Regex =
  /// The pattern compiled (the regex crate's syntax: `\d`, `(?i)`, groups), or why it isn't valid.
  let compile (pattern: string) : result<Regex, string> =
    let c = tk_regex_compile pattern
    let error = taken c.error
    if error = "" then Ok { raw = c.regex } else Error error

  /// Where each match is in the text, as byte offsets (start, stop).
  let matches (r: Regex) (text: string) : list<int * int> =
    let rec go (from: int) (found: list<int * int>) =
      let m = tk_regex_find r.raw text (usize from)
      if not m.found then
        List.rev found
      else
        let start = int m.start
        let stop = int m.stop
        // an empty match moves on a byte, so the search ends
        go (if stop = start then stop + 1 else stop) ((start, stop) :: found)
    go 0 []

  /// The text with every match replaced by `by`, where `$1` names a group.
  let replace (r: Regex) (text: string) (by: string) : string =
    taken (tk_regex_replace r.raw text by)

/// SHA-256 of a string's bytes, in lower-case hex.
let sha256 (text: string) : string = taken (tk_sha256_hex text)
