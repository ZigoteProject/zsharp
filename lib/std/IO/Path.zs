/// File paths as text, with `/` between the parts (on Windows `\`, and `/` is one too):
/// joining them and taking them apart. Nothing here touches the file system (`getFullPath`
/// reads the working directory). Paths compare as strings, case and all.
module IO.Path

let private windows = Native.isWindows ()

/// The character between a path's parts: `\` on Windows, else `/`.
let separator = if Native.isWindows () then '\\' else '/'

let private sep = if windows then "\\" else "/"

// whether the path starts with a separator
let private rooted (path: string) =
  String.startsWith "/" path || (windows && String.startsWith "\\" path)

// a drive and a colon (`C:`) at the start, on Windows
let private drive (path: string) =
  windows && String.length path >= 2 && String.sub path 1 1 = ":"

/// Whether the path starts at a root: `/`; on Windows also `\`, a drive's (`C:\`) or a share
/// (`\\server\share`).
let isAbsolute (path: string) =
  rooted path || (drive path && String.length path >= 3 && rooted (String.sub path 2 (String.length path - 2)))

// where the last separator is
let private lastSep (path: string) =
  match (String.lastIndexOf "/" path, (if windows then String.lastIndexOf "\\" path else None)) with
  | (Some i, Some j) -> Some (max i j)
  | (Some i, None) | (None, Some i) -> Some i
  | (None, None) -> None

/// `a` and `b` joined with a separator; `b` itself when it is absolute. A bare drive joins
/// without one (`C:x`, relative to that drive), as .NET's `Path.Combine`.
let combine (a: string) (b: string) =
  if isAbsolute b || String.isEmpty a then b
  else if String.endsWith "/" a || (windows && String.endsWith "\\" a) || (drive a && String.length a = 2) then
    a + b
  else a + sep + b

/// The part after the last separator: `"main.zs"` for `src/main.zs`.
let getFileName (path: string) =
  match lastSep path with
  | Some i -> String.sub path (i + 1) (String.length path - i - 1)
  | None -> path

/// The part before the last separator: `"src"` for `src/main.zs`, `"/"` for `/etc` (`C:\` for
/// `C:\a`), and `""` when there is none.
let getDirectoryName (path: string) =
  match lastSep path with
  | Some 0 -> String.sub path 0 1
  | Some 2 when drive path -> String.sub path 0 3
  | Some i -> String.sub path 0 i
  | None -> ""

/// The file name's extension with its dot (`".zs"`), or `""` when it has none. A name that
/// only starts with a dot, like `.gitignore`, has none.
let getExtension (path: string) =
  let name = getFileName path
  match String.lastIndexOf "." name with
  | Some i when i > 0 -> String.sub name i (String.length name - i)
  | _ -> ""

/// The file name without its extension: `"main"` for `src/main.zs`.
let getFileNameWithoutExtension (path: string) =
  let name = getFileName path
  String.sub name 0 (String.length name - String.length (getExtension name))

/// The path with its extension replaced by `ext` (`".md"` or `"md"`); `""` removes it.
let changeExtension (path: string) (ext: string) =
  let stem = String.sub path 0 (String.length path - String.length (getExtension path))
  if String.isEmpty ext then stem
  else if String.startsWith "." ext then stem + ext
  else stem + "." + ext

// the parts of a path without `.`, empty parts and the `..` that cancel a part before them
let private normalParts (path: string) =
  let step acc part =
    match part with
    | ""
    | "." -> acc
    | ".." ->
      match acc with
      | p :: rest when p <> ".." -> rest
      | _ -> if isAbsolute path then acc else ".." :: acc
    | _ -> part :: acc
  let parts = String.split "/" (if windows then String.replace path "\\" "/" else path)
  List.rev (List.fold step [] (if drive path then List.tail parts else parts))

/// The path made absolute against the working directory, with `.`, `..` and repeated
/// separators worked out on the text (symbolic links aren't followed), as .NET's
/// `Path.GetFullPath`.
let getFullPath (path: string) =
  let full = if isAbsolute path then path else combine (Environment.currentDirectory ()) path
  let root = if drive full then String.sub full 0 2 + sep else sep
  root + String.join sep (normalParts full)

/// The path of `path` from the directory `from`: `getRelativePath "/a/b" "/a/c/d"` is
/// `"../c/d"`, and `"."` for the same place.
let getRelativePath (from: string) (path: string) =
  let rec drop (xs: list<string>) (ys: list<string>) =
    match (xs, ys) with
    | (x :: xrest, y :: yrest) when x = y -> drop xrest yrest
    | _ -> (xs, ys)
  let fullFrom = getFullPath from
  let fullPath = getFullPath path
  // on Windows, paths on two drives have no relative path between them: the path itself, whole
  if drive fullFrom && String.sub fullFrom 0 2 <> String.sub fullPath 0 2 then
    fullPath
  else
    let (up, down) = drop (normalParts fullFrom) (normalParts fullPath)
    match List.map (fun _ -> "..") up @ down with
    | [] -> "."
    | parts -> String.join sep parts
