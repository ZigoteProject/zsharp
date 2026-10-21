/// Directories: creating and listing them. `Directory.exists path` tests for one.
module IO.Directory

let private ioResult (value: 'a) : result<'a, string> =
  if Native.ioOk () then Ok value else Error (Native.ioError ())

/// Creates the directory; an existing one is fine.
let create (path: string) =
  Native.createDirectory path
  ioResult ()

/// The names in the directory (not `.` or `..`), sorted.
let list (path: string) =
  let raw = Native.listDirectory path // the names, separated by NUL bytes
  let names = if String.isEmpty raw then [] else String.split (String.ofByte (u8 0)) raw
  ioResult (List.sort names)
