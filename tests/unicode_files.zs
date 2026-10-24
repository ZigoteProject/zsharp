// File names, contents and directory listings in UTF-8 on every OS (Windows: the manifest's
// code page)
let run () : result<unit, string> =
  let dir = (Directory.createTemp "zsutf")?
  let path = Path.combine dir "été 東京.txt"
  (File.writeAllText path "naïve ✓")?
  let text = (File.readAllText path)?
  let names = (Directory.list dir)?
  println $"{text} {names} {File.exists path}"
  (Directory.deleteRecursive dir)?
  Ok ()

let main () =
  match run () with
  | Ok () -> 0
  | Error e ->
    println e
    1
