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
  0
