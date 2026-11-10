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

/// The directory for temporary files: `$TMPDIR`, else `/tmp` (on Windows `%TMP%`, else
/// `%TEMP%`).
let temp () =
  let set (name: string) =
    match Environment.getVariable name with
    | Some d when not (String.isEmpty d) -> Some d
    | _ -> None
  match set "TMPDIR" with
  | Some d -> d
  | None ->
    if not (Native.isWindows ()) then "/tmp"
    else Option.defaultValue "." (Option.orElse (set "TEMP") (set "TMP"))

/// A new empty directory in the temporary directory, named `prefix` and six characters: its path.
let createTemp (prefix: string) : result<string, string> =
  let path = Native.tempDirectory prefix
  ioResult path

/// Deletes the directory, which must be empty.
let delete (path: string) =
  Native.deleteDirectory path
  ioResult ()

/// The paths of every file and directory under `path`, relative to it, sorted; a symbolic link
/// is listed and not followed.
let listRecursive (path: string) : result<list<string>, string> =
  // directories still to read (relative to path), and what's found so far
  let rec walk (pending: list<string>) (found: list<string>) =
    match pending with
    | [] -> Ok (List.sort found)
    | dir :: rest ->
      let full = if String.isEmpty dir then path else path + "/" + dir
      match list full with
      | Error e -> Error e
      | Ok names ->
        let rels = names |> List.map (fun n -> if String.isEmpty dir then n else dir + "/" + n)
        let dirs =
          rels
          |> List.filter (fun r ->
            Directory.exists (path + "/" + r) && not (Native.isSymlink (path + "/" + r)))
        walk (dirs @ rest) (rels @ found)
  walk [ "" ] []

/// Deletes the directory and everything under it. A symbolic link (or a Windows junction) is
/// deleted as itself, never what it points to: `path` itself, or one in the tree.
let deleteRecursive (path: string) =
  // the runtime's walk, each directory opened from its parent without following a link, so one
  // swapped in meanwhile doesn't lead it out of the tree
  Native.deleteTree path
  ioResult ()
