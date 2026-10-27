// Arguments reach a program as they're given. One holding a NUL, which ends a C string, isn't
// passed on as two (printf repeats its format for each argument: "a\0b" printed [a][b]): the
// program isn't started, nor is one with a NUL in its name, directory or environment. An empty
// argument is passed, last or alone (sh -c 'echo $#' counts those after $0; expr exits 1 for
// one empty argument, 2 for none).
let started (s: ProcessStart) : string =
  match Process.start s with
  | Ok p ->
    use proc = p
    let out = match proc.stdout with | Some r -> Reader.readToEnd r | None -> Ok ""
    $"{Result.map String.trim out} {Task.run (Process.wait proc)}"
  | Error e -> e

let main () =
  let nul = String.ofByte (u8 0)
  match Process.run "printf" [ "[%s]"; "a" + nul + "b" ] with
  | Ok r -> println $"ran {r.output}"
  | Error e -> println e
  println (started { program = "printf"; args = [ "[%s]"; "a" + nul + "b" ]; stdout = Piped })
  println (started { program = "true"; environment = Some [ ("A", "1" + nul + "B=2") ] })
  println (started { program = "true"; directory = Some ("/" + nul + "tmp") })
  println $"{Result.isOk (Process.run ("sh" + nul + "x") [])}"
  for args in [ [ "x"; "" ]; [ "x"; ""; "" ]; [ "x"; ""; "y" ]; [ "x" ] ] do
    let n =
      match Process.run "sh" (List.append [ "-c"; "echo $#" ] args) with
      | Ok r -> String.trim r.output
      | Error e -> e
    println $"{n} {started { program = "sh"; args = List.append [ "-c"; "echo $#" ] args; stdout = Piped }}"
  match Process.run "expr" [ "" ] with
  | Ok r -> println $"expr {r.code}"
  | Error e -> println e
  println (started { program = "expr"; args = [ "" ]; stdout = Null })
  0
