/// Diagnostics as the terminal shows them: `file:line:col: error: message`, then the line with a
/// caret under the place; a warning's kind after its message; then its notes, each the same way.
open Diagnostic

// a message at a place: where and what, then the source line with a caret under the column (a
// span of length -1 is a line's, the F# compiler's errors with no column: the caret under its
// first character)
let private placed (src: Syntax.Source.Source) (word: string) (offset: int) (span: int) (message: string) : list<string> =
  let (line, col0) = Syntax.Source.position src offset
  let from = src.lines.[line - 1]
  let stop = if line < Array.length src.lines then src.lines.[line] - 1 else String.length src.text
  let gutter = $"{line}"
  let mutable first = from
  while first < stop && String.byte src.text first = u8 32 do
    first <- first + 1
  let col = if span < 0 then first - from + 1 else col0
  let head =
    if span < 0 then
      $"{src.path}:{line}: {word}: {message}"
    else
      $"{src.path}:{line}:{col}: {word}: {message}"
  [ head
    $" {gutter} | {String.sub src.text from (stop - from)}"
    $" {String.repeat (String.length gutter) " "} | {String.repeat (col - 1) " "}^" ]

// one message: where and what, then the source line with a caret under the column; with no place
// (offset -1), the file's
let private lines (src: Syntax.Source.Source) (word: string) (offset: int) (span: int) (message: string) : list<string> =
  if offset < 0 then [ $"{src.path}: {word}: {message}" ] else placed src word offset span message

/// A diagnostic's lines, its notes' after it; `sourceOf` gives a span's file.
let render (sourceOf: int -> Syntax.Source.Source) (d: Diagnostic) : list<string> =
  let first =
    match d.severity with
    | Err -> lines (sourceOf d.at.file) "error" d.at.offset d.at.length d.message
    | Warn -> lines (sourceOf d.at.file) "warning" d.at.offset d.at.length $"{d.message} [{d.name}]"
  List.concat (first :: List.map (fun (n: Note) ->
      lines (sourceOf n.at.file) "note" n.at.offset n.at.length n.text) d.notes)

/// Prints diagnostics on standard error, in order.
let print (sourceOf: int -> Syntax.Source.Source) (ds: array<Diagnostic>) : unit =
  for d in ds do
    for l in render sourceOf d do
      eprintln l
