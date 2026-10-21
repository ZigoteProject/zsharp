/// The console: standard input, output and error.
module Console

/// Writes the string to standard output, without a newline.
let write (s: string) = print s

/// Writes the string and a newline to standard output.
let writeLine (s: string) = println s

/// The next line of standard input without its newline, or `None` at the end.
let readLine () =
  let line = Native.readLine ()
  if Native.eof () then None else Some line

/// All of standard input, line by line (without the newlines).
let readLines () =
  let rec go acc =
    match readLine () with
    | Some l -> go (l :: acc)
    | None -> List.rev acc
  go []

/// Standard error.
module Error =
  /// Writes the string and a newline to standard error.
  let writeLine (s: string) = eprintln s
