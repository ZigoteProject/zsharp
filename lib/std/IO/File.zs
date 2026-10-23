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

/// The whole file as a string, read on `Task.blocking`'s helper thread so tasks go on meanwhile.
let readAllTextAsync (path: string) : Task<result<string, string>> =
  Task.blocking (fun () -> readAllText path)

/// Replaces the file's contents with `text`, on `Task.blocking`'s helper thread.
let writeAllTextAsync (path: string) (text: string) : Task<result<unit, string>> =
  Task.blocking (fun () -> writeAllText path text)

/// Deletes the file.
let delete (path: string) =
  Native.deleteFile path
  ioResult ()

/// The file opened to read, through a buffer; `use` closes it.
let openRead (path: string) : result<Reader, string> =
  let fd = Native.fileOpen path 0
  ioResult (Reader.ofFd fd)

/// The file opened to write, emptied first (or created); `use` flushes and closes it.
let openWrite (path: string) : result<Writer, string> =
  let fd = Native.fileOpen path 1
  ioResult (Writer.ofFd fd)

/// The file opened to write at its end (or created); `use` flushes and closes it.
let openAppend (path: string) : result<Writer, string> =
  let fd = Native.fileOpen path 2
  ioResult (Writer.ofFd fd)

/// The whole file's bytes, as they are (not read as text).
let readAllBytes (path: string) : result<array<u8>, string> =
  match openRead path with
  | Error e -> Error e
  | Ok r ->
    use reader = r
    let all = Buffer.empty
    let chunk = Buffer.create 65536 (u8 0)
    let rec go () =
      match Reader.readBytes reader chunk with
      | Ok 0 -> Ok(Buffer.toArray all)
      | Ok n ->
        for i in 0 .. n - 1 do
          Buffer.push chunk.[i] all
        go ()
      | Error e -> Error e
    go ()

/// Replaces the file's contents with the bytes, as they are (creating it if needed).
let writeAllBytes (path: string) (bytes: span<u8>) : result<unit, string> =
  match openWrite path with
  | Error e -> Error e
  | Ok w ->
    use writer = w
    match Writer.write writer bytes with
    | Ok () -> Writer.flush writer
    | Error e -> Error e

/// The whole file's bytes.

/// Copies the file to `target`, replacing what's there.
let copy (path: string) (target: string) =
  Native.fileCopy path target
  ioResult ()

/// Moves the file to `target`, replacing what's there: a rename, or a copy and a delete from
/// another file system.
let move (path: string) (target: string) =
  Native.fileMove path target
  ioResult ()

/// When the file was last changed.
let modifiedAt (path: string) : result<DateTime, string> =
  let nanos = Native.fileModified path
  ioResult ({ sinceEpoch = nanos * 1<ns> }: DateTime)

/// The file's size in bytes.
let size (path: string) : result<i64, string> =
  let n = Native.fileSize path
  ioResult n

/// Marks the file changed now (its modification time), as `touch` does.
let touch (path: string) =
  Native.fileTouch path
  ioResult ()

/// A new empty file in the temporary directory (`$TMPDIR`, else `/tmp`), named `prefix` and six
/// characters, readable by its owner only: its path.
let createTemp (prefix: string) : result<string, string> =
  let path = Native.tempFile prefix
  ioResult path
