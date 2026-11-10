// Links and modes (ln -s, chmod, ls -l): Directory.deleteRecursive deletes a symbolic link, the
// path given or one in the tree (or the path with a trailing slash), as itself and never what it
// points to; File.copy onto a link to the file itself is an Error; a copy keeps the file's
// permission bits, and a move does from another file system too (the temporary directory, to the
// working directory), leaving no temporary file beside its target
let mode (path: string) =
  match Process.run "ls" [ "-ld"; path ] with
  | Ok r -> String.sub r.output 0 10
  | Error e -> e

let link (target: string) (path: string) = Process.run "ln" [ "-s"; target; path ] |> ignore

let run () : result<unit, string> =
  let dir = (Directory.createTemp "zslinks")?
  let at (name: string) = Path.combine dir name
  (Directory.create (at "kept"))?
  (File.writeAllText (at "kept/file.txt") "kept\n")?
  link (at "kept") (at "link")
  link (at "kept") (at "slash")
  (Directory.create (at "tree"))?
  link (at "kept") (at "tree/inner")
  let given = Directory.deleteRecursive (at "link")
  let slash = Directory.deleteRecursive (at "slash/")
  let inner = Directory.deleteRecursive (at "tree")
  let kept = File.readAllText (at "kept/file.txt") |> Result.map String.trim
  let gone = not (Directory.exists (at "link") || Directory.exists (at "slash"))
  let deleted = [ Result.isOk given; Result.isOk slash; Result.isOk inner; gone ]
  println $"links deleted: {deleted}, kept {kept}"
  (File.writeAllText (at "a.txt") "important\n")?
  link (at "a.txt") (at "alias")
  let onto = File.copy (at "a.txt") (at "alias")
  let left = File.readAllText (at "a.txt") |> Result.map String.trim
  println $"onto a link to itself: {Result.isError onto}, left {left}"
  let secret = (File.createTemp "zssecret")?
  (File.writeAllText secret "token\n")?
  (File.copy secret (at "copy"))?
  let copied = mode (at "copy")
  Process.run "chmod" [ "700"; at "copy" ] |> ignore
  (File.copy (at "copy") (at "tool"))?
  println $"copies: {copied} {mode (at "tool")}"
  let target = "zs-file-links.tmp"
  (File.writeAllText target "old\n")?
  (File.move secret target)?
  let moved = File.readAllText target |> Result.map String.trim
  let names = (Directory.list ".")?
  let temporary = List.exists (fun (n: string) -> String.startsWith ".zs-move-" n) names
  println $"moved: {mode target} {moved} {File.exists secret}, a temporary file left: {temporary}"
  (File.delete target)?
  (Directory.deleteRecursive dir)?
  Ok ()

let main () =
  match run () with
  | Ok () -> 0
  | Error e ->
    println e
    1
