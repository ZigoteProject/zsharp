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

// a path's root and what follows it, separators as `sep`: `/` (on Windows `\`), a drive's `C:\`,
// a share's `\\server\share` (a device's `\\.\name` too), or "" when it has none
let private rootOf (path: string) : string * string =
  let p = if windows then String.replace path "/" "\\" else path
  let after (n: int) = String.sub p n (String.length p - n)
  if windows && String.startsWith "\\\\" p then
    match String.split "\\" (after 2) with
    | server :: share :: rest when not (String.isEmpty share) ->
      ("\\\\" + server + "\\" + share, String.join "\\" rest)
    | server :: rest -> ("\\\\" + server, String.join "\\" rest)
    | [] -> ("\\\\", "")
  else if drive p && String.length p >= 3 && rooted (after 2) then
    (String.sub p 0 3, after 3)
  else if rooted p then
    (sep, after 1)
  else
    ("", p)

// the parts of what follows a root, without `.`, empty parts and the `..` that cancel a part
// before them (a `..` at the root goes: it doesn't climb above it)
let private normalParts (path: string) =
  let step acc part =
    match part with
    | ""
    | "." -> acc
    | ".." ->
      match acc with
      | _ :: rest -> rest
      | [] -> acc
    | _ -> part :: acc
  let parts = String.split "/" (if windows then String.replace path "\\" "/" else path)
  List.rev (List.fold step [] parts)

/// The path made absolute against the working directory, with `.`, `..` and repeated
/// separators worked out on the text (symbolic links aren't followed), as .NET's
/// `Path.GetFullPath`. On Windows a share (`\\server\share`) is a root, which `..` doesn't
/// climb above; `D:x` is from the working directory when that's on drive D, else from `D:\`;
/// and a `\\?\` path is left as it is.
let getFullPath (path: string) =
  if windows && String.startsWith "\\\\?\\" path then
    path
  else
    let full =
      if isAbsolute path then
        path
      else if drive path then
        let cwd = Environment.currentDirectory ()
        let letter (p: string) = String.toUpper (String.sub p 0 1)
        let rest = String.sub path 2 (String.length path - 2)
        if drive cwd && letter cwd = letter path then combine cwd rest
        else String.sub path 0 2 + sep + rest
      else
        combine (Environment.currentDirectory ()) path
    let (root, rest) = rootOf full
    let parts = String.join sep (normalParts rest)
    if String.isEmpty parts then root
    else if String.endsWith sep root then root + parts
    else root + sep + parts

/// The path of `path` from the directory `from`: `getRelativePath "/a/b" "/a/c/d"` is
/// `"../c/d"`, and `"."` for the same place.
let getRelativePath (from: string) (path: string) =
  let rec drop (xs: list<string>) (ys: list<string>) =
    match (xs, ys) with
    | (x :: xrest, y :: yrest) when x = y -> drop xrest yrest
    | _ -> (xs, ys)
  let (fromRoot, fromRest) = rootOf (getFullPath from)
  let fullPath = getFullPath path
  let (pathRoot, pathRest) = rootOf fullPath
  // on Windows, paths under two roots (two drives, two shares) have no relative path between
  // them: the path itself, whole
  if fromRoot <> pathRoot then
    fullPath
  else
    let (up, down) = drop (normalParts fromRest) (normalParts pathRest)
    match List.map (fun _ -> "..") up @ down with
    | [] -> "."
    | parts -> String.join sep parts
