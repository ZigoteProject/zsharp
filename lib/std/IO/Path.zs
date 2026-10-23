/// File paths as text, with `/` between the parts: joining them and taking them apart. Nothing
/// here touches the file system (`getFullPath` reads the working directory).
module IO.Path

/// The character between a path's parts.
let separator = '/'

/// Whether the path starts at the root (`/`).
let isAbsolute (path: string) = String.startsWith "/" path

/// `a` and `b` joined with a `/`; `b` itself when it is absolute (starts with `/`).
let combine (a: string) (b: string) =
  if String.startsWith "/" b || String.isEmpty a then b
  else if String.endsWith "/" a then a + b
  else a + "/" + b

/// The part after the last `/`: `"main.zs"` for `src/main.zs`.
let getFileName (path: string) =
  match String.lastIndexOf "/" path with
  | Some i -> String.sub path (i + 1) (String.length path - i - 1)
  | None -> path

/// The part before the last `/`: `"src"` for `src/main.zs`, `"/"` for `/etc`, and `""` when
/// there is no `/`.
let getDirectoryName (path: string) =
  match String.lastIndexOf "/" path with
  | Some 0 -> "/"
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
  List.rev (List.fold step [] (String.split "/" path))

/// The path made absolute against the working directory, with `.`, `..` and repeated `/`
/// worked out on the text (symbolic links aren't followed), as .NET's `Path.GetFullPath`.
let getFullPath (path: string) =
  let full = if isAbsolute path then path else combine (Environment.currentDirectory ()) path
  "/" + String.join "/" (normalParts full)

/// The path of `path` from the directory `from`: `getRelativePath "/a/b" "/a/c/d"` is
/// `"../c/d"`, and `"."` for the same place.
let getRelativePath (from: string) (path: string) =
  let rec drop (xs: list<string>) (ys: list<string>) =
    match (xs, ys) with
    | (x :: xrest, y :: yrest) when x = y -> drop xrest yrest
    | _ -> (xs, ys)
  let (up, down) = drop (normalParts (getFullPath from)) (normalParts (getFullPath path))
  match List.map (fun _ -> "..") up @ down with
  | [] -> "."
  | parts -> String.join "/" parts
