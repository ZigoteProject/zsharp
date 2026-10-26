// Rust from Z# through the C ABI (README.md): textkit/ is a Rust crate wrapping two crates.io
// packages, regex and sha2, built as a static library; Textkit.zs is its Z# side
open Textkit

let log =
  """2026-10-26 08:12 ERROR disk full
2026-10-26 08:15 INFO backup done
2026-10-27 09:01 ERROR fan stopped"""

let main () =
  match Regex.compile """(\d{4}-\d\d-\d\d) (\d\d:\d\d) ERROR (.*)""" with
  | Ok pattern ->
    use errors = pattern
    for (start, stop) in Regex.matches errors log do
      println $"error at bytes {start}..{stop}: {String.sub log start (stop - start)}"
    println (Regex.replace errors log "$3 (on $1 at $2)")
  | Error why -> println why
  // an invalid pattern: the regex crate says why
  match Regex.compile "(unclosed" with
  | Ok _ -> println "accepted?"
  | Error why ->
    // the crate's message ends with the reason
    println $"rejected: {String.trim (List.last (String.split "\n" why))}"
  println $"sha256 of \"abc\": {sha256 "abc"}"
  0
