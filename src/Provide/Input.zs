/// What a provider reads (proposal 0001): a file whole, when it's a regular file or a link to
/// one. A pipe or a device read whole blocks or never ends (an import of /dev/stdin would read
/// the language server's own requests, /dev/zero would fill its memory), so it isn't read.

/// Whether something is at the path that's neither a regular file nor a directory (a pipe, a
/// device, a socket), or a link to one.
let special (path: string) : bool =
  not (File.exists path) && not (Directory.exists path) && Result.isOk (File.size path)

/// The file's text; Error "not found" when there's none (or it can't be read), else what it is
/// instead of a file, as words to follow its name.
let read (path: string) : result<string, string> =
  if special path then Error "isn't a regular file: a provider reads a file, not a pipe or a device"
  else if Directory.exists path then Error "is a directory, not a file"
  else
    match File.readAllText path with
    | Ok text -> Ok text
    | Error _ -> Error "not found"
