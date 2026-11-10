// A Windows batch file (.bat, .cmd) runs in cmd.exe, which reads its command line by rules of its
// own: its arguments are quoted for it, so none of these runs a command of its own (BatBadBut),
// and an argument with a line break, which cmd.exe can't be given, is an Error. Elsewhere there is
// no cmd.exe (process_batch.windows.out has Windows's lines).
let attempts (dir: string) =
  let marker = Path.combine dir "ran.txt"
  [ "a&echo ran>" + marker
    "\"&echo ran>" + marker
    "a|echo ran>" + marker
    "%COMSPEC% /c echo ran>" + marker
    "^\"&echo ran>" + marker
    "a\\\"&echo ran>" + marker ]

let run () : result<unit, string> =
  let dir = (Directory.createTemp "zsbatch")?
  let script = Path.combine dir "t.cmd"
  (File.writeAllText script "@exit /b 7\r\n")?
  let p = (Process.start { program = script; args = attempts dir; directory = Some dir })?
  let code = Task.run (Process.wait p)
  let ran = File.exists (Path.combine dir "ran.txt")
  println $"batch file: code {code}, a command of its own ran: {ran}"
  let broken = Process.run script [ "a\nb" ]
  println $"a line break: an Error {Result.isError broken}"
  (Directory.deleteRecursive dir)?
  Ok ()

let main () =
  if Path.separator = '\\' then
    match run () with
    | Ok () -> 0
    | Error e ->
      println e
      1
  else
    println "no batch files here"
    0
