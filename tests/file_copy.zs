// File.copy onto the file itself (its path, or the path spelt another way) is an Error and leaves
// it as it was (the target opened to be emptied first would empty the source before a byte was
// read); a copy and a move replace a target that's another file
let run () : result<unit, string> =
  let dir = (Directory.createTemp "zscopy")?
  let a = Path.combine dir "a.txt"
  (File.writeAllText a "important\n")?
  let again = File.copy a a
  let spelt = File.copy a (Path.combine (Path.combine dir ".") "a.txt")
  let left = File.readAllText a |> Result.map String.trim
  println $"onto itself: {Result.isError again} {Result.isError spelt}, left {left}"
  let b = Path.combine dir "b.txt"
  (File.writeAllText b "old\n")?
  (File.copy a b)?
  let copied = File.readAllText b |> Result.map String.trim
  (File.writeAllText a "moved\n")?
  (File.move a b)?
  let moved = File.readAllText b |> Result.map String.trim
  println $"copied: {copied}, then moved over it: {moved} {File.exists a}"
  (Directory.deleteRecursive dir)?
  println $"{Directory.exists dir}"
  Ok ()

let main () =
  match run () with
  | Ok () -> 0
  | Error e ->
    println e
    1
