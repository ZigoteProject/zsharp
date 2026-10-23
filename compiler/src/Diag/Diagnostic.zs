/// What the compiler tells the programmer (0021): an error or a warning, its name, where it is,
/// the message and notes at other places. A span is a file's index, an offset and a length; the
/// line and column come from the file's line index when it's shown.

/// An error stops a build; a warning doesn't, unless the build is `--strict`. (The cases aren't
/// `Error` and `Warning`, which would hide `result`'s `Error` where this module is open.)
type Severity =
  | Err
  | Warn

/// A place in a file of the build: the file's index, a byte offset and a length.
type Span = { file: int; offset: int; length: int }

/// Something said about another place: "the other definition is here".
type Note = { at: Span; text: string }

/// A diagnostic: its severity, its name (`unused-value`, "" for an error), where, what, and notes.
type Diagnostic =
  { severity: Severity
    name: string
    at: Span
    message: string
    notes: list<Note> }

/// An error at a span.
let error (at: Span) (message: string) : Diagnostic =
  { severity = Err; name = ""; at = at; message = message; notes = [] }

/// A warning of a kind at a span.
let warning (name: string) (at: Span) (message: string) : Diagnostic =
  { severity = Warn; name = name; at = at; message = message; notes = [] }
