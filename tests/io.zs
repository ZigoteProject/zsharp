// Files, directories and paths (0024): readers and writers, bytes, copying and moving, times
// and sizes, temporary directories, recursive listing and deleting
let run () : result<unit, string> =
  let dir = (Directory.createTemp "zsio")?
  let path = Path.combine dir "a.txt"
  let opened = (File.openWrite path)?
  use w = opened
  (Writer.writeText w "first line\r\nsecond\n")?
  (Writer.write w (String.bytes "no newline"))?
  (Writer.flush w)?
  let reading = (File.openRead path)?
  use r = reading
  println $"{Reader.readLine r} {Reader.readLine r} {Reader.readLine r} {Reader.readLine r}"
  let bytes = (File.readAllBytes path)?
  let size = (File.size path)?
  let changed = (File.modifiedAt path)?
  println $"{Array.length bytes} {size} {changed.sinceEpoch > 0<ns>}"
  (File.copy path (Path.combine dir "b.txt"))?
  (File.move (Path.combine dir "b.txt") (Path.combine dir "c.txt"))?
  (Directory.create (Path.combine dir "sub"))?
  (File.writeAllBytes (Path.combine dir "sub/d.txt") (String.bytes "d"))?
  let all = (Directory.listRecursive dir)?
  println $"{all} {File.exists (Path.combine dir "b.txt")}"
  match File.openRead (Path.combine dir "missing") with
  | Ok _ -> println "unexpected"
  | Error e -> println (String.replace e dir "DIR")
  (Directory.deleteRecursive dir)?
  println $"{Directory.exists dir}"
  Ok ()

let main () =
  println $"{Path.getFullPath "/a/./b/../c//d"} {Path.getRelativePath "/a/b" "/a/c/d"} {Path.getRelativePath "/a" "/a"} {Path.isAbsolute "x"} {Path.separator}"
  println $"{Path.isAbsolute (Environment.currentDirectory ())} {Path.isAbsolute (Path.getFullPath "x")}"
  match run () with
  | Ok () -> 0
  | Error e ->
    println e
    1
