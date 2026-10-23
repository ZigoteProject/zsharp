/// A file of the build: its text (with "\r\n" read as "\n"), its index among the build's files,
/// and where each of its lines starts, found once.

/// A source file.
type Source =
  { /// Its index in the build: a span's `file`.
    file: int
    /// Its path, as the programmer gave it.
    path: string
    /// Its text.
    text: string
    /// The offset each line starts at, in order; the first is 0.
    lines: array<int> }

/// A source of a file's text.
let make (file: int) (path: string) (text: string) : Source =
  let text = String.replace text "\r\n" "\n"
  let starts = Buffer.empty
  Buffer.push 0 starts
  for i in 0 .. String.length text - 1 do
    if String.byte text i = u8 10 then
      Buffer.push (i + 1) starts
  { file = file; path = path; text = text; lines = Buffer.toArray starts }

/// The index (0-based) of the line an offset is on.
let lineOf (s: Source) (offset: int) : int =
  let mutable lo = 0
  let mutable hi = Array.length s.lines - 1
  while lo < hi do
    let mid = (lo + hi + 1) / 2
    if s.lines.[mid] <= offset then lo <- mid else hi <- mid - 1
  lo

/// The line (from 1) and column (from 1, in characters) of an offset, as a message shows them.
let position (s: Source) (offset: int) : int * int =
  let li = lineOf s offset
  let mutable col = 1
  for i in s.lines.[li] .. offset - 1 do
    // a byte that starts a character (not a UTF-8 continuation byte)
    if (String.byte s.text i &&& u8 0xC0) <> u8 0x80 then
      col <- col + 1
  (li + 1, col)
