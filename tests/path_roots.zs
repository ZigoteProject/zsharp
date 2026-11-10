// Path.getFullPath and getRelativePath on Windows's roots: a share's \\server\share is a root,
// which `..` doesn't climb above; `Q:x` is from Q:\ (the working directory is on another drive),
// and `D:x` from the working directory on D; a \\?\ path is as it is. Elsewhere these are POSIX's
// paths (path_roots.windows.out has Windows's)
let main () =
  let cwd = Environment.currentDirectory ()
  let rel (p: string) = Path.getRelativePath cwd p
  let share = Path.getFullPath "//server/share/a/../b"
  let above = Path.getFullPath "//server/share/../../x"
  println $"{share} {above} {Path.getFullPath "//server/share"}"
  println $"{rel (Path.getFullPath "Q:x")} {rel (Path.getFullPath "Q:")}"
  // the working directory's own drive, relative
  let here = if Path.separator = '\\' then String.sub cwd 0 2 + "x" else "x"
  println $"{rel (Path.getFullPath here)}"
  let verbatim = "\\\\?\\C:\\a\\..\\b"
  println $"{rel (Path.getFullPath verbatim)}"
  println $"{Path.getRelativePath "//a/b/c" "//a/d/e"} {Path.getRelativePath "//a/b/c" "//a/b/d"}"
  0
