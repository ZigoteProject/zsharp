// Process.start (0024): each stream inherited, piped or null; the exit code awaited as a task
let main () =
  match Process.start { program = "sh"
    args = [ "-c"; "read x; echo got $x; echo err >&2; exit 3" ]
    stdin = Piped
    stdout = Piped
    stderr = Piped } with
  | Ok p ->
    use proc = p
    match proc.stdin with
    | Some w ->
      Writer.writeText w "hi\n" |> ignore
      Dispose.dispose w
    | None -> ()
    let out = match proc.stdout with | Some r -> Reader.readToEnd r | None -> Ok ""
    let err = match proc.stderr with | Some r -> Reader.readToEnd r | None -> Ok ""
    println $"{out} {err} {Task.run (Process.wait proc)}"
  | Error e -> println e
  match Process.start { program = "no-such-program-zs" } with
  | Ok _ -> println "unexpected"
  | Error e -> println e
  match Process.start { program = "sh"
    args = [ "-c"; "pwd; echo $A" ]
    directory = Some "/"
    stdout = Piped
    environment = Some [ ("A", "1") ] } with
  | Ok p ->
    use proc = p
    let out = match proc.stdout with | Some r -> Reader.readToEnd r | None -> Ok ""
    println $"{out} {Task.run (Process.wait proc)}"
  | Error e -> println e
  // standard error into standard output's pipe (2>&1): both in the order written, and errors
  // past a pipe's worth before the output ends don't block the program (read apart, they would)
  match Process.start { program = "sh"
    args = [ "-c"; "echo one; echo two >&2; i=0; while [ $i -lt 3000 ]; do echo 'an error line, long enough to fill a pipe' >&2; i=$((i+1)); done; echo three" ]
    stdout = Piped
    stderr = ToOutput } with
  | Ok p ->
    use proc = p
    let out = match proc.stdout with | Some r -> Result.defaultValue "" (Reader.readToEnd r) | None -> ""
    let lines = String.split "\n" (String.trim out)
    println $"{List.head lines} {List.head (List.tail lines)} {List.length lines} {List.last lines} {Option.isNone proc.stderr} {Task.run (Process.wait proc)}"
  | Error e -> println e
  match Process.start { program = "sh"; stdout = ToOutput } with
  | Ok _ -> println "unexpected"
  | Error e -> println e
  0
