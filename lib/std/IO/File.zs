/// Reading and writing whole files. A failure is an `Error` with a readable message, such as
/// `cannot open data.txt: No such file or directory`. `File.exists path` tests for one.
module IO.File

// the runtime reports how the last operation went; this turns it into a result
let private ioResult (value: 'a) : result<'a, string> =
  if Native.ioOk () then Ok value else Error (Native.ioError ())

let private toLines (text: string) =
  let text = String.replace text (String.ofByte (u8 13) + "\n") "\n"
  let text = if String.endsWith "\n" text then String.sub text 0 (String.length text - 1) else text
  if String.isEmpty text then [] else String.split "\n" text

/// The whole file as a string.
let readAllText (path: string) = ioResult (Native.readFile path)

/// The file's lines, without line endings; a final newline doesn't add an empty line.
let readAllLines (path: string) = readAllText path |> Result.map toLines

/// Replaces the file's contents with `text` (creating it if needed).
let writeAllText (path: string) (text: string) =
  Native.writeFile path text
  ioResult ()

/// Replaces the file's contents with the lines, each ending in a newline.
let writeAllLines (path: string) (lines: list<string>) =
  writeAllText path (String.concat (List.map (fun l -> l + "\n") lines))

/// Adds `text` to the end of the file (creating it if needed).
let appendAllText (path: string) (text: string) =
  Native.appendFile path text
  ioResult ()

/// Deletes the file.
let delete (path: string) =
  Native.deleteFile path
  ioResult ()
