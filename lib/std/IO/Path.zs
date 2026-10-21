/// File paths as text, with `/` between the parts: joining them and taking them apart. Nothing
/// here touches the file system.
module IO.Path

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
